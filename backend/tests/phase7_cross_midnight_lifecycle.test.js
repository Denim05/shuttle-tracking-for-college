const { test, describe } = require('node:test');
const assert = require('node:assert/strict');

const { terminateActiveTripLog } = require('../server');

function makeInMemoryLiveTripLogModel(records) {
    return {
        findOne: (query) => {
            const filterDocs = () => records.filter((doc) => {
                if (query._id && String(doc._id) !== String(query._id)) return false;
                if (query.busId && String(doc.busId) !== String(query.busId)) return false;
                if (query.date && doc.date !== query.date) return false;
                if (query.status && doc.status !== query.status) return false;
                if (query.tripType && doc.tripType !== query.tripType) return false;
                return true;
            });

            const buildResult = (sortSpec) => {
                const matched = filterDocs();
                if (matched.length === 0) return null;
                if (sortSpec && sortSpec.startTime === -1) {
                    matched.sort((a, b) => new Date(b.startTime) - new Date(a.startTime));
                }
                return matched[0];
            };

            return {
                sort: async (sortSpec) => buildResult(sortSpec),
                then: (resolve, reject) => Promise.resolve(buildResult(null)).then(resolve, reject)
            };
        }
    };
}

function makeDoc(overrides) {
    return {
        _id: 'trip_1',
        busId: 'bus_1',
        driverId: 'drv_1',
        date: '2026-11-13',
        tripType: 'pickup',
        status: 'Active',
        startTime: new Date('2026-11-13T07:15:00+05:30'),
        save: async function () {
            this.savedCount = (this.savedCount || 0) + 1;
        },
        ...overrides
    };
}

