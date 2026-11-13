/**
 * journey_analytics_service.js
 * Pure, deterministic GPS journey reconstruction & telemetry analytics engine (Phase 3).
 *
 * Input:  { liveTripLog, telemetryPoints, route, options }
 * Output: Deterministic enriched journey analytics object with explicit provenance.
 *
 * Rules:
 * - Read-only and side-effect free: never writes to MongoDB, mutates inputs, or emits Socket.IO events.
 * - Never fabricates missing GPS data or overwrites actual values with scheduled values.
 * - Reuses haversineMeters, getIstDateString, and parseTimeMinutes from telemetry_persistence_service.js.
 */

const { haversineMeters, getIstDateString, parseTimeMinutes } = require('./telemetry_persistence_service');

const DEFAULT_MOVEMENT_MIN_SPEED_KMH = 5;
const DEFAULT_MOVEMENT_MIN_SAMPLES = 2;
const DEFAULT_STOP_RADIUS_METERS = 120;
const DEFAULT_STOP_EXIT_RADIUS_METERS = 150;
const DEFAULT_MIN_ARRIVAL_SAMPLES = 2;
const DEFAULT_MIN_EXIT_SAMPLES = 2;
const DEFAULT_GPS_GAP_THRESHOLD_SECONDS = 45;

const MAX_VALID_SPEED_KMH = 200;
const MAX_VALID_ACCURACY_METERS = 5000;

function round2(val) {
    if (val === null || val === undefined || !Number.isFinite(val)) return null;
    return Math.round(val * 100) / 100;
}

/**
 * Resolves a "HH:MM AM/PM" schedule string on a given IST YYYY-MM-DD date
 * into an exact UTC Date representing that IST wall-clock time (+05:30).
 */
function resolveIstScheduleDate(istDateStr, timeStr) {
    if (!istDateStr || !timeStr) return null;
    const match = String(istDateStr).trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!match) return null;
    const mins = parseTimeMinutes(timeStr);
    if (mins === null) return null;

    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const hours = Math.floor(mins / 60);
    const minutes = mins % 60;

    // IST is UTC+05:30 (330 minutes ahead of UTC)
    const utcMs = Date.UTC(year, month - 1, day, hours, minutes, 0, 0) - (330 * 60 * 1000);
    return new Date(utcMs);
}

/**
 * Validates and classifies raw TripTelemetryPoint records into chronological VALID points
 * and counted INVALID samples. Duplicate timestamps are rejected to preserve strict monotonicity.
 */
function validateAndSortTelemetry(telemetryPoints) {
    const list = Array.isArray(telemetryPoints) ? telemetryPoints : [];
    const totalSamples = list.length;
    const preValid = [];
    let invalidSamples = 0;

    for (const raw of list) {
        if (!raw || typeof raw !== 'object') {
            invalidSamples++;
            continue;
        }

        const lat = Number(raw.lat);
        const lng = Number(raw.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            invalidSamples++;
            continue;
        }
        if (lat === 0 && lng === 0) {
            invalidSamples++;
            continue;
        }

        const ts = raw.timestamp instanceof Date ? raw.timestamp : new Date(raw.timestamp);
        if (!raw.timestamp || Number.isNaN(ts.getTime())) {
            invalidSamples++;
            continue;
        }

        let speed = null;
        if (raw.speed !== undefined && raw.speed !== null && raw.speed !== '') {
            const parsedSpeed = Number(raw.speed);
            if (!Number.isFinite(parsedSpeed) || parsedSpeed < 0 || parsedSpeed > MAX_VALID_SPEED_KMH) {
                invalidSamples++;
                continue;
            }
            speed = parsedSpeed;
        }

        let heading = null;
        if (raw.heading !== undefined && raw.heading !== null && raw.heading !== '') {
            const parsedHeading = Number(raw.heading);
            if (!Number.isFinite(parsedHeading) || parsedHeading < 0 || parsedHeading > 360) {
                invalidSamples++;
                continue;
            }
            heading = parsedHeading;
        }

        let accuracy = null;
        if (raw.accuracy !== undefined && raw.accuracy !== null && raw.accuracy !== '') {
            const parsedAcc = Number(raw.accuracy);
            if (!Number.isFinite(parsedAcc) || parsedAcc < 0 || parsedAcc > MAX_VALID_ACCURACY_METERS) {
                invalidSamples++;
                continue;
            }
            accuracy = parsedAcc;
        }

        preValid.push({
            lat,
            lng,
            speed,
            heading,
            accuracy,
            timestamp: ts,
            tsMs: ts.getTime()
        });
    }

    // Sort chronologically
    preValid.sort((a, b) => a.tsMs - b.tsMs);

    // Enforce strict monotonicity (reject duplicate timestamps)
    const validPoints = [];
    for (const pt of preValid) {
        if (validPoints.length > 0 && pt.tsMs === validPoints[validPoints.length - 1].tsMs) {
            invalidSamples++;
            continue;
        }
        validPoints.push(pt);
    }

    return {
        totalSamples,
        validSamples: validPoints.length,
        invalidSamples,
        validPoints
    };
}

