/**
 * Phase 1: Telemetry Persistence & IST Trip Identity Test Suite
 * Covers Tests 1-8:
 *  1. Valid telemetry creates a TripTelemetryPoint without fabricating absent fields
 *  2. Sampling throttles rapid < 5s, < 25m updates
 *  3. Movement threshold (>= 25m) triggers persistence before 5s
 *  4. Invalid GPS (NaN, Infinity, out-of-range, Null Island, bad timestamp) is rejected
 *  5. Multiple trips on the same bus isolate telemetry by tripLogId
 *  6. IST date helper handles 00:00 IST, 05:30 IST, and 23:59 IST accurately
 *  7. TripTelemetryPoint schema & 90-day TTL indexes are configured
 *  8. Trip completion preserves historical telemetry association and clears sampler state
 */

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const TripTelemetryPoint = require('../models/TripTelemetryPoint');
const {
    getIstDateString,
    validateTelemetryPoint,
    persistTelemetryPointIfSampled,
    clearTelemetrySamplerState
} = require('../services/telemetry_persistence_service');

function createMockTelemetryModel() {
    const store = [];
    return {
        store,
        async create(doc) {
            const saved = { _id: new mongoose.Types.ObjectId(), ...doc };
            store.push(saved);
            return saved;
        }
    };
}

