/**
 * road_routing_service.js
 * Hybrid Google Maps & OSRM High-Resolution Road Routing Engine.
 * 
 * Supports:
 * 1. Google Routes API (Next-Gen directions with live traffic & highway geometries)
 * 2. Google Roads API (Snap-to-Roads precision for GPS tracks & bus stops)
 * 3. OSRM High-Resolution Engine (Multi-waypoint & segmented road fallback)
 */

const https = require('https');

/**
 * Universal Google Encoded Polyline Decoder (Lossless 5-decimal precision)
 */
function decodePolyline(encoded) {
    if (!encoded) return [];
    const points = [];
    let index = 0, len = encoded.length;
    let lat = 0, lng = 0;

    while (index < len) {
        let b, shift = 0, result = 0;
        do {
            b = encoded.charCodeAt(index++) - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        const dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lat += dlat;

        shift = 0;
        result = 0;
        do {
            b = encoded.charCodeAt(index++) - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        const dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lng += dlng;

        points.push({
            latitude: Number((lat / 1e5).toFixed(6)),
            longitude: Number((lng / 1e5).toFixed(6))
        });
    }
    return points;
}

/**
 * Query Next-Gen Google Routes API (directions/v2:computeRoutes)
 */
async function queryGoogleRoutes(stops) {
    const key = process.env.GOOGLE_MAPS_API_KEY;
    if (!key || key.startsWith('YOUR_') || key.trim() === '') return null;
    if (stops.length < 2) return null;

    const origin = {
        location: {
            latLng: {
                latitude: stops[0].lat,
                longitude: stops[0].lng
            }
        }
    };
    const destination = {
        location: {
            latLng: {
                latitude: stops[stops.length - 1].lat,
                longitude: stops[stops.length - 1].lng
            }
        }
    };

    // Google Routes API supports up to 25 intermediate waypoints
    const intermediates = stops.slice(1, -1).slice(0, 25).map(s => ({
        location: {
            latLng: {
                latitude: s.lat,
                longitude: s.lng
            }
        }
    }));

    const postData = JSON.stringify({
        origin,
        destination,
        intermediates,
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
        polylineQuality: 'HIGH_QUALITY'
    });

    return new Promise((resolve) => {
        const req = https.request({
            hostname: 'routes.googleapis.com',
            path: '/directions/v2:computeRoutes',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': key,
                'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline'
            },
            timeout: 10000
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    if (res.statusCode !== 200) {
                        return resolve(null);
                    }
                    const json = JSON.parse(data);
                    if (json.routes && json.routes.length > 0 && json.routes[0].polyline) {
                        const r = json.routes[0];
                        const coords = decodePolyline(r.polyline.encodedPolyline);
                        const durationSec = parseInt(r.duration || '0', 10);
                        const distanceM = r.distanceMeters || 0;
                        resolve({
                            distanceKm: (distanceM / 1000).toFixed(1),
                            durationMins: Math.round(durationSec / 60),
                            coordinates: coords
                        });
                    } else {
                        resolve(null);
                    }
                } catch (_) {
                    resolve(null);
                }
            });
        });

        req.on('error', () => resolve(null));
        req.on('timeout', () => {
            req.destroy();
            resolve(null);
        });
        req.write(postData);
        req.end();
    });
}

/**
 * Snap an array of GPS coordinates to Google Roads geometry via Roads API
 */
async function snapPointsToGoogleRoads(points) {
    const key = process.env.GOOGLE_MAPS_API_KEY;
    if (!key || key.startsWith('YOUR_') || key.trim() === '' || !points || points.length === 0) {
        return points;
    }

    // Google Roads API allows up to 100 points per call
    const chunks = [];
    for (let i = 0; i < points.length; i += 90) {
        chunks.push(points.slice(i, i + 90));
    }

    const snappedAll = [];
    for (const chunk of chunks) {
        const pathParam = chunk.map(p => `${p.latitude || p.lat},${p.longitude || p.lng}`).join('|');
        const url = `https://roads.googleapis.com/v1/snapToRoads?path=${encodeURIComponent(pathParam)}&interpolate=true&key=${key}`;

        const chunkResult = await new Promise((resolve) => {
            https.get(url, { timeout: 8000 }, (res) => {
                let data = '';
                res.on('data', d => data += d);
                res.on('end', () => {
                    try {
                        if (res.statusCode !== 200) return resolve(null);
                        const j = JSON.parse(data);
                        if (j.snappedPoints && j.snappedPoints.length > 0) {
                            return resolve(j.snappedPoints.map(sp => ({
                                latitude: sp.location.latitude,
                                longitude: sp.location.longitude
                            })));
                        }
                        resolve(null);
                    } catch (_) {
                        resolve(null);
                    }
                });
            }).on('error', () => resolve(null));
        });

        if (chunkResult && chunkResult.length > 0) {
            snappedAll.push(...chunkResult);
        } else {
            snappedAll.push(...chunk.map(p => ({
                latitude: p.latitude || p.lat,
                longitude: p.longitude || p.lng
            })));
        }
    }

    return snappedAll.length > 0 ? snappedAll : points;
}