/**
 * Computes effective speed (km/h) for a valid point at index i:
 * prefers explicit point.speed, falls back to derived segment speed from i-1 -> i.
 */
function getEffectiveSpeedKmh(validPoints, idx) {
    const pt = validPoints[idx];
    if (pt.speed !== null && Number.isFinite(pt.speed)) {
        return pt.speed;
    }
    if (idx <= 0) return null;
    const prev = validPoints[idx - 1];
    const dtHours = (pt.tsMs - prev.tsMs) / 3600000;
    if (dtHours <= 0) return null;
    const distKm = haversineMeters(prev.lat, prev.lng, pt.lat, pt.lng) / 1000;
    const derived = distKm / dtHours;
    return Number.isFinite(derived) && derived <= MAX_VALID_SPEED_KMH ? derived : null;
}

/**
 * Movement Start Rule:
 * Requires >= movementMinSamples (default 2) consecutive valid points with effective speed >= movementMinSpeedKmh (default 5 km/h).
 * Returns the FIRST point of that consecutive moving sequence.
 */
function detectMovementStart(validPoints, minSpeedKmh, minSamples) {
    if (validPoints.length < minSamples) {
        return {
            movementStartTimestamp: null,
            movementStartLat: null,
            movementStartLng: null,
            movementStartStatus: 'INSUFFICIENT GPS DATA'
        };
    }

    let streakStartIdx = -1;
    let streakLen = 0;

    for (let i = 0; i < validPoints.length; i++) {
        const effSpeed = getEffectiveSpeedKmh(validPoints, i);
        if (effSpeed !== null && effSpeed >= minSpeedKmh) {
            if (streakStartIdx === -1) streakStartIdx = i;
            streakLen++;
            if (streakLen >= minSamples) {
                const startPt = validPoints[streakStartIdx];
                return {
                    movementStartTimestamp: startPt.timestamp,
                    movementStartLat: startPt.lat,
                    movementStartLng: startPt.lng,
                    movementStartStatus: 'CALCULATED'
                };
            }
        } else {
            streakStartIdx = -1;
            streakLen = 0;
        }
    }

    return {
        movementStartTimestamp: null,
        movementStartLat: null,
        movementStartLng: null,
        movementStartStatus: 'INSUFFICIENT GPS DATA'
    };
}

/**
 * Computes GPS quality metrics and detects gaps (> gpsGapThresholdSeconds).
 */
