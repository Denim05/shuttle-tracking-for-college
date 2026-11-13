const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const XLSX = require('xlsx');

const Route = require('../models/Route');
const Bus = require('../models/Bus');
const Driver = require('../models/Driver');
const LiveTripLog = require('../models/LiveTripLog');
const TripTelemetryPoint = require('../models/TripTelemetryPoint');

const {
    DATA_SOURCES,
    generateTripReportData,
    generateTripReportCsvFiles,
    generateTripReportCsvString,
    generateTripReportExcelBuffer,
    generateTripReportPdfBuffer
} = require('../services/trip_report_generator');

const {
    buildMorningSheetRow,
    buildEveningSheetRow,
    buildStopSheetRow,
    buildKpiSheetRow
} = require('../services/google_sheets_service');

const { getIstDateString } = require('../services/telemetry_persistence_service');

function istDate(dateStr, hh, mm, ss = 0) {
    const pad = (n) => String(n).padStart(2, '0');
    return new Date(`${dateStr}T${pad(hh)}:${pad(mm)}:${pad(ss)}+05:30`);
}

function buildRealisticFleetFixture() {
    const routes = [
        {
            _id: 'r5_1',
            name: 'Kolar Road Corridor',
            stops: [
                { name: 'Kolar Square', time: '07:15 AM', lat: 23.1800, lng: 77.4100 },
                { name: 'Bansal Hospital', time: '07:35 AM', lat: 23.2000, lng: 77.4000 },
                { name: 'Mact Square', time: '07:55 AM', lat: 23.2150, lng: 77.3800 },
                { name: 'Ratibad Gate', time: '08:05 AM', lat: 23.1650, lng: 77.3300 },
                { name: 'SISTec Ratibad Campus', time: '08:30 AM', lat: 23.1500, lng: 77.3100 }
            ],
            coordinates: [
                { lat: 23.1800, lng: 77.4100 },
                { lat: 23.2000, lng: 77.4000 },
                { lat: 23.2150, lng: 77.3800 },
                { lat: 23.1650, lng: 77.3300 },
                { lat: 23.1500, lng: 77.3100 }
            ]
        },
        {
            _id: 'r5_2',
            name: 'MP Nagar Express',
            stops: [
                { name: 'MP Nagar Zone 1', time: '07:20 AM', lat: 23.2300, lng: 77.4300 },
                { name: 'Habibganj Naka', time: '07:45 AM', lat: 23.2100, lng: 77.4200 },
                { name: 'SISTec Ratibad Campus', time: '08:35 AM', lat: 23.1500, lng: 77.3100 }
            ],
            coordinates: [
                { lat: 23.2300, lng: 77.4300 },
                { lat: 23.2100, lng: 77.4200 },
                { lat: 23.1500, lng: 77.3100 }
            ]
        }
    ];

    const buses = [
        { _id: 'b5_1', name: 'Bus 01 - Kolar', busNumber: 'MP-04-PA-1001', routeId: 'r5_1', routeName: 'Kolar Road Corridor', driverId: 'd5_1' },
        { _id: 'b5_2', name: 'Bus 02 - MP Nagar', busNumber: 'MP-04-PA-1002', routeId: 'r5_2', routeName: 'MP Nagar Express', driverId: 'd5_2' },
        { _id: 'b5_3', name: 'Bus 03 - Reserve', busNumber: 'MP-04-PA-1003', routeId: null, routeName: 'Unassigned', driverId: 'd5_3' }
    ];

    const drivers = [
        { _id: 'd5_1', name: 'Rajesh Kumar', phone: '9876543210', assignedBus: 'b5_1' },
        { _id: 'd5_2', name: 'Suresh Verma', phone: '9876501234', assignedBus: 'b5_2' },
        { _id: 'd5_3', name: 'Mahesh Singh', phone: '9876509999', assignedBus: 'b5_3' }
    ];

    const liveLogs = [
        // Bus 01 Trip 1 (Complete GPS, Stop 1 & 2 REACHED with long dwell, Stop 3 MISSED, Stop 4 UNRECORDED due to gap)
        {
            _id: 'log5_b1_t1',
            busId: 'b5_1',
            busNumber: 'MP-04-PA-1001',
            routeId: 'r5_1',
            routeName: 'Kolar Road Corridor',
            driverName: 'Rajesh Kumar',
            shiftType: 'pickup',
            tripType: 'pickup',
            direction: 'to_campus',
            date: '2026-11-13',
            tripDateIst: '2026-11-13',
            status: 'completed',
            startedAt: istDate('2026-11-13', 7, 14, 0),
            endedAt: istDate('2026-11-13', 8, 42, 0),
            distanceKm: 15.0,
            reachedStops: []
        },
        // Bus 01 Trip 2 (Dropoff from_campus with GPS, early arrival, unsupported stop schedules)
        {
            _id: 'log5_b1_t2',
            busId: 'b5_1',
            busNumber: 'MP-04-PA-1001',
            routeId: 'r5_1',
            routeName: 'Kolar Road Corridor',
            driverName: 'Rajesh Kumar',
            shiftType: 'dropoff',
            tripType: 'dropoff',
            direction: 'from_campus',
            date: '2026-11-13',
            tripDateIst: '2026-11-13',
            status: 'completed',
            startedAt: istDate('2026-11-13', 16, 40, 0),
            endedAt: istDate('2026-11-13', 17, 45, 0),
            distanceKm: 14.2,
            reachedStops: []
        },
        // Bus 01 Trip 3 (Partial GPS trip, GPS stops before tripEndTimestamp)
        {
            _id: 'log5_b1_t3',
            busId: 'b5_1',
            busNumber: 'MP-04-PA-1001',
            routeId: 'r5_1',
            routeName: 'Kolar Road Corridor',
            driverName: 'Rajesh Kumar',
            shiftType: 'pickup',
            tripType: 'pickup',
            direction: 'to_campus',
            date: '2026-11-13',
            tripDateIst: '2026-11-13',
            status: 'completed',
            startedAt: istDate('2026-11-13', 9, 0, 0),
            endedAt: istDate('2026-11-13', 9, 45, 0),
            distanceKm: 4.1,
            reachedStops: []
        },
        // Bus 02 Trip 1 (Insufficient GPS data: only 1 valid point)
        {
            _id: 'log5_b2_t1',
            busId: 'b5_2',
            busNumber: 'MP-04-PA-1002',
            routeId: 'r5_2',
            routeName: 'MP Nagar Express',
            driverName: 'Suresh Verma',
            shiftType: 'pickup',
            tripType: 'pickup',
            direction: 'to_campus',
            date: '2026-11-13',
            tripDateIst: '2026-11-13',
            status: 'completed',
            startedAt: istDate('2026-11-13', 7, 25, 0),
            endedAt: istDate('2026-11-13', 8, 45, 0),
            reachedStops: []
        }
        // Bus 02 dropoff has NO LiveTripLog -> SCHEDULED / ESTIMATED
        // Bus 03 has NO LiveTripLog and NO route -> NO DATA
    ];

    // Continuous 30s-spaced bypass points between 07:45:30 and 08:04:30 (avoiding Mact Square 23.2150,77.3800)
    const bypassSegment = [];
    const bypassStartMs = istDate('2026-11-13', 7, 46, 0).getTime();
    const bypassEndMs = istDate('2026-11-13', 8, 4, 30).getTime();
    for (let ms = bypassStartMs, step = 0; ms <= bypassEndMs; ms += 30000, step++) {
        const frac = step / 37;
        bypassSegment.push({
            tripLogId: 'log5_b1_t1',
            timestamp: new Date(ms),
            lat: 23.2045 - frac * (23.2045 - 23.1680),
            lng: 77.3920 - frac * (77.3920 - 77.3340),
            speedKmh: 38,
            accuracyMeters: 9
        });
    }

    const telemetry = [
        // log5_b1_t1: Stop 1 (07:15->07:19, 4m dwell), Stop 2 (07:40->07:45, 5m dwell, delayed +5m), continuous bypass of Stop 3, reach Stop 4, gap before Stop 5
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 14, 30), lat: 23.1800, lng: 77.4100, speedKmh: 0, accuracyMeters: 8 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 15, 0), lat: 23.1801, lng: 77.4101, speedKmh: 1, accuracyMeters: 7 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 15, 30), lat: 23.1801, lng: 77.4100, speedKmh: 1, accuracyMeters: 7 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 19, 0), lat: 23.1820, lng: 77.4090, speedKmh: 18, accuracyMeters: 9 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 19, 30), lat: 23.1840, lng: 77.4080, speedKmh: 28, accuracyMeters: 9 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 25, 0), lat: 23.1900, lng: 77.4050, speedKmh: 36, accuracyMeters: 10 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 40, 0), lat: 23.2000, lng: 77.4000, speedKmh: 0, accuracyMeters: 6 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 40, 30), lat: 23.2001, lng: 77.4001, speedKmh: 1, accuracyMeters: 6 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 45, 0), lat: 23.2030, lng: 77.3950, speedKmh: 32, accuracyMeters: 8 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 7, 45, 30), lat: 23.2045, lng: 77.3920, speedKmh: 35, accuracyMeters: 8 },
        ...bypassSegment,
        // Reach Stop 4 (Ratibad Gate 23.1650, 77.3300) at 08:05->08:06, then GPS ends -> Stop 5 UNRECORDED
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 8, 5, 0), lat: 23.1650, lng: 77.3300, speedKmh: 0, accuracyMeters: 7 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 8, 5, 30), lat: 23.1651, lng: 77.3301, speedKmh: 1, accuracyMeters: 7 },
        { tripLogId: 'log5_b1_t1', timestamp: istDate('2026-11-13', 8, 6, 30), lat: 23.1630, lng: 77.3280, speedKmh: 24, accuracyMeters: 9 },

        // log5_b1_t2 (overlapping afternoon points isolated by tripLogId)
        { tripLogId: 'log5_b1_t2', timestamp: istDate('2026-11-13', 16, 40, 0), lat: 23.1500, lng: 77.3100, speedKmh: 0, accuracyMeters: 8 },
        { tripLogId: 'log5_b1_t2', timestamp: istDate('2026-11-13', 16, 45, 0), lat: 23.1650, lng: 77.3400, speedKmh: 35, accuracyMeters: 9 },
        { tripLogId: 'log5_b1_t2', timestamp: istDate('2026-11-13', 17, 45, 0), lat: 23.1800, lng: 77.4100, speedKmh: 0, accuracyMeters: 7 },

        // log5_b1_t3 (partial GPS stops 30 min before endedAt)
        { tripLogId: 'log5_b1_t3', timestamp: istDate('2026-11-13', 9, 0, 0), lat: 23.1800, lng: 77.4100, speedKmh: 0, accuracyMeters: 10 },
        { tripLogId: 'log5_b1_t3', timestamp: istDate('2026-11-13', 9, 5, 0), lat: 23.1850, lng: 77.4070, speedKmh: 28, accuracyMeters: 12 },
        { tripLogId: 'log5_b1_t3', timestamp: istDate('2026-11-13', 9, 12, 0), lat: 23.1920, lng: 77.4030, speedKmh: 30, accuracyMeters: 11 },

        // log5_b2_t1 (only 1 valid GPS point -> INSUFFICIENT GPS DATA)
        { tripLogId: 'log5_b2_t1', timestamp: istDate('2026-11-13', 7, 25, 0), lat: 23.2300, lng: 77.4300, speedKmh: 0, accuracyMeters: 9 }
    ];

    return { routes, buses, drivers, liveLogs, telemetry };
}

