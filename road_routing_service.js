/**
 * road_routing_service.js
 * Generates high-resolution, road-following driving polyline coordinates
 * for college transit routes using OSRM (Open Source Routing Machine) with
 * graceful waypoint segmentation and interpolation fallbacks.
 */

const https = require('https');

/**
 * Fetch road polyline between an array of stops [{ lat, lng, name }, ...]
 * Returns { distanceKm, durationMins, coordinates: [{ latitude, longitude }] }
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

    // Attempt 1: Full multi-waypoint route in a single call
    try {
        const fullResult = await queryOSRM(validStops);
        if (fullResult && fullResult.coordinates && fullResult.coordinates.length > 0) {
            return fullResult;
        }
    } catch (e) {
        console.warn('   ⚠️ Full OSRM routing warning:', e.message);
    }

    // Attempt 2: Segment-by-segment routing for long routes with many stops
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
                // Direct line fallback for this single segment
                if (i === 0) allCoords.push({ latitude: validStops[i].lat, longitude: validStops[i].lng });
                allCoords.push({ latitude: validStops[i + 1].lat, longitude: validStops[i + 1].lng });
            }

            // Brief throttle between rapid requests
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
                } catch (err) {
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

module.exports = {
    getRoadPolylineForStops
};