function computeGpsQuality(validPoints, totalSamples, invalidSamples, gapThresholdSeconds) {
    const validSamples = validPoints.length;
    if (validSamples === 0) {
        return {
            totalSamples,
            validSamples: 0,
            invalidSamples,
            firstGpsTimestamp: null,
            lastGpsTimestamp: null,
            coverageDurationMinutes: 0,
            averageSamplingIntervalSeconds: null,
            minimumSamplingIntervalSeconds: null,
            maximumSamplingIntervalSeconds: null,
            gpsGapCount: 0,
            longestGpsGapSeconds: null,
            longestGapStart: null,
            longestGapEnd: null,
            gaps: [],
            gapStatus: 'INSUFFICIENT GPS DATA',
            accuracyAvailable: false,
            averageAccuracyMeters: null,
            minimumAccuracyMeters: null,
            maximumAccuracyMeters: null,
            telemetryCompletenessPercent: null
        };
    }

    const firstPt = validPoints[0];
    const lastPt = validPoints[validPoints.length - 1];

    const accuracies = validPoints.map(p => p.accuracy).filter(a => a !== null && Number.isFinite(a));
    const accuracyAvailable = accuracies.length > 0;
    const averageAccuracyMeters = accuracyAvailable ? round2(accuracies.reduce((s, a) => s + a, 0) / accuracies.length) : null;
    const minimumAccuracyMeters = accuracyAvailable ? round2(Math.min(...accuracies)) : null;
    const maximumAccuracyMeters = accuracyAvailable ? round2(Math.max(...accuracies)) : null;

    if (validSamples < 2) {
        return {
            totalSamples,
            validSamples,
            invalidSamples,
            firstGpsTimestamp: firstPt.timestamp,
            lastGpsTimestamp: lastPt.timestamp,
            coverageDurationMinutes: 0,
            averageSamplingIntervalSeconds: null,
            minimumSamplingIntervalSeconds: null,
            maximumSamplingIntervalSeconds: null,
            gpsGapCount: 0,
            longestGpsGapSeconds: null,
            longestGapStart: null,
            longestGapEnd: null,
            gaps: [],
            gapStatus: 'INSUFFICIENT GPS DATA',
            accuracyAvailable,
            averageAccuracyMeters,
            minimumAccuracyMeters,
            maximumAccuracyMeters,
            telemetryCompletenessPercent: null
        };
    }

    const intervalsSec = [];
    const gaps = [];
    let totalGapSeconds = 0;

    for (let i = 1; i < validPoints.length; i++) {
        const dtSec = (validPoints[i].tsMs - validPoints[i - 1].tsMs) / 1000;
        intervalsSec.push(dtSec);
        if (dtSec > gapThresholdSeconds) {
            totalGapSeconds += dtSec;
            gaps.push({
                gapStart: validPoints[i - 1].timestamp,
                gapEnd: validPoints[i].timestamp,
                gapDurationSeconds: round2(dtSec)
            });
        }
    }

    const coverageSeconds = (lastPt.tsMs - firstPt.tsMs) / 1000;
    const coverageDurationMinutes = round2(coverageSeconds / 60);
    const avgInterval = round2(intervalsSec.reduce((s, x) => s + x, 0) / intervalsSec.length);
    const minInterval = round2(Math.min(...intervalsSec));
    const maxInterval = round2(Math.max(...intervalsSec));

    let longestGap = null;
    for (const g of gaps) {
        if (!longestGap || g.gapDurationSeconds > longestGap.gapDurationSeconds) {
            longestGap = g;
        }
    }

    // Completeness formula: 1 - (total gap duration / telemetry coverage duration)
    const rawCompleteness = coverageSeconds > 0
        ? Math.max(0, Math.min(1, 1 - (totalGapSeconds / coverageSeconds))) * 100
        : null;

    return {
        totalSamples,
        validSamples,
        invalidSamples,
        firstGpsTimestamp: firstPt.timestamp,
        lastGpsTimestamp: lastPt.timestamp,
        coverageDurationMinutes,
        averageSamplingIntervalSeconds: avgInterval,
        minimumSamplingIntervalSeconds: minInterval,
        maximumSamplingIntervalSeconds: maxInterval,
        gpsGapCount: gaps.length,
        longestGpsGapSeconds: longestGap ? longestGap.gapDurationSeconds : 0,
        longestGapStart: longestGap ? longestGap.gapStart : null,
        longestGapEnd: longestGap ? longestGap.gapEnd : null,
        gaps,
        gapStatus: 'CALCULATED',
        accuracyAvailable,
        averageAccuracyMeters,
        minimumAccuracyMeters,
        maximumAccuracyMeters,
        telemetryCompletenessPercent: round2(rawCompleteness)
    };
}

/**
 * Reconstructs ordered route stops from valid telemetry using geofence arrival/departure rules.
 */
