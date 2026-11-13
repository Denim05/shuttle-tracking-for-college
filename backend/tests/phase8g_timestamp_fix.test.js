const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { parseTelemetryPacketTimestamp } = require('../server');

const MAX_FUTURE_SKEW_MS = 60000;

describe('Phase 8G.2: Production Live GPS Timestamp Fix', () => {
    const serverNowMs = new Date('2026-11-13T15:13:00.000Z').getTime(); // 20:43:00 IST

    test('1. Accepts explicit UTC Z timestamp matching current server time', () => {
        const parsed = parseTelemetryPacketTimestamp('2026-11-13T15:13:00.000Z', serverNowMs);
        assert.equal(parsed.toISOString(), '2026-11-13T15:13:00.000Z');
        assert.equal(parsed.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, false);
    });

    test('2. Accepts explicit +05:30 IST offset timestamp matching current server time', () => {
        const parsed = parseTelemetryPacketTimestamp('2026-11-13T20:43:00.000+05:30', serverNowMs);
        assert.equal(parsed.toISOString(), '2026-11-13T15:13:00.000Z');
        assert.equal(parsed.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, false);
    });

    test('3. Interprets legacy timezone-naive IST timestamp (3-digit ms and 6-digit us) as IST rather than UTC', () => {
        const parsedMs = parseTelemetryPacketTimestamp('2026-11-13T20:43:00.000', serverNowMs);
        assert.equal(parsedMs.toISOString(), '2026-11-13T15:13:00.000Z');
        assert.equal(parsedMs.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, false);

        const parsedUs = parseTelemetryPacketTimestamp('2026-11-13T20:43:00.123456', serverNowMs);
        assert.equal(parsedUs.toISOString(), '2026-11-13T15:13:00.123Z');
        assert.equal(parsedUs.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, false);
    });

    test('4. Rejects genuine future timestamp beyond 60s skew', () => {
        const futureUtc = parseTelemetryPacketTimestamp('2026-11-13T15:15:00.000Z', serverNowMs);
        assert.equal(futureUtc.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, true);

        const futureNaiveIst = parseTelemetryPacketTimestamp('2026-11-13T20:45:00.000', serverNowMs);
        assert.equal(futureNaiveIst.getTime() > serverNowMs + MAX_FUTURE_SKEW_MS, true);
    });

    test('5. Driver dashboard emits explicit UTC ISO-8601 timestamp', () => {
        const driverSrc = fs.readFileSync(
            path.resolve(__dirname, '..', '..', 'lib', 'screens', 'driver_dashboard.dart'),
            'utf8'
        );
        assert.ok(
            driverSrc.includes("'timestamp': DateTime.now().toUtc().toIso8601String()"),
            'driver_dashboard.dart must emit UTC timestamp with Z suffix'
        );
        assert.equal(
            driverSrc.includes("'timestamp': DateTime.now().toIso8601String()"),
            false,
            'driver_dashboard.dart must not emit timezone-naive local timestamp'
        );
    });
});