/**
 * Query OSRM High-Resolution Road Network
 */
function queryOSRM(stops) {
    return new Promise((resolve) => {
        const waypoints = stops.map(s => `${s.lng},${s.lat}`).join(';');
        const url = `https://router.project-osrm.org/route/v1/driving/${waypoints}?overview=full&geometries=geojson&continue_straight=true`;

        const req = https.get(url, {
            headers: { 'User-Agent': 'SISTecChalo-TransitApp/1.0' },
            timeout: 12000
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    if (json.code === 'Ok' && json.routes && json.routes.length > 0) {
                        const r = json.routes[0];
                        const coords = r.geometry.coordinates.map(([lng, lat]) => ({
                            latitude: lat,
                            longitude: lng
                        }));
                        resolve({
                            distanceKm: (r.distance / 1000).toFixed(1),
                            durationMins: Math.round(r.duration / 60),
                            coordinates: coords
                        });
                    } else {
                        resolve(null);
                    }
                } catch (_) {
                    resolve(null);
                }
            });
        });

        req.on('error', () => resolve(null));
        req.on('timeout', () => {
            req.destroy();
            resolve(null);
        });
    });
}

/**
 * Fetch road polyline between an array of stops [{ lat, lng, name }, ...]
 * Automatically tries Google Routes API first, falling back to OSRM.
 */
async function getRoadPolylineForStops(stops) {
    if (!stops || stops.length < 2) {
        return {
            distanceKm: '0.0',
            durationMins: 0,
            coordinates: (stops || []).map(s => ({ latitude: s.lat, longitude: s.lng }))
        };
    }

    // Filter out invalid coordinates (0,0)
    const validStops = stops.filter(s => s.lat && s.lng && s.lat !== 0 && s.lng !== 0);
    if (validStops.length < 2) {
        return {
            distanceKm: '0.0',
            durationMins: 0,
            coordinates: validStops.map(s => ({ latitude: s.lat, longitude: s.lng }))
        };
    }

    // 1. Google Routes API (Gold Standard: Traffic-Aware + High-Quality Highway Polylines)
    try {
        const googleResult = await queryGoogleRoutes(validStops);
        if (googleResult && googleResult.coordinates && googleResult.coordinates.length > 10) {
            console.log(`🗺️ [Google Routes API] Route generated: ${googleResult.coordinates.length} coords, ${googleResult.distanceKm} km, ${googleResult.durationMins} mins`);
            return googleResult;
        }
    } catch (e) {
        console.warn('   ⚠️ Google Routes API note:', e.message);
    }

    // 2. OSRM Multi-waypoint Highway Routing
    try {
        const fullResult = await queryOSRM(validStops);
        if (fullResult && fullResult.coordinates && fullResult.coordinates.length > 0) {
            return fullResult;
        }
    } catch (e) {
        console.warn('   ⚠️ Full OSRM routing warning:', e.message);
    }

    // 3. OSRM Segment-by-segment routing for long routes
    try {
        const allCoords = [];
        let totalDistance = 0;
        let totalDuration = 0;

        for (let i = 0; i < validStops.length - 1; i++) {
            const segStops = [validStops[i], validStops[i + 1]];
            const segResult = await queryOSRM(segStops);

            if (segResult && segResult.coordinates && segResult.coordinates.length > 0) {
                if (i > 0) {
                    allCoords.push(...segResult.coordinates.slice(1));
                } else {
                    allCoords.push(...segResult.coordinates);
                }
                totalDistance += parseFloat(segResult.distanceKm || 0);
                totalDuration += parseInt(segResult.durationMins || 0, 10);
            } else {
                if (i === 0) allCoords.push({ latitude: validStops[i].lat, longitude: validStops[i].lng });
                allCoords.push({ latitude: validStops[i + 1].lat, longitude: validStops[i + 1].lng });
            }

            // Brief throttle
            await new Promise(r => setTimeout(r, 40));
        }

        if (allCoords.length > 0) {
            return {
                distanceKm: totalDistance.toFixed(1),
                durationMins: totalDuration,
                coordinates: allCoords
            };
        }
    } catch (e) {
        console.warn('   ⚠️ Segment routing warning:', e.message);
    }

    // Fallback: Direct coordinates
    return {
        distanceKm: '0.0',
        durationMins: 0,
        coordinates: validStops.map(s => ({ latitude: s.lat, longitude: s.lng }))
    };
}