function reconstructStops({
    orderedStops,
    tripType,
    validPoints,
    gpsQuality,
    istTripDate,
    stopRadiusMeters,
    stopExitRadiusMeters,
    minArrivalSamples,
    minExitSamples,
    gapThresholdSeconds
}) {
    if (!Array.isArray(orderedStops) || orderedStops.length === 0) {
        return [];
    }

    const results = [];
    let searchStartIdx = 0;

    // Pass 1: Detect arrivals and departures sequentially along the route
    for (let sIdx = 0; sIdx < orderedStops.length; sIdx++) {
        const st = orderedStops[sIdx];
        const stopName = st.name || `Stop ${sIdx + 1}`;
        const stopId = st._id ? st._id.toString() : null;
        const lat = st.lat ?? st.latitude ?? null;
        const lng = st.lng ?? st.longitude ?? null;
        const hasCoords = lat !== null && lng !== null && Number.isFinite(Number(lat)) && Number.isFinite(Number(lng));

        const scheduledTimeStr = tripType === 'pickup' ? (st.time || null) : null;
        const scheduledDate = scheduledTimeStr ? resolveIstScheduleDate(istTripDate, scheduledTimeStr) : null;

        if (!hasCoords) {
            results.push({
                stopSequence: sIdx + 1,
                stopId,
                stopName,
                latitude: null,
                longitude: null,
                scheduledArrival: scheduledDate,
                scheduledDeparture: scheduledDate,
                actualArrival: null,
                actualDeparture: null,
                arrivalVarianceMinutes: null,
                departureVarianceMinutes: null,
                dwellMinutes: null,
                dwellStatus: 'INSUFFICIENT GPS DATA',
                status: 'UNRECORDED',
                detectionSource: 'NO STOP COORDINATES',
                confidence: 0,
                _arrivalIdx: null,
                _departureIdx: null
            });
            continue;
        }

        const stopLat = Number(lat);
        const stopLng = Number(lng);

        if (validPoints.length === 0) {
            results.push({
                stopSequence: sIdx + 1,
                stopId,
                stopName,
                latitude: stopLat,
                longitude: stopLng,
                scheduledArrival: scheduledDate,
                scheduledDeparture: scheduledDate,
                actualArrival: null,
                actualDeparture: null,
                arrivalVarianceMinutes: null,
                departureVarianceMinutes: null,
                dwellMinutes: null,
                dwellStatus: 'INSUFFICIENT GPS DATA',
                status: 'NO GPS DATA',
                detectionSource: 'NO TELEMETRY',
                confidence: 0,
                _arrivalIdx: null,
                _departureIdx: null
            });
            continue;
        }

        // Look for >= minArrivalSamples consecutive points within stopRadiusMeters with timestamp continuity
        let arrivalIdx = null;
        let streak = 0;
        let streakStart = -1;

        for (let i = searchStartIdx; i < validPoints.length; i++) {
            const dist = haversineMeters(validPoints[i].lat, validPoints[i].lng, stopLat, stopLng);
            const continuous = streak === 0 || ((validPoints[i].tsMs - validPoints[i - 1].tsMs) / 1000) <= gapThresholdSeconds;

            if (dist <= stopRadiusMeters) {
                if (streak === 0 || !continuous) {
                    streakStart = i;
                    streak = 1;
                } else {
                    streak++;
                }
                if (streak >= minArrivalSamples) {
                    arrivalIdx = streakStart;
                    break;
                }
            } else {
                streak = 0;
                streakStart = -1;
            }
        }

        if (arrivalIdx === null) {
            results.push({
                stopSequence: sIdx + 1,
                stopId,
                stopName,
                latitude: stopLat,
                longitude: stopLng,
                scheduledArrival: scheduledDate,
                scheduledDeparture: scheduledDate,
                actualArrival: null,
                actualDeparture: null,
                arrivalVarianceMinutes: null,
                departureVarianceMinutes: null,
                dwellMinutes: null,
                dwellStatus: 'INSUFFICIENT GPS DATA',
                status: 'UNRECORDED', // Refined in Pass 2 (MISSED vs UNRECORDED)
                detectionSource: 'PENDING_CLASSIFICATION',
                confidence: 0,
                _arrivalIdx: null,
                _departureIdx: null
            });
            continue;
        }

        // Detect departure: first point after arrival where bus leaves stopExitRadiusMeters
        // for >= minExitSamples consecutive points (or single clear exit at end)
        let departureIdx = null;
        let exitStreak = 0;
        let exitStart = -1;

        for (let i = arrivalIdx + 1; i < validPoints.length; i++) {
            const dist = haversineMeters(validPoints[i].lat, validPoints[i].lng, stopLat, stopLng);
            if (dist > stopExitRadiusMeters) {
                if (exitStreak === 0) exitStart = i;
                exitStreak++;
                if (exitStreak >= minExitSamples) {
                    departureIdx = exitStart;
                    break;
                }
            } else {
                exitStreak = 0;
                exitStart = -1;
            }
        }

        const actualArrival = validPoints[arrivalIdx].timestamp;
        const actualDeparture = departureIdx !== null ? validPoints[departureIdx].timestamp : null;

        let dwellMinutes = null;
        let dwellStatus = 'INSUFFICIENT GPS DATA';
        if (actualArrival && actualDeparture) {
            dwellMinutes = round2(Math.max(0, (actualDeparture.getTime() - actualArrival.getTime()) / 60000));
            dwellStatus = 'CALCULATED';
        }

        const arrivalVarianceMinutes = (actualArrival && scheduledDate)
            ? Math.round((actualArrival.getTime() - scheduledDate.getTime()) / 60000)
            : null;
        const departureVarianceMinutes = (actualDeparture && scheduledDate)
            ? Math.round((actualDeparture.getTime() - scheduledDate.getTime()) / 60000)
            : null;

        searchStartIdx = departureIdx !== null ? departureIdx : arrivalIdx + 1;

        results.push({
            stopSequence: sIdx + 1,
            stopId,
            stopName,
            latitude: stopLat,
            longitude: stopLng,
            scheduledArrival: scheduledDate,
            scheduledDeparture: scheduledDate,
            actualArrival,
            actualDeparture,
            arrivalVarianceMinutes,
            departureVarianceMinutes,
            dwellMinutes,
            dwellStatus,
            status: 'REACHED',
            detectionSource: 'GPS_GEOFENCE',
            confidence: 0.9,
            _arrivalIdx: arrivalIdx,
            _departureIdx: departureIdx
        });
    }

    // Pass 2: Distinguish MISSED vs UNRECORDED for unreached stops that have coordinates
    for (let i = 0; i < results.length; i++) {
        const cur = results[i];
        if (cur.status !== 'UNRECORDED' || cur.detectionSource !== 'PENDING_CLASSIFICATION') {
            continue;
        }

        if (validPoints.length < 2) {
            cur.status = 'UNRECORDED';
            cur.detectionSource = 'INSUFFICIENT_TELEMETRY';
            continue;
        }

        // Find bounding timestamps around this stop from adjacent reached stops or trip start/end
        let prevIdx = 0;
        for (let p = i - 1; p >= 0; p--) {
            if (results[p]._departureIdx !== null) {
                prevIdx = results[p]._departureIdx;
                break;
            }
            if (results[p]._arrivalIdx !== null) {
                prevIdx = results[p]._arrivalIdx;
                break;
            }
        }

        let nextIdx = null;
        for (let n = i + 1; n < results.length; n++) {
            if (results[n]._arrivalIdx !== null) {
                nextIdx = results[n]._arrivalIdx;
                break;
            }
        }

        // If a later stop was reached, check whether there was a GPS gap between prevIdx and nextIdx
        if (nextIdx !== null) {
            const winStartMs = validPoints[prevIdx].tsMs;
            const winEndMs = validPoints[nextIdx].tsMs;
            const hasGapInWindow = gpsQuality.gaps.some(g => {
                const gs = g.gapStart.getTime();
                const ge = g.gapEnd.getTime();
                return gs < winEndMs && ge > winStartMs;
            });

            if (hasGapInWindow) {
                cur.status = 'UNRECORDED';
                cur.detectionSource = 'GPS_GAP';
            } else {
                cur.status = 'MISSED';
                cur.detectionSource = 'GPS_BYPASSED';
                cur.confidence = 0.85;
            }
        } else {
            // No later stop was reached: check if GPS ended early or if vehicle passed near/past the stop
            cur.status = 'UNRECORDED';
            cur.detectionSource = 'INSUFFICIENT_COVERAGE';
        }
    }

    return results;
}

