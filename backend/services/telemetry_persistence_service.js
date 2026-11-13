/**
 * telemetry_persistence_service.js
 * Phase 1: Historical GPS Telemetry Foundation & Centralized IST Trip Identity.
 *
 * Responsibilities:
 * 1. Centralized Asia/Kolkata (IST) YYYY-MM-DD trip-date calculation.
 * 2. Strict validation of incoming GPS telemetry (no NaN, Infinity, or fabricated defaults).
 * 3. Deterministic server-side sampling (5s interval OR >= 25m movement) per tripLogId.
 * 4. Non-blocking append-only persistence to TripTelemetryPoint.
 */

const DEFAULT_MIN_INTERVAL_MS = 5000;
const DEFAULT_MIN_DISTANCE_METERS = 25;
const MAX_FUTURE_DRIFT_MS = 60000;

// In-memory last persisted sample per tripLogId (keyed by String(tripLogId))
const defaultSamplerState = new Map();

/**
 * Returns YYYY-MM-DD in Asia/Kolkata (IST, UTC+05:30).
 * @param {Date|string|number} [inputDate=new Date()]
 * @returns {string}
 */
function getIstDateString(inputDate = new Date()) {
    const dt = inputDate instanceof Date ? inputDate : new Date(inputDate);
    const validDt = !isNaN(dt.getTime()) ? dt : new Date();
    try {
        // en-CA formats deterministically as YYYY-MM-DD
        return new Intl.DateTimeFormat('en-CA', {
            timeZone: 'Asia/Kolkata',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        }).format(validDt);
    } catch (_) {
        const istMs = validDt.getTime() + (330 * 60 * 1000);
        return new Date(istMs).toISOString().split('T')[0];
    }
}

/**
 * Computes great-circle Haversine distance in meters between two coordinates.
 */
function haversineMeters(lat1, lng1, lat2, lng2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) *
        Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLng / 2) * Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

/**
 * Validates a telemetry point before persistence.
 * Never fabricates missing optional fields (speed, heading, accuracy remain null if absent).
 */
function validateTelemetryPoint(payload) {
    if (!payload || typeof payload !== 'object') {
        return { valid: false, reason: 'Empty telemetry payload' };
    }

    const tripLogId = payload.tripLogId != null ? String(payload.tripLogId).trim() : '';
    const busId = payload.busId != null ? String(payload.busId).trim() : '';

    if (!tripLogId) {
        return { valid: false, reason: 'Missing tripLogId' };
    }
    if (!busId) {
        return { valid: false, reason: 'Missing busId' };
    }

    const lat = Number(payload.lat);
    const lng = Number(payload.lng);
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
        return { valid: false, reason: 'Invalid latitude' };
    }
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
        return { valid: false, reason: 'Invalid longitude' };
    }
    if (lat === 0 && lng === 0) {
        return { valid: false, reason: 'Null Island (0, 0) coordinates rejected' };
    }

    let speed = null;
    if (payload.speed !== undefined && payload.speed !== null && payload.speed !== '') {
        const parsedSpeed = Number(payload.speed);
        if (!Number.isFinite(parsedSpeed) || parsedSpeed < 0 || parsedSpeed > 200) {
            return { valid: false, reason: 'Invalid speed' };
        }
        speed = parsedSpeed;
    }

    let heading = null;
    if (payload.heading !== undefined && payload.heading !== null && payload.heading !== '') {
        const parsedHeading = Number(payload.heading);
        if (!Number.isFinite(parsedHeading) || parsedHeading < 0 || parsedHeading > 360) {
            return { valid: false, reason: 'Invalid heading' };
        }
        heading = parsedHeading;
    }

    let accuracy = null;
    if (payload.accuracy !== undefined && payload.accuracy !== null && payload.accuracy !== '') {
        const parsedAccuracy = Number(payload.accuracy);
        if (!Number.isFinite(parsedAccuracy) || parsedAccuracy < 0 || parsedAccuracy > 5000) {
            return { valid: false, reason: 'Invalid accuracy' };
        }
        accuracy = parsedAccuracy;
    }

    const ts = payload.timestamp instanceof Date
        ? payload.timestamp
        : (payload.timestamp ? new Date(payload.timestamp) : new Date());
    if (isNaN(ts.getTime())) {
        return { valid: false, reason: 'Malformed timestamp' };
    }
    if (ts.getTime() > Date.now() + MAX_FUTURE_DRIFT_MS) {
        return { valid: false, reason: 'Timestamp too far in future' };
    }

    return {
        valid: true,
        point: {
            tripLogId: payload.tripLogId,
            busId,
            lat,
            lng,
            speed,
            heading,
            accuracy,
            timestamp: ts
        }
    };
}