/**
 * Haversine distance in meters between two lat/lng coordinates
 */
function haversineDistMeters(lat1, lon1, lat2, lon2) {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return 0;
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Find the nearest coordinate index in an array of { latitude/lat, longitude/lng }
 */
function findNearestCoordIndex(targetLat, targetLng, coordinates) {
    if (!coordinates || coordinates.length === 0) return { index: 0, distanceMeters: 0 };
    let minD = Infinity;
    let bestIdx = 0;
    for (let i = 0; i < coordinates.length; i++) {
        const c = coordinates[i];
        const lat = c.latitude != null ? c.latitude : c.lat;
        const lng = c.longitude != null ? c.longitude : c.lng;
        if (lat == null || lng == null) continue;
        const d = haversineDistMeters(targetLat, targetLng, lat, lng);
        if (d < minD) {
            minD = d;
            bestIdx = i;
        }
    }
    return { index: bestIdx, distanceMeters: minD };
}

/**
 * Sum distance in meters along a slice of polyline coordinates
 */
function measurePolylineDistanceMeters(coordinates, startIdx, endIdx) {
    if (!coordinates || startIdx >= endIdx) return 0;
    let total = 0;
    const max = Math.min(endIdx, coordinates.length - 1);
    for (let i = startIdx; i < max; i++) {
        const c1 = coordinates[i];
        const c2 = coordinates[i + 1];
        const lat1 = c1.latitude != null ? c1.latitude : c1.lat;
        const lng1 = c1.longitude != null ? c1.longitude : c1.lng;
        const lat2 = c2.latitude != null ? c2.latitude : c2.lat;
        const lng2 = c2.longitude != null ? c2.longitude : c2.lng;
        total += haversineDistMeters(lat1, lng1, lat2, lng2);
    }
    return total;
}

// In-memory memoization cache for point-to-point OSRM queries (TTL 45s)
const p2pCache = new Map();
function getP2PCacheKey(lat1, lon1, lat2, lon2) {
    return `${Number(lat1).toFixed(4)},${Number(lon1).toFixed(4)}_${Number(lat2).toFixed(4)},${Number(lon2).toFixed(4)}`;
}

/**
 * Query point-to-point driving route via OSRM with memory caching
 */
async function queryOSRMPointToPoint(lat1, lon1, lat2, lon2) {
    const key = getP2PCacheKey(lat1, lon1, lat2, lon2);
    const cached = p2pCache.get(key);
    if (cached && Date.now() - cached.timestamp < 45000) {
        return cached.data;
    }

    return new Promise((resolve) => {
        const url = `https://router.project-osrm.org/route/v1/driving/${lon1},${lat1};${lon2},${lat2}?overview=false`;
        const req = https.get(url, {
            headers: { 'User-Agent': 'SISTecChalo-TransitApp/1.0' },
            timeout: 6000
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    if (json.code === 'Ok' && json.routes && json.routes.length > 0) {
                        const r = json.routes[0];
                        const result = {
                            distanceMeters: r.distance,
                            durationSeconds: r.duration,
                            distanceKm: (r.distance / 1000).toFixed(1),
                            minutes: Math.max(1, Math.round(r.duration / 60))
                        };
                        p2pCache.set(key, { data: result, timestamp: Date.now() });
                        // Cap cache size
                        if (p2pCache.size > 500) {
                            const oldestKey = p2pCache.keys().next().value;
                            p2pCache.delete(oldestKey);
                        }
                        return resolve(result);
                    }
                    resolve(null);
                } catch (_) {
                    resolve(null);
                }
            });
        });

        req.on('error', () => resolve(null));
        req.on('timeout', () => {
            req.destroy();
            resolve(null);
        });
    });
}

