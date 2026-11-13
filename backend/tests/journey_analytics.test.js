const { test, describe } = require('node:test');
const assert = require('node:assert/strict');

const {
    analyzeJourney
} = require('../services/journey_analytics_service');

// Helper to build a UTC Date from an IST wall-clock ISO string like '2026-11-13T08:00:00+05:30'
const ist = (isoWithOffset) => new Date(isoWithOffset);

const BASE_ROUTE = {
    _id: 'route_kolar_1',
    name: 'Kolar Road Route',
    stops: [
        { _id: 'stop_1', name: 'Kolar Square', lat: 23.1800, lng: 77.4100, time: '08:05 AM' },
        { _id: 'stop_2', name: 'Bansal Hospital', lat: 23.1900, lng: 77.4100, time: '08:15 AM' },
        { _id: 'stop_3', name: 'SISTec Campus', lat: 23.2000, lng: 77.4100, time: '08:25 AM' }
    ]
};

const BASE_TRIP = {
    _id: '6734b0000000000000000001',
    busId: 'bus_01',
    busNumber: 'MP-04-PA-0001',
    routeId: 'route_kolar_1',
    routeName: 'Kolar Road Route',
    date: '2026-11-13',
    tripType: 'pickup',
    status: 'Completed',
    startTime: ist('2026-11-13T08:00:00+05:30'),
    endTime: ist('2026-11-13T08:30:00+05:30')
};