/**
 * Reconstructs inter-stop travel segments for consecutive stop pairs.
 */
function reconstructSegments(stops, validPoints) {
    if (!Array.isArray(stops) || stops.length < 2) {
        return [];
    }

    const segments = [];
    for (let i = 0; i < stops.length - 1; i++) {
        const fromStop = stops[i];
        const toStop = stops[i + 1];

        const actualDeparture = fromStop.actualDeparture || null;
        const actualArrival = toStop.actualArrival || null;
        const scheduledTravelDurationMinutes = (fromStop.scheduledDeparture && toStop.scheduledArrival)
            ? round2((toStop.scheduledArrival.getTime() - fromStop.scheduledDeparture.getTime()) / 60000)
            : null;

        if (actualDeparture && actualArrival && actualArrival.getTime() >= actualDeparture.getTime()) {
            const travelDurationMinutes = round2((actualArrival.getTime() - actualDeparture.getTime()) / 60000);
            const segPts = validPoints.filter(
                p => p.tsMs >= actualDeparture.getTime() && p.tsMs <= actualArrival.getTime()
            );

            let distanceKm = null;
            let distanceSource = 'INSUFFICIENT GPS DATA';
            if (segPts.length >= 2) {
                let meters = 0;
                for (let k = 1; k < segPts.length; k++) {
                    meters += haversineMeters(segPts[k - 1].lat, segPts[k - 1].lng, segPts[k].lat, segPts[k].lng);
                }
                distanceKm = round2(meters / 1000);
                distanceSource = 'GPS';
            }

            const averageSpeedKmh = (distanceKm !== null && travelDurationMinutes > 0)
                ? round2(distanceKm / (travelDurationMinutes / 60))
                : null;

            const varianceMinutes = (travelDurationMinutes !== null && scheduledTravelDurationMinutes !== null)
                ? Math.round(travelDurationMinutes - scheduledTravelDurationMinutes)
                : null;

            segments.push({
                segmentSequence: i + 1,
                fromStop: fromStop.stopName,
                toStop: toStop.stopName,
                fromStopId: fromStop.stopId,
                toStopId: toStop.stopId,
                actualDeparture,
                actualArrival,
                travelDurationMinutes,
                distanceKm,
                distanceSource,
                averageSpeedKmh,
                scheduledTravelDurationMinutes,
                varianceMinutes,
                status: 'COMPLETED'
            });
        } else if (actualDeparture || actualArrival) {
            segments.push({
                segmentSequence: i + 1,
                fromStop: fromStop.stopName,
                toStop: toStop.stopName,
                fromStopId: fromStop.stopId,
                toStopId: toStop.stopId,
                actualDeparture,
                actualArrival,
                travelDurationMinutes: null,
                distanceKm: null,
                distanceSource: 'INSUFFICIENT GPS DATA',
                averageSpeedKmh: null,
                scheduledTravelDurationMinutes,
                varianceMinutes: null,
                status: 'PARTIAL'
            });
        } else {
            segments.push({
                segmentSequence: i + 1,
                fromStop: fromStop.stopName,
                toStop: toStop.stopName,
                fromStopId: fromStop.stopId,
                toStopId: toStop.stopId,
                actualDeparture: null,
                actualArrival: null,
                travelDurationMinutes: null,
                distanceKm: null,
                distanceSource: 'INSUFFICIENT GPS DATA',
                averageSpeedKmh: null,
                scheduledTravelDurationMinutes,
                varianceMinutes: null,
                status: 'NO GPS DATA'
            });
        }
    }

    return segments;
}