describe('Phase 1: Telemetry Persistence & IST Trip Identity', () => {
    test('1. Valid telemetry creates a TripTelemetryPoint without fabricating absent optional fields', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripLogId = new mongoose.Types.ObjectId();
        const ts = new Date('2026-11-13T02:00:00.000Z');

        const res = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-01',
            lat: 23.1852,
            lng: 77.3021,
            speed: null,
            heading: null,
            accuracy: null,
            timestamp: ts,
            samplerState
        });

        assert.equal(res.persisted, true);
        assert.equal(res.reason, 'first_point');
        assert.equal(mockModel.store.length, 1);
        assert.equal(String(mockModel.store[0].tripLogId), String(tripLogId));
        assert.equal(mockModel.store[0].busId, 'bus-01');
        assert.equal(mockModel.store[0].speed, null);
        assert.equal(mockModel.store[0].heading, null);
        assert.equal(mockModel.store[0].accuracy, null);
    });

    test('2. Sampling throttles rapid repeated updates (< 5s and < 25m) and persists after >= 5s', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripLogId = new mongoose.Types.ObjectId();
        const t0 = new Date('2026-11-13T02:00:00.000Z');

        // 0ms: First point persisted
        const r1 = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-01',
            lat: 23.1852,
            lng: 77.3021,
            speed: 25,
            heading: 90,
            accuracy: 6,
            timestamp: t0,
            samplerState
        });
        assert.equal(r1.persisted, true);

        // +800ms, ~2m movement: throttled
        const r2 = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-01',
            lat: 23.18521,
            lng: 77.30211,
            speed: 25,
            heading: 90,
            accuracy: 6,
            timestamp: new Date(t0.getTime() + 800),
            samplerState
        });
        assert.equal(r2.persisted, false);
        assert.equal(r2.reason, 'throttled');

        // +1600ms, ~4m movement: throttled
        const r3 = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-01',
            lat: 23.18522,
            lng: 77.30212,
            speed: 25,
            heading: 90,
            accuracy: 6,
            timestamp: new Date(t0.getTime() + 1600),
            samplerState
        });
        assert.equal(r3.persisted, false);

        // +5000ms: interval elapsed -> persisted
        const r4 = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-01',
            lat: 23.18522,
            lng: 77.30212,
            speed: 25,
            heading: 90,
            accuracy: 6,
            timestamp: new Date(t0.getTime() + 5000),
            samplerState
        });
        assert.equal(r4.persisted, true);
        assert.equal(r4.reason, 'interval_elapsed');
        assert.equal(mockModel.store.length, 2);
    });

    test('3. Movement >= 25m triggers persistence before 5s interval elapses', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripLogId = new mongoose.Types.ObjectId();
        const t0 = new Date('2026-11-13T02:00:00.000Z');

        await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-02',
            lat: 23.1850,
            lng: 77.3020,
            timestamp: t0,
            samplerState
        });

        // Move ~35m north within 1 second
        const r2 = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-02',
            lat: 23.18532,
            lng: 77.3020,
            timestamp: new Date(t0.getTime() + 1000),
            samplerState
        });
        assert.equal(r2.persisted, true);
        assert.equal(r2.reason, 'movement_threshold');
        assert.equal(mockModel.store.length, 2);
    });

    test('4. Invalid GPS packets (NaN, Infinity, out-of-range, Null Island, bad speed/timestamp) are never persisted', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripLogId = new mongoose.Types.ObjectId();

        const invalidPayloads = [
            { lat: NaN, lng: 77.3 },
            { lat: 23.1, lng: Infinity },
            { lat: 95.0, lng: 77.3 },
            { lat: 23.1, lng: -181.0 },
            { lat: 0, lng: 0 },
            { lat: 23.1, lng: 77.3, speed: -5 },
            { lat: 23.1, lng: 77.3, heading: 400 },
            { lat: 23.1, lng: 77.3, timestamp: 'not-a-date' }
        ];

        for (const bad of invalidPayloads) {
            const res = await persistTelemetryPointIfSampled({
                TripTelemetryPointModel: mockModel,
                tripLogId,
                busId: 'bus-01',
                ...bad,
                samplerState
            });
            assert.equal(res.persisted, false);
        }
        assert.equal(mockModel.store.length, 0);
        assert.equal(validateTelemetryPoint({ tripLogId: '', busId: 'b1', lat: 23.1, lng: 77.3 }).valid, false);
    });

    test('5. Multiple trips on the same bus isolate telemetry by tripLogId with zero cross-contamination', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripA = new mongoose.Types.ObjectId();
        const tripB = new mongoose.Types.ObjectId();
        const t0 = new Date('2026-11-13T02:00:00.000Z');

        await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId: tripA,
            busId: 'bus-04',
            lat: 23.1850,
            lng: 77.3020,
            timestamp: t0,
            samplerState
        });

        // Trip B starts 500ms later on the SAME busId — must NOT be throttled by Trip A
        const resB = await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId: tripB,
            busId: 'bus-04',
            lat: 23.1850,
            lng: 77.3020,
            timestamp: new Date(t0.getTime() + 500),
            samplerState
        });

        assert.equal(resB.persisted, true);
        assert.equal(resB.reason, 'first_point');
        const tripAPoints = mockModel.store.filter(p => String(p.tripLogId) === String(tripA));
        const tripBPoints = mockModel.store.filter(p => String(p.tripLogId) === String(tripB));
        assert.equal(tripAPoints.length, 1);
        assert.equal(tripBPoints.length, 1);
    });

    test('6. IST date helper returns accurate Asia/Kolkata YYYY-MM-DD around 00:00, 05:30, and 23:59 IST', () => {
        // 2026-11-12T18:30:00Z == 2026-11-13 00:00:00 IST
        assert.equal(getIstDateString(new Date('2026-11-12T18:30:00.000Z')), '2026-11-13');
        // 2026-11-12T18:29:59Z == 2026-11-12 23:59:59 IST
        assert.equal(getIstDateString(new Date('2026-11-12T18:29:59.000Z')), '2026-11-12');
        // 2026-11-13T00:00:00Z == 2026-11-13 05:30:00 IST
        assert.equal(getIstDateString(new Date('2026-11-13T00:00:00.000Z')), '2026-11-13');
        // 2026-11-13T18:29:00Z == 2026-11-13 23:59:00 IST
        assert.equal(getIstDateString(new Date('2026-11-13T18:29:00.000Z')), '2026-11-13');
    });

    test('7. TripTelemetryPoint schema defines required compound and 90-day TTL indexes', () => {
        const indexes = TripTelemetryPoint.schema.indexes();
        const hasTripIdx = indexes.some(([fields]) => fields.tripLogId === 1 && fields.timestamp === 1);
        const hasBusIdx = indexes.some(([fields]) => fields.busId === 1 && fields.timestamp === 1);
        const hasTtlIdx = indexes.some(([fields, opts]) =>
            fields.timestamp === 1 && opts && opts.expireAfterSeconds === 90 * 24 * 60 * 60
        );

        assert.equal(hasTripIdx, true);
        assert.equal(hasBusIdx, true);
        assert.equal(hasTtlIdx, true);
    });

    test('8. Trip completion clears sampler state without affecting persisted telemetry points', async () => {
        const mockModel = createMockTelemetryModel();
        const samplerState = new Map();
        const tripLogId = new mongoose.Types.ObjectId();

        await persistTelemetryPointIfSampled({
            TripTelemetryPointModel: mockModel,
            tripLogId,
            busId: 'bus-07',
            lat: 23.2100,
            lng: 77.4100,
            timestamp: new Date('2026-11-13T03:00:00.000Z'),
            samplerState
        });

        assert.equal(samplerState.has(String(tripLogId)), true);
        clearTelemetrySamplerState(tripLogId, samplerState);
        assert.equal(samplerState.has(String(tripLogId)), false);
        assert.equal(mockModel.store.length, 1);
    });
});