describe('Phase 3: Actual GPS Journey Reconstruction & Telemetry Analytics', () => {
    test('1. First GPS detection captures exact first valid point', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 0, accuracy: 8, timestamp: ist('2026-11-13T08:01:12+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 0, accuracy: 8, timestamp: ist('2026-11-13T08:01:17+05:30') }
            ]
        });

        assert.equal(result.firstGpsTimestamp.toISOString(), ist('2026-11-13T08:01:12+05:30').toISOString());
        assert.equal(result.firstGpsLat, 23.1750);
        assert.equal(result.firstGpsLng, 77.4100);
    });

    test('2. Movement start detection ignores stationary points and requires consecutive >= 5 km/h samples', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:01:12+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 1.2, timestamp: ist('2026-11-13T08:01:17+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 6.0, timestamp: ist('2026-11-13T08:01:22+05:30') }, // single noisy spike
                { lat: 23.1750, lng: 77.4100, speed: 0.5, timestamp: ist('2026-11-13T08:01:27+05:30') },
                { lat: 23.1755, lng: 77.4100, speed: 12.0, timestamp: ist('2026-11-13T08:01:32+05:30') },
                { lat: 23.1762, lng: 77.4100, speed: 18.0, timestamp: ist('2026-11-13T08:01:37+05:30') }
            ]
        });

        assert.equal(result.movementStartStatus, 'CALCULATED');
        assert.equal(result.movementStartTimestamp.toISOString(), ist('2026-11-13T08:01:32+05:30').toISOString());
        assert.equal(result.movementStartLat, 23.1755);
    });

    test('3. Stationary vehicle leaves movementStartTimestamp null with INSUFFICIENT GPS DATA', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:01:05+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 1, timestamp: ist('2026-11-13T08:01:10+05:30') }
            ]
        });

        assert.equal(result.firstGpsTimestamp.toISOString(), ist('2026-11-13T08:01:00+05:30').toISOString());
        assert.equal(result.movementStartTimestamp, null);
        assert.equal(result.movementStartStatus, 'INSUFFICIENT GPS DATA');
    });

    test('4. Trip end handling distinguishes tripEndTimestamp from lastGpsTimestamp', () => {
        const withLogEnd = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:20:00+05:30') }
            ]
        });
        assert.equal(withLogEnd.lastGpsTimestamp.toISOString(), ist('2026-11-13T08:20:00+05:30').toISOString());
        assert.equal(withLogEnd.tripEndTimestamp.toISOString(), ist('2026-11-13T08:30:00+05:30').toISOString());
        assert.equal(withLogEnd.tripEndSource, 'LIVE_TRIP_LOG');

        const withoutLogEnd = analyzeJourney({
            liveTripLog: { ...BASE_TRIP, endTime: null, status: 'Active' },
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:20:00+05:30') }
            ]
        });
        assert.equal(withoutLogEnd.tripEndTimestamp.toISOString(), ist('2026-11-13T08:20:00+05:30').toISOString());
        assert.equal(withoutLogEnd.tripEndSource, 'LAST_GPS');
    });

    test('5, 6, 7. Stop arrival, departure, and dwell calculation', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: { _id: 'r1', name: 'R1', stops: [BASE_ROUTE.stops[0]] },
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:03:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 2, timestamp: ist('2026-11-13T08:05:00+05:30') }, // Arrival
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:05:10+05:30') }, // Consecutive inside stop
                { lat: 23.1801, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:06:00+05:30') }, // Still at stop
                { lat: 23.1820, lng: 77.4100, speed: 20, timestamp: ist('2026-11-13T08:07:00+05:30') }, // Departure (>150m)
                { lat: 23.1840, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:07:10+05:30') }
            ]
        });

        const stop = result.stops[0];
        assert.equal(stop.status, 'REACHED');
        assert.equal(stop.actualArrival.toISOString(), ist('2026-11-13T08:05:00+05:30').toISOString());
        assert.equal(stop.actualDeparture.toISOString(), ist('2026-11-13T08:07:00+05:30').toISOString());
        assert.equal(stop.dwellMinutes, 2);
        assert.equal(stop.dwellStatus, 'CALCULATED');
    });

    test('8. Missed stop detected when continuous GPS bypasses intermediate stop to reach later stop', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                // Stop 1 reached
                { lat: 23.1800, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:05:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:05:20+05:30') },
                // Continuous 20s telemetry bypassing Stop 2 (offset in lng by ~500m)
                { lat: 23.1850, lng: 77.4150, speed: 30, timestamp: ist('2026-11-13T08:05:40+05:30') },
                { lat: 23.1900, lng: 77.4150, speed: 30, timestamp: ist('2026-11-13T08:06:00+05:30') },
                { lat: 23.1950, lng: 77.4150, speed: 30, timestamp: ist('2026-11-13T08:06:20+05:30') },
                // Stop 3 reached
                { lat: 23.2000, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:06:40+05:30') },
                { lat: 23.2000, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:07:00+05:30') }
            ]
        });

        assert.equal(result.stops[0].status, 'REACHED');
        assert.equal(result.stops[1].status, 'MISSED');
        assert.equal(result.stops[1].detectionSource, 'GPS_BYPASSED');
        assert.equal(result.stops[2].status, 'REACHED');
        assert.equal(result.missedStopCount, 1);
    });

    test('9. Unrecorded stop due to GPS gap spanning stop window', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                // Stop 1 reached
                { lat: 23.1800, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:05:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:05:10+05:30') },
                { lat: 23.1825, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:05:30+05:30') },
                // 10-minute GPS blackout across Stop 2
                { lat: 23.2000, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:15:30+05:30') },
                { lat: 23.2000, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:15:40+05:30') }
            ]
        });

        assert.equal(result.stops[0].status, 'REACHED');
        assert.equal(result.stops[1].status, 'UNRECORDED');
        assert.equal(result.stops[1].detectionSource, 'GPS_GAP');
        assert.equal(result.stops[2].status, 'REACHED');
    });

    test('10. Missing stop coordinates returns UNRECORDED with NO STOP COORDINATES', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: {
                _id: 'r_nocoords',
                name: 'No Coords',
                stops: [{ _id: 's1', name: 'Unknown Stop', time: '08:10 AM' }]
            },
            telemetryPoints: [
                { lat: 23.1800, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:05:00+05:30') },
                { lat: 23.1850, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:05:10+05:30') }
            ]
        });

        assert.equal(result.stops[0].status, 'UNRECORDED');
        assert.equal(result.stops[0].detectionSource, 'NO STOP COORDINATES');
    });

    test('11, 12, 13. Segment travel time, GPS distance, and average speed', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: { _id: 'r2', name: 'R2', stops: [BASE_ROUTE.stops[0], BASE_ROUTE.stops[1]] },
            telemetryPoints: [
                // Stop 1 arrival & departure
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:05:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:05:20+05:30') },
                { lat: 23.1820, lng: 77.4100, speed: 20, timestamp: ist('2026-11-13T08:06:00+05:30') }, // Dep Stop 1
                { lat: 23.1860, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:07:30+05:30') },
                // Stop 2 arrival
                { lat: 23.1900, lng: 77.4100, speed: 5, timestamp: ist('2026-11-13T08:09:00+05:30') },  // Arr Stop 2
                { lat: 23.1900, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:09:10+05:30') }
            ]
        });

        assert.equal(result.segments.length, 1);
        const seg = result.segments[0];
        assert.equal(seg.status, 'COMPLETED');
        assert.equal(seg.travelDurationMinutes, 3); // 08:06 -> 08:09 = 3 mins
        assert.equal(seg.distanceSource, 'GPS');
        assert.ok(seg.distanceKm > 0.8 && seg.distanceKm < 1.0); // ~0.89 km
        assert.equal(seg.averageSpeedKmh, Math.round((seg.distanceKm / (3 / 60)) * 100) / 100);
    });

    test('14. Scheduled vs actual variance (early, on-time, late)', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                // Stop 1 (sched 08:05) -> arrived 08:03 (-2m early)
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:03:00+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:03:10+05:30') },
                { lat: 23.1830, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:03:30+05:30') },
                { lat: 23.1860, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:03:50+05:30') },
                // Stop 2 (sched 08:15) -> arrived 08:15 (0m on-time)
                { lat: 23.1900, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:15:00+05:30') },
                { lat: 23.1900, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:15:10+05:30') },
                { lat: 23.1930, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:15:30+05:30') },
                { lat: 23.1960, lng: 77.4100, speed: 25, timestamp: ist('2026-11-13T08:15:50+05:30') },
                // Stop 3 (sched 08:25) -> arrived 08:30 (+5m late)
                { lat: 23.2000, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:30:00+05:30') },
                { lat: 23.2000, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T08:30:10+05:30') }
            ]
        });

        assert.equal(result.stops[0].arrivalVarianceMinutes, -2);
        assert.equal(result.stops[1].arrivalVarianceMinutes, 0);
        assert.equal(result.stops[2].arrivalVarianceMinutes, 5);
        assert.equal(result.maximumDelayMinutes, 5);
        assert.equal(result.averageDelayMinutes, 1);
    });

    test('15, 16, 17, 18, 19. GPS sample stats, gap detection, longest gap, accuracy stats, completeness', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 10, accuracy: 6, timestamp: ist('2026-11-13T08:00:00+05:30') },
                { lat: 23.1752, lng: 77.4100, speed: 10, accuracy: 10, timestamp: ist('2026-11-13T08:00:10+05:30') }, // 10s
                // 60s gap (> 45s threshold)
                { lat: 23.1760, lng: 77.4100, speed: 12, accuracy: 14, timestamp: ist('2026-11-13T08:01:10+05:30') }, // 60s gap
                // 120s gap (> 45s threshold)
                { lat: 23.1780, lng: 77.4100, speed: 15, accuracy: 10, timestamp: ist('2026-11-13T08:03:10+05:30') }  // 120s gap
            ]
        });

        const q = result.gpsQuality;
        assert.equal(q.totalSamples, 4);
        assert.equal(q.validSamples, 4);
        assert.equal(q.invalidSamples, 0);
        assert.equal(q.minimumSamplingIntervalSeconds, 10);
        assert.equal(q.maximumSamplingIntervalSeconds, 120);
        assert.equal(q.averageSamplingIntervalSeconds, 63.33);
        assert.equal(q.gpsGapCount, 2);
        assert.equal(q.longestGpsGapSeconds, 120);
        assert.equal(q.longestGapStart.toISOString(), ist('2026-11-13T08:01:10+05:30').toISOString());
        assert.equal(q.longestGapEnd.toISOString(), ist('2026-11-13T08:03:10+05:30').toISOString());
        assert.equal(q.accuracyAvailable, true);
        assert.equal(q.minimumAccuracyMeters, 6);
        assert.equal(q.maximumAccuracyMeters, 14);
        assert.equal(q.averageAccuracyMeters, 10);
        // Total coverage = 190s, total gap duration = 180s => completeness = (1 - 180/190)*100 = 5.26%
        assert.equal(q.telemetryCompletenessPercent, 5.26);
    });

    test('20. Multiple trips for same bus/date remain independent by LiveTripLog._id', () => {
        const tripA = { ...BASE_TRIP, _id: 'trip_a_id' };
        const tripB = { ...BASE_TRIP, _id: 'trip_b_id', startTime: ist('2026-11-13T10:00:00+05:30'), endTime: ist('2026-11-13T10:20:00+05:30') };

        const resA = analyzeJourney({
            liveTripLog: tripA,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1760, lng: 77.4100, speed: 20, timestamp: ist('2026-11-13T08:01:10+05:30') }
            ]
        });
        const resB = analyzeJourney({
            liveTripLog: tripB,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1800, lng: 77.4100, speed: 0, timestamp: ist('2026-11-13T10:01:00+05:30') }
            ]
        });

        assert.equal(resA.tripId, 'trip_a_id');
        assert.equal(resB.tripId, 'trip_b_id');
        assert.equal(resA.gpsSampleCount, 2);
        assert.equal(resB.gpsSampleCount, 1);
        assert.equal(resA.dataSource, 'LIVE GPS');
        assert.equal(resB.dataSource, 'INSUFFICIENT GPS DATA');
    });

    test('21. Cross-midnight trip (23:50 IST to 00:25 IST) preserves IST trip identity and timestamps', () => {
        const midnightTrip = {
            ...BASE_TRIP,
            _id: 'trip_cross_midnight',
            date: '2026-11-13',
            startTime: ist('2026-11-13T23:50:00+05:30'),
            endTime: ist('2026-11-14T00:25:00+05:30')
        };

        const result = analyzeJourney({
            liveTripLog: midnightTrip,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 20, timestamp: ist('2026-11-13T23:55:00+05:30') },
                { lat: 23.1850, lng: 77.4100, speed: 25, timestamp: ist('2026-11-14T00:15:00+05:30') }
            ]
        });

        assert.equal(result.istTripDate, '2026-11-13');
        assert.equal(result.totalDurationMinutes, 30); // 23:55 -> 00:25 = 30 mins
        assert.equal(result.tripEndTimestamp.toISOString(), ist('2026-11-14T00:25:00+05:30').toISOString());
    });

    test('22. Empty telemetry produces NO DATA / INSUFFICIENT GPS DATA without fabrication', () => {
        const result = analyzeJourney({
            liveTripLog: { ...BASE_TRIP, startTime: null, endTime: null },
            route: BASE_ROUTE,
            telemetryPoints: []
        });

        assert.equal(result.gpsSampleCount, 0);
        assert.equal(result.firstGpsTimestamp, null);
        assert.equal(result.movementStartTimestamp, null);
        assert.equal(result.distanceKm, null);
        assert.equal(result.distanceSource, 'INSUFFICIENT GPS DATA');
        assert.equal(result.averageSpeedKmh, null);
        assert.equal(result.dataSource, 'NO DATA');
        assert.equal(result.telemetryStatus, 'EMPTY');
    });

    test('23. Invalid telemetry (NaN, Null Island, bad speed, duplicate timestamp, unsorted) is rejected cleanly', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1760, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:02:00+05:30') }, // out-of-order valid
                { lat: 0, lng: 0, speed: 10, timestamp: ist('2026-11-13T08:01:00+05:30') }, // Null Island
                { lat: 95, lng: 77.41, speed: 10, timestamp: ist('2026-11-13T08:01:05+05:30') }, // bad lat
                { lat: 23.1750, lng: 77.4100, speed: -5, timestamp: ist('2026-11-13T08:01:10+05:30') }, // negative speed
                { lat: 23.1750, lng: 77.4100, speed: 500, timestamp: ist('2026-11-13T08:01:15+05:30') }, // impossible speed
                { lat: 23.1750, lng: 77.4100, speed: 12, timestamp: 'invalid-date' }, // bad timestamp
                { lat: 23.1750, lng: 77.4100, speed: 12, timestamp: ist('2026-11-13T08:01:20+05:30') }, // valid earliest
                { lat: 23.1755, lng: 77.4100, speed: 14, timestamp: ist('2026-11-13T08:01:20+05:30') }  // duplicate timestamp
            ]
        });

        assert.equal(result.gpsQuality.totalSamples, 8);
        assert.equal(result.gpsQuality.validSamples, 2);
        assert.equal(result.gpsQuality.invalidSamples, 6);
        assert.equal(result.firstGpsTimestamp.toISOString(), ist('2026-11-13T08:01:20+05:30').toISOString());
        assert.equal(result.lastGpsTimestamp.toISOString(), ist('2026-11-13T08:02:00+05:30').toISOString());
    });

    test('24. One noisy GPS point near a stop does NOT mark stop as REACHED', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: { _id: 'r1', name: 'R1', stops: [BASE_ROUTE.stops[0]] },
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 30, timestamp: ist('2026-11-13T08:04:50+05:30') },
                { lat: 23.1800, lng: 77.4100, speed: 30, timestamp: ist('2026-11-13T08:05:00+05:30') }, // 1 single point
                { lat: 23.1850, lng: 77.4100, speed: 30, timestamp: ist('2026-11-13T08:05:10+05:30') }
            ]
        });

        assert.notEqual(result.stops[0].status, 'REACHED');
        assert.equal(result.reachedStopCount, 0);
    });

    test('25. Partial trip where GPS stops before tripEndTimestamp sets telemetryStatus = PARTIAL', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP, // endTime = 08:30 IST
            route: BASE_ROUTE,
            telemetryPoints: [
                { lat: 23.1750, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1760, lng: 77.4100, speed: 15, timestamp: ist('2026-11-13T08:02:00+05:30') }
                // GPS stops 28 minutes before liveTripLog.endTime
            ]
        });

        assert.equal(result.telemetryStatus, 'PARTIAL');
        assert.equal(result.tripEndSource, 'LIVE_TRIP_LOG');
        assert.ok(result.lastGpsTimestamp < result.tripEndTimestamp);
    });

    test('26. Full journey reconstruction builds complete ordered timeline, stops, segments, and quality', () => {
        const result = analyzeJourney({
            liveTripLog: BASE_TRIP,
            route: BASE_ROUTE,
            telemetryPoints: [
                // Stationary at origin
                { lat: 23.1750, lng: 77.4100, speed: 0, accuracy: 5, timestamp: ist('2026-11-13T08:01:00+05:30') },
                { lat: 23.1750, lng: 77.4100, speed: 0, accuracy: 5, timestamp: ist('2026-11-13T08:01:10+05:30') },
                // Movement starts
                { lat: 23.1765, lng: 77.4100, speed: 15, accuracy: 6, timestamp: ist('2026-11-13T08:02:00+05:30') },
                { lat: 23.1785, lng: 77.4100, speed: 20, accuracy: 6, timestamp: ist('2026-11-13T08:03:00+05:30') },
                // Stop 1 (08:05 -> 08:06)
                { lat: 23.1800, lng: 77.4100, speed: 2, accuracy: 5, timestamp: ist('2026-11-13T08:05:00+05:30') },
                { lat: 23.1801, lng: 77.4100, speed: 0, accuracy: 5, timestamp: ist('2026-11-13T08:05:30+05:30') },
                { lat: 23.1820, lng: 77.4100, speed: 22, accuracy: 6, timestamp: ist('2026-11-13T08:06:00+05:30') },
                { lat: 23.1850, lng: 77.4100, speed: 26, accuracy: 6, timestamp: ist('2026-11-13T08:06:30+05:30') },
                // Stop 2 (08:15 -> 08:16)
                { lat: 23.1900, lng: 77.4100, speed: 3, accuracy: 5, timestamp: ist('2026-11-13T08:15:00+05:30') },
                { lat: 23.1901, lng: 77.4100, speed: 0, accuracy: 5, timestamp: ist('2026-11-13T08:15:30+05:30') },
                { lat: 23.1920, lng: 77.4100, speed: 22, accuracy: 6, timestamp: ist('2026-11-13T08:16:00+05:30') },
                { lat: 23.1950, lng: 77.4100, speed: 26, accuracy: 6, timestamp: ist('2026-11-13T08:16:30+05:30') },
                // Stop 3 (Campus arrival 08:25)
                { lat: 23.2000, lng: 77.4100, speed: 2, accuracy: 5, timestamp: ist('2026-11-13T08:25:00+05:30') },
                { lat: 23.2000, lng: 77.4100, speed: 0, accuracy: 5, timestamp: ist('2026-11-13T08:25:30+05:30') }
            ],
            options: { gapThresholdSeconds: 600 }
        });

        assert.equal(result.analyticsStatus, 'CALCULATED FROM GPS');
        assert.equal(result.reachedStopCount, 3);
        assert.equal(result.missedStopCount, 0);
        assert.equal(result.segments.length, 2);
        assert.ok(result.segments.every(s => s.status === 'COMPLETED'));
        assert.equal(result.averageDwellMinutes, 1);
        assert.ok(result.distanceKm > 2.5);
        assert.ok(result.timeline.some(e => e.eventType === 'GPS_START'));
        assert.ok(result.timeline.some(e => e.eventType === 'MOVEMENT_START'));
        assert.ok(result.timeline.some(e => e.eventType === 'STOP_ARRIVAL'));
        assert.ok(result.timeline.some(e => e.eventType === 'STOP_DEPARTURE'));
        assert.ok(result.timeline.some(e => e.eventType === 'TRIP_END'));
        // Timeline strictly sorted
        for (let i = 1; i < result.timeline.length; i++) {
            assert.ok(result.timeline[i].timestamp.getTime() >= result.timeline[i - 1].timestamp.getTime());
        }
    });
});
