/**
 * socketRateLimiter.js — Per-Socket, Per-User, Per-IP Rate Limiting & Validation Engine
 *
 * Responsibilities:
 * 1. Implements sliding-window rate limiting per connected socket ID, authenticated user ID, and client IP.
 * 2. Prevents rate-limit bypass via reconnect loops or multiple concurrent socket connections.
 * 3. Enforces specific thresholds for high-frequency telemetry, life-safety SOS, and room subscriptions.
 * 4. Validates payload sizes and coordinate bounds to prevent buffer exhaustion and malformed data attacks.
 * 5. Cleans up socket-specific state on disconnect while preserving user/IP limits across reconnects.
 * 6. Provides explicit acknowledgements and audit logging (never silently drops emergency SOS events).
 * 7. Supports a pluggable Store Adapter pattern for multi-instance Redis scaling.
 */

class InMemoryRateLimitStore {
    constructor() {
        this.records = new Map(); // key -> Array<number> (timestamps)
    }

    /**
     * Non-mutating pre-check to verify if an action would be allowed.
     *
     * @param {string} key
     * @param {number} windowMs
     * @param {number} maxRequests
     * @returns {{ allowed: boolean, count: number, retryAfterMs: number }}
     */
    peek(key, windowMs, maxRequests) {
        const now = Date.now();
        let timestamps = this.records.get(key) || [];
        const windowStart = now - windowMs;
        timestamps = timestamps.filter(ts => ts > windowStart);

        if (timestamps.length >= maxRequests) {
            const oldestInWindow = timestamps[0];
            const retryAfterMs = Math.max(100, (oldestInWindow + windowMs) - now);
            return { allowed: false, count: timestamps.length, retryAfterMs };
        }

        return { allowed: true, count: timestamps.length, retryAfterMs: 0 };
    }

    /**
     * Checks if an action is permitted under the sliding window and records the invocation.
     *
     * @param {string} key - Unique key, e.g. "socketId:eventName" or "userId:eventName"
     * @param {number} windowMs - Time window in milliseconds
     * @param {number} maxRequests - Max requests permitted in the window
     * @returns {{ allowed: boolean, count: number, retryAfterMs: number }}
     */
    check(key, windowMs, maxRequests) {
        const now = Date.now();
        let timestamps = this.records.get(key) || [];

        // Prune timestamps older than windowMs
        const windowStart = now - windowMs;
        timestamps = timestamps.filter(ts => ts > windowStart);

        if (timestamps.length >= maxRequests) {
            const oldestInWindow = timestamps[0];
            const retryAfterMs = Math.max(100, (oldestInWindow + windowMs) - now);
            this.records.set(key, timestamps);
            return {
                allowed: false,
                count: timestamps.length,
                retryAfterMs
            };
        }

        timestamps.push(now);
        this.records.set(key, timestamps);

        return {
            allowed: true,
            count: timestamps.length,
            retryAfterMs: 0
        };
    }

    /**
     * Removes all keys belonging to a specific socketId.
     * Note: user_* and ip_* records are deliberately NOT cleared on socket disconnect
     * so that reconnecting or opening multiple sockets cannot bypass the rate limit.
     *
     * @param {string} socketId
     */
    clearSocket(socketId) {
        const prefix = `${socketId}:`;
        for (const key of this.records.keys()) {
            if (key.startsWith(prefix)) {
                this.records.delete(key);
            }
        }
    }

    /**
     * Prunes expired records across the entire store.
     * Called periodically to prevent unbounded memory growth.
     */
    pruneExpired(maxIdleMs = 600000) {
        const now = Date.now();
        const cutoff = now - maxIdleMs;
        for (const [key, timestamps] of this.records.entries()) {
            if (timestamps.length === 0 || timestamps[timestamps.length - 1] < cutoff) {
                this.records.delete(key);
            }
        }
    }
}

/**
 * SocketRateLimiter coordinating per-event limits and security validation.
 */
class SocketRateLimiter {
    constructor(store = new InMemoryRateLimitStore()) {
        this.store = store;

        // Default event configurations (windowMs, maxRequests, maxPayloadBytes)
        this.limits = {
            locationUpdate: { windowMs: 1000, maxRequests: 3, maxPayloadBytes: 4096 },
            triggerSOS:     { windowMs: 30000, maxRequests: 3, maxPayloadBytes: 2048 },
            joinRoute:      { windowMs: 10000, maxRequests: 10, maxPayloadBytes: 512 },
            joinManager:    { windowMs: 10000, maxRequests: 5, maxPayloadBytes: 512 },
            startTrip:      { windowMs: 60000, maxRequests: 5, maxPayloadBytes: 2048 },
            tripEnd:        { windowMs: 60000, maxRequests: 5, maxPayloadBytes: 2048 }
        };

        // Periodic maintenance cleanup every 5 minutes
        this._gcInterval = setInterval(() => {
            this.store.pruneExpired();
        }, 300000);
        if (this._gcInterval.unref) this._gcInterval.unref();
    }

    destroy() {
        if (this._gcInterval) clearInterval(this._gcInterval);
    }