describe('Phase 5: End-to-End Report Validation & Data Reconciliation', () => {
    const origRouteFind = Route.find;
    const origBusFind = Bus.find;
    const origDriverFind = Driver.find;
    const origLiveTripLogFind = LiveTripLog.find;
    const origTripTelemetryPointFind = TripTelemetryPoint.find;

    let fixture;
    let telemetryQueryCount = 0;

    beforeEach(() => {
        fixture = buildRealisticFleetFixture();
        telemetryQueryCount = 0;

        Route.find = async () => fixture.routes;
        Bus.find = () => ({ sort: async () => fixture.buses });
        Driver.find = async () => fixture.drivers;
        LiveTripLog.find = () => ({ sort: async () => fixture.liveLogs });
        TripTelemetryPoint.find = (query) => {
            telemetryQueryCount += 1;
            const ids = new Set((query?.tripLogId?.$in || []).map(String));
            const filtered = ids.size > 0
                ? fixture.telemetry.filter((pt) => ids.has(String(pt.tripLogId)))
                : fixture.telemetry;
            return { sort: async () => filtered };
        };
    });

    afterEach(() => {
        Route.find = origRouteFind;
        Bus.find = origBusFind;
        Driver.find = origDriverFind;
        LiveTripLog.find = origLiveTripLogFind;
        TripTelemetryPoint.find = origTripTelemetryPointFind;
    });

    test('1. 17/17 reached-stop bug prevention: reachedStops=[] yields 0/17, 2 stops yields 2/17', async () => {
        const stops17 = Array.from({ length: 17 }, (_, i) => ({
            name: `Stop ${i + 1}`,
            time: '07:30 AM',
            lat: 23.18 + i * 0.001,
            lng: 77.41 - i * 0.001
        }));
        fixture.routes = [{ _id: 'r17', name: '17-Stop Route', stops: stops17, coordinates: [] }];
        fixture.buses = [{ _id: 'b17', name: 'Bus 17', busNumber: 'MP-04-PA-0017', routeId: 'r17', routeName: '17-Stop Route', driverId: 'd5_1' }];
        fixture.liveLogs = [
            {
                _id: 'log_17_empty',
                busId: 'b17',
                busNumber: 'MP-04-PA-0017',
                routeId: 'r17',
                routeName: '17-Stop Route',
                shiftType: 'pickup',
                tripType: 'pickup',
                direction: 'to_campus',
                date: '2026-11-13',
                tripDateIst: '2026-11-13',
                status: 'completed',
                startedAt: istDate('2026-11-13', 7, 15, 0),
                endedAt: istDate('2026-11-13', 8, 30, 0),
                reachedStops: []
            },
            {
                _id: 'log_17_two',
                busId: 'b17',
                busNumber: 'MP-04-PA-0017',
                routeId: 'r17',
                routeName: '17-Stop Route',
                shiftType: 'pickup',
                tripType: 'pickup',
                direction: 'to_campus',
                date: '2026-11-13',
                tripDateIst: '2026-11-13',
                status: 'completed',
                startedAt: istDate('2026-11-13', 9, 15, 0),
                endedAt: istDate('2026-11-13', 10, 30, 0),
                reachedStops: [
                    { stopName: 'Stop 1', stopIndex: 0, reachedAt: istDate('2026-11-13', 9, 20, 0) },
                    { stopName: 'Stop 2', stopIndex: 1, reachedAt: istDate('2026-11-13', 9, 30, 0) }
                ]
            }
        ];
        fixture.telemetry = [];

        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'morning' });
        const emptyTrip = report.allTrips.find((t) => t.tripId === 'log_17_empty');
        const twoTrip = report.allTrips.find((t) => t.tripId === 'log_17_two');

        assert.equal(emptyTrip.actualReachedCount, 0);
        assert.equal(emptyTrip.stopsCompleted, '0 / 17');
        assert.equal(twoTrip.actualReachedCount, 2);
        assert.equal(twoTrip.stopsCompleted, '2 / 17');
    });

    test('2. Batch telemetry query avoids N+1 and isolates trips strictly by tripLogId', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        // Exactly 1 batch TripTelemetryPoint.find() query for all 4 LiveTripLog records
        assert.equal(telemetryQueryCount, 1);

        const t1 = report.allTrips.find((t) => t.tripId === 'log5_b1_t1');
        const t2 = report.allTrips.find((t) => t.tripId === 'log5_b1_t2');
        const t3 = report.allTrips.find((t) => t.tripId === 'log5_b1_t3');

        assert.equal(t1.validGpsSamples, 51);
        assert.equal(t2.validGpsSamples, 3);
        assert.equal(t3.validGpsSamples, 3);
        assert.equal(t3.telemetryStatus, 'PARTIAL');
    });

    test('3. Data source classification & Actual vs Scheduled reconciliation across all 4 cases', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });

        const liveTrip = report.allTrips.find((t) => t.tripId === 'log5_b1_t1');
        const insufTrip = report.allTrips.find((t) => t.tripId === 'log5_b2_t1');
        const schedTrip = report.allTrips.find((t) => t.busId === 'b5_2' && t.shiftType === 'dropoff');
        const noDataTrip = report.allTrips.find((t) => t.busId === 'b5_3');

        assert.equal(liveTrip.dataSource, DATA_SOURCES.LIVE_GPS);
        assert.equal(insufTrip.dataSource, DATA_SOURCES.INSUFFICIENT_GPS_DATA);
        assert.equal(schedTrip.dataSource, DATA_SOURCES.SCHEDULED_ESTIMATED);
        assert.equal(noDataTrip.dataSource, DATA_SOURCES.NO_DATA);

        // Scheduled-only: actuals must be null (never substituted with scheduled)
        assert.equal(schedTrip.actualDeparture, null);
        assert.equal(schedTrip.actualArrival, null);
        assert.notEqual(schedTrip.scheduledDeparture, 'NO DATA');

        // No-data: actuals are null & scheduled are NO DATA
        assert.equal(noDataTrip.actualDeparture, null);
        assert.equal(noDataTrip.scheduledDeparture, 'NO DATA');
        assert.equal(noDataTrip.actualArrival, null);
        assert.equal(noDataTrip.scheduledArrival, 'NO DATA');
    });

    test('4. Journey timestamps, stop classification (REACHED/MISSED/UNRECORDED), dwell, and segments reconcile', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const t1 = report.allTrips.find((t) => t.tripId === 'log5_b1_t1');

        // Chronological order: firstGps <= movementStart <= lastGps <= tripEnd
        assert.ok(new Date(t1.firstGpsTimestamp) <= new Date(t1.movementStartTimestamp));
        assert.ok(new Date(t1.movementStartTimestamp) <= new Date(t1.lastGpsTimestamp));
        assert.ok(new Date(t1.lastGpsTimestamp) <= new Date(t1.tripEndTimestamp));

        // Stop classifications & sum = scheduled stops (5)
        assert.equal(t1.stopCount, 5);
        assert.equal(t1.reachedStopCount + t1.missedStopCount + t1.unrecordedStopCount, 5);
        assert.equal(t1.stops[0].status, 'REACHED');
        assert.equal(t1.stops[1].status, 'REACHED');
        assert.equal(t1.stops[2].status, 'MISSED');
        assert.equal(t1.stops[3].status, 'REACHED');
        assert.equal(t1.stops[4].status, 'UNRECORDED');

        // Dwell reconciliation: Stop 1 (07:14:30->07:19:00 = 4.5m), Stop 2 (07:40:00->07:45:00 = 5m)
        assert.equal(t1.stops[0].dwellMinutes, 4.5);
        assert.equal(t1.stops[1].dwellMinutes, 5);
        assert.equal(t1.stops[2].dwellMinutes, null);
        assert.equal(t1.stops[3].dwellMinutes, null);

        // Segment reconciliation
        assert.ok(Array.isArray(t1.segments) && t1.segments.length >= 1);
        assert.equal(t1.segments[0].fromStop, 'Kolar Square');
        assert.equal(t1.segments[0].toStop, 'Bansal Hospital');
        assert.ok(t1.segments[0].travelDurationMinutes > 0);
        assert.ok(t1.segments[0].distanceKm > 0);
        assert.ok(t1.segments[0].averageSpeedKmh > 0);
    });

    test('5. Fleet, Bus, Route, and Stop Performance KPIs reconcile with canonical trips', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const { fleetAnalytics, busAnalytics, routeAnalytics, stopPerformance, allTrips } = report;

        assert.equal(fleetAnalytics.totalTrips, allTrips.length);
        assert.equal(
            fleetAnalytics.liveGpsTrips +
            fleetAnalytics.insufficientGpsTrips +
            fleetAnalytics.scheduledEstimatedTrips +
            fleetAnalytics.noDataTrips,
            fleetAnalytics.totalTrips
        );

        const b1Summary = busAnalytics.find((b) => b.busId === 'b5_1');
        const b1Trips = allTrips.filter((t) => t.busId === 'b5_1');
        assert.equal(b1Summary.totalTrips, b1Trips.length);
        assert.equal(b1Summary.gpsTripCount, b1Trips.filter((t) => t.dataSource === DATA_SOURCES.LIVE_GPS).length);

        const kolarToCampus = routeAnalytics.find((r) => r.routeId === 'r5_1' && r.direction === 'to_campus');
        const kolarFromCampus = routeAnalytics.find((r) => r.routeId === 'r5_1' && r.direction === 'from_campus');
        assert.ok(kolarToCampus && kolarFromCampus);

        // Stop performance does not count UNRECORDED as MISSED
        const stop3Perf = stopPerformance.find((s) => s.stopName === 'Mact Square');
        const stop4Perf = stopPerformance.find((s) => s.stopName === 'SISTec Ratibad Campus');
        assert.ok(stop3Perf.missedCount >= 1);
        assert.ok(stop4Perf.unrecordedCount >= 1);
    });

    test('6. Cross-format concordance & structural validation across JSON, PDF, Excel, CSV, and Google Sheets', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const canonical = report.allTrips.find((t) => t.tripId === 'log5_b1_t1');

        // CSV (all 6 files)
        const csvFiles = generateTripReportCsvFiles(report);
        assert.deepEqual(Object.keys(csvFiles), [
            'trip_summary.csv',
            'journey_timeline.csv',
            'stop_analytics.csv',
            'travel_segments.csv',
            'gps_telemetry.csv',
            'fleet_summary.csv'
        ]);
        for (const [name, content] of Object.entries(csvFiles)) {
            assert.ok(content.startsWith('\uFEFF'), `${name} missing UTF-8 BOM`);
            assert.ok(!content.includes('undefined'), `${name} contains undefined`);
            assert.ok(!content.includes('<html'), `${name} contains HTML`);
        }
        assert.ok(csvFiles['trip_summary.csv'].includes(canonical.tripId));
        assert.ok(csvFiles['stop_analytics.csv'].includes('Kolar Square'));

        // Excel (all 12 sheets)
        const xlsxBuf = generateTripReportExcelBuffer(report);
        const wb = XLSX.read(xlsxBuf, { type: 'buffer' });
        assert.deepEqual(wb.SheetNames, [
            'Executive Summary',
            'Fleet Summary',
            'Bus Journey Summary',
            'Journey Timeline',
            'Stop Analytics',
            'Travel Segments',
            'GPS Telemetry',
            'Route Analytics',
            'Bus Analytics',
            'Stop Performance',
            'Data Quality',
            'Master Trip Log'
        ]);
        const masterRows = XLSX.utils.sheet_to_json(wb.Sheets['Master Trip Log']);
        const excelRow = masterRows.find((r) => r['Trip ID'] === canonical.tripId);
        assert.ok(excelRow);
        assert.equal(excelRow['Data Source'], canonical.dataSource);
        assert.equal(excelRow['Actual Departure'], canonical.actualDeparture);
        assert.equal(excelRow['Actual GPS Distance (km)'], canonical.actualDistanceKm);
        assert.equal(excelRow['Avg Speed (km/h)'], canonical.averageSpeedKmh);
        assert.equal(excelRow['Completeness %'], canonical.telemetryCompletenessPercent);

        // PDF (binary %PDF-, multi-page, > 2000 bytes)
        const pdfBuf = await generateTripReportPdfBuffer(report);
        assert.equal(pdfBuf.subarray(0, 5).toString('utf8'), '%PDF-');
        assert.ok(pdfBuf.length > 2000);
        const pageMatches = pdfBuf.toString('latin1').match(/\/Type\s*\/Page\b/g) || [];
        assert.ok(pageMatches.length >= 2, `Expected multi-page PDF, got ${pageMatches.length} pages`);

        // Google Sheets row concordance
        const gsRow = buildMorningSheetRow(canonical);
        assert.equal(gsRow[0], canonical.tripId);
        assert.equal(gsRow[6], canonical.dataSource);
        assert.equal(gsRow[9], canonical.scheduledDeparture);
        assert.equal(gsRow[10], canonical.actualDeparture);
        assert.equal(gsRow[18], canonical.averageSpeedKmh);
        assert.equal(gsRow[19], canonical.validGpsSamples);
        assert.equal(gsRow[20], canonical.gpsGapCount);
        assert.equal(gsRow[21], canonical.telemetryCompletenessPercent);
        assert.equal(gsRow[22], canonical.averageDelayMinutes);
    });

    test('7. IST boundary (23:59 / 00:01 IST) and exact tripId / route / direction filters', async () => {
        assert.equal(getIstDateString(istDate('2026-11-13', 23, 59, 0)), '2026-11-13');
        assert.equal(getIstDateString(istDate('2026-11-14', 0, 1, 0)), '2026-11-14');

        const scoped = await generateTripReportData({ targetDate: '2026-11-13', tripId: 'log5_b1_t2' });
        assert.equal(scoped.allTrips.length, 1);
        assert.equal(scoped.allTrips[0].tripId, 'log5_b1_t2');

        const byDir = await generateTripReportData({ targetDate: '2026-11-13', routeId: 'r5_1', direction: 'from_campus' });
        assert.ok(byDir.allTrips.every((t) => t.routeId === 'r5_1' && t.direction === 'from_campus'));
    });
});
