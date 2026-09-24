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

module.exports = {
    getRoadPolylineForStops,
    snapPointsToGoogleRoads,
    decodePolyline
};
