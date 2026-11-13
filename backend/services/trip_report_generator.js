/**
 * trip_report_generator.js
 * Comprehensive 2-Trip (Morning Pickup & Afternoon/Evening Drop-off) Day-Wise Report Generator.
 * Accurately tracks per-bus, per-trip, and per-stop metrics with live GPS telemetry + official timetable synchronization.
 */

const Route = require('../models/Route');
const Bus = require('../models/Bus');
const Driver = require('../models/Driver');
const LiveTripLog = require('../models/LiveTripLog');
const TripTelemetryPoint = require('../models/TripTelemetryPoint');
const { getIstDateString, parseTimeMinutes } = require('./telemetry_persistence_service');
const { analyzeJourney } = require('./journey_analytics_service');
const XLSX = require('xlsx');
const PDFDocument = require('pdfkit');

const DATA_SOURCES = Object.freeze({
    LIVE_GPS: 'LIVE GPS',
    SCHEDULED_ESTIMATED: 'SCHEDULED / ESTIMATED',
    NO_DATA: 'NO DATA',
    INSUFFICIENT_GPS_DATA: 'INSUFFICIENT GPS DATA'
});

const fmtTime = (d) => {
    if (!d) return 'N/A';
    const dt = new Date(d);
    if (isNaN(dt.getTime())) return String(d);
    return dt.toLocaleTimeString('en-IN', {
        timeZone: 'Asia/Kolkata',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    });
};

const fmtDate = (d) => {
    if (!d) return getIstDateString();
    if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d.trim())) {
        return d.trim();
    }
    const dt = new Date(d);
    return isNaN(dt.getTime()) ? String(d).split('T')[0] : getIstDateString(dt);
};

const getDayOfWeek = (dateStr) => {
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const match = typeof dateStr === 'string' && dateStr.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    const d = match
        ? new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12, 0, 0))
        : new Date(dateStr);
    return isNaN(d.getTime()) ? 'Monday' : days[d.getUTCDay()];
};

function formatMinutesToTime(mins) {
    if (mins == null || isNaN(mins)) return '08:45 AM';
    let h = Math.floor(mins / 60) % 24;
    const m = Math.round(mins % 60);
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h === 0) h = 12;
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')} ${ampm}`;
}