/**
 * Calculate accurate road ETA between two coordinates, prioritizing route polyline,
 * point-to-point OSRM, or calibrated road factor.
 */
async function calculateAccurateETA(busLat, busLng, stopLat, stopLng, currentSpeed = 28, route = null) {
    if (!busLat || !busLng || !stopLat || !stopLng) return 0;

    // 1. If route coordinates exist, calculate along the true road polyline path
    if (route && route.coordinates && route.coordinates.length > 10) {
        const busNearest = findNearestCoordIndex(busLat, busLng, route.coordinates);
        const stopNearest = findNearestCoordIndex(stopLat, stopLng, route.coordinates);

        if (stopNearest.index >= busNearest.index) {
            const roadDistMeters = measurePolylineDistanceMeters(route.coordinates, busNearest.index, stopNearest.index);
            // Use actual broadcast speed with a floor of 8 km/h (crawling traffic)
            const speedKmh = (currentSpeed && currentSpeed >= 8) ? Math.min(currentSpeed, 60) : 25;
            const speedMps = (speedKmh * 1000) / 3600;
            const travelSec = roadDistMeters / speedMps;
            return Math.max(1, Math.round(travelSec / 60));
        }
    }

    // 2. Query live OSRM point-to-point driving engine
    try {
        const osrmResult = await queryOSRMPointToPoint(busLat, busLng, stopLat, stopLng);
        if (osrmResult && osrmResult.minutes) {
            // Blend OSRM free-flow duration with actual speed for traffic-aware ETA
            if (currentSpeed && currentSpeed >= 8 && osrmResult.distanceMeters) {
                const actualSpeedMps = (Math.min(currentSpeed, 60) * 1000) / 3600;
                const actualSec = osrmResult.distanceMeters / actualSpeedMps;
                // Weighted: 60% actual-speed-based, 40% OSRM free-flow
                const blended = (actualSec * 0.6) + (osrmResult.durationSeconds * 0.4);
                return Math.max(1, Math.round(blended / 60));
            }
            return osrmResult.minutes;
        }
    } catch (_) {}

    // 3. Fallback: Calibrated Indian mixed road curvature model (1.5x Haversine)
    //    Indian roads have winding/detour ratios of 1.4-1.6× straight-line distance
    const directDistM = haversineDistMeters(busLat, busLng, stopLat, stopLng);
    const roadDistKm = (directDistM * 1.5) / 1000.0;
    const speedKmh = (currentSpeed && currentSpeed >= 8) ? Math.min(currentSpeed, 60) : 25;
    return Math.max(1, Math.round((roadDistKm / speedKmh) * 60));
}

/**
 * Compute true road ETAs and progress for all stops along a bus route.
 * Determines which stops are upcoming based on current bus position along the polyline.
 */