/**
 * Determines whether a validated point should be persisted for the given tripLogId.
 * Always persists the first point of a trip, then throttles by minIntervalMs (5s) OR minDistanceMeters (25m).
 */
function shouldPersistTelemetryPoint(lastSample, nextPoint, options = {}) {
    const minIntervalMs = options.minIntervalMs ?? DEFAULT_MIN_INTERVAL_MS;
    const minDistanceMeters = options.minDistanceMeters ?? DEFAULT_MIN_DISTANCE_METERS;

    if (!lastSample) {
        return { shouldPersist: true, reason: 'first_point' };
    }

    const elapsedMs = nextPoint.timestamp.getTime() - lastSample.timestampMs;
    if (elapsedMs >= minIntervalMs) {
        return { shouldPersist: true, reason: 'interval_elapsed' };
    }

    const movedMeters = haversineMeters(lastSample.lat, lastSample.lng, nextPoint.lat, nextPoint.lng);
    if (movedMeters >= minDistanceMeters) {
        return { shouldPersist: true, reason: 'movement_threshold' };
    }

    return { shouldPersist: false, reason: 'throttled' };
}

/**
 * Validates, samples, and asynchronously persists a telemetry point scoped to tripLogId.
 * Never throws into callers so live Socket.IO tracking is never disrupted.
 */
async function persistTelemetryPointIfSampled({
    TripTelemetryPointModel,
    tripLogId,
    busId,
    lat,
    lng,
    speed = null,
    heading = null,
    accuracy = null,
    timestamp = new Date(),
    samplerState = defaultSamplerState,
    minIntervalMs = DEFAULT_MIN_INTERVAL_MS,
    minDistanceMeters = DEFAULT_MIN_DISTANCE_METERS
}) {
    const validation = validateTelemetryPoint({
        tripLogId,
        busId,
        lat,
        lng,
        speed,
        heading,
        accuracy,
        timestamp
    });

    if (!validation.valid) {
        return { persisted: false, skipped: true, reason: validation.reason };
    }

    const point = validation.point;
    const tripKey = String(point.tripLogId);
    const lastSample = samplerState.get(tripKey) || null;
    const decision = shouldPersistTelemetryPoint(lastSample, point, { minIntervalMs, minDistanceMeters });

    if (!decision.shouldPersist) {
        return { persisted: false, skipped: true, reason: decision.reason };
    }

    // Update sampler state synchronously before await to prevent concurrent bursts racing
    const previousSample = lastSample;
    samplerState.set(tripKey, {
        lat: point.lat,
        lng: point.lng,
        timestampMs: point.timestamp.getTime()
    });

    try {
        const doc = await TripTelemetryPointModel.create(point);
        return { persisted: true, skipped: false, reason: decision.reason, doc };
    } catch (err) {
        // Restore previous state if DB write failed so next valid packet retries
        if (previousSample) {
            samplerState.set(tripKey, previousSample);
        } else {
            samplerState.delete(tripKey);
        }
        return { persisted: false, skipped: false, error: err.message };
    }
}

function parseTimeMinutes(timeStr) {
    if (!timeStr) return null;
    const match = String(timeStr).trim().match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
    if (!match) return null;
    let h = parseInt(match[1], 10);
    const m = parseInt(match[2], 10);
    const ampm = (match[3] || 'AM').toUpperCase();
    if (ampm === 'PM' && h < 12) h += 12;
    if (ampm === 'AM' && h === 12) h = 0;
    return h * 60 + m;
}

function clearTelemetrySamplerState(tripLogId, samplerState = defaultSamplerState) {
    if (tripLogId !== undefined && tripLogId !== null) {
        samplerState.delete(String(tripLogId));
    }
}

module.exports = {
    DEFAULT_MIN_INTERVAL_MS,
    DEFAULT_MIN_DISTANCE_METERS,
    getIstDateString,
    parseTimeMinutes,
    haversineMeters,
    validateTelemetryPoint,
    shouldPersistTelemetryPoint,
    persistTelemetryPointIfSampled,
    clearTelemetrySamplerState
};