function computeHaversineDistanceKm(coords) {
    if (!coords || coords.length < 2) return 0;
    let total = 0;
    for (let i = 0; i < coords.length - 1; i++) {
        const c1 = coords[i];
        const c2 = coords[i + 1];
        const lat1 = (c1.latitude || c1.lat) * Math.PI / 180;
        const lat2 = (c2.latitude || c2.lat) * Math.PI / 180;
        const dLat = ((c2.latitude || c2.lat) - (c1.latitude || c1.lat)) * Math.PI / 180;
        const dLng = ((c2.longitude || c2.lng) - (c1.longitude || c1.lng)) * Math.PI / 180;
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                  Math.cos(lat1) * Math.cos(lat2) *
                  Math.sin(dLng / 2) * Math.sin(dLng / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        total += 6371 * c;
    }
    return total;
}

/**
 * Builds realistic stop timeline for an individual trip
 */
function buildStopTimeline({ stops, tripType, liveLog, defaultStartMins, defaultDurationMins, dateStr }) {
    if (!stops || stops.length === 0) {
        return [];
    }

    const isPickup = tripType === 'pickup';
    const sequenceStops = isPickup ? [...stops] : [...stops].reverse();
    const totalStops = sequenceStops.length;
    const stepMins = totalStops > 1 ? defaultDurationMins / (totalStops - 1) : 0;

    return sequenceStops.map((st, idx) => {
        const stopName = st.name || `Stop ${idx + 1}`;
        
        // Scheduled Time Calculation
        let scheduledTimeStr = st.time;
        if (!isPickup || !scheduledTimeStr) {
            const calculatedMins = defaultStartMins + Math.round(idx * stepMins);
            scheduledTimeStr = formatMinutesToTime(calculatedMins);
        }

        // Live Reached Entry lookup (case-insensitive fuzzy match)
        const reachedEntry = liveLog?.reachedStops?.find(rs => 
            rs.stopName && (
                rs.stopName.toLowerCase().trim() === stopName.toLowerCase().trim() ||
                stopName.toLowerCase().includes(rs.stopName.toLowerCase().trim()) ||
                rs.stopName.toLowerCase().includes(stopName.toLowerCase().trim())
            )
        );

        let actualTimeStr = null;
        let dwellTime = liveLog ? 'Unrecorded' : 'Scheduled';
        let status = liveLog ? 'Not Recorded' : 'Scheduled';
        let delayMinutes = 0;
        let varianceStr = liveLog ? 'Unrecorded' : 'Timetable';

        if (!liveLog) {
            // Scheduled / Estimated trip (no live GPS log recorded for this shift)
            actualTimeStr = null;
            status = 'Scheduled';
            varianceStr = 'Timetable';
        } else if (reachedEntry) {
            actualTimeStr = reachedEntry.reachedTime ? fmtTime(reachedEntry.reachedTime) : 'Recorded (No GPS Time)';
            status = '✅ Reached';
            dwellTime = 'Recorded';

            if (reachedEntry.reachedTime) {
                const schedMins = parseTimeMinutes(scheduledTimeStr);
                const actMins = parseTimeMinutes(actualTimeStr);
                if (schedMins != null && actMins != null) {
                    delayMinutes = actMins - schedMins;
                    if (delayMinutes > 2) {
                        varianceStr = `+${delayMinutes}m (Delayed)`;
                    } else if (delayMinutes < -2) {
                        varianceStr = `${delayMinutes}m (Early)`;
                    } else {
                        varianceStr = 'On-Time (±2m)';
                    }
                }
            } else {
                varianceStr = 'Unrecorded';
            }
        } else if (liveLog?.status === 'Cancelled') {
            status = '❌ Cancelled';
            actualTimeStr = null;
            varianceStr = 'N/A';
        } else if (liveLog?.status === 'Failed') {
            status = '⚠️ Breakdown/Failed';
            actualTimeStr = null;
            varianceStr = 'N/A';
        } else if (liveLog?.status === 'Active') {
            const reachedCount = Array.isArray(liveLog.reachedStops) ? liveLog.reachedStops.length : 0;
            if (idx === reachedCount) {
                status = '🟡 Next Stop (In-Transit)';
                actualTimeStr = null;
            } else {
                status = '🕒 En Route';
                actualTimeStr = null;
            }
        } else if (liveLog?.status === 'Completed') {
            status = 'Unrecorded (No GPS Stop)';
            actualTimeStr = null;
            varianceStr = 'Unrecorded';
        }

        return {
            stopNumber: idx + 1,
            name: stopName,
            scheduledTime: scheduledTimeStr,
            actualTime: actualTimeStr || 'NO DATA',
            actualTimeRaw: actualTimeStr,
            dwellTime,
            status,
            delayMinutes,
            variance: varianceStr,
            lat: st.lat || 0,
            lng: st.lng || 0
        };
    });
}

function normalizeDirectionFilter(direction) {
    if (!direction) return null;
    const raw = String(direction).trim().toLowerCase();
    if (raw === 'pickup' || raw === 'morning' || raw === 'inbound' || raw.includes('stops -> campus') || raw.includes('stops ➔ campus')) {
        return 'stops -> campus';
    }
    if (raw === 'dropoff' || raw === 'evening' || raw === 'afternoon' || raw === 'outbound' || raw.includes('campus -> stops') || raw.includes('campus ➔ stops')) {
        return 'campus -> stops';
    }
    return raw;
}

function avgNumbers(nums) {
    const valid = nums.filter(n => n !== null && n !== undefined && Number.isFinite(n));
    if (valid.length === 0) return null;
    return Math.round((valid.reduce((s, x) => s + x, 0) / valid.length) * 100) / 100;
}

function sumNumbers(nums) {
    const valid = nums.filter(n => n !== null && n !== undefined && Number.isFinite(n));
    if (valid.length === 0) return null;
    return Math.round(valid.reduce((s, x) => s + x, 0) * 100) / 100;
}

function buildCanonicalTripRecord({
    liveLog = null,
    telemetryPoints = [],
    tripIndex = 1,
    tripType = 'pickup',
    bus,
    route,
    stops,
    cleanBusName,
    driverName,
    driverPhone,
    defaultDistanceKm,
    distanceSource,
    officialStart,
    officialEnd,
    schedStartMins,
    schedEndMins,
    defaultDurMins,
    officialDuration,
    currentDateStr,
    dayName
}) {
    const isPickup = tripType === 'pickup';
    const firstStop = stops.length > 0 ? stops[0] : null;
    const stopsCount = stops.length;
    const hasSchedule = Boolean(route || stopsCount > 0);

    const routeId = liveLog?.routeId?.toString() || route?._id?.toString() || bus.routeId?.toString() || null;
    const baseRouteName = liveLog?.routeName || (route ? route.name : (bus.routeName || 'Official Route'));
    const routeName = isPickup
        ? baseRouteName
        : (route || bus.routeName ? `SISTec Ratibad Campus ➔ ${firstStop ? firstStop.name : baseRouteName}` : 'SISTec Ratibad Campus ➔ City Terminus');

    const direction = liveLog?.direction || (isPickup ? 'stops -> campus' : 'campus -> stops');
    const shift = isPickup ? '🌅 Morning Pickup' : '🌆 Evening Drop-off';
    const shiftPrefix = isPickup ? 'AM' : 'PM';
    const baseDisplayId = `TRIP-${shiftPrefix}-${cleanBusName.replace(/\s+/g, '')}-${currentDateStr}`;
    const displayTripId = tripIndex > 1 ? `${baseDisplayId}-#${tripIndex}` : baseDisplayId;
    const tripId = liveLog && liveLog._id ? liveLog._id.toString() : `SCHED-${shiftPrefix}-${bus._id.toString()}-${currentDateStr}`;

    // Single source of truth: Phase 3 journey analytics engine
    const journey = liveLog
        ? analyzeJourney({
            liveTripLog: {
                ...liveLog,
                busNumber: liveLog.busNumber || bus.busNumber || 'N/A',
                routeName: liveLog.routeName || baseRouteName,
                tripType
            },
            telemetryPoints,
            route: route || { _id: routeId, name: baseRouteName, stops }
        })
        : null;

    let dataSource = DATA_SOURCES.SCHEDULED_ESTIMATED;
    if (liveLog) {
        const hasGpsPoints = journey && journey.gpsSampleCount >= 2;
        const hasActualLogData = Boolean(
            liveLog.startTime ||
            liveLog.endTime ||
            (Array.isArray(liveLog.reachedStops) && liveLog.reachedStops.length > 0) ||
            (liveLog.distanceKm && liveLog.distanceKm > 0)
        );
        dataSource = (hasGpsPoints || hasActualLogData) ? DATA_SOURCES.LIVE_GPS : DATA_SOURCES.INSUFFICIENT_GPS_DATA;
    } else if (!hasSchedule) {
        dataSource = DATA_SOURCES.NO_DATA;
    }

    const scheduledDeparture = hasSchedule ? (isPickup ? officialStart : officialStart) : 'NO DATA';
    const scheduledArrival = hasSchedule ? officialEnd : 'NO DATA';

    // Actual departure/arrival: prefer liveLog/journey GPS timestamps, never overwrite with scheduled
    const actualDepartureDate = liveLog?.startTime || journey?.movementStartTimestamp || journey?.firstGpsTimestamp || null;
    const actualArrivalDate = liveLog?.endTime || (liveLog?.status === 'Completed' ? journey?.tripEndTimestamp : null) || null;
    const actualDeparture = actualDepartureDate ? fmtTime(actualDepartureDate) : null;
    const actualArrival = actualArrivalDate ? fmtTime(actualArrivalDate) : null;

    const departureVarianceMinutes = (actualDeparture && scheduledDeparture !== 'NO DATA')
        ? (() => {
            const actM = parseTimeMinutes(actualDeparture);
            const schM = parseTimeMinutes(scheduledDeparture);
            return (actM !== null && schM !== null) ? (actM - schM) : null;
        })()
        : null;

    const arrivalVarianceMinutes = (actualArrival && scheduledArrival !== 'NO DATA')
        ? (() => {
            const actM = parseTimeMinutes(actualArrival);
            const schM = parseTimeMinutes(scheduledArrival);
            return (actM !== null && schM !== null) ? (actM - schM) : null;
        })()
        : null;

    // Reached stop count: prefer Phase 3 GPS-verified stops when telemetry >= 2, else liveLog.reachedStops.length
    const actualReachedCount = (journey && journey.gpsSampleCount >= 2)
        ? journey.reachedStopCount
        : (liveLog && Array.isArray(liveLog.reachedStops) ? liveLog.reachedStops.length : 0);

    // Distance: actualDistanceKm is GPS-only (null when unavailable); distanceKm preserves display formatting
    const actualDistanceKm = (journey && journey.distanceKm !== null)
        ? journey.distanceKm
        : (liveLog && liveLog.distanceKm > 0 ? Math.round(liveLog.distanceKm * 100) / 100 : null);

    let tripDistanceKm = defaultDistanceKm;
    let tripDistanceSource = distanceSource;
    if (journey && journey.distanceKm !== null) {
        tripDistanceKm = `${journey.distanceKm.toFixed(1)} km`;
        tripDistanceSource = journey.distanceSource || 'GPS';
    } else if (liveLog && liveLog.distanceKm && liveLog.distanceKm > 0) {
        tripDistanceKm = `${liveLog.distanceKm.toFixed(1)} km`;
        tripDistanceSource = liveLog.distanceSource || 'GPS';
    }

    let status;
    let punctuality;
    let delayMins = 0;
    let duration;
    let startTime;
    let endTime;
    let departureTime;
    let arrivalTime;

    if (liveLog) {
        startTime = actualDeparture || 'NO DATA';
        departureTime = startTime;

        if (liveLog.status === 'Cancelled') {
            status = '❌ Cancelled';
            punctuality = '❌ Cancelled';
            endTime = actualArrival || 'Cancelled';
            arrivalTime = endTime;
            const durMin = journey?.totalDurationMinutes ?? ((liveLog.startTime && liveLog.endTime)
                ? Math.max(1, Math.round((new Date(liveLog.endTime) - new Date(liveLog.startTime)) / 60000))
                : null);
            duration = durMin != null ? `${Math.round(durMin)}m` : 'Unavailable';
        } else if (liveLog.status === 'Failed') {
            status = '⚠️ Breakdown/Failed';
            punctuality = '⚠️ Failed';
            endTime = actualArrival || 'Failed';
            arrivalTime = endTime;
            duration = 'Unavailable';
        } else if (liveLog.status === 'Active') {
            status = '⚡ In-Transit (Live)';
            punctuality = '⚡ In-Transit';
            endTime = actualArrival || 'In-Progress';
            arrivalTime = actualArrival || (hasSchedule ? `Est. ${scheduledArrival}` : 'In-Progress');
            duration = 'In-Progress';
        } else {
            status = '✅ Completed';
            if (actualArrival) {
                endTime = actualArrival;
                arrivalTime = actualArrival;
                const reachMins = parseTimeMinutes(actualArrival);
                delayMins = reachMins != null ? Math.max(0, reachMins - schedEndMins) : 0;
                punctuality = delayMins <= 5 ? '🟢 On-Time' : `🔴 Delayed (+${delayMins}m)`;
                const durMin = journey?.totalDurationMinutes ?? ((liveLog.startTime && liveLog.endTime)
                    ? Math.max(1, Math.round((new Date(liveLog.endTime) - new Date(liveLog.startTime)) / 60000))
                    : null);
                duration = durMin != null ? `${Math.floor(durMin / 60)}h ${Math.round(durMin) % 60}m` : 'Unavailable';
            } else {
                endTime = 'NO DATA';
                arrivalTime = 'Completed (No GPS Time)';
                punctuality = 'Unrecorded';
                duration = 'Unavailable';
            }
        }
    } else if (dataSource === DATA_SOURCES.NO_DATA) {
        status = 'No Data';
        punctuality = 'NO DATA';
        duration = 'NO DATA';
        startTime = 'NO DATA';
        endTime = 'NO DATA';
        departureTime = 'NO DATA';
        arrivalTime = 'NO DATA';
    } else {
        status = 'Scheduled';
        punctuality = 'Scheduled Timetable';
        duration = officialDuration;
        startTime = scheduledDeparture;
        endTime = scheduledArrival;
        departureTime = scheduledDeparture;
        arrivalTime = scheduledArrival;
    }

    // Build canonical stops: use Phase 3 reconstructed stops when GPS telemetry exists, else Phase 2 timetable/log stops
    let tripStopTimeline;
    if (journey && journey.gpsSampleCount >= 2 && journey.stops.length > 0) {
        tripStopTimeline = journey.stops.map(js => {
            const schedLabel = js.scheduledArrival ? fmtTime(js.scheduledArrival) : (isPickup ? 'N/A' : 'SCHEDULE DATA UNAVAILABLE');
            const actArrLabel = js.actualArrival ? fmtTime(js.actualArrival) : 'NO DATA';
            const actDepLabel = js.actualDeparture ? fmtTime(js.actualDeparture) : null;
            let varLabel = 'Unrecorded';
            if (js.arrivalVarianceMinutes !== null) {
                if (js.arrivalVarianceMinutes > 2) varLabel = `+${js.arrivalVarianceMinutes}m (Delayed)`;
                else if (js.arrivalVarianceMinutes < -2) varLabel = `${js.arrivalVarianceMinutes}m (Early)`;
                else varLabel = 'On-Time (±2m)';
            }
            return {
                ...js,
                stopNumber: js.stopSequence,
                name: js.stopName,
                scheduledTime: schedLabel,
                actualTime: actArrLabel,
                actualDepartureTime: actDepLabel,
                dwellTime: js.dwellMinutes !== null ? `${js.dwellMinutes}m` : 'Insufficient GPS',
                variance: varLabel
            };
        });
    } else {
        const legacyStops = buildStopTimeline({
            stops,
            tripType,
            liveLog,
            defaultStartMins: schedStartMins,
            defaultDurationMins: defaultDurMins,
            dateStr: currentDateStr
        });
        tripStopTimeline = legacyStops.map(s => ({
            stopSequence: s.stopNumber,
            stopId: null,
            stopName: s.name,
            name: s.name,
            stopNumber: s.stopNumber,
            latitude: s.lat || null,
            longitude: s.lng || null,
            scheduledArrival: null,
            scheduledDeparture: null,
            scheduledTime: isPickup ? s.scheduledTime : 'SCHEDULE DATA UNAVAILABLE',
            actualArrival: null,
            actualDeparture: null,
            actualTime: s.actualTime,
            arrivalVarianceMinutes: null,
            departureVarianceMinutes: null,
            dwellMinutes: null,
            dwellTime: s.dwellTime,
            status: liveLog ? (s.status.includes('Reached') ? 'REACHED' : 'UNRECORDED') : 'NO GPS DATA',
            detectionSource: liveLog ? 'LIVE_TRIP_LOG' : 'SCHEDULED_ONLY',
            confidence: liveLog ? 0.5 : 0,
            variance: s.variance
        }));
    }

    const cappedReached = stopsCount > 0 ? Math.min(actualReachedCount, stopsCount) : actualReachedCount;
    const gpsQuality = journey ? journey.gpsQuality : {
        totalSamples: 0,
        validSamples: 0,
        invalidSamples: 0,
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
        accuracyAvailable: false,
        averageAccuracyMeters: null,
        minimumAccuracyMeters: null,
        maximumAccuracyMeters: null,
        telemetryCompletenessPercent: null
    };

    return {
        tripId,
        liveTripLogId: liveLog && liveLog._id ? liveLog._id.toString() : null,
        displayTripId,
        tripSequence: tripIndex,
        date: currentDateStr,
        day: dayName,
        shift,
        shiftType: tripType,
        tripType,
        direction,
        dataSource,
        analyticsStatus: journey ? journey.analyticsStatus : (dataSource === DATA_SOURCES.NO_DATA ? 'NO DATA' : 'SCHEDULED ONLY'),
        telemetryStatus: journey ? journey.telemetryStatus : 'EMPTY',
        busId: bus._id.toString(),
        busNo: cleanBusName,
        busNumber: bus.busNumber || 'N/A',
        vehicleNo: bus.busNumber || 'N/A',
        routeId,
        routeName,
        originStop: isPickup ? (firstStop ? firstStop.name : 'Origin Terminus') : 'SISTec Ratibad Campus',
        destinationStop: isPickup ? 'SISTec Ratibad Campus' : (firstStop ? firstStop.name : 'Origin Terminus'),
        driverName,
        driverPhone,
        startTime,
        endTime,
        actualDeparture,
        actualArrival,
        scheduledDeparture,
        scheduledArrival,
        departureVarianceMinutes,
        arrivalVarianceMinutes,
        departureTime,
        arrivalTime,
        duration,
        punctuality,
        delayMinutes: delayMins,
        stopsCount,
        scheduledStopsCount: stopsCount,
        actualReachedCount,
        stopsCompleted: `${cappedReached} / ${stopsCount}`,
        stopsCompletedNum: cappedReached,
        distanceKm: tripDistanceKm,
        actualDistanceKm,
        distanceSource: tripDistanceSource,
        cancellationReason: liveLog?.cancellationReason || null,
        status,

        // Phase 3 / 4 enriched journey analytics
        firstGpsTimestamp: journey ? journey.firstGpsTimestamp : null,
        firstGpsLat: journey ? journey.firstGpsLat : null,
        firstGpsLng: journey ? journey.firstGpsLng : null,
        movementStartTimestamp: journey ? journey.movementStartTimestamp : null,
        movementStartLat: journey ? journey.movementStartLat : null,
        movementStartLng: journey ? journey.movementStartLng : null,
        movementStartStatus: journey ? journey.movementStartStatus : 'INSUFFICIENT GPS DATA',
        lastGpsTimestamp: journey ? journey.lastGpsTimestamp : null,
        lastGpsLat: journey ? journey.lastGpsLat : null,
        lastGpsLng: journey ? journey.lastGpsLng : null,
        tripEndTimestamp: journey ? journey.tripEndTimestamp : null,
        tripEndSource: journey ? journey.tripEndSource : 'NO DATA',
        totalDurationMinutes: journey ? journey.totalDurationMinutes : null,
        drivingDurationMinutes: journey ? journey.drivingDurationMinutes : null,
        stationaryDurationMinutes: journey ? journey.stationaryDurationMinutes : null,
        averageSpeedKmh: journey ? journey.averageSpeedKmh : null,
        minimumSpeedKmh: journey ? journey.minimumSpeedKmh : null,
        maximumSpeedKmh: journey ? journey.maximumSpeedKmh : null,
        stopCount: journey ? journey.stopCount : stopsCount,
        reachedStopCount: journey ? journey.reachedStopCount : actualReachedCount,
        missedStopCount: journey ? journey.missedStopCount : 0,
        unrecordedStopCount: journey ? journey.unrecordedStopCount : (liveLog ? Math.max(0, stopsCount - actualReachedCount) : stopsCount),
        averageDwellMinutes: journey ? journey.averageDwellMinutes : null,
        longestDwellMinutes: journey ? journey.longestDwellMinutes : null,
        averageSegmentTravelMinutes: journey ? journey.averageSegmentTravelMinutes : null,
        longestSegmentTravelMinutes: journey ? journey.longestSegmentTravelMinutes : null,
        shortestSegmentTravelMinutes: journey ? journey.shortestSegmentTravelMinutes : null,
        averageDelayMinutes: journey ? journey.averageDelayMinutes : null,
        maximumDelayMinutes: journey ? journey.maximumDelayMinutes : null,
        gpsSampleCount: gpsQuality.validSamples,
        validGpsSamples: gpsQuality.validSamples,
        invalidGpsSamples: gpsQuality.invalidSamples,
        coverageDurationMinutes: gpsQuality.coverageDurationMinutes,
        averageSamplingIntervalSeconds: gpsQuality.averageSamplingIntervalSeconds,
        minimumSamplingIntervalSeconds: gpsQuality.minimumSamplingIntervalSeconds,
        maximumSamplingIntervalSeconds: gpsQuality.maximumSamplingIntervalSeconds,
        gpsGapCount: gpsQuality.gpsGapCount,
        longestGpsGapSeconds: gpsQuality.longestGpsGapSeconds,
        longestGapStart: gpsQuality.longestGapStart,
        longestGapEnd: gpsQuality.longestGapEnd,
        accuracyAvailable: gpsQuality.accuracyAvailable,
        averageAccuracyMeters: gpsQuality.averageAccuracyMeters,
        minimumAccuracyMeters: gpsQuality.minimumAccuracyMeters,
        maximumAccuracyMeters: gpsQuality.maximumAccuracyMeters,
        telemetryCompletenessPercent: gpsQuality.telemetryCompletenessPercent,
        gpsTelemetry: {
            totalSamples: gpsQuality.totalSamples,
            validSamples: gpsQuality.validSamples,
            invalidSamples: gpsQuality.invalidSamples,
            firstGpsTimestamp: gpsQuality.firstGpsTimestamp,
            lastGpsTimestamp: gpsQuality.lastGpsTimestamp,
            coverageDurationMinutes: gpsQuality.coverageDurationMinutes,
            averageSamplingIntervalSeconds: gpsQuality.averageSamplingIntervalSeconds,
            minimumSamplingIntervalSeconds: gpsQuality.minimumSamplingIntervalSeconds,
            maximumSamplingIntervalSeconds: gpsQuality.maximumSamplingIntervalSeconds,
            gpsGapCount: gpsQuality.gpsGapCount,
            longestGpsGapSeconds: gpsQuality.longestGpsGapSeconds,
            longestGapStart: gpsQuality.longestGapStart,
            longestGapEnd: gpsQuality.longestGapEnd,
            accuracyAvailable: gpsQuality.accuracyAvailable,
            averageAccuracyMeters: gpsQuality.averageAccuracyMeters,
            minimumAccuracyMeters: gpsQuality.minimumAccuracyMeters,
            maximumAccuracyMeters: gpsQuality.maximumAccuracyMeters,
            telemetryCompletenessPercent: gpsQuality.telemetryCompletenessPercent
        },
        gpsGaps: gpsQuality.gaps || [],
        journeyTimeline: journey ? journey.timeline : [],
        segments: journey ? journey.segments : [],
        stops: tripStopTimeline
    };
}

function computeFleetAnalytics(allTrips, totalBuses) {
    const activeBuses = new Set(allTrips.filter(t => t.status === '⚡ In-Transit (Live)').map(t => t.busId)).size;
    const totalTrips = allTrips.length;
    const completedTrips = allTrips.filter(t => t.status === '✅ Completed').length;
    const liveGpsTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.LIVE_GPS).length;
    const insufficientGpsTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.INSUFFICIENT_GPS_DATA).length;
    const scheduledEstimatedTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.SCHEDULED_ESTIMATED).length;
    const noDataTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.NO_DATA).length;

    const gpsTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.LIVE_GPS);
    const gpsDistances = gpsTrips.map(t => t.actualDistanceKm).filter(d => d !== null && Number.isFinite(d));
    const totalDistanceKm = sumNumbers(gpsDistances);
    const averageDistanceKm = avgNumbers(gpsDistances);
    const averageTripDurationMinutes = avgNumbers(gpsTrips.map(t => t.totalDurationMinutes));
    const averageSpeedKmh = avgNumbers(gpsTrips.map(t => t.averageSpeedKmh));
    const averageDelayMinutes = avgNumbers(gpsTrips.map(t => t.averageDelayMinutes));
    const averageDwellMinutes = avgNumbers(gpsTrips.map(t => t.averageDwellMinutes));
    const averageTelemetryCompletenessPercent = avgNumbers(gpsTrips.map(t => t.telemetryCompletenessPercent));

    const completedLive = gpsTrips.filter(t => t.status === '✅ Completed');
    const onTimeLive = completedLive.filter(t => t.punctuality && (t.punctuality.includes('On-Time') || t.punctuality.includes('🟢'))).length;
    const delayedLive = completedLive.filter(t => (t.maximumDelayMinutes ?? t.delayMinutes ?? 0) > 5).length;

    const onTimeTripPercent = completedLive.length > 0 ? Math.round((onTimeLive / completedLive.length) * 1000) / 10 : null;
    const delayedTripPercent = completedLive.length > 0 ? Math.round((delayedLive / completedLive.length) * 1000) / 10 : null;

    return {
        totalBuses,
        activeBuses,
        totalTrips,
        completedTrips,
        liveGpsTrips,
        insufficientGpsTrips,
        scheduledEstimatedTrips,
        noDataTrips,
        totalDistanceKm,
        averageTripDurationMinutes,
        averageDistanceKm,
        averageSpeedKmh,
        averageDelayMinutes,
        onTimeTripPercent,
        delayedTripPercent,
        averageDwellMinutes,
        totalGpsSamples: allTrips.reduce((s, t) => s + (t.validGpsSamples || 0), 0),
        totalGpsGaps: allTrips.reduce((s, t) => s + (t.gpsGapCount || 0), 0),
        averageTelemetryCompletenessPercent
    };
}