function computeRouteProgressAndETAs(busLat, busLng, currentSpeed = 28, stops = [], coordinates = [], tripType = 'pickup', reachedStops = []) {
    if (!stops || stops.length === 0) return { etas: [], currentStopIndex: 0, nextStopName: '' };

    const reachedSet = new Set((reachedStops || []).map(s => String(s).trim().toLowerCase()));
    const isStopPassed = (name) => {
        if (!name) return false;
        const n = String(name).trim().toLowerCase();
        if (reachedSet.has(n)) return true;
        for (const r of reachedSet) {
            if (r.length > 2 && (n === r || n.includes(r) || r.includes(n))) return true;
        }
        return false;
    };

    const orderedStops = tripType === 'dropoff' ? [...stops].reverse() : [...stops];
    // Use actual broadcast speed with 8 km/h floor (crawling traffic) and 60 km/h ceiling
    const speedKmh = (currentSpeed && currentSpeed >= 8) ? Math.min(currentSpeed, 60) : 25;
    const speedMps = (speedKmh * 1000) / 3600;

    // In dropoff (Campus -> Stops), polyline coordinates must run in reverse direction
    const activeCoords = (tripType === 'dropoff' && coordinates && coordinates.length > 10)
        ? [...coordinates].reverse()
        : coordinates;

    // If we have a high-resolution road polyline
    if (activeCoords && activeCoords.length > 10) {
        const busNearest = findNearestCoordIndex(busLat, busLng, activeCoords);
        const busIdx = busNearest.index;

        // Map each stop to its nearest point along the route polyline
        const stopsWithIndex = orderedStops.map((stop, origIndex) => {
            if (!stop.lat || !stop.lng) return { stop, index: -1, origIndex };
            const n = findNearestCoordIndex(stop.lat, stop.lng, activeCoords);
            return { stop, index: n.index, origIndex };
        });

        const upcomingETAs = [];
        let intermediateStopCount = 0;
        let nextStopName = '';

        for (const item of stopsWithIndex) {
            if (item.index === -1) continue;

            // Skip if stop has already been reached by the bus
            if (isStopPassed(item.stop.name)) continue;

            // Stop is upcoming if it lies ahead of the bus (with 5-point grace threshold ~100m for current stop)
            if (item.index >= busIdx - 5) {
                const distMeters = measurePolylineDistanceMeters(activeCoords, busIdx, item.index);
                const dwellTimeSec = intermediateStopCount * 30; // 30 seconds boarding dwell per intermediate stop
                const travelTimeSec = (distMeters / speedMps) + dwellTimeSec;
                const minutes = Math.max(1, Math.round(travelTimeSec / 60));

                if (!nextStopName) {
                    nextStopName = item.stop.name;
                }

                upcomingETAs.push({
                    name: item.stop.name,
                    stopName: item.stop.name,
                    minutes: minutes,
                    distanceKm: (distMeters / 1000).toFixed(1),
                    lat: item.stop.lat,
                    lng: item.stop.lng
                });

                intermediateStopCount++;
            }
        }

        // If all stops appear behind (e.g. bus is at end of route), keep the last stop
        if (upcomingETAs.length === 0 && orderedStops.length > 0) {
            const lastStop = orderedStops[orderedStops.length - 1];
            upcomingETAs.push({
                name: lastStop.name,
                stopName: lastStop.name,
                minutes: 1,
                distanceKm: '0.1',
                lat: lastStop.lat,
                lng: lastStop.lng
            });
            nextStopName = lastStop.name;
        }

        return {
            etas: upcomingETAs,
            nextStopName: nextStopName || (upcomingETAs[0] ? upcomingETAs[0].stopName : ''),
            busPolylineIndex: busIdx
        };
    }

    // Fallback if coordinates are not available: sequential stops model
    let cumulativeMins = 0;
    let prevLat = busLat;
    let prevLng = busLng;
    const fallbackETAs = [];

    for (let i = 0; i < orderedStops.length; i++) {
        const stop = orderedStops[i];
        if (!stop.lat || !stop.lng) continue;

        // Skip already reached stops in fallback mode too
        if (isStopPassed(stop.name)) continue;

        const dM = haversineDistMeters(prevLat, prevLng, stop.lat, stop.lng);
        // Avoid unrealistic leaps if stop has far-away coordinates (> 6km inside city)
        const effectiveDistM = dM > 7000 ? 900 : dM;
        const roadDistKm = (effectiveDistM * 1.5) / 1000.0; // 1.5× for Indian road curvature
        const legMins = Math.max(1, Math.round((roadDistKm / speedKmh) * 60));
        cumulativeMins += legMins;
        if (fallbackETAs.length > 0) cumulativeMins += 0.5; // 30s dwell per intermediate stop

        fallbackETAs.push({
            name: stop.name,
            stopName: stop.name,
            minutes: Math.max(1, Math.round(cumulativeMins)),
            distanceKm: (roadDistKm).toFixed(1),
            lat: stop.lat,
            lng: stop.lng
        });
        prevLat = stop.lat;
        prevLng = stop.lng;
    }

    return {
        etas: fallbackETAs,
        nextStopName: fallbackETAs[0] ? fallbackETAs[0].stopName : '',
        busPolylineIndex: 0
    };
}

module.exports = {
    getRoadPolylineForStops,
    snapPointsToGoogleRoads,
    decodePolyline,
    haversineDistMeters,
    findNearestCoordIndex,
    measurePolylineDistanceMeters,
    queryOSRMPointToPoint,
    calculateAccurateETA,
    computeRouteProgressAndETAs
};
