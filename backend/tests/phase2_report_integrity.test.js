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
    generateTripReportCsvString,
    generateTripReportExcelBuffer,
    generateTripReportPdfBuffer,
    fmtDate
} = require('../services/trip_report_generator');

const {
    buildMorningSheetRow,
    buildEveningSheetRow,
    buildStopSheetRow,
    buildKpiSheetRow
} = require('../services/google_sheets_service');

const { getIstDateString } = require('../services/telemetry_persistence_service');

describe('Phase 2: Report Data Integrity & Multi-Trip Support', () => {
    const origRouteFind = Route.find;
    const origBusFind = Bus.find;
    const origDriverFind = Driver.find;
    const origLiveTripLogFind = LiveTripLog.find;
    const origTripTelemetryPointFind = TripTelemetryPoint.find;

    let mockRoutes = [];
    let mockBuses = [];
    let mockDrivers = [];
    let mockLiveLogs = [];

    beforeEach(() => {
        mockRoutes = [
            {
                _id: 'route_1',
                name: 'Kolar Road Route',
                stops: [
                    { name: 'Kolar Square', time: '07:15 AM', lat: 23.18, lng: 77.41 },
                    { name: 'Bansal Hospital', time: '07:45 AM', lat: 23.20, lng: 77.40 },
                    { name: 'SISTec Ratibad Campus', time: '08:30 AM', lat: 23.15, lng: 77.31 }
                ],
                coordinates: [
                    { lat: 23.18, lng: 77.41 },
                    { lat: 23.20, lng: 77.40 },
                    { lat: 23.15, lng: 77.31 }
                ]
            },
            {
                _id: 'route_2',
                name: 'MP Nagar Route',
                stops: [
                    { name: 'MP Nagar Zone 1', time: '07:20 AM', lat: 23.23, lng: 77.43 },
                    { name: 'SISTec Ratibad Campus', time: '08:35 AM', lat: 23.15, lng: 77.31 }
                ],
                coordinates: [
                    { lat: 23.23, lng: 77.43 },
                    { lat: 23.15, lng: 77.31 }
                ]
            }
        ];

        mockBuses = [
            {
                _id: 'bus_1',
                name: 'Bus 01 - Kolar',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_1',
                routeName: 'Kolar Road Route',
                driverId: 'drv_1'
            },
            {
                _id: 'bus_2',
                name: 'Bus 02 - MP Nagar',
                busNumber: 'MP-04-PA-0002',
                routeId: 'route_2',
                routeName: 'MP Nagar Route',
                driverId: 'drv_2'
            }
        ];

        mockDrivers = [
            { _id: 'drv_1', name: 'Rajesh Kumar', phone: '9876543210', assignedBus: 'bus_1' },
            { _id: 'drv_2', name: 'Suresh Verma', phone: '9876501234', assignedBus: 'bus_2' }
        ];

        mockLiveLogs = [];

        Route.find = async () => mockRoutes;
        Bus.find = () => ({ sort: async () => mockBuses });
        Driver.find = async () => mockDrivers;
        LiveTripLog.find = () => ({
            sort: async () => mockLiveLogs
        });
        TripTelemetryPoint.find = () => ({
            sort: async () => []
        });
    });

    afterEach(() => {
        Route.find = origRouteFind;
        Bus.find = origBusFind;
        Driver.find = origDriverFind;
        LiveTripLog.find = origLiveTripLogFind;
        TripTelemetryPoint.find = origTripTelemetryPointFind;
    });

    test('1. Multiple same-type trips for one bus appear as distinct rows with unique tripId', async () => {
        mockLiveLogs = [
            {
                _id: '6734a0000000000000000001',
                busId: 'bus_1',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:45:00.000Z'), // 07:15 IST
                endTime: new Date('2026-11-13T02:55:00.000Z'),   // 08:25 IST
                reachedStops: [{ stopName: 'Kolar Square', reachedTime: new Date('2026-11-13T01:50:00.000Z') }]
            },
            {
                _id: '6734a0000000000000000002',
                busId: 'bus_1',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T03:30:00.000Z'), // 09:00 IST
                endTime: new Date('2026-11-13T04:15:00.000Z'),   // 09:45 IST
                reachedStops: []
            },
            {
                _id: '6734a0000000000000000003',
                busId: 'bus_1',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Active',
                startTime: new Date('2026-11-13T05:00:00.000Z'), // 10:30 IST
                reachedStops: []
            }
        ];

        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'morning', busId: 'bus_1' });
        assert.equal(report.morningTrips.length, 3);
        assert.deepEqual(
            report.morningTrips.map(t => t.tripId),
            ['6734a0000000000000000001', '6734a0000000000000000002', '6734a0000000000000000003']
        );
        assert.equal(new Set(report.morningTrips.map(t => t.displayTripId)).size, 3);
    });

    test('2. Pickup and dropoff trips appear separately with distinct tripType and direction', async () => {
        mockLiveLogs = [
            {
                _id: 'log_pickup_1',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:46:00.000Z'),
                endTime: new Date('2026-11-13T02:58:00.000Z'),
                reachedStops: []
            },
            {
                _id: 'log_dropoff_1',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'dropoff',
                status: 'Completed',
                startTime: new Date('2026-11-13T11:16:00.000Z'),
                endTime: new Date('2026-11-13T12:20:00.000Z'),
                reachedStops: []
            }
        ];

        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all', busId: 'bus_1' });
        assert.equal(report.morningTrips.length, 1);
        assert.equal(report.eveningTrips.length, 1);
        assert.equal(report.allTrips.length, 2);
        assert.equal(report.morningTrips[0].tripType, 'pickup');
        assert.equal(report.morningTrips[0].direction, 'stops -> campus');
        assert.equal(report.eveningTrips[0].tripType, 'dropoff');
        assert.equal(report.eveningTrips[0].direction, 'campus -> stops');
    });

    test('3. Empty reachedStops=[] produces actualReachedCount=0 (never infers total scheduled stops)', async () => {
        mockLiveLogs = [
            {
                _id: 'log_empty_stops',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:50:00.000Z'),
                endTime: new Date('2026-11-13T03:00:00.000Z'),
                reachedStops: []
            }
        ];

        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'morning', busId: 'bus_1' });
        const trip = report.morningTrips[0];
        assert.equal(trip.actualReachedCount, 0);
        assert.equal(trip.scheduledStopsCount, 3);
        assert.equal(trip.stopsCompleted, '0 / 3');
        assert.ok(trip.stops.every(s => s.status !== '✅ Reached'));
    });

    test('4. Strict Actual vs Scheduled semantics & NO DATA / INSUFFICIENT GPS DATA states', async () => {
        mockLiveLogs = [
            {
                _id: 'log_live_gps',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:50:00.000Z'), // 07:20 AM IST
                endTime: new Date('2026-11-13T03:05:00.000Z'),   // 08:35 AM IST
                reachedStops: [
                    { stopName: 'Kolar Square', reachedTime: new Date('2026-11-13T01:52:00.000Z') }
                ]
            },
            {
                _id: 'log_insufficient',
                busId: 'bus_2',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Failed',
                reachedStops: []
            }
        ];

        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'morning' });
        const bus1Trip = report.morningTrips.find(t => t.busId === 'bus_1');
        const bus2Trip = report.morningTrips.find(t => t.busId === 'bus_2');

        assert.equal(bus1Trip.dataSource, DATA_SOURCES.LIVE_GPS);
        assert.equal(bus1Trip.scheduledDeparture, '07:15 AM');
        assert.ok(bus1Trip.actualDeparture && bus1Trip.actualDeparture !== bus1Trip.scheduledDeparture);
        assert.ok(bus1Trip.actualArrival);

        assert.equal(bus2Trip.dataSource, DATA_SOURCES.INSUFFICIENT_GPS_DATA);
        assert.equal(bus2Trip.actualDeparture, null);
        assert.equal(bus2Trip.actualArrival, null);
    });

    test('5. Google Sheets rows preserve actual GPS times without overwriting with scheduled times', () => {
        const trip = {
            tripId: 'log_gs_1',
            date: '2026-11-13',
            day: 'Friday',
            busNo: 'Bus 01',
            busNumber: 'MP-04-PA-0001',
            routeName: 'Kolar Road Route',
            dataSource: DATA_SOURCES.LIVE_GPS,
            originStop: 'Kolar Square',
            destinationStop: 'SISTec Ratibad Campus',
            scheduledDeparture: '07:15 AM',
            actualDeparture: '07:22 AM',
            scheduledArrival: '08:42 AM',
            actualArrival: '08:49 AM',
            duration: '1h 27m',
            driverName: 'Rajesh Kumar',
            driverPhone: '+91 98765 43210',
            stopsCompleted: '1 / 3',
            distanceKm: '15.2 km',
            punctuality: '🔴 Delayed (+7m)',
            delayMinutes: 7,
            status: '✅ Completed'
        };

        const morningRow = buildMorningSheetRow(trip);
        // Col 0: tripId, Col 6: dataSource, Col 8: movementStart, Col 9: scheduledDeparture, Col 10: actualDeparture, Col 11: scheduledArrival, Col 12: actualArrival
        assert.equal(morningRow[0], 'log_gs_1');
        assert.equal(morningRow[6], 'LIVE GPS');
        assert.equal(morningRow[9], '07:15 AM');
        assert.equal(morningRow[10], '07:22 AM');
        assert.equal(morningRow[11], '08:42 AM');
        assert.equal(morningRow[12], '08:49 AM');

        const eveningRow = buildEveningSheetRow(trip);
        assert.equal(eveningRow[0], 'log_gs_1');
        assert.equal(eveningRow[10], '07:15 AM');
        assert.equal(eveningRow[11], '07:22 AM');
        assert.equal(eveningRow[12], '08:42 AM');
        assert.equal(eveningRow[13], '08:49 AM');

        const stopRow = buildStopSheetRow({
            tripId: 'log_gs_1',
            date: '2026-11-13',
            shift: 'Morning Pickup',
            dataSource: DATA_SOURCES.LIVE_GPS,
            busNo: 'Bus 01',
            vehicleNo: 'MP-04-PA-0001',
            routeName: 'Kolar Road Route',
            stopNo: 1,
            stopName: 'Kolar Square',
            scheduledTime: '07:15 AM',
            actualTime: '07:22 AM',
            variance: '+7m (Delayed)',
            status: '✅ Reached'
        });
        assert.equal(stopRow[0], 'log_gs_1');
        assert.equal(stopRow[9], '07:15 AM');
        assert.equal(stopRow[10], '07:22 AM');

        const kpiRow = buildKpiSheetRow({
            day: 'Friday',
            totalBuses: 2,
            totalTrips: 4,
            liveGpsTrips: 1,
            scheduledEstimatedTrips: 3,
            punctualityRate: '95.0',
            totalDistance: '60.0',
            morningTrips: [{}, {}],
            eveningTrips: [{}, {}]
        }, '2026-11-13', '09:00:00 AM');
        assert.equal(kpiRow[0], '2026-11-13');
        assert.equal(kpiRow[6], '95.0%');
    });

    test('6. IST report date helper handles 00:00, 05:29, 05:30, and 23:59 IST boundaries accurately', () => {
        // 2026-11-13 00:00 IST == 2026-11-12 18:30:00 UTC
        assert.equal(fmtDate(new Date('2026-11-12T18:30:00.000Z')), '2026-11-13');
        // 2026-11-13 05:29 IST == 2026-11-12 23:59:00 UTC
        assert.equal(fmtDate(new Date('2026-11-12T23:59:00.000Z')), '2026-11-13');
        // 2026-11-13 05:30 IST == 2026-11-13 00:00:00 UTC
        assert.equal(fmtDate(new Date('2026-11-13T00:00:00.000Z')), '2026-11-13');
        // 2026-11-13 23:59 IST == 2026-11-13 18:29:00 UTC
        assert.equal(fmtDate(new Date('2026-11-13T18:29:00.000Z')), '2026-11-13');
        // Default equals getIstDateString()
        assert.equal(fmtDate(), getIstDateString());
    });

    test('7. Route, direction, and bus filtering return accurate scoped subsets', async () => {
        const fleetWide = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        assert.equal(fleetWide.totalTrips, 4); // 2 buses * (pickup + dropoff)

        const routeOnly = await generateTripReportData({ targetDate: '2026-11-13', routeId: 'route_2' });
        assert.equal(routeOnly.totalTrips, 2);
        assert.ok(routeOnly.allTrips.every(t => t.routeId === 'route_2'));

        const dirOnly = await generateTripReportData({ targetDate: '2026-11-13', routeId: 'route_1', direction: 'campus -> stops' });
        assert.equal(dirOnly.totalTrips, 1);
        assert.equal(dirOnly.allTrips[0].tripType, 'dropoff');
        assert.equal(dirOnly.allTrips[0].busId, 'bus_1');

        const busOnly = await generateTripReportData({ targetDate: '2026-11-13', busId: 'bus_2' });
        assert.equal(busOnly.totalTrips, 2);
        assert.ok(busOnly.allTrips.every(t => t.busId === 'bus_2'));
    });

    test('8. Exact tripId filtering resolves LiveTripLog._id and ignores displayTripId', async () => {
        mockLiveLogs = [
            {
                _id: 'exact_log_id_123',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:45:00.000Z'),
                endTime: new Date('2026-11-13T02:55:00.000Z'),
                reachedStops: []
            },
            {
                _id: 'exact_log_id_456',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T03:00:00.000Z'),
                endTime: new Date('2026-11-13T04:00:00.000Z'),
                reachedStops: []
            }
        ];

        const matched = await generateTripReportData({ targetDate: '2026-11-13', tripId: 'exact_log_id_456' });
        assert.equal(matched.totalTrips, 1);
        assert.equal(matched.allTrips[0].tripId, 'exact_log_id_456');

        // displayTripId must NOT match as tripId
        const fakeByDisplay = await generateTripReportData({
            targetDate: '2026-11-13',
            tripId: matched.allTrips[0].displayTripId
        });
        assert.equal(fakeByDisplay.totalTrips, 0);
    });

    test('9. Export concordance across JSON, CSV, Excel, PDF, and Google Sheets from one canonical dataset', async () => {
        mockLiveLogs = [
            {
                _id: 'concordance_trip_1',
                busId: 'bus_1',
                date: '2026-11-13',
                tripType: 'pickup',
                status: 'Completed',
                startTime: new Date('2026-11-13T01:50:00.000Z'),
                endTime: new Date('2026-11-13T03:00:00.000Z'),
                reachedStops: [
                    { stopName: 'Kolar Square', reachedTime: new Date('2026-11-13T01:52:00.000Z') }
                ]
            }
        ];

        const report = await generateTripReportData({ targetDate: '2026-11-13', tripId: 'concordance_trip_1' });
        assert.equal(report.allTrips.length, 1);
        const canonical = report.allTrips[0];

        // CSV concordance
        const csv = generateTripReportCsvString(report);
        assert.ok(csv.startsWith('\uFEFFTrip ID,Date,Bus Name,License Plate,Assigned Route,Direction,Driver,Data Source,Scheduled Departure,Actual Departure,Scheduled Arrival,Actual Arrival'));
        assert.ok(csv.includes(canonical.tripId));
        assert.ok(csv.includes(canonical.dataSource));
        assert.ok(csv.includes(canonical.startTime));

        // Excel concordance
        const xlsxBuf = generateTripReportExcelBuffer(report);
        const wb = XLSX.read(xlsxBuf, { type: 'buffer' });
        const masterRows = XLSX.utils.sheet_to_json(wb.Sheets['Master Trip Log']);
        assert.equal(masterRows.length, 1);
        assert.equal(masterRows[0]['Trip ID'], canonical.tripId);
        assert.equal(masterRows[0]['Data Source'], canonical.dataSource);
        assert.equal(masterRows[0]['Actual Departure'], canonical.actualDeparture);
        assert.equal(masterRows[0]['Scheduled Departure'], canonical.scheduledDeparture);

        // PDF concordance (valid PDF binary buffer)
        const pdfBuf = await generateTripReportPdfBuffer(report);
        assert.ok(Buffer.isBuffer(pdfBuf));
        assert.equal(pdfBuf.subarray(0, 5).toString('utf8'), '%PDF-');
        assert.ok(pdfBuf.length > 1000);

        // Google Sheets row concordance
        const sheetRow = buildMorningSheetRow(canonical);
        assert.equal(sheetRow[0], canonical.tripId);
        assert.equal(sheetRow[6], canonical.dataSource);
        assert.equal(sheetRow[9], canonical.scheduledDeparture);
        assert.equal(sheetRow[10], canonical.actualDeparture);
    });
});