/**
 * Pure deterministic journey reconstruction from (liveTripLog, telemetryPoints, route).
 */
function analyzeJourney({ liveTripLog = null, telemetryPoints = [], route = null, options = {} }) {
    const movementMinSpeedKmh = options.movementMinSpeedKmh ?? DEFAULT_MOVEMENT_MIN_SPEED_KMH;
    const movementMinSamples = options.movementMinSamples ?? DEFAULT_MOVEMENT_MIN_SAMPLES;
    const stopRadiusMeters = options.stopRadiusMeters ?? DEFAULT_STOP_RADIUS_METERS;
    const stopExitRadiusMeters = options.stopExitRadiusMeters ?? DEFAULT_STOP_EXIT_RADIUS_METERS;
    const minArrivalSamples = options.minArrivalSamples ?? DEFAULT_MIN_ARRIVAL_SAMPLES;
    const minExitSamples = options.minExitSamples ?? DEFAULT_MIN_EXIT_SAMPLES;
    const gapThresholdSeconds = options.gapThresholdSeconds ?? DEFAULT_GPS_GAP_THRESHOLD_SECONDS;

    const tripId = liveTripLog && liveTripLog._id ? liveTripLog._id.toString() : null;
    const busId = liveTripLog?.busId ? String(liveTripLog.busId) : null;
    const busNumber = liveTripLog?.busNumber || 'N/A';
    const routeId = liveTripLog?.routeId?.toString() || route?._id?.toString() || null;
    const routeName = liveTripLog?.routeName || route?.name || 'Unassigned';
    const tripType = liveTripLog?.tripType === 'dropoff' ? 'dropoff' : 'pickup';
    const direction = tripType === 'dropoff' ? 'campus -> stops' : 'stops -> campus';

    const { totalSamples, validSamples, invalidSamples, validPoints } = validateAndSortTelemetry(telemetryPoints);

    const firstPt = validPoints.length > 0 ? validPoints[0] : null;
    const lastPt = validPoints.length > 0 ? validPoints[validPoints.length - 1] : null;

    const firstGpsTimestamp = firstPt ? firstPt.timestamp : null;
    const firstGpsLat = firstPt ? firstPt.lat : null;
    const firstGpsLng = firstPt ? firstPt.lng : null;

    const lastGpsTimestamp = lastPt ? lastPt.timestamp : null;
    const lastGpsLat = lastPt ? lastPt.lat : null;
    const lastGpsLng = lastPt ? lastPt.lng : null;

    const movement = detectMovementStart(validPoints, movementMinSpeedKmh, movementMinSamples);

    const logEndTime = liveTripLog?.endTime ? new Date(liveTripLog.endTime) : null;
    const hasValidLogEnd = logEndTime && !Number.isNaN(logEndTime.getTime());

    let tripEndTimestamp = null;
    let tripEndSource = 'NO DATA';
    if (hasValidLogEnd) {
        tripEndTimestamp = logEndTime;
        tripEndSource = 'LIVE_TRIP_LOG';
    } else if (lastGpsTimestamp) {
        tripEndTimestamp = lastGpsTimestamp;
        tripEndSource = 'LAST_GPS';
    }

    const gpsQuality = computeGpsQuality(validPoints, totalSamples, invalidSamples, gapThresholdSeconds);

    // Resolve IST trip date from liveTripLog.date or startTime/firstGpsTimestamp (cross-midnight safe)
    const refStart = liveTripLog?.startTime ? new Date(liveTripLog.startTime) : firstGpsTimestamp;
    const istTripDate = (liveTripLog?.date && /^\d{4}-\d{2}-\d{2}$/.test(liveTripLog.date))
        ? liveTripLog.date
        : (refStart ? getIstDateString(refStart) : null);

    const rawStops = Array.isArray(route?.stops) ? route.stops : [];
    const orderedStops = tripType === 'dropoff' ? [...rawStops].reverse() : [...rawStops];

    const stopsInternal = reconstructStops({
        orderedStops,
        tripType,
        validPoints,
        gpsQuality,
        istTripDate,
        stopRadiusMeters,
        stopExitRadiusMeters,
        minArrivalSamples,
        minExitSamples,
        gapThresholdSeconds
    });

    const segments = reconstructSegments(stopsInternal, validPoints);

    // Strip internal indices from public stops array
    const stops = stopsInternal.map(({ _arrivalIdx, _departureIdx, ...pub }) => pub);

    // Total GPS distance & speed analytics
    let distanceKm = null;
    let distanceSource = 'INSUFFICIENT GPS DATA';
    let drivingSeconds = 0;
    let stationarySeconds = 0;
    const speeds = [];

    if (validSamples >= 2) {
        let totalMeters = 0;
        for (let i = 1; i < validPoints.length; i++) {
            const dtSec = (validPoints[i].tsMs - validPoints[i - 1].tsMs) / 1000;
            const segMeters = haversineMeters(validPoints[i - 1].lat, validPoints[i - 1].lng, validPoints[i].lat, validPoints[i].lng);
            totalMeters += segMeters;

            const effSpeed = getEffectiveSpeedKmh(validPoints, i);
            if (effSpeed !== null) {
                speeds.push(effSpeed);
            }

            if (dtSec <= gapThresholdSeconds) {
                if (effSpeed !== null && effSpeed >= movementMinSpeedKmh) {
                    drivingSeconds += dtSec;
                } else {
                    stationarySeconds += dtSec;
                }
            }
        }
        distanceKm = round2(totalMeters / 1000);
        distanceSource = 'GPS';
    } else if (validSamples === 1 && validPoints[0].speed !== null) {
        speeds.push(validPoints[0].speed);
    }

    const totalDurationAnchor = movement.movementStartTimestamp || firstGpsTimestamp || (liveTripLog?.startTime ? new Date(liveTripLog.startTime) : null);
    const totalDurationMinutes = (totalDurationAnchor && tripEndTimestamp && tripEndTimestamp.getTime() >= totalDurationAnchor.getTime())
        ? round2((tripEndTimestamp.getTime() - totalDurationAnchor.getTime()) / 60000)
        : null;

    const drivingDurationMinutes = validSamples >= 2 ? round2(drivingSeconds / 60) : null;
    const stationaryDurationMinutes = validSamples >= 2 ? round2(stationarySeconds / 60) : null;

    const averageSpeedKmh = (distanceKm !== null && totalDurationMinutes !== null && totalDurationMinutes > 0)
        ? round2(distanceKm / (totalDurationMinutes / 60))
        : (speeds.length > 0 ? round2(speeds.reduce((s, x) => s + x, 0) / speeds.length) : null);
    const minimumSpeedKmh = speeds.length > 0 ? round2(Math.min(...speeds)) : null;
    const maximumSpeedKmh = speeds.length > 0 ? round2(Math.max(...speeds)) : null;

    // Stop & dwell aggregates
    const stopCount = stops.length;
    const reachedStopCount = stops.filter(s => s.status === 'REACHED').length;
    const missedStopCount = stops.filter(s => s.status === 'MISSED').length;
    const unrecordedStopCount = stops.filter(s => s.status === 'UNRECORDED' || s.status === 'NO GPS DATA').length;

    const calculatedDwells = stops.map(s => s.dwellMinutes).filter(d => d !== null);
    const averageDwellMinutes = calculatedDwells.length > 0
        ? round2(calculatedDwells.reduce((s, d) => s + d, 0) / calculatedDwells.length)
        : null;
    const longestDwellMinutes = calculatedDwells.length > 0 ? round2(Math.max(...calculatedDwells)) : null;

    // Segment aggregates
    const completedSegDurations = segments.filter(s => s.status === 'COMPLETED' && s.travelDurationMinutes !== null).map(s => s.travelDurationMinutes);
    const averageSegmentTravelMinutes = completedSegDurations.length > 0
        ? round2(completedSegDurations.reduce((s, d) => s + d, 0) / completedSegDurations.length)
        : null;
    const longestSegmentTravelMinutes = completedSegDurations.length > 0 ? round2(Math.max(...completedSegDurations)) : null;
    const shortestSegmentTravelMinutes = completedSegDurations.length > 0 ? round2(Math.min(...completedSegDurations)) : null;

    // Delay aggregates
    const delays = stops.map(s => s.arrivalVarianceMinutes).filter(v => v !== null);
    const averageDelayMinutes = delays.length > 0
        ? round2(delays.reduce((s, d) => s + d, 0) / delays.length)
        : null;
    const maximumDelayMinutes = delays.length > 0 ? Math.max(...delays) : null;

    // Complete ordered timeline
    const timeline = [];
    if (firstGpsTimestamp) {
        timeline.push({ timestamp: firstGpsTimestamp, eventType: 'GPS_START', stopId: null, stopName: null, source: 'GPS', confidence: 1 });
    }
    if (movement.movementStartTimestamp) {
        timeline.push({ timestamp: movement.movementStartTimestamp, eventType: 'MOVEMENT_START', stopId: null, stopName: null, source: 'GPS', confidence: 0.9 });
    }
    for (const st of stops) {
        if (st.actualArrival) {
            timeline.push({ timestamp: st.actualArrival, eventType: 'STOP_ARRIVAL', stopId: st.stopId, stopName: st.stopName, source: st.detectionSource, confidence: st.confidence });
        }
        if (st.actualDeparture) {
            timeline.push({ timestamp: st.actualDeparture, eventType: 'STOP_DEPARTURE', stopId: st.stopId, stopName: st.stopName, source: st.detectionSource, confidence: st.confidence });
        }
    }
    for (const seg of segments) {
        if (seg.status === 'COMPLETED') {
            timeline.push({ timestamp: seg.actualDeparture, eventType: 'SEGMENT_START', stopId: seg.fromStopId, stopName: `${seg.fromStop} -> ${seg.toStop}`, source: seg.distanceSource, confidence: 0.9 });
            timeline.push({ timestamp: seg.actualArrival, eventType: 'SEGMENT_END', stopId: seg.toStopId, stopName: `${seg.fromStop} -> ${seg.toStop}`, source: seg.distanceSource, confidence: 0.9 });
        }
    }
    if (tripEndTimestamp) {
        timeline.push({ timestamp: tripEndTimestamp, eventType: 'TRIP_END', stopId: null, stopName: null, source: tripEndSource, confidence: 1 });
    }
    timeline.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    // Telemetry completeness & overall status
    let telemetryStatus = 'EMPTY';
    if (validSamples >= 2) {
        const stoppedEarly = hasValidLogEnd && lastGpsTimestamp && ((logEndTime.getTime() - lastGpsTimestamp.getTime()) / 1000) > gapThresholdSeconds;
        telemetryStatus = (gpsQuality.gpsGapCount > 0 || stoppedEarly) ? 'PARTIAL' : 'COMPLETE';
    } else if (validSamples === 1) {
        telemetryStatus = 'PARTIAL';
    }

    let dataSource = 'NO DATA';
    let analyticsStatus = 'INSUFFICIENT GPS DATA';
    if (validSamples >= 2) {
        dataSource = 'LIVE GPS';
        analyticsStatus = 'CALCULATED FROM GPS';
    } else if (validSamples === 1) {
        dataSource = 'INSUFFICIENT GPS DATA';
        analyticsStatus = 'INSUFFICIENT GPS DATA';
    } else if (liveTripLog && (liveTripLog.startTime || liveTripLog.endTime)) {
        dataSource = 'INSUFFICIENT GPS DATA';
        analyticsStatus = 'CALCULATED FROM TRIP LOG';
    }

    return {
        tripId,
        busId,
        busNumber,
        routeId,
        routeName,
        tripType,
        direction,
        istTripDate,

        firstGpsTimestamp,
        firstGpsLat,
        firstGpsLng,

        movementStartTimestamp: movement.movementStartTimestamp,
        movementStartLat: movement.movementStartLat,
        movementStartLng: movement.movementStartLng,
        movementStartStatus: movement.movementStartStatus,

        lastGpsTimestamp,
        lastGpsLat,
        lastGpsLng,
        tripEndTimestamp,
        tripEndSource,

        totalDurationMinutes,
        drivingDurationMinutes,
        stationaryDurationMinutes,

        distanceKm,
        distanceSource,
        averageSpeedKmh,
        minimumSpeedKmh,
        maximumSpeedKmh,

        stopCount,
        reachedStopCount,
        missedStopCount,
        unrecordedStopCount,

        averageDwellMinutes,
        longestDwellMinutes,

        averageSegmentTravelMinutes,
        longestSegmentTravelMinutes,
        shortestSegmentTravelMinutes,

        averageDelayMinutes,
        maximumDelayMinutes,

        gpsSampleCount: validSamples,
        gpsGapCount: gpsQuality.gpsGapCount,
        longestGpsGapSeconds: gpsQuality.longestGpsGapSeconds,
        telemetryCompletenessPercent: gpsQuality.telemetryCompletenessPercent,

        gpsQuality,
        stops,
        segments,
        timeline,

        telemetryStatus,
        dataSource,
        analyticsStatus
    };
}

module.exports = {
    DEFAULT_MOVEMENT_MIN_SPEED_KMH,
    DEFAULT_MOVEMENT_MIN_SAMPLES,
    DEFAULT_STOP_RADIUS_METERS,
    DEFAULT_STOP_EXIT_RADIUS_METERS,
    DEFAULT_MIN_ARRIVAL_SAMPLES,
    DEFAULT_MIN_EXIT_SAMPLES,
    DEFAULT_GPS_GAP_THRESHOLD_SECONDS,
    analyzeJourney,
    validateAndSortTelemetry,
    detectMovementStart,
    computeGpsQuality,
    reconstructStops,
    reconstructSegments,
    resolveIstScheduleDate
};