function computeBusAnalytics(allTrips) {
    const byBus = new Map();
    for (const t of allTrips) {
        if (!byBus.has(t.busId)) byBus.set(t.busId, []);
        byBus.get(t.busId).push(t);
    }

    const result = [];
    for (const [busId, trips] of byBus.entries()) {
        const gpsTrips = trips.filter(t => t.dataSource === DATA_SOURCES.LIVE_GPS);
        const completedLive = gpsTrips.filter(t => t.status === '✅ Completed');
        const onTimeLive = completedLive.filter(t => t.punctuality && (t.punctuality.includes('On-Time') || t.punctuality.includes('🟢'))).length;
        const gpsDistances = gpsTrips.map(t => t.actualDistanceKm).filter(d => d !== null);

        result.push({
            busId,
            busNo: trips[0].busNo,
            busNumber: trips[0].busNumber,
            totalTrips: trips.length,
            completedTrips: trips.filter(t => t.status === '✅ Completed').length,
            totalDistanceKm: sumNumbers(gpsDistances),
            averageDistanceKm: avgNumbers(gpsDistances),
            averageTripDurationMinutes: avgNumbers(gpsTrips.map(t => t.totalDurationMinutes)),
            averageSpeedKmh: avgNumbers(gpsTrips.map(t => t.averageSpeedKmh)),
            averageDelayMinutes: avgNumbers(gpsTrips.map(t => t.averageDelayMinutes)),
            onTimePercent: completedLive.length > 0 ? Math.round((onTimeLive / completedLive.length) * 1000) / 10 : null,
            averageDwellMinutes: avgNumbers(gpsTrips.map(t => t.averageDwellMinutes)),
            gpsTripCount: gpsTrips.length,
            scheduledOnlyTripCount: trips.filter(t => t.dataSource === DATA_SOURCES.SCHEDULED_ESTIMATED).length,
            telemetryCompletenessPercent: avgNumbers(gpsTrips.map(t => t.telemetryCompletenessPercent))
        });
    }
    return result;
}

function computeRouteAnalytics(allTrips) {
    const byRouteDir = new Map();
    for (const t of allTrips) {
        const key = `${t.routeId || 'unassigned'}::${t.direction || 'unknown'}`;
        if (!byRouteDir.has(key)) byRouteDir.set(key, []);
        byRouteDir.get(key).push(t);
    }

    const result = [];
    for (const trips of byRouteDir.values()) {
        const gpsTrips = trips.filter(t => t.dataSource === DATA_SOURCES.LIVE_GPS);
        const completedLive = gpsTrips.filter(t => t.status === '✅ Completed');
        const onTimeLive = completedLive.filter(t => t.punctuality && (t.punctuality.includes('On-Time') || t.punctuality.includes('🟢'))).length;
        const gpsDistances = gpsTrips.map(t => t.actualDistanceKm).filter(d => d !== null);

        result.push({
            routeId: trips[0].routeId,
            routeName: trips[0].routeName,
            direction: trips[0].direction,
            tripCount: trips.length,
            distanceKm: sumNumbers(gpsDistances),
            averageDistanceKm: avgNumbers(gpsDistances),
            averageDurationMinutes: avgNumbers(gpsTrips.map(t => t.totalDurationMinutes)),
            averageSpeedKmh: avgNumbers(gpsTrips.map(t => t.averageSpeedKmh)),
            averageDelayMinutes: avgNumbers(gpsTrips.map(t => t.averageDelayMinutes)),
            onTimePercent: completedLive.length > 0 ? Math.round((onTimeLive / completedLive.length) * 1000) / 10 : null,
            averageDwellMinutes: avgNumbers(gpsTrips.map(t => t.averageDwellMinutes)),
            gpsCompletenessPercent: avgNumbers(gpsTrips.map(t => t.telemetryCompletenessPercent))
        });
    }
    return result;
}

function computeStopPerformanceAnalytics(allTrips) {
    const byStop = new Map();
    for (const t of allTrips) {
        for (const s of (t.stops || [])) {
            const key = `${t.routeId || 'unassigned'}::${s.stopId || s.stopName}`;
            if (!byStop.has(key)) {
                byStop.set(key, {
                    stopId: s.stopId || null,
                    stopName: s.stopName || s.name,
                    routeId: t.routeId || null,
                    scheduledArrival: s.scheduledTime || null,
                    actualArrivalDates: [],
                    arrVars: [],
                    depVars: [],
                    dwells: [],
                    reachedCount: 0,
                    missedCount: 0,
                    unrecordedCount: 0
                });
            }
            const entry = byStop.get(key);
            if (s.status === 'REACHED') entry.reachedCount++;
            else if (s.status === 'MISSED') entry.missedCount++;
            else entry.unrecordedCount++;

            if (s.actualArrival) entry.actualArrivalDates.push(new Date(s.actualArrival));
            if (s.arrivalVarianceMinutes !== null && s.arrivalVarianceMinutes !== undefined) entry.arrVars.push(s.arrivalVarianceMinutes);
            if (s.departureVarianceMinutes !== null && s.departureVarianceMinutes !== undefined) entry.depVars.push(s.departureVarianceMinutes);
            if (s.dwellMinutes !== null && s.dwellMinutes !== undefined) entry.dwells.push(s.dwellMinutes);
        }
    }

    const result = [];
    for (const e of byStop.values()) {
        let averageActualArrival = null;
        if (e.actualArrivalDates.length > 0) {
            const avgMs = e.actualArrivalDates.reduce((s, d) => s + d.getTime(), 0) / e.actualArrivalDates.length;
            averageActualArrival = fmtTime(new Date(avgMs));
        }
        const onTimeSamples = e.arrVars.filter(v => v <= 5).length;
        result.push({
            stopId: e.stopId,
            stopName: e.stopName,
            routeId: e.routeId,
            scheduledArrival: e.scheduledArrival,
            averageActualArrival,
            averageArrivalVariance: avgNumbers(e.arrVars),
            averageDepartureVariance: avgNumbers(e.depVars),
            averageDwellMinutes: avgNumbers(e.dwells),
            reachedCount: e.reachedCount,
            missedCount: e.missedCount,
            unrecordedCount: e.unrecordedCount,
            onTimePercent: e.arrVars.length > 0 ? Math.round((onTimeSamples / e.arrVars.length) * 1000) / 10 : null
        });
    }
    return result;
}