describe('Phase 7.1: Cross-Midnight Trip Lifecycle Hardening', () => {
    test('1. Normal same-day cancel terminates active trip and clears only its sampler state', async () => {
        const trip1 = makeDoc({ _id: 'trip_same_cancel', busId: 'bus_1', driverId: 'drv_1' });
        const tripOther = makeDoc({ _id: 'trip_other', busId: 'bus_2', driverId: 'drv_2' });
        const Model = makeInMemoryLiveTripLogModel([trip1, tripOther]);
        const samplerState = new Map([
            ['trip_same_cancel', { timestampMs: 1000, lat: 23.18, lng: 77.41 }],
            ['trip_other', { timestampMs: 2000, lat: 23.20, lng: 77.40 }]
        ]);

        const res = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_1',
            tripType: 'pickup',
            targetStatus: 'Cancelled',
            reason: 'Traffic halt',
            verifiedDriverId: 'drv_1',
            samplerState
        });

        assert.equal(res._id, 'trip_same_cancel');
        assert.equal(res.status, 'Cancelled');
        assert.equal(res.cancellationReason, 'Traffic halt');
        assert.equal(tripOther.status, 'Active');
        assert.equal(samplerState.has('trip_same_cancel'), false);
        assert.equal(samplerState.has('trip_other'), true);
    });

    test('2. Normal same-day fail terminates active trip and marks status Failed', async () => {
        const trip1 = makeDoc({ _id: 'trip_same_fail', busId: 'bus_1', driverId: 'drv_1' });
        const Model = makeInMemoryLiveTripLogModel([trip1]);
        const samplerState = new Map([['trip_same_fail', { timestampMs: 1000, lat: 23.18, lng: 77.41 }]]);

        const res = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_1',
            targetStatus: 'Failed',
            reason: 'Flat tire',
            verifiedDriverId: 'drv_1',
            samplerState
        });

        assert.equal(res._id, 'trip_same_fail');
        assert.equal(res.status, 'Failed');
        assert.equal(res.cancellationReason, 'Flat tire');
        assert.equal(res.savedCount, 1);
        assert.equal(samplerState.has('trip_same_fail'), false);
    });

    test('3. Cross-midnight cancel succeeds even when trip started on previous IST calendar date', async () => {
        // Started 2026-11-13 23:50 IST, terminated on 2026-11-14 IST without todayStr date filter mismatch
        const midnightTrip = makeDoc({
            _id: 'trip_cm_cancel',
            busId: 'bus_cm_1',
            date: '2026-11-13',
            tripType: 'dropoff',
            startTime: new Date('2026-11-13T23:50:00+05:30')
        });
        const Model = makeInMemoryLiveTripLogModel([midnightTrip]);
        const samplerState = new Map([['trip_cm_cancel', { timestampMs: Date.now(), lat: 23.16, lng: 77.33 }]]);

        const res = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_cm_1',
            tripType: 'dropoff',
            targetStatus: 'Cancelled',
            reason: 'Late night cancel',
            samplerState
        });

        assert.ok(res);
        assert.equal(res._id, 'trip_cm_cancel');
        assert.equal(res.status, 'Cancelled');
        assert.equal(res.date, '2026-11-13');
        assert.equal(samplerState.has('trip_cm_cancel'), false);
    });

    test('4. Cross-midnight fail succeeds via explicit tripId and via active bus fallback', async () => {
        const midnightFail = makeDoc({
            _id: 'trip_cm_fail',
            busId: 'bus_cm_2',
            date: '2026-11-13',
            startTime: new Date('2026-11-13T23:55:00+05:30')
        });
        const Model = makeInMemoryLiveTripLogModel([midnightFail]);
        const samplerState = new Map([['trip_cm_fail', { timestampMs: Date.now(), lat: 23.17, lng: 77.35 }]]);

        const res = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_cm_2',
            tripId: 'trip_cm_fail',
            targetStatus: 'Failed',
            reason: 'Engine fault',
            samplerState
        });

        assert.ok(res);
        assert.equal(res._id, 'trip_cm_fail');
        assert.equal(res.status, 'Failed');
        assert.equal(res.date, '2026-11-13');
        assert.equal(samplerState.has('trip_cm_fail'), false);
    });

    test('5. Multiple active trips/buses remain isolated; explicit tripId cannot terminate another bus trip', async () => {
        const bus1Earlier = makeDoc({
            _id: 'trip_b1_old',
            busId: 'bus_1',
            driverId: 'drv_1',
            startTime: new Date('2026-11-13T07:00:00+05:30')
        });
        const bus1Latest = makeDoc({
            _id: 'trip_b1_new',
            busId: 'bus_1',
            driverId: 'drv_1',
            startTime: new Date('2026-11-13T23:45:00+05:30')
        });
        const bus2Active = makeDoc({
            _id: 'trip_b2_active',
            busId: 'bus_2',
            driverId: 'drv_2',
            startTime: new Date('2026-11-13T23:50:00+05:30')
        });

        const Model = makeInMemoryLiveTripLogModel([bus1Earlier, bus1Latest, bus2Active]);
        const samplerState = new Map([
            ['trip_b1_old', { timestampMs: 1 }],
            ['trip_b1_new', { timestampMs: 2 }],
            ['trip_b2_active', { timestampMs: 3 }]
        ]);

        // Bus 1 trying to cancel Bus 2's tripId is rejected safely
        const crossBusAttempt = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_1',
            tripId: 'trip_b2_active',
            targetStatus: 'Cancelled',
            reason: 'Wrong bus',
            samplerState
        });
        assert.equal(crossBusAttempt, null);
        assert.equal(bus2Active.status, 'Active');
        assert.equal(samplerState.has('trip_b2_active'), true);

        // Terminating bus_1 without tripId selects the latest active trip on bus_1 only
        const latestCancelled = await terminateActiveTripLog({
            LiveTripLogModel: Model,
            busId: 'bus_1',
            targetStatus: 'Cancelled',
            reason: 'Driver cancel',
            samplerState
        });
        assert.equal(latestCancelled._id, 'trip_b1_new');
        assert.equal(bus1Latest.status, 'Cancelled');
        assert.equal(bus1Earlier.status, 'Active');
        assert.equal(bus2Active.status, 'Active');

        // 6. Sampler state cleared ONLY for trip_b1_new
        assert.equal(samplerState.has('trip_b1_new'), false);
        assert.equal(samplerState.has('trip_b1_old'), true);
        assert.equal(samplerState.has('trip_b2_active'), true);
    });
});