    /**
     * Inspects whether a socket event is permitted across all associated entity IDs.
     * Checks both socketId and optionally authenticated userId or client IP.
     *
     * @param {string|string[]} entityIds - Socket identifier(s) (e.g. socket.id, userId, ip)
     * @param {string} eventName - Name of the Socket.IO event
     * @returns {{ allowed: boolean, retryAfterMs: number, reason?: string }}
     */
    consume(entityIds, eventName) {
        if (!entityIds || !eventName) return { allowed: true, retryAfterMs: 0 };

        const ids = (Array.isArray(entityIds) ? entityIds : [entityIds])
            .filter(Boolean)
            .map(id => String(id).trim());

        if (ids.length === 0) return { allowed: true, retryAfterMs: 0 };

        const config = this.limits[eventName] || { windowMs: 5000, maxRequests: 20 };

        // 1. Pre-check: Verify that EVERY entity has capacity remaining before recording
        for (const id of ids) {
            const key = `${id}:${eventName}`;
            const peek = this.store.peek(key, config.windowMs, config.maxRequests);
            if (!peek.allowed) {
                return {
                    allowed: false,
                    retryAfterMs: peek.retryAfterMs,
                    reason: `Rate limit exceeded for event "${eventName}". Allowed ${config.maxRequests} per ${config.windowMs}ms.`
                };
            }
        }

        // 2. Consume a slot for each entity ID
        let worstRetryAfterMs = 0;
        let anyDisallowed = false;

        for (const id of ids) {
            const key = `${id}:${eventName}`;
            const result = this.store.check(key, config.windowMs, config.maxRequests);
            if (!result.allowed) {
                anyDisallowed = true;
                worstRetryAfterMs = Math.max(worstRetryAfterMs, result.retryAfterMs);
            }
        }

        if (anyDisallowed) {
            return {
                allowed: false,
                retryAfterMs: worstRetryAfterMs,
                reason: `Rate limit exceeded for event "${eventName}". Allowed ${config.maxRequests} per ${config.windowMs}ms.`
            };
        }

        return { allowed: true, retryAfterMs: 0 };
    }

    /**
     * Helper to resolve standard identifier array for a socket.
     * For authenticated users, uses socket.id and persistent user_${socket.user.id}
     * so that reconnecting on fresh sockets cannot bypass rate limits, while multiple
     * distinct users behind the same NAT/college Wi-Fi gateway do not collide.
     * For unauthenticated guest sockets, uses socket.id and ip_${socket.handshake.address}.
     *
     * @param {Object} socket - Socket.IO socket instance
     * @returns {string[]}
     */
    getSocketEntities(socket) {
        if (!socket) return [];
        const entities = [socket.id];
        if (socket.user && socket.user.id) {
            entities.push(`user_${socket.user.id}`);
        } else if (socket.handshake && socket.handshake.address) {
            entities.push(`ip_${socket.handshake.address}`);
        }
        return entities;
    }

    /**
     * Validates that payload size does not exceed maximum byte boundary.
     *
     * @param {any} data - Client payload
     * @param {number} maxBytes - Maximum permitted serialized length
     * @returns {boolean}
     */
    validatePayloadSize(data, maxBytes = 4096) {
        if (data === null || data === undefined) return true;
        try {
            const str = typeof data === 'string' ? data : JSON.stringify(data);
            return Buffer.byteLength(str, 'utf8') <= maxBytes;
        } catch (_) {
            return false;
        }
    }

    /**
     * Validates the schema and coordinates of a locationUpdate packet.
     * Standardizes vehicle speed upper bound to 130 km/h across all layers.
     *
     * @param {any} data
     * @returns {{ valid: boolean, error?: string }}
     */
    validateLocationPayload(data) {
        if (!data || typeof data !== 'object') {
            return { valid: false, error: 'Payload must be a non-empty object' };
        }

        const busId = data.busId || data.id || data._id;
        if (!busId || typeof busId.toString !== 'function' || busId.toString().trim().length === 0) {
            return { valid: false, error: 'busId is strictly required' };
        }

        const lat = Number(data.lat ?? data.latitude);
        const lng = Number(data.lng ?? data.longitude);

        if (isNaN(lat) || isNaN(lng)) {
            return { valid: false, error: 'Latitude and Longitude must be valid numbers' };
        }

        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            return { valid: false, error: 'Coordinates out of geographical bounds' };
        }

        // Null Island Check
        if (Math.abs(lat) < 0.0001 && Math.abs(lng) < 0.0001) {
            return { valid: false, error: 'Null Island (0,0) coordinates rejected' };
        }

        // Unified 130 km/h Policy (matches AIS-063 speed governor buffer and server kinematic filter)
        if (data.speed !== undefined && data.speed !== null) {
            const speed = Number(data.speed);
            if (isNaN(speed) || speed < 0 || speed > 130) {
                return { valid: false, error: 'Speed must be between 0 and 130 km/h' };
            }
        }

        if (data.heading !== undefined && data.heading !== null) {
            const heading = Number(data.heading);
            if (isNaN(heading) || heading < 0 || heading > 360) {
                return { valid: false, error: 'Heading must be between 0 and 360 degrees' };
            }
        }

        return { valid: true };
    }

    /**
     * Cleans up socket-specific state when a socket disconnects.
     * Retains user_* and ip_* records to prevent reconnect bypass attacks.
     *
     * @param {string} socketId
     */
    handleDisconnect(socketId) {
        if (socketId) {
            this.store.clearSocket(socketId);
        }
    }
}

// Export singleton instance and classes
const defaultLimiter = new SocketRateLimiter();

module.exports = {
    SocketRateLimiter,
    InMemoryRateLimitStore,
    defaultLimiter
};