function computeDataQualityAnalytics(allTrips) {
    const tripsWithGps = allTrips.filter(t => (t.validGpsSamples || 0) >= 2).length;
    const tripsWithoutGps = allTrips.length - tripsWithGps;
    const completeTelemetryTrips = allTrips.filter(t => t.telemetryStatus === 'COMPLETE').length;
    const partialTelemetryTrips = allTrips.filter(t => t.telemetryStatus === 'PARTIAL').length;
    const gapDurations = allTrips.map(t => t.longestGpsGapSeconds).filter(g => g !== null && Number.isFinite(g));

    return {
        totalTrips: allTrips.length,
        tripsWithGps,
        tripsWithoutGps,
        completeTelemetryTrips,
        partialTelemetryTrips,
        averageTelemetryCompletenessPercent: avgNumbers(allTrips.map(t => t.telemetryCompletenessPercent)),
        totalGpsGaps: allTrips.reduce((s, t) => s + (t.gpsGapCount || 0), 0),
        longestGpsGapSeconds: gapDurations.length > 0 ? Math.max(...gapDurations) : null,
        tripsWithMissingStopCoordinates: allTrips.filter(t => (t.stops || []).some(s => s.detectionSource === 'NO STOP COORDINATES')).length,
        tripsWithUnrecordedStops: allTrips.filter(t => (t.unrecordedStopCount || 0) > 0).length,
        invalidGpsSampleCount: allTrips.reduce((s, t) => s + (t.invalidGpsSamples || 0), 0)
    };
}

/**
 * Generates multi-trip records for a specific date or lookback range
 * @param {Object} options { targetDate, shift: 'all'|'morning'|'evening', busId, routeId, direction, tripId, days }
 */
async function generateTripReportData({
    targetDate,
    shift = 'all',
    busId = null,
    routeId = null,
    direction = null,
    tripId = null,
    days = 1
}) {
    const primaryDateStr = fmtDate(targetDate);
    const lookbackDays = Math.max(1, Math.min(parseInt(days, 10) || 1, 30));

    const routes = await Route.find();
    const buses = await Bus.find().sort({ name: 1 });
    const drivers = await Driver.find();

    const targetBuses = busId
        ? buses.filter(b => b._id.toString() === busId || b.busNumber === busId)
        : buses;

    // Build operational dates list (today down to lookbackDays ago) in IST
    const operationalDates = [];
    const dateMatch = primaryDateStr.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    for (let d = 0; d < lookbackDays; d++) {
        if (dateMatch) {
            const dt = new Date(Date.UTC(Number(dateMatch[1]), Number(dateMatch[2]) - 1, Number(dateMatch[3]) - d, 12, 0, 0));
            operationalDates.push(getIstDateString(dt));
        } else {
            const dt = new Date(primaryDateStr);
            dt.setDate(dt.getDate() - d);
            operationalDates.push(fmtDate(dt));
        }
    }

    // Fetch live logs for target buses and dates
    const liveLogsQuery = { date: { $in: operationalDates } };
    if (busId) {
        liveLogsQuery.$or = [{ busId }, { busNumber: busId }];
    }
    const allLiveLogs = await LiveTripLog.find(liveLogsQuery).sort({ startTime: 1 });

    // Batch-retrieve persisted TripTelemetryPoint records by exact tripLogId (avoids N+1 & prevents busId+date mixing)
    const tripLogIds = allLiveLogs.map(l => l._id).filter(Boolean);
    const telemetryByTripId = new Map();
    if (tripLogIds.length > 0 && typeof TripTelemetryPoint?.find === 'function') {
        const allTelemetry = await TripTelemetryPoint.find({ tripLogId: { $in: tripLogIds } }).sort({ timestamp: 1 });
        for (const pt of (allTelemetry || [])) {
            const key = pt.tripLogId ? pt.tripLogId.toString() : null;
            if (!key) continue;
            if (!telemetryByTripId.has(key)) telemetryByTripId.set(key, []);
            telemetryByTripId.get(key).push(pt);
        }
    }

    const normalizedDirectionFilter = normalizeDirectionFilter(direction);
    const includePickup = shift === 'all' || shift === 'morning' || shift === 'pickup';
    const includeDropoff = shift === 'all' || shift === 'evening' || shift === 'afternoon' || shift === 'dropoff';

    let morningTrips = [];
    let eveningTrips = [];
    let flatStopLogs = [];

    operationalDates.forEach((currentDateStr) => {
        const dayName = getDayOfWeek(currentDateStr);

        targetBuses.forEach((b) => {
            const route = routes.find(r => r._id?.toString() === b.routeId?.toString());
            const driver = drivers.find(d =>
                (b.driverId && d._id?.toString() === b.driverId.toString()) ||
                (d.assignedBus && d.assignedBus.toString() === b._id.toString()) ||
                (d.busNumber && d.busNumber === b.busNumber)
            );
            const stops = route ? (route.stops || []) : [];
            const rawBusName = b.name || `Bus ${b.busNumber || ''}`;
            const splitName = rawBusName.split(' - ')[0].trim();
            const numMatch = splitName.match(/\d+/);
            const cleanBusName = numMatch ? `Bus ${String(numMatch[0]).padStart(2, '0')}` : splitName;
            const driverName = driver ? (driver.name || driver.username) : 'Assigned Driver';

            let rawPhone = driver ? (driver.phone || driver.contactNumber) : 'N/A';
            let driverPhone = 'N/A';
            if (rawPhone && rawPhone !== 'N/A' && rawPhone !== 'null') {
                const digits = String(rawPhone).replace(/\D/g, '');
                if (digits.length === 10) {
                    driverPhone = `+91 ${digits.slice(0, 5)} ${digits.slice(5)}`;
                } else if (digits.length === 12 && digits.startsWith('91')) {
                    driverPhone = `+91 ${digits.slice(2, 7)} ${digits.slice(7)}`;
                } else {
                    driverPhone = String(rawPhone);
                }
            }

            let distanceNum = 0;
            let distanceSource = 'Unavailable';
            if (route && route.coordinates && route.coordinates.length > 1) {
                distanceNum = computeHaversineDistanceKm(route.coordinates);
                distanceSource = 'Polyline (Route)';
            } else if (stops.length > 1) {
                distanceNum = computeHaversineDistanceKm(stops);
                distanceSource = 'Polyline (Stops)';
            }
            const defaultDistanceKm = distanceNum > 0 ? `${distanceNum.toFixed(1)} km` : 'N/A';

            const firstStop = stops.length > 0 ? stops[0] : null;
            const lastStop = stops.length > 0 ? stops[stops.length - 1] : null;

            const officialMorningStart = firstStop && firstStop.time ? firstStop.time : '07:15 AM';
            let officialMorningEnd = '08:45 AM';
            if (lastStop && lastStop.time) {
                const lastTimeMins = parseTimeMinutes(lastStop.time);
                if (lastTimeMins && lastTimeMins > (7 * 60)) {
                    officialMorningEnd = formatMinutesToTime(Math.min(9 * 60, lastTimeMins + 12));
                }
            }

            const schedStartMins = parseTimeMinutes(officialMorningStart) || (7 * 60 + 15);
            const schedEndMins = parseTimeMinutes(officialMorningEnd) || (8 * 60 + 45);
            const morningDurMins = Math.max(30, schedEndMins - schedStartMins);
            const officialMorningDuration = `${Math.floor(morningDurMins / 60)}h ${morningDurMins % 60}m`;

            const officialEveningStart = '04:45 PM';
            const eveningStartMins = parseTimeMinutes(officialEveningStart) || (16 * 60 + 45);
            const eveningEndMins = eveningStartMins + morningDurMins;
            const officialEveningEnd = formatMinutesToTime(eveningEndMins);

            const dayLiveLogs = allLiveLogs.filter(l =>
                l.date === currentDateStr &&
                (l.busId === b._id.toString() || (b.busNumber && l.busNumber === b.busNumber))
            );

            const pickupLogs = dayLiveLogs
                .filter(l => !l.tripType || String(l.tripType).toLowerCase() === 'pickup')
                .sort((a, x) => new Date(a.startTime || 0) - new Date(x.startTime || 0));

            const dropoffLogs = dayLiveLogs
                .filter(l => String(l.tripType).toLowerCase() === 'dropoff')
                .sort((a, x) => new Date(a.startTime || 0) - new Date(x.startTime || 0));

            if (includePickup) {
                const logsToRender = pickupLogs.length > 0 ? pickupLogs : (tripId ? [] : [null]);
                logsToRender.forEach((liveLog, idx) => {
                    const tripTelemetry = liveLog && liveLog._id
                        ? (telemetryByTripId.get(liveLog._id.toString()) || [])
                        : [];
                    const tripObj = buildCanonicalTripRecord({
                        liveLog,
                        telemetryPoints: tripTelemetry,
                        tripIndex: idx + 1,
                        tripType: 'pickup',
                        bus: b,
                        route,
                        stops,
                        cleanBusName,
                        driverName,
                        driverPhone,
                        defaultDistanceKm,
                        distanceSource,
                        officialStart: officialMorningStart,
                        officialEnd: officialMorningEnd,
                        schedStartMins,
                        schedEndMins,
                        defaultDurMins: morningDurMins,
                        officialDuration: officialMorningDuration,
                        currentDateStr,
                        dayName
                    });
                    morningTrips.push(tripObj);
                });
            }

            if (includeDropoff) {
                const logsToRender = dropoffLogs.length > 0 ? dropoffLogs : (tripId ? [] : [null]);
                logsToRender.forEach((liveLog, idx) => {
                    const tripTelemetry = liveLog && liveLog._id
                        ? (telemetryByTripId.get(liveLog._id.toString()) || [])
                        : [];
                    const tripObj = buildCanonicalTripRecord({
                        liveLog,
                        telemetryPoints: tripTelemetry,
                        tripIndex: idx + 1,
                        tripType: 'dropoff',
                        bus: b,
                        route,
                        stops,
                        cleanBusName,
                        driverName,
                        driverPhone,
                        defaultDistanceKm,
                        distanceSource,
                        officialStart: officialEveningStart,
                        officialEnd: officialEveningEnd,
                        schedStartMins: eveningStartMins,
                        schedEndMins: eveningEndMins,
                        defaultDurMins: morningDurMins,
                        officialDuration: officialMorningDuration,
                        currentDateStr,
                        dayName
                    });
                    eveningTrips.push(tripObj);
                });
            }
        });
    });

    // Apply optional routeId, direction, and exact tripId filters
    const matchesExtraFilters = (t) => {
        if (routeId && String(t.routeId || '') !== String(routeId)) return false;
        if (normalizedDirectionFilter && String(t.direction || '').toLowerCase() !== normalizedDirectionFilter) return false;
        if (tripId && String(t.tripId) !== String(tripId)) return false;
        return true;
    };

    morningTrips = morningTrips.filter(matchesExtraFilters);
    eveningTrips = eveningTrips.filter(matchesExtraFilters);

    const parseBusNum = str => parseInt(String(str).replace(/[^0-9]/g, ''), 10) || 0;
    const sortTrips = (a, b) => {
        const busDiff = parseBusNum(a.busNo) - parseBusNum(b.busNo);
        if (busDiff !== 0) return busDiff;
        return (a.tripSequence || 1) - (b.tripSequence || 1);
    };
    morningTrips.sort(sortTrips);
    eveningTrips.sort(sortTrips);

    const allTrips = [...morningTrips, ...eveningTrips];

    // Build flatStopLogs strictly from the canonical filtered allTrips
    flatStopLogs = [];
    allTrips.forEach(t => {
        const shiftLabel = t.tripType === 'dropoff' ? 'Evening Drop-off' : 'Morning Pickup';
        (t.stops || []).forEach(st => {
            flatStopLogs.push({
                tripId: t.tripId,
                displayTripId: t.displayTripId,
                date: t.date,
                shift: shiftLabel,
                tripType: t.tripType,
                direction: t.direction,
                dataSource: t.dataSource,
                busId: t.busId,
                busNo: t.busNo,
                vehicleNo: t.vehicleNo,
                routeId: t.routeId,
                routeName: t.routeName,
                stopNo: st.stopNumber,
                stopName: st.name,
                scheduledTime: st.scheduledTime,
                actualTime: st.actualTime,
                dwellTime: st.dwellTime,
                variance: st.variance,
                status: st.status
            });
        });
    });

    // Compute Comprehensive Summary KPIs from canonical allTrips
    const totalTrips = allTrips.length;
    const completedTrips = allTrips.filter(t => t.status === '✅ Completed').length;
    const cancelledTrips = allTrips.filter(t => t.status === '❌ Cancelled').length;
    const activeTrips = allTrips.filter(t => t.status === '⚡ In-Transit (Live)').length;
    const scheduledTrips = allTrips.filter(t => t.status === 'Scheduled' || t.status === '⚪ Scheduled').length;
    const liveGpsTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.LIVE_GPS).length;
    const scheduledEstimatedTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.SCHEDULED_ESTIMATED).length;
    const noDataTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.NO_DATA).length;
    const insufficientGpsTrips = allTrips.filter(t => t.dataSource === DATA_SOURCES.INSUFFICIENT_GPS_DATA).length;
    const onTimeTrips = allTrips.filter(t => t.punctuality && (t.punctuality.includes('On-Time') || t.punctuality.includes('🟢'))).length;
    const delayedTrips = allTrips.filter(t => t.delayMinutes > 5).length;
    const punctualityRate = (completedTrips > 0)
        ? ((onTimeTrips / completedTrips) * 100).toFixed(1)
        : (totalTrips > 0 ? '100.0' : '0.0');
    const totalDistance = allTrips.reduce((acc, t) => acc + (parseFloat(String(t.distanceKm).replace(/[^0-9.]/g, '')) || 0), 0).toFixed(1);
    const totalStopsServiced = allTrips.reduce((acc, t) => acc + (t.actualReachedCount || 0), 0);
    const uniqueBusCount = new Set(allTrips.map(t => t.busId)).size;

    const effectiveTotalBuses = (routeId || tripId) ? uniqueBusCount : targetBuses.length;
    const fleetAnalytics = computeFleetAnalytics(allTrips, effectiveTotalBuses);
    const busAnalytics = computeBusAnalytics(allTrips);
    const routeAnalytics = computeRouteAnalytics(allTrips);
    const stopPerformance = computeStopPerformanceAnalytics(allTrips);
    const dataQuality = computeDataQualityAnalytics(allTrips);

    return {
        date: primaryDateStr,
        day: getDayOfWeek(primaryDateStr),
        daysLookback: lookbackDays,
        shift,
        filters: {
            date: primaryDateStr,
            shift,
            busId: busId || null,
            routeId: routeId || null,
            direction: normalizedDirectionFilter || null,
            tripId: tripId || null
        },
        totalBuses: effectiveTotalBuses,
        totalTrips,
        completedTrips,
        cancelledTrips,
        activeTrips,
        scheduledTrips,
        liveGpsTrips,
        scheduledEstimatedTrips,
        noDataTrips,
        insufficientGpsTrips,
        onTimeTrips,
        delayedTrips,
        punctualityRate,
        totalDistance,
        totalStopsServiced,
        fleetAnalytics,
        busAnalytics,
        routeAnalytics,
        stopPerformance,
        dataQuality,
        morningTrips,
        eveningTrips,
        allTrips,
        stopLogs: flatStopLogs
    };
}

