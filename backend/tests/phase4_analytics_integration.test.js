const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const XLSX = require('xlsx');

const Route = require('../models/Route');
const Bus = require('../models/Bus');
const Driver = require('../models/Driver');
const LiveTripLog = require('../models/LiveTripLog');
const TripTelemetryPoint = require('../models/TripTelemetryPoint');

const {
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

function createIstTimestamp(dateStr, hh, mm, ss = 0) {
    const pad = (n) => String(n).padStart(2, '0');
    return new Date(`${dateStr}T${pad(hh)}:${pad(mm)}:${pad(ss)}+05:30`);
}

describe('Phase 4: Canonical Journey Analytics Integration & Reporting', () => {
    const origRouteFind = Route.find;
    const origBusFind = Bus.find;
    const origDriverFind = Driver.find;
    const origLiveTripLogFind = LiveTripLog.find;
    const origTripTelemetryPointFind = TripTelemetryPoint.find;

    let mockRoutes = [];
    let mockBuses = [];
    let mockDrivers = [];
    let mockLiveLogs = [];
    let mockTelemetry = [];

    beforeEach(() => {
        mockRoutes = [
            {
                _id: 'route_p4_1',
                name: 'Kolar Road Route',
                stops: [
                    { name: 'Kolar Square', time: '07:15 AM', lat: 23.1800, lng: 77.4100 },
                    { name: 'Bansal Hospital', time: '07:45 AM', lat: 23.2000, lng: 77.4000 },
                    { name: 'SISTec Ratibad Campus', time: '08:30 AM', lat: 23.1500, lng: 77.3100 }
                ],
                coordinates: [
                    { lat: 23.1800, lng: 77.4100 },
                    { lat: 23.2000, lng: 77.4000 },
                    { lat: 23.1500, lng: 77.3100 }
                ]
            }
        ];

        mockBuses = [
            {
                _id: 'bus_p4_1',
                name: 'Bus 01 - Kolar',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_p4_1',
                routeName: 'Kolar Road Route',
                driverId: 'drv_p4_1'
            }
        ];

        mockDrivers = [
            { _id: 'drv_p4_1', name: 'Rajesh Kumar', phone: '9876543210', assignedBus: 'bus_p4_1' }
        ];

        const trip1Start = createIstTimestamp('2026-11-13', 7, 15, 0);
        const trip1End = createIstTimestamp('2026-11-13', 8, 35, 0);
        const trip2Start = createIstTimestamp('2026-11-13', 16, 40, 0);
        const trip2End = createIstTimestamp('2026-11-13', 17, 50, 0);

        mockLiveLogs = [
            {
                _id: 'trip_p4_pickup_1',
                busId: 'bus_p4_1',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_p4_1',
                routeName: 'Kolar Road Route',
                driverName: 'Rajesh Kumar',
                shiftType: 'pickup',
                tripType: 'pickup',
                direction: 'to_campus',
                date: '2026-11-13',
                tripDateIst: '2026-11-13',
                status: 'completed',
                startedAt: trip1Start,
                endedAt: trip1End,
                distanceKm: 14.5,
                reachedStops: [
                    { stopName: 'Kolar Square', stopIndex: 0, reachedAt: createIstTimestamp('2026-11-13', 7, 20, 0) },
                    { stopName: 'Bansal Hospital', stopIndex: 1, reachedAt: createIstTimestamp('2026-11-13', 7, 50, 0) },
                    { stopName: 'SISTec Ratibad Campus', stopIndex: 2, reachedAt: createIstTimestamp('2026-11-13', 8, 35, 0) }
                ]
            },
            {
                _id: 'trip_p4_dropoff_2',
                busId: 'bus_p4_1',
                busNumber: 'MP-04-PA-0001',
                routeId: 'route_p4_1',
                routeName: 'Kolar Road Route',
                driverName: 'Rajesh Kumar',
                shiftType: 'dropoff',
                tripType: 'dropoff',
                direction: 'from_campus',
                date: '2026-11-13',
                tripDateIst: '2026-11-13',
                status: 'completed',
                startedAt: trip2Start,
                endedAt: trip2End,
                distanceKm: 13.8,
                reachedStops: [
                    { stopName: 'SISTec Ratibad Campus', stopIndex: 0, reachedAt: createIstTimestamp('2026-11-13', 16, 42, 0) }
                ]
            }
        ];

        mockTelemetry = [
            // Trip 1 telemetry points
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 7, 15, 0), lat: 23.1800, lng: 77.4100, speedKmh: 0, accuracyMeters: 8 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 7, 18, 0), lat: 23.1825, lng: 77.4085, speedKmh: 28, accuracyMeters: 10 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 7, 20, 0), lat: 23.1801, lng: 77.4101, speedKmh: 2, accuracyMeters: 7 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 7, 35, 0), lat: 23.1920, lng: 77.4040, speedKmh: 36, accuracyMeters: 9 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 7, 50, 0), lat: 23.2000, lng: 77.4000, speedKmh: 1, accuracyMeters: 6 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 8, 15, 0), lat: 23.1750, lng: 77.3550, speedKmh: 42, accuracyMeters: 11 },
            { tripLogId: 'trip_p4_pickup_1', timestamp: createIstTimestamp('2026-11-13', 8, 35, 0), lat: 23.1500, lng: 77.3100, speedKmh: 0, accuracyMeters: 5 },
            // Trip 2 telemetry points (isolated by tripLogId)
            { tripLogId: 'trip_p4_dropoff_2', timestamp: createIstTimestamp('2026-11-13', 16, 40, 0), lat: 23.1500, lng: 77.3100, speedKmh: 0, accuracyMeters: 9 },
            { tripLogId: 'trip_p4_dropoff_2', timestamp: createIstTimestamp('2026-11-13', 17, 10, 0), lat: 23.1750, lng: 77.3550, speedKmh: 34, accuracyMeters: 12 },
            { tripLogId: 'trip_p4_dropoff_2', timestamp: createIstTimestamp('2026-11-13', 17, 50, 0), lat: 23.1800, lng: 77.4100, speedKmh: 0, accuracyMeters: 8 }
        ];

        Route.find = async () => mockRoutes;
        Bus.find = () => ({ sort: async () => mockBuses });
        Driver.find = async () => mockDrivers;
        LiveTripLog.find = () => ({ sort: async () => mockLiveLogs });
        TripTelemetryPoint.find = (query) => {
            const ids = new Set((query?.tripLogId?.$in || []).map(String));
            const filtered = ids.size > 0
                ? mockTelemetry.filter((pt) => ids.has(String(pt.tripLogId)))
                : mockTelemetry;
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

    test('1. generateTripReportData integrates analyzeJourney & telemetry per tripLogId without cross-trip bleed', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });

        assert.equal(report.allTrips.length, 2);
        const pickup = report.allTrips.find((t) => t.tripId === 'trip_p4_pickup_1');
        const dropoff = report.allTrips.find((t) => t.tripId === 'trip_p4_dropoff_2');

        assert.ok(pickup);
        assert.ok(dropoff);

        // Telemetry isolation
        assert.equal(pickup.validGpsSamples, 7);
        assert.equal(dropoff.validGpsSamples, 3);
        assert.equal(pickup.gpsTelemetry.validSamples, 7);
        assert.equal(dropoff.gpsTelemetry.validSamples, 3);

        // Journey analytics enrichment
        assert.ok(pickup.actualDistanceKm > 0);
        assert.ok(pickup.averageSpeedKmh > 0);
        assert.ok(Array.isArray(pickup.journeyTimeline) && pickup.journeyTimeline.length > 0);
        assert.ok(Array.isArray(pickup.segments) && pickup.segments.length >= 1);
        assert.ok(Array.isArray(pickup.stops) && pickup.stops.length === 3);

        // Dropoff unsupported stop schedule remains null / unavailable
        assert.ok(Array.isArray(dropoff.stops) && dropoff.stops.length > 0);
        assert.equal(dropoff.stops[0].scheduledArrival, null);
        assert.equal(dropoff.stops[0].scheduledDeparture, null);
    });

    test('2. Fleet, Bus, Route, Stop Performance, and Data Quality analytics aggregations are populated', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });

        assert.ok(report.fleetAnalytics);
        assert.equal(report.fleetAnalytics.totalTrips, 2);
        assert.equal(report.fleetAnalytics.liveGpsTrips, 2);

        assert.ok(Array.isArray(report.busAnalytics) && report.busAnalytics.length === 1);
        assert.equal(report.busAnalytics[0].totalTrips, 2);

        assert.ok(Array.isArray(report.routeAnalytics) && report.routeAnalytics.length === 2);
        assert.equal(report.routeAnalytics[0].routeName, 'Kolar Road Route');

        assert.ok(Array.isArray(report.stopPerformance) && report.stopPerformance.length >= 1);
        assert.ok(report.dataQuality);
        assert.equal(report.dataQuality.tripsWithGps, 2);
        assert.equal(report.dataQuality.tripsWithoutGps, 0);
        assert.equal(report.dataQuality.invalidGpsSampleCount, 0);
    });

    test('3. All 6 normalized CSV files and csvType selector include UTF-8 BOM and canonical metrics', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const csvFiles = generateTripReportCsvFiles(report);

        const expectedNames = [
            'trip_summary.csv',
            'journey_timeline.csv',
            'stop_analytics.csv',
            'travel_segments.csv',
            'gps_telemetry.csv',
            'fleet_summary.csv'
        ];
        assert.deepEqual(Object.keys(csvFiles), expectedNames);

        for (const fileName of expectedNames) {
            assert.ok(csvFiles[fileName].startsWith('\uFEFF'), `${fileName} must start with UTF-8 BOM`);
            assert.ok(csvFiles[fileName].split('\n').length >= 2, `${fileName} must have header and data rows`);
        }

        assert.equal(generateTripReportCsvString(report, 'stop_analytics'), csvFiles['stop_analytics.csv']);
        assert.equal(generateTripReportCsvString(report, 'travel_segments'), csvFiles['travel_segments.csv']);
        assert.equal(generateTripReportCsvString(report), csvFiles['trip_summary.csv']);
        assert.ok(csvFiles['trip_summary.csv'].includes('trip_p4_pickup_1'));
    });

    test('4. Excel workbook contains all 12 structured sheets with canonical concordance', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const xlsxBuf = generateTripReportExcelBuffer(report);
        const wb = XLSX.read(xlsxBuf, { type: 'buffer' });

        const expectedSheets = [
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
        ];
        assert.deepEqual(wb.SheetNames, expectedSheets);

        const masterRows = XLSX.utils.sheet_to_json(wb.Sheets['Master Trip Log']);
        assert.equal(masterRows.length, 2);
        const p1 = masterRows.find((r) => r['Trip ID'] === 'trip_p4_pickup_1');
        assert.ok(p1);
        assert.equal(p1['Actual GPS Distance (km)'], report.allTrips[0].actualDistanceKm);

        const stopRows = XLSX.utils.sheet_to_json(wb.Sheets['Stop Analytics']);
        assert.ok(stopRows.some((r) => r['Trip ID'] === 'trip_p4_pickup_1' && r['Stop Name'] === 'Kolar Square'));
    });

    test('5. Multi-page PDF buffer is valid PDF binary with canonical content', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const pdfBuf = await generateTripReportPdfBuffer(report);

        assert.ok(Buffer.isBuffer(pdfBuf));
        assert.equal(pdfBuf.subarray(0, 5).toString('utf8'), '%PDF-');
        assert.ok(pdfBuf.length > 2000);
    });

    test('6. Google Sheets row builders expose Phase 4 telemetry & speed columns accurately', async () => {
        const report = await generateTripReportData({ targetDate: '2026-11-13', shift: 'all' });
        const pickup = report.allTrips.find((t) => t.tripId === 'trip_p4_pickup_1');
        const dropoff = report.allTrips.find((t) => t.tripId === 'trip_p4_dropoff_2');

        const mRow = buildMorningSheetRow(pickup);
        assert.equal(mRow[0], 'trip_p4_pickup_1');
        assert.equal(mRow[6], 'LIVE GPS');
        assert.equal(mRow[19], 7);
        assert.equal(mRow[21], pickup.telemetryCompletenessPercent);

        const eRow = buildEveningSheetRow(dropoff);
        assert.equal(eRow[0], 'trip_p4_dropoff_2');
        assert.equal(eRow[6], 'LIVE GPS');
        assert.equal(eRow[20], 3);

        const sRow = buildStopSheetRow({
            tripId: pickup.tripId,
            date: pickup.date,
            shift: 'Morning Pickup',
            dataSource: pickup.dataSource,
            busNo: pickup.busNo,
            vehicleNo: pickup.vehicleNo,
            routeName: pickup.routeName,
            stopNo: 1,
            stopName: 'Kolar Square',
            scheduledTime: '07:15 AM',
            actualTime: '07:20 AM',
            variance: '+5m (Delayed)',
            status: 'Reached'
        });
        assert.equal(sRow[0], 'trip_p4_pickup_1');

        const kpiRows = buildKpiSheetRow({ ...report, totalTrips: 2, onTimeTrips: 2, delayedTrips: 0, punctualityRate: 100 });
        assert.ok(Array.isArray(kpiRows) && kpiRows.length >= 1);
    });

    test('7. Manager API HTTP route serves JSON, csvType CSV, Excel, and PDF consistently', async () => {
        const app = express();
        const secret = 'test_phase4_secret';
        const authMiddleware = (req, res, next) => {
            const token = (req.headers.authorization || '').replace('Bearer ', '');
            if (!token) return res.status(401).json({ error: 'Unauthorized' });
            req.user = jwt.verify(token, secret);
            next();
        };

        app.get('/api/manager/reports/bus-trip-report', authMiddleware, async (req, res) => {
            const { date, shift, format, csvType } = req.query;
            const reportData = await generateTripReportData({
                targetDate: date || '2026-11-13',
                shift: shift || 'all'
            });
            if (format === 'xlsx') {
                const buf = generateTripReportExcelBuffer(reportData);
                res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
                return res.status(200).send(buf);
            }
            if (format === 'pdf') {
                const buf = await generateTripReportPdfBuffer(reportData);
                res.setHeader('Content-Type', 'application/pdf');
                return res.status(200).send(buf);
            }
            if (format === 'json') {
                return res.json({ success: true, ...reportData });
            }
            const csv = generateTripReportCsvString(reportData, csvType || 'trip_summary');
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            return res.status(200).send(csv);
        });

        const server = http.createServer(app);
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
        const port = server.address().port;
        const token = jwt.sign({ id: 'mgr_1', role: 'manager' }, secret);

        try {
            const base = `http://127.0.0.1:${port}/api/manager/reports/bus-trip-report?date=2026-11-13&shift=all`;

            const jsonRes = await fetch(`${base}&format=json`, { headers: { Authorization: `Bearer ${token}` } });
            assert.equal(jsonRes.status, 200);
            const jsonBody = await jsonRes.json();
            assert.equal(jsonBody.success, true);
            assert.equal(jsonBody.allTrips.length, 2);
            assert.ok(jsonBody.fleetAnalytics);

            const csvRes = await fetch(`${base}&format=csv&csvType=stop_analytics`, { headers: { Authorization: `Bearer ${token}` } });
            assert.equal(csvRes.status, 200);
            const csvBytes = Buffer.from(await csvRes.arrayBuffer());
            assert.equal(csvBytes.subarray(0, 3).toString('hex'), 'efbbbf');
            const csvText = csvBytes.toString('utf8');
            assert.ok(csvText.includes('Kolar Square'));

            const xlsxRes = await fetch(`${base}&format=xlsx`, { headers: { Authorization: `Bearer ${token}` } });
            assert.equal(xlsxRes.status, 200);
            const xlsxAb = await xlsxRes.arrayBuffer();
            const wb = XLSX.read(Buffer.from(xlsxAb), { type: 'buffer' });
            assert.equal(wb.SheetNames.length, 12);

            const pdfRes = await fetch(`${base}&format=pdf`, { headers: { Authorization: `Bearer ${token}` } });
            assert.equal(pdfRes.status, 200);
            const pdfAb = await pdfRes.arrayBuffer();
            assert.equal(Buffer.from(pdfAb).subarray(0, 5).toString('utf8'), '%PDF-');
        } finally {
            await new Promise((resolve) => server.close(resolve));
        }
    });
});