function stripReportDecorators(value) {
    if (value === undefined || value === null) return '';
    return String(value)
        .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/gu, '')
        .replace(/➔/g, '->')
        .replace(/\s+/g, ' ')
        .trim();
}

function csvEscape(value) {
    const str = String(value ?? '').replace(/"/g, '""');
    return `"${str}"`;
}

function buildCsvFromRows(headers, rows) {
    const lines = [headers.join(',')];
    for (const r of rows) {
        lines.push(r.map(csvEscape).join(','));
    }
    return `\uFEFF${lines.join('\r\n')}\r\n`;
}

/**
 * Generates all 6 normalized CSV files strictly from the canonical reportData.
 */
function generateTripReportCsvFiles(reportData) {
    const trips = Array.isArray(reportData.allTrips) ? reportData.allTrips : [];
    const fleet = reportData.fleetAnalytics || computeFleetAnalytics(trips, reportData.totalBuses || 0);
    const dq = reportData.dataQuality || computeDataQualityAnalytics(trips);

    // 1. trip_summary.csv
    const tripSummaryHeaders = [
        'Trip ID', 'Date', 'Bus Name', 'License Plate', 'Assigned Route', 'Direction',
        'Driver', 'Data Source', 'Scheduled Departure', 'Actual Departure',
        'Scheduled Arrival', 'Actual Arrival', 'Distance (km)', 'Duration (min)',
        'Avg Speed (km/h)', 'Avg Delay (min)', 'GPS Samples', 'GPS Gaps',
        'Completeness %', 'Status', 'Stops Reached'
    ];
    const tripSummaryRows = trips.map(t => [
        t.tripId || '',
        t.date || reportData.date || '',
        t.busNo || '',
        t.busNumber || t.vehicleNo || 'N/A',
        stripReportDecorators(t.routeName || ''),
        t.direction || '',
        t.driverName || 'Assigned Driver',
        t.dataSource || DATA_SOURCES.SCHEDULED_ESTIMATED,
        t.scheduledDeparture || 'NO DATA',
        t.actualDeparture || 'NO DATA',
        t.scheduledArrival || 'NO DATA',
        t.actualArrival || 'NO DATA',
        t.actualDistanceKm ?? 'NO DATA',
        t.totalDurationMinutes ?? 'NO DATA',
        t.averageSpeedKmh ?? 'NO DATA',
        t.averageDelayMinutes ?? 'NO DATA',
        t.validGpsSamples ?? 0,
        t.gpsGapCount ?? 0,
        t.telemetryCompletenessPercent ?? 'NO DATA',
        stripReportDecorators(t.status || 'Scheduled') || 'Scheduled',
        String(t.stopsCompleted || `${t.actualReachedCount ?? 0}/${t.scheduledStopsCount ?? t.stopsCount ?? 0}`).replace(/\s+/g, '')
    ]);

    // 2. journey_timeline.csv
    const timelineHeaders = ['Trip ID', 'Bus Name', 'Date', 'Timestamp (IST)', 'Event Type', 'Stop ID', 'Stop Name', 'Source', 'Confidence'];
    const timelineRows = [];
    trips.forEach(t => {
        (t.journeyTimeline || []).forEach(ev => {
            timelineRows.push([
                t.tripId || '',
                t.busNo || '',
                t.date || reportData.date || '',
                ev.timestamp ? fmtTime(ev.timestamp) : 'NO DATA',
                ev.eventType || '',
                ev.stopId || '',
                ev.stopName || '',
                ev.source || '',
                ev.confidence ?? ''
            ]);
        });
    });

    // 3. stop_analytics.csv
    const stopHeaders = [
        'Trip ID', 'Bus Name', 'Date', 'Stop Sequence', 'Stop ID', 'Stop Name',
        'Scheduled Arrival', 'Actual Arrival', 'Arrival Variance (min)',
        'Scheduled Departure', 'Actual Departure', 'Departure Variance (min)',
        'Dwell (min)', 'Status', 'Detection Source', 'Confidence'
    ];
    const stopRows = [];
    trips.forEach(t => {
        (t.stops || []).forEach(s => {
            stopRows.push([
                t.tripId || '',
                t.busNo || '',
                t.date || reportData.date || '',
                s.stopSequence ?? s.stopNumber ?? '',
                s.stopId || '',
                s.stopName || s.name || '',
                s.scheduledArrival ? fmtTime(s.scheduledArrival) : (s.scheduledTime || 'NO DATA'),
                s.actualArrival ? fmtTime(s.actualArrival) : 'NO DATA',
                s.arrivalVarianceMinutes ?? 'NO DATA',
                s.scheduledDeparture ? fmtTime(s.scheduledDeparture) : (s.scheduledTime || 'NO DATA'),
                s.actualDeparture ? fmtTime(s.actualDeparture) : 'NO DATA',
                s.departureVarianceMinutes ?? 'NO DATA',
                s.dwellMinutes ?? 'NO DATA',
                s.status || '',
                s.detectionSource || '',
                s.confidence ?? ''
            ]);
        });
    });

    // 4. travel_segments.csv
    const segHeaders = [
        'Trip ID', 'Bus Name', 'Date', 'Segment Sequence', 'From Stop', 'To Stop',
        'Actual Departure', 'Actual Arrival', 'Actual Travel Time (min)',
        'Distance (km)', 'Distance Source', 'Avg Speed (km/h)',
        'Scheduled Travel Time (min)', 'Variance (min)', 'Status'
    ];
    const segRows = [];
    trips.forEach(t => {
        (t.segments || []).forEach(seg => {
            segRows.push([
                t.tripId || '',
                t.busNo || '',
                t.date || reportData.date || '',
                seg.segmentSequence ?? '',
                seg.fromStop || '',
                seg.toStop || '',
                seg.actualDeparture ? fmtTime(seg.actualDeparture) : 'NO DATA',
                seg.actualArrival ? fmtTime(seg.actualArrival) : 'NO DATA',
                seg.travelDurationMinutes ?? 'NO DATA',
                seg.distanceKm ?? 'NO DATA',
                seg.distanceSource || 'INSUFFICIENT GPS DATA',
                seg.averageSpeedKmh ?? 'NO DATA',
                seg.scheduledTravelDurationMinutes ?? 'NO DATA',
                seg.varianceMinutes ?? 'NO DATA',
                seg.status || ''
            ]);
        });
    });

    // 5. gps_telemetry.csv
    const gpsHeaders = [
        'Trip ID', 'Bus Name', 'Date', 'Total Samples', 'Valid Samples', 'Invalid Samples',
        'First GPS (IST)', 'Last GPS (IST)', 'Coverage (min)', 'Avg Interval (s)',
        'Min Interval (s)', 'Max Interval (s)', 'GPS Gaps', 'Longest Gap (s)',
        'Accuracy Available', 'Avg Accuracy (m)', 'Completeness %'
    ];
    const gpsRows = trips.map(t => {
        const g = t.gpsTelemetry || {};
        return [
            t.tripId || '',
            t.busNo || '',
            t.date || reportData.date || '',
            g.totalSamples ?? 0,
            g.validSamples ?? 0,
            g.invalidSamples ?? 0,
            g.firstGpsTimestamp ? fmtTime(g.firstGpsTimestamp) : 'NO DATA',
            g.lastGpsTimestamp ? fmtTime(g.lastGpsTimestamp) : 'NO DATA',
            g.coverageDurationMinutes ?? 0,
            g.averageSamplingIntervalSeconds ?? 'NO DATA',
            g.minimumSamplingIntervalSeconds ?? 'NO DATA',
            g.maximumSamplingIntervalSeconds ?? 'NO DATA',
            g.gpsGapCount ?? 0,
            g.longestGpsGapSeconds ?? 'NO DATA',
            g.accuracyAvailable ? 'YES' : 'NO',
            g.averageAccuracyMeters ?? 'NO DATA',
            g.telemetryCompletenessPercent ?? 'NO DATA'
        ];
    });

    // 6. fleet_summary.csv
    const fleetHeaders = ['Metric', 'Value'];
    const fleetRows = [
        ['Date', reportData.date || ''],
        ['Total Buses', fleet.totalBuses],
        ['Active Buses', fleet.activeBuses],
        ['Total Trips', fleet.totalTrips],
        ['Completed Trips', fleet.completedTrips],
        ['LIVE GPS Trips', fleet.liveGpsTrips],
        ['Insufficient GPS Trips', fleet.insufficientGpsTrips],
        ['Scheduled / Estimated Trips', fleet.scheduledEstimatedTrips],
        ['No Data Trips', fleet.noDataTrips],
        ['Total GPS Distance (km)', fleet.totalDistanceKm ?? 'NO DATA'],
        ['Avg Trip Duration (min)', fleet.averageTripDurationMinutes ?? 'NO DATA'],
        ['Avg GPS Distance (km)', fleet.averageDistanceKm ?? 'NO DATA'],
        ['Avg Speed (km/h)', fleet.averageSpeedKmh ?? 'NO DATA'],
        ['Avg Delay (min)', fleet.averageDelayMinutes ?? 'NO DATA'],
        ['On-Time %', fleet.onTimeTripPercent ?? 'NO DATA'],
        ['Delayed %', fleet.delayedTripPercent ?? 'NO DATA'],
        ['Avg Dwell (min)', fleet.averageDwellMinutes ?? 'NO DATA'],
        ['Total GPS Samples', fleet.totalGpsSamples],
        ['Total GPS Gaps', fleet.totalGpsGaps],
        ['Avg Telemetry Completeness %', fleet.averageTelemetryCompletenessPercent ?? 'NO DATA'],
        ['Invalid GPS Samples', dq.invalidGpsSampleCount]
    ];

    return {
        'trip_summary.csv': buildCsvFromRows(tripSummaryHeaders, tripSummaryRows),
        'journey_timeline.csv': buildCsvFromRows(timelineHeaders, timelineRows),
        'stop_analytics.csv': buildCsvFromRows(stopHeaders, stopRows),
        'travel_segments.csv': buildCsvFromRows(segHeaders, segRows),
        'gps_telemetry.csv': buildCsvFromRows(gpsHeaders, gpsRows),
        'fleet_summary.csv': buildCsvFromRows(fleetHeaders, fleetRows)
    };
}

/**
 * Generates a single normalized CSV string from the canonical reportData.
 * @param {Object} reportData
 * @param {string} csvType 'trip_summary' | 'journey_timeline' | 'stop_analytics' | 'travel_segments' | 'gps_telemetry' | 'fleet_summary'
 */
function generateTripReportCsvString(reportData, csvType = 'trip_summary') {
    const files = generateTripReportCsvFiles(reportData);
    const key = csvType.endsWith('.csv') ? csvType : `${csvType}.csv`;
    return files[key] || files['trip_summary.csv'];
}

/**
 * Generates a structured multi-page A4 Landscape PDF report consuming ONLY canonical reportData:
 * Page 1: Executive Summary
 * Page 2: Actual Journey Timeline
 * Page 3: Stop Performance
 * Page 4: Travel Segments
 * Page 5: GPS Telemetry
 * Page 6: Delay / Route Analysis
 * Page 7+: Fleet / Bus / Stop Analytics
 */
function generateTripReportPdfBuffer(reportData) {
    return new Promise((resolve, reject) => {
        try {
            const doc = new PDFDocument({
                size: 'A4',
                layout: 'landscape',
                margin: 28,
                bufferPages: true
            });

            const chunks = [];
            doc.on('data', chunk => chunks.push(chunk));
            doc.on('end', () => resolve(Buffer.concat(chunks)));
            doc.on('error', err => reject(err));

            const pageWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
            const startX = doc.page.margins.left;
            const bottomLimit = doc.page.height - doc.page.margins.bottom - 26;

            const trips = Array.isArray(reportData.allTrips) ? reportData.allTrips : [];
            const fleet = reportData.fleetAnalytics || computeFleetAnalytics(trips, reportData.totalBuses || 0);
            const dq = reportData.dataQuality || computeDataQualityAnalytics(trips);
            const busList = reportData.busAnalytics || computeBusAnalytics(trips);
            const routeList = reportData.routeAnalytics || computeRouteAnalytics(trips);
            const stopPerfList = reportData.stopPerformance || computeStopPerformanceAnalytics(trips);
            const generatedAt = new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });

            const drawSectionTitle = (title, subtitle) => {
                doc.fillColor('#0F172A').font('Helvetica-Bold').fontSize(12).text(title, startX, doc.y, { width: pageWidth });
                if (subtitle) {
                    doc.fillColor('#475569').font('Helvetica').fontSize(8.5).text(subtitle, startX, doc.y + 2, { width: pageWidth });
                }
                doc.y += 8;
            };

            const drawTableSection = ({ title, subtitle, columns, rows, newPage = true, emptyMsg = 'No records available.' }) => {
                if (newPage) {
                    doc.addPage();
                } else if (doc.y + 60 > bottomLimit) {
                    doc.addPage();
                }

                drawSectionTitle(title, subtitle);

                const drawHeader = () => {
                    const hy = doc.y;
                    doc.save();
                    doc.rect(startX, hy, pageWidth, 18).fill('#1E293B');
                    let cx = startX;
                    doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(7.5);
                    columns.forEach(col => {
                        doc.text(col.label, cx + 4, hy + 5, { width: col.width - 8, ellipsis: true, lineBreak: false });
                        cx += col.width;
                    });
                    doc.restore();
                    doc.y = hy + 20;
                };

                drawHeader();

                if (!rows || rows.length === 0) {
                    doc.fillColor('#64748B').font('Helvetica').fontSize(9).text(emptyMsg, startX, doc.y + 6);
                    doc.y += 24;
                    return;
                }

                rows.forEach((rowCells, idx) => {
                    const rowHeight = 16;
                    if (doc.y + rowHeight > bottomLimit) {
                        doc.addPage();
                        drawHeader();
                    }
                    const ry = doc.y;
                    doc.save();
                    doc.rect(startX, ry, pageWidth, rowHeight).fill(idx % 2 === 0 ? '#FFFFFF' : '#F8FAFC');
                    doc.restore();

                    let cx = startX;
                    doc.font('Helvetica').fontSize(7).fillColor('#0F172A');
                    columns.forEach((col, cIdx) => {
                        doc.text(String(rowCells[cIdx] ?? 'NO DATA'), cx + 4, ry + 4, {
                            width: col.width - 8,
                            ellipsis: true,
                            lineBreak: false
                        });
                        cx += col.width;
                    });
                    doc.y = ry + rowHeight;
                });
                doc.y += 10;
            };

            // ── PAGE 1: EXECUTIVE SUMMARY ──
            doc.save();
            doc.rect(startX, doc.y, pageWidth, 48).fill('#0F172A');
            doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(14)
                .text('SISTec Ratibad Campus - Fleet & Journey Analytics Report', startX + 12, doc.y + 8, { width: pageWidth - 24 });
            doc.fillColor('#CBD5E1').font('Helvetica').fontSize(9)
                .text(`Date: ${reportData.date || 'N/A'} (${reportData.day || ''})  |  Shift: ${String(reportData.shift || 'all').toUpperCase()}  |  Generated: ${generatedAt} IST`, startX + 12, doc.y + 2, { width: pageWidth - 24 });
            doc.restore();
            doc.y += 58;

            const kpis = [
                { label: 'Fleet Size', value: String(fleet.totalBuses ?? 0) },
                { label: 'Total Trips', value: String(fleet.totalTrips ?? 0) },
                { label: 'GPS-Backed Trips', value: String(fleet.liveGpsTrips ?? 0) },
                { label: 'Scheduled-Only Trips', value: String(fleet.scheduledEstimatedTrips ?? 0) },
                { label: 'Total GPS Distance', value: fleet.totalDistanceKm !== null ? `${fleet.totalDistanceKm} km` : 'NO DATA' },
                { label: 'Avg Trip Duration', value: fleet.averageTripDurationMinutes !== null ? `${fleet.averageTripDurationMinutes} min` : 'NO DATA' },
                { label: 'Avg Delay', value: fleet.averageDelayMinutes !== null ? `${fleet.averageDelayMinutes} min` : 'NO DATA' },
                { label: 'On-Time %', value: fleet.onTimeTripPercent !== null ? `${fleet.onTimeTripPercent}%` : 'NO DATA' },
                { label: 'Avg Completeness', value: fleet.averageTelemetryCompletenessPercent !== null ? `${fleet.averageTelemetryCompletenessPercent}%` : 'NO DATA' },
                { label: 'Total GPS Gaps', value: String(fleet.totalGpsGaps ?? 0) }
            ];
            const boxGap = 8;
            const colsPerRow = 5;
            const boxWidth = (pageWidth - boxGap * (colsPerRow - 1)) / colsPerRow;
            kpis.forEach((kpi, idx) => {
                const rowIdx = Math.floor(idx / colsPerRow);
                const colIdx = idx % colsPerRow;
                const bx = startX + colIdx * (boxWidth + boxGap);
                const by = doc.y + rowIdx * 42;
                doc.save();
                doc.roundedRect(bx, by, boxWidth, 36, 4).fillAndStroke('#F1F5F9', '#CBD5E1');
                doc.fillColor('#475569').font('Helvetica').fontSize(7.5).text(kpi.label, bx + 8, by + 6, { width: boxWidth - 16 });
                doc.fillColor('#0F172A').font('Helvetica-Bold').fontSize(10.5).text(kpi.value, bx + 8, by + 18, { width: boxWidth - 16 });
                doc.restore();
            });
            doc.y += 96;

            // Executive Trip Summary Table on Page 1
            drawTableSection({
                title: 'Trip Summary (Canonical Dataset)',
                subtitle: `Complete Trips: ${dq.completeTelemetryTrips} | Partial Telemetry: ${dq.partialTelemetryTrips} | Invalid GPS Samples: ${dq.invalidGpsSampleCount}`,
                newPage: false,
                columns: [
                    { label: 'Trip ID', width: 92 },
                    { label: 'Bus', width: 52 },
                    { label: 'Route', width: 120 },
                    { label: 'Dir', width: 72 },
                    { label: 'Data Source', width: 88 },
                    { label: 'Sched Dep', width: 54 },
                    { label: 'Act Dep', width: 54 },
                    { label: 'Act Arr', width: 54 },
                    { label: 'Dist(km)', width: 50 },
                    { label: 'Stops', width: 44 },
                    { label: 'Status', width: pageWidth - 680 }
                ],
                rows: trips.map(t => [
                    t.displayTripId || t.tripId,
                    t.busNo,
                    stripReportDecorators(t.routeName),
                    t.direction,
                    t.dataSource,
                    t.scheduledDeparture || 'NO DATA',
                    t.actualDeparture || 'NO DATA',
                    t.actualArrival || 'NO DATA',
                    t.actualDistanceKm ?? 'NO DATA',
                    String(t.stopsCompleted || '0/0').replace(/\s+/g, ''),
                    stripReportDecorators(t.status)
                ])
            });

            // ── PAGE 2: ACTUAL JOURNEY TIMELINE ──
            const timelineRows = [];
            trips.forEach(t => {
                (t.journeyTimeline || []).forEach(ev => {
                    timelineRows.push([
                        t.displayTripId || t.tripId,
                        t.busNo,
                        ev.timestamp ? fmtTime(ev.timestamp) : 'NO DATA',
                        ev.eventType,
                        ev.stopName || '-',
                        ev.source || '-',
                        ev.confidence ?? '-'
                    ]);
                });
            });
            drawTableSection({
                title: 'Actual Journey Timeline',
                subtitle: 'Chronological GPS Start, Movement Start, Stop Arrivals/Departures, and Trip End events',
                newPage: true,
                columns: [
                    { label: 'Trip ID', width: 130 },
                    { label: 'Bus', width: 65 },
                    { label: 'Timestamp (IST)', width: 90 },
                    { label: 'Event Type', width: 125 },
                    { label: 'Stop / Segment', width: 185 },
                    { label: 'Source', width: 115 },
                    { label: 'Confidence', width: pageWidth - 710 }
                ],
                rows: timelineRows,
                emptyMsg: 'No GPS journey timeline events available for the selected filters.'
            });

            // ── PAGE 3: STOP PERFORMANCE ──
            const stopPerfRows = [];
            trips.forEach(t => {
                (t.stops || []).forEach(s => {
                    stopPerfRows.push([
                        t.displayTripId || t.tripId,
                        s.stopName || s.name,
                        s.scheduledArrival ? fmtTime(s.scheduledArrival) : (s.scheduledTime || 'NO DATA'),
                        s.actualArrival ? fmtTime(s.actualArrival) : 'NO DATA',
                        s.arrivalVarianceMinutes ?? 'NO DATA',
                        s.actualDeparture ? fmtTime(s.actualDeparture) : 'NO DATA',
                        s.departureVarianceMinutes ?? 'NO DATA',
                        s.dwellMinutes !== null && s.dwellMinutes !== undefined ? `${s.dwellMinutes}m` : 'NO DATA',
                        s.status || 'UNRECORDED'
                    ]);
                });
            });
            drawTableSection({
                title: 'Stop Performance (Trip-Level Reconstructed Stops)',
                subtitle: 'Actual geofence arrival, departure, dwell, and schedule variance',
                newPage: true,
                columns: [
                    { label: 'Trip ID', width: 115 },
                    { label: 'Stop', width: 145 },
                    { label: 'Sched Arr', width: 70 },
                    { label: 'Act Arr', width: 70 },
                    { label: 'Arr Var', width: 55 },
                    { label: 'Act Dep', width: 70 },
                    { label: 'Dep Var', width: 55 },
                    { label: 'Dwell', width: 55 },
                    { label: 'Status', width: pageWidth - 635 }
                ],
                rows: stopPerfRows
            });

            // ── PAGE 4: TRAVEL SEGMENTS ──
            const segRows = [];
            trips.forEach(t => {
                (t.segments || []).forEach(seg => {
                    segRows.push([
                        t.displayTripId || t.tripId,
                        seg.fromStop,
                        seg.toStop,
                        seg.travelDurationMinutes ?? 'NO DATA',
                        seg.distanceKm ?? 'NO DATA',
                        seg.averageSpeedKmh ?? 'NO DATA',
                        seg.scheduledTravelDurationMinutes ?? 'NO DATA',
                        seg.varianceMinutes ?? 'NO DATA',
                        seg.status
                    ]);
                });
            });
            drawTableSection({
                title: 'Travel Segments (Inter-Stop Analytics)',
                subtitle: 'Actual GPS segment travel duration, distance, average speed, and schedule variance',
                newPage: true,
                columns: [
                    { label: 'Trip ID', width: 115 },
                    { label: 'From', width: 130 },
                    { label: 'To', width: 130 },
                    { label: 'Act Time(m)', width: 65 },
                    { label: 'Dist(km)', width: 60 },
                    { label: 'Avg Spd', width: 60 },
                    { label: 'Sched(m)', width: 60 },
                    { label: 'Var(m)', width: 55 },
                    { label: 'Status', width: pageWidth - 675 }
                ],
                rows: segRows,
                emptyMsg: 'No inter-stop travel segments available.'
            });

            // ── PAGE 5: GPS TELEMETRY ──
            drawTableSection({
                title: 'GPS Telemetry Quality',
                subtitle: 'Sample counts, coverage duration, sampling intervals, gaps, accuracy, and completeness',
                newPage: true,
                columns: [
                    { label: 'Trip ID', width: 120 },
                    { label: 'Bus', width: 60 },
                    { label: 'Valid/Total', width: 70 },
                    { label: 'Coverage(m)', width: 70 },
                    { label: 'Avg Int(s)', width: 65 },
                    { label: 'GPS Gaps', width: 60 },
                    { label: 'Max Gap(s)', width: 70 },
                    { label: 'Avg Acc(m)', width: 70 },
                    { label: 'Completeness %', width: pageWidth - 585 }
                ],
                rows: trips.map(t => {
                    const g = t.gpsTelemetry || {};
                    return [
                        t.displayTripId || t.tripId,
                        t.busNo,
                        `${g.validSamples ?? 0}/${g.totalSamples ?? 0}`,
                        g.coverageDurationMinutes ?? 0,
                        g.averageSamplingIntervalSeconds ?? 'NO DATA',
                        g.gpsGapCount ?? 0,
                        g.longestGpsGapSeconds ?? 'NO DATA',
                        g.averageAccuracyMeters ?? 'NO DATA',
                        g.telemetryCompletenessPercent !== null && g.telemetryCompletenessPercent !== undefined ? `${g.telemetryCompletenessPercent}%` : 'NO DATA'
                    ];
                })
            });

            // ── PAGE 6: DELAY / ROUTE ANALYSIS ──
            drawTableSection({
                title: 'Delay & Route Analysis (Direction-Separated)',
                subtitle: 'Route performance separated by direction (stops -> campus vs campus -> stops)',
                newPage: true,
                columns: [
                    { label: 'Route Name', width: 165 },
                    { label: 'Direction', width: 95 },
                    { label: 'Trips', width: 45 },
                    { label: 'Avg Dist(km)', width: 75 },
                    { label: 'Avg Dur(m)', width: 70 },
                    { label: 'Avg Spd', width: 65 },
                    { label: 'Avg Delay(m)', width: 75 },
                    { label: 'On-Time %', width: 65 },
                    { label: 'Avg Dwell(m)', width: 70 },
                    { label: 'Completeness %', width: pageWidth - 725 }
                ],
                rows: routeList.map(r => [
                    stripReportDecorators(r.routeName),
                    r.direction,
                    r.tripCount,
                    r.averageDistanceKm ?? 'NO DATA',
                    r.averageDurationMinutes ?? 'NO DATA',
                    r.averageSpeedKmh ?? 'NO DATA',
                    r.averageDelayMinutes ?? 'NO DATA',
                    r.onTimePercent !== null ? `${r.onTimePercent}%` : 'NO DATA',
                    r.averageDwellMinutes ?? 'NO DATA',
                    r.gpsCompletenessPercent !== null ? `${r.gpsCompletenessPercent}%` : 'NO DATA'
                ])
            });

            // ── PAGE 7+: FLEET / BUS / STOP ANALYTICS ──
            drawTableSection({
                title: 'Bus-Level Analytics',
                subtitle: 'Per-bus GPS vs Scheduled breakdown',
                newPage: true,
                columns: [
                    { label: 'Bus', width: 70 },
                    { label: 'Plate', width: 95 },
                    { label: 'Trips', width: 45 },
                    { label: 'GPS Trips', width: 60 },
                    { label: 'Sched Trips', width: 65 },
                    { label: 'Total Dist(km)', width: 80 },
                    { label: 'Avg Dur(m)', width: 70 },
                    { label: 'Avg Spd', width: 65 },
                    { label: 'Avg Delay(m)', width: 75 },
                    { label: 'On-Time %', width: 65 },
                    { label: 'Completeness %', width: pageWidth - 690 }
                ],
                rows: busList.map(b => [
                    b.busNo,
                    b.busNumber,
                    b.totalTrips,
                    b.gpsTripCount,
                    b.scheduledOnlyTripCount,
                    b.totalDistanceKm ?? 'NO DATA',
                    b.averageTripDurationMinutes ?? 'NO DATA',
                    b.averageSpeedKmh ?? 'NO DATA',
                    b.averageDelayMinutes ?? 'NO DATA',
                    b.onTimePercent !== null ? `${b.onTimePercent}%` : 'NO DATA',
                    b.telemetryCompletenessPercent !== null ? `${b.telemetryCompletenessPercent}%` : 'NO DATA'
                ])
            });

            drawTableSection({
                title: 'Fleet Stop Performance Summary',
                subtitle: 'Aggregated stop punctuality, dwell, reached, missed, and unrecorded counts',
                newPage: false,
                columns: [
                    { label: 'Stop Name', width: 175 },
                    { label: 'Sched Arr', width: 75 },
                    { label: 'Avg Act Arr', width: 75 },
                    { label: 'Avg Arr Var', width: 75 },
                    { label: 'Avg Dwell(m)', width: 75 },
                    { label: 'Reached', width: 60 },
                    { label: 'Missed', width: 55 },
                    { label: 'Unrecorded', width: 70 },
                    { label: 'On-Time %', width: pageWidth - 660 }
                ],
                rows: stopPerfList.map(sp => [
                    sp.stopName,
                    sp.scheduledArrival || 'NO DATA',
                    sp.averageActualArrival || 'NO DATA',
                    sp.averageArrivalVariance ?? 'NO DATA',
                    sp.averageDwellMinutes ?? 'NO DATA',
                    sp.reachedCount,
                    sp.missedCount,
                    sp.unrecordedCount,
                    sp.onTimePercent !== null ? `${sp.onTimePercent}%` : 'NO DATA'
                ])
            });

            // Footer page numbers
            const pageRange = doc.bufferedPageRange();
            for (let i = 0; i < pageRange.count; i++) {
                doc.switchToPage(i);
                doc.fillColor('#64748B').font('Helvetica').fontSize(7.5).text(
                    `SISTecChalo Fleet & Journey Analytics  |  Page ${i + 1} of ${pageRange.count}`,
                    startX,
                    doc.page.height - doc.page.margins.bottom - 12,
                    { width: pageWidth, align: 'right' }
                );
            }

            doc.end();
        } catch (err) {
            reject(err);
        }
    });
}

/**
 * Generates an executive 12-sheet Microsoft Excel (.xlsx) workbook strictly from canonical reportData:
 * 1. Executive Summary
 * 2. Fleet Summary
 * 3. Bus Journey Summary
 * 4. Journey Timeline (1 row per event)
 * 5. Stop Analytics (1 row per trip-stop)
 * 6. Travel Segments (1 row per segment)
 * 7. GPS Telemetry (1 row per trip)
 * 8. Route Analytics
 * 9. Bus Analytics
 * 10. Stop Performance
 * 11. Data Quality
 * 12. Master Trip Log
 */
function generateTripReportExcelBuffer(reportData) {
    const wb = XLSX.utils.book_new();
    const allTrips = reportData.allTrips || [];
    const fleet = reportData.fleetAnalytics || computeFleetAnalytics(allTrips, reportData.totalBuses || 0);
    const busList = reportData.busAnalytics || computeBusAnalytics(allTrips);
    const routeList = reportData.routeAnalytics || computeRouteAnalytics(allTrips);
    const stopPerfList = reportData.stopPerformance || computeStopPerformanceAnalytics(allTrips);
    const dq = reportData.dataQuality || computeDataQualityAnalytics(allTrips);

    // 1. Executive Summary
    const execRows = [
        ['SISTec Ratibad Campus - Fleet & Journey Analytics Executive Report'],
        [`Operational Date: ${reportData.date} (${reportData.day}) | Shift: ${reportData.shift || 'all'} | Generated: ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })} IST`],
        [],
        ['Key Metric', 'Value'],
        ['Fleet Size', fleet.totalBuses],
        ['Active Buses', fleet.activeBuses],
        ['Total Trips', fleet.totalTrips],
        ['Completed Trips', fleet.completedTrips],
        ['LIVE GPS Trips', fleet.liveGpsTrips],
        ['Insufficient GPS Trips', fleet.insufficientGpsTrips],
        ['Scheduled / Estimated Trips', fleet.scheduledEstimatedTrips],
        ['No Data Trips', fleet.noDataTrips],
        ['Total Actual GPS Distance (km)', fleet.totalDistanceKm ?? 'NO DATA'],
        ['Average Trip Duration (min)', fleet.averageTripDurationMinutes ?? 'NO DATA'],
        ['Average Delay (min)', fleet.averageDelayMinutes ?? 'NO DATA'],
        ['On-Time %', fleet.onTimeTripPercent !== null ? `${fleet.onTimeTripPercent}%` : 'NO DATA'],
        ['Average Telemetry Completeness %', fleet.averageTelemetryCompletenessPercent !== null ? `${fleet.averageTelemetryCompletenessPercent}%` : 'NO DATA']
    ];
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(execRows), 'Executive Summary');

    // 2. Fleet Summary
    const fleetRows = [
        ['Metric', 'Value'],
        ...Object.entries(fleet).map(([k, v]) => [k, v ?? 'NO DATA'])
    ];
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(fleetRows), 'Fleet Summary');

    // 3. Bus Journey Summary
    const busJourneyHeaders = [
        'Trip ID', 'Display Trip ID', 'Date', 'Bus No', 'Vehicle Plate', 'Route Name', 'Direction',
        'Data Source', 'Movement Start', 'Scheduled Departure', 'Actual Departure',
        'Scheduled Arrival', 'Actual Arrival', 'Actual Distance (km)', 'Actual Duration (min)',
        'Avg Speed (km/h)', 'Stops Reached', 'Avg Dwell (min)', 'Avg Delay (min)', 'Completeness %', 'Status'
    ];
    const busJourneyRows = allTrips.map(t => [
        t.tripId,
        t.displayTripId || t.tripId,
        t.date,
        t.busNo,
        t.busNumber || t.vehicleNo,
        stripReportDecorators(t.routeName),
        t.direction,
        t.dataSource,
        t.movementStartTimestamp ? fmtTime(t.movementStartTimestamp) : 'NO DATA',
        t.scheduledDeparture || 'NO DATA',
        t.actualDeparture || 'NO DATA',
        t.scheduledArrival || 'NO DATA',
        t.actualArrival || 'NO DATA',
        t.actualDistanceKm ?? 'NO DATA',
        t.totalDurationMinutes ?? 'NO DATA',
        t.averageSpeedKmh ?? 'NO DATA',
        t.stopsCompleted,
        t.averageDwellMinutes ?? 'NO DATA',
        t.averageDelayMinutes ?? 'NO DATA',
        t.telemetryCompletenessPercent ?? 'NO DATA',
        stripReportDecorators(t.status)
    ]);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([busJourneyHeaders, ...busJourneyRows]), 'Bus Journey Summary');

    // 4. Journey Timeline (1 row per event)
    const timelineHeaders = ['Trip ID', 'Display Trip ID', 'Bus No', 'Date', 'Timestamp (IST)', 'Event Type', 'Stop ID', 'Stop Name', 'Source', 'Confidence'];
    const timelineRows = [];
    allTrips.forEach(t => {
        (t.journeyTimeline || []).forEach(ev => {
            timelineRows.push([
                t.tripId,
                t.displayTripId || t.tripId,
                t.busNo,
                t.date,
                ev.timestamp ? fmtTime(ev.timestamp) : 'NO DATA',
                ev.eventType,
                ev.stopId || '',
                ev.stopName || '',
                ev.source || '',
                ev.confidence ?? ''
            ]);
        });
    });
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([timelineHeaders, ...timelineRows]), 'Journey Timeline');

    // 5. Stop Analytics (1 row per trip-stop)
    const stopHeaders = [
        'Trip ID', 'Bus No', 'Date', 'Stop Sequence', 'Stop ID', 'Stop Name',
        'Scheduled Arrival', 'Actual Arrival', 'Arrival Variance (min)',
        'Scheduled Departure', 'Actual Departure', 'Departure Variance (min)',
        'Dwell (min)', 'Status', 'Detection Source', 'Confidence'
    ];
    const stopRows = [];
    allTrips.forEach(t => {
        (t.stops || []).forEach(s => {
            stopRows.push([
                t.tripId,
                t.busNo,
                t.date,
                s.stopSequence ?? s.stopNumber ?? '',
                s.stopId || '',
                s.stopName || s.name,
                s.scheduledArrival ? fmtTime(s.scheduledArrival) : (s.scheduledTime || 'NO DATA'),
                s.actualArrival ? fmtTime(s.actualArrival) : 'NO DATA',
                s.arrivalVarianceMinutes ?? 'NO DATA',
                s.scheduledDeparture ? fmtTime(s.scheduledDeparture) : (s.scheduledTime || 'NO DATA'),
                s.actualDeparture ? fmtTime(s.actualDeparture) : 'NO DATA',
                s.departureVarianceMinutes ?? 'NO DATA',
                s.dwellMinutes ?? 'NO DATA',
                s.status,
                s.detectionSource || '',
                s.confidence ?? ''
            ]);
        });
    });
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([stopHeaders, ...stopRows]), 'Stop Analytics');

    // 6. Travel Segments (1 row per segment)
    const segHeaders = [
        'Trip ID', 'Bus No', 'Date', 'Segment Sequence', 'From Stop', 'To Stop',
        'Actual Departure', 'Actual Arrival', 'Travel Duration (min)',
        'Distance (km)', 'Distance Source', 'Avg Speed (km/h)',
        'Scheduled Duration (min)', 'Variance (min)', 'Status'
    ];
    const segRows = [];
    allTrips.forEach(t => {
        (t.segments || []).forEach(seg => {
            segRows.push([
                t.tripId,
                t.busNo,
                t.date,
                seg.segmentSequence,
                seg.fromStop,
                seg.toStop,
                seg.actualDeparture ? fmtTime(seg.actualDeparture) : 'NO DATA',
                seg.actualArrival ? fmtTime(seg.actualArrival) : 'NO DATA',
                seg.travelDurationMinutes ?? 'NO DATA',
                seg.distanceKm ?? 'NO DATA',
                seg.distanceSource,
                seg.averageSpeedKmh ?? 'NO DATA',
                seg.scheduledTravelDurationMinutes ?? 'NO DATA',
                seg.varianceMinutes ?? 'NO DATA',
                seg.status
            ]);
        });
    });
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([segHeaders, ...segRows]), 'Travel Segments');

    // 7. GPS Telemetry
    const gpsHeaders = [
        'Trip ID', 'Bus No', 'Date', 'Total Samples', 'Valid Samples', 'Invalid Samples',
        'First GPS', 'Last GPS', 'Coverage (min)', 'Avg Interval (s)', 'Min Interval (s)',
        'Max Interval (s)', 'GPS Gaps', 'Longest Gap (s)', 'Accuracy Available', 'Avg Accuracy (m)', 'Completeness %'
    ];
    const gpsRows = allTrips.map(t => {
        const g = t.gpsTelemetry || {};
        return [
            t.tripId,
            t.busNo,
            t.date,
            g.totalSamples ?? 0,
            g.validSamples ?? 0,
            g.invalidSamples ?? 0,
            g.firstGpsTimestamp ? fmtTime(g.firstGpsTimestamp) : 'NO DATA',
            g.lastGpsTimestamp ? fmtTime(g.lastGpsTimestamp) : 'NO DATA',
            g.coverageDurationMinutes ?? 0,
            g.averageSamplingIntervalSeconds ?? 'NO DATA',
            g.minimumSamplingIntervalSeconds ?? 'NO DATA',
            g.maximumSamplingIntervalSeconds ?? 'NO DATA',
            g.gpsGapCount ?? 0,
            g.longestGpsGapSeconds ?? 'NO DATA',
            g.accuracyAvailable ? 'YES' : 'NO',
            g.averageAccuracyMeters ?? 'NO DATA',
            g.telemetryCompletenessPercent ?? 'NO DATA'
        ];
    });
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([gpsHeaders, ...gpsRows]), 'GPS Telemetry');

    // 8. Route Analytics
    const routeHeaders = [
        'Route ID', 'Route Name', 'Direction', 'Trip Count', 'Total GPS Distance (km)',
        'Avg Distance (km)', 'Avg Duration (min)', 'Avg Speed (km/h)', 'Avg Delay (min)',
        'On-Time %', 'Avg Dwell (min)', 'GPS Completeness %'
    ];
    const routeRows = routeList.map(r => [
        r.routeId || '',
        stripReportDecorators(r.routeName),
        r.direction,
        r.tripCount,
        r.distanceKm ?? 'NO DATA',
        r.averageDistanceKm ?? 'NO DATA',
        r.averageDurationMinutes ?? 'NO DATA',
        r.averageSpeedKmh ?? 'NO DATA',
        r.averageDelayMinutes ?? 'NO DATA',
        r.onTimePercent ?? 'NO DATA',
        r.averageDwellMinutes ?? 'NO DATA',
        r.gpsCompletenessPercent ?? 'NO DATA'
    ]);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([routeHeaders, ...routeRows]), 'Route Analytics');

    // 9. Bus Analytics
    const busHeaders = [
        'Bus ID', 'Bus No', 'Vehicle Plate', 'Total Trips', 'Completed Trips',
        'Total GPS Distance (km)', 'Avg Distance (km)', 'Avg Duration (min)', 'Avg Speed (km/h)',
        'Avg Delay (min)', 'On-Time %', 'Avg Dwell (min)', 'GPS Trips', 'Scheduled-Only Trips', 'Completeness %'
    ];
    const busRows = busList.map(b => [
        b.busId,
        b.busNo,
        b.busNumber,
        b.totalTrips,
        b.completedTrips,
        b.totalDistanceKm ?? 'NO DATA',
        b.averageDistanceKm ?? 'NO DATA',
        b.averageTripDurationMinutes ?? 'NO DATA',
        b.averageSpeedKmh ?? 'NO DATA',
        b.averageDelayMinutes ?? 'NO DATA',
        b.onTimePercent ?? 'NO DATA',
        b.averageDwellMinutes ?? 'NO DATA',
        b.gpsTripCount,
        b.scheduledOnlyTripCount,
        b.telemetryCompletenessPercent ?? 'NO DATA'
    ]);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([busHeaders, ...busRows]), 'Bus Analytics');

    // 10. Stop Performance
    const stopPerfHeaders = [
        'Stop ID', 'Stop Name', 'Route ID', 'Scheduled Arrival', 'Avg Actual Arrival',
        'Avg Arrival Variance (min)', 'Avg Departure Variance (min)', 'Avg Dwell (min)',
        'Reached Count', 'Missed Count', 'Unrecorded Count', 'On-Time %'
    ];
    const stopPerfRows = stopPerfList.map(sp => [
        sp.stopId || '',
        sp.stopName,
        sp.routeId || '',
        sp.scheduledArrival || 'NO DATA',
        sp.averageActualArrival || 'NO DATA',
        sp.averageArrivalVariance ?? 'NO DATA',
        sp.averageDepartureVariance ?? 'NO DATA',
        sp.averageDwellMinutes ?? 'NO DATA',
        sp.reachedCount,
        sp.missedCount,
        sp.unrecordedCount,
        sp.onTimePercent ?? 'NO DATA'
    ]);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([stopPerfHeaders, ...stopPerfRows]), 'Stop Performance');

    // 11. Data Quality
    const dqRows = [
        ['Data Quality Metric', 'Value'],
        ...Object.entries(dq).map(([k, v]) => [k, v ?? 'NO DATA'])
    ];
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(dqRows), 'Data Quality');

    // 12. Master Trip Log
    const masterHeaders = [
        'Trip ID', 'Display Trip ID', 'Date', 'Day', 'Shift', 'Trip Type', 'Direction', 'Data Source', 'Bus No', 'Vehicle Plate', 'Route Name',
        'Assigned Driver', 'Driver Contact', 'Origin Terminus', 'Destination Terminus',
        'Scheduled Departure', 'Actual Departure', 'Scheduled Arrival', 'Actual Arrival',
        'Movement Start', 'Actual GPS Distance (km)', 'Actual Duration (min)', 'Avg Speed (km/h)',
        'Stops Reached', 'GPS Samples', 'GPS Gaps', 'Completeness %', 'Avg Delay (min)', 'Operational Status'
    ];
    const masterRows = allTrips.map(t => [
        t.tripId,
        t.displayTripId || t.tripId,
        t.date,
        t.day,
        stripReportDecorators(t.shift),
        t.tripType || t.shiftType || 'pickup',
        t.direction || '',
        t.dataSource || DATA_SOURCES.SCHEDULED_ESTIMATED,
        t.busNo,
        t.busNumber || t.vehicleNo,
        stripReportDecorators(t.routeName),
        t.driverName,
        t.driverPhone,
        t.originStop,
        t.destinationStop,
        t.scheduledDeparture || 'NO DATA',
        t.actualDeparture || 'NO DATA',
        t.scheduledArrival || 'NO DATA',
        t.actualArrival || 'NO DATA',
        t.movementStartTimestamp ? fmtTime(t.movementStartTimestamp) : 'NO DATA',
        t.actualDistanceKm ?? 'NO DATA',
        t.totalDurationMinutes ?? 'NO DATA',
        t.averageSpeedKmh ?? 'NO DATA',
        t.stopsCompleted,
        t.validGpsSamples ?? 0,
        t.gpsGapCount ?? 0,
        t.telemetryCompletenessPercent ?? 'NO DATA',
        t.averageDelayMinutes ?? 'NO DATA',
        stripReportDecorators(t.status)
    ]);
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([masterHeaders, ...masterRows]), 'Master Trip Log');

    return XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
}

module.exports = {
    DATA_SOURCES,
    buildCanonicalTripRecord,
    computeFleetAnalytics,
    computeBusAnalytics,
    computeRouteAnalytics,
    computeStopPerformanceAnalytics,
    computeDataQualityAnalytics,
    generateTripReportData,
    generateTripReportExcelBuffer,
    generateTripReportCsvFiles,
    generateTripReportCsvString,
    generateTripReportPdfBuffer,
    stripReportDecorators,
    fmtDate,
    fmtTime,
    getDayOfWeek,
    parseTimeMinutes,
    formatMinutesToTime
};

