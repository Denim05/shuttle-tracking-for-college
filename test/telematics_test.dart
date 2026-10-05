import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sistecchalo/services/telematics/telematics_engine.dart';

void main() {
  group('Telematics Engine: RouteSnapMatcher & Geometry', () {
    late RouteSnapMatcher matcher;
    late List<LatLng> testRoute;

    setUp(() {
      matcher = RouteSnapMatcher(snapThresholdMeters: 35.0, detourConsecutivePingsThreshold: 3);
      // Route running from Bhopal Link Road south to north
      testRoute = const [
        LatLng(23.25000, 77.41000), // Segment 1 Start
        LatLng(23.26000, 77.41000), // Middle
        LatLng(23.27000, 77.41000), // Segment 2 End
      ];
    });

    test('Orthogonal projection snaps GPS drift within threshold to line', () {
      // Raw GPS point drifted 15 meters east of the line (at lat 23.255)
      // Longitude offset ~0.00015 ≈ 15m
      const driftedGps = LatLng(23.25500, 77.41015);
      final snap = matcher.snap(driftedGps, testRoute);

      expect(snap.isSnapped, isTrue);
      expect(snap.isDetour, isFalse);
      expect(snap.crossTrackDistanceMeters, lessThan(35.0));
      // Projected point should be snapped onto long 77.41000
      expect(snap.point.longitude, closeTo(77.41000, 1e-4));
      expect(snap.point.latitude, closeTo(23.25500, 1e-4));
    });

    test('Detour detector triggers after 3 consecutive pings beyond threshold', () {
      // Severe GPS drift 80m off route
      const offRouteGps = LatLng(23.25500, 77.41080);

      final p1 = matcher.snap(offRouteGps, testRoute);
      expect(p1.isSnapped, isFalse);
      expect(p1.isDetour, isFalse); // ping 1

      final p2 = matcher.snap(offRouteGps, testRoute);
      expect(p2.isSnapped, isFalse);
      expect(p2.isDetour, isFalse); // ping 2

      final p3 = matcher.snap(offRouteGps, testRoute);
      expect(p3.isSnapped, isFalse);
      expect(p3.isDetour, isTrue); // ping 3 >= threshold!
    });

    test('Monotonic cumulative progress never regresses on minor GPS jitter', () {
      // Point 1: At 40% along route
      const p1 = LatLng(23.25800, 77.41000);
      final s1 = matcher.snap(p1, testRoute);

      // Point 2: GPS jitter claims bus went 10 meters backward
      const p2Jitter = LatLng(23.25790, 77.41000);
      final s2 = matcher.snap(p2Jitter, testRoute);

      // Progress should be monotonically preserved
      expect(s2.cumulativeDistanceMeters, greaterThanOrEqualTo(s1.cumulativeDistanceMeters));
      expect(s2.progressFraction, greaterThanOrEqualTo(s1.progressFraction));
    });
  });

  group('Telematics Engine: SmoothMarkerAnimator Physics & Slerp', () {
    test('Shortest angle delta correctly wraps 355° to 5° across zero-meridian', () {
      final deltaClockwise = computeShortestAngleDelta(355.0, 5.0);
      expect(deltaClockwise, closeTo(10.0, 1e-5));

      final deltaCounterClockwise = computeShortestAngleDelta(5.0, 355.0);
      expect(deltaCounterClockwise, closeTo(-10.0, 1e-5));
    });

    test('Slerp bearing midpoint smoothly passes through 0° / 360°', () {
      // Halfway between 350° and 10° should be 0°
      final mid = slerpBearing(350.0, 10.0, 0.5);
      expect((mid == 0.0 || mid == 360.0), isTrue);
    });
  });

  group('Telematics Engine: TripProgressionFSM & Milestone State Machine', () {
    late TripProgressionFSM fsm;
    late List<LatLng> polyline;
    late List<Map<String, dynamic>> stops;

    setUp(() {
      polyline = const [
        LatLng(23.25000, 77.41000),
        LatLng(23.26000, 77.41000),
        LatLng(23.27000, 77.41000),
      ];

      stops = const [
        {'name': 'Stop A - Origin', 'lat': 23.25000, 'lng': 77.41000},
        {'name': 'Stop B - Mid Stop', 'lat': 23.26000, 'lng': 77.41000},
        {'name': 'Stop C - Campus', 'lat': 23.27000, 'lng': 77.41000},
      ];

      fsm = TripProgressionFSM(
        rawStops: stops,
        routePolyline: polyline,
        arrivalGeofenceRadiusMeters: 45.0,
        approachingThresholdMeters: 200.0,
        minDwellSecondsForArrival: 0, // instant for unit test verification
      );
    });

    test('Stop status transitions from upcoming to approaching to departed', () {
      // 1. Bus is at origin
      var snapshot = fsm.updateTelemetry(
        busPosition: const LatLng(23.25000, 77.41000),
        currentSpeedKmh: 20.0,
        busCumulativeDistanceMeters: 0.0,
        routeProgressFraction: 0.0,
      );

      // Stop B is ~1111m away -> Upcoming
      expect(snapshot.stops[1].status, equals(StopStatus.upcoming));

      // 2. Bus approaches Stop B (150m away, at lat 23.25865)
      snapshot = fsm.updateTelemetry(
        busPosition: const LatLng(23.25865, 77.41000),
        currentSpeedKmh: 15.0,
        busCumulativeDistanceMeters: 960.0,
        routeProgressFraction: 0.43,
      );
      expect(snapshot.stops[1].status, equals(StopStatus.approaching));

      // 3. Bus arrives at Stop B (within 20m, slow speed)
      snapshot = fsm.updateTelemetry(
        busPosition: const LatLng(23.25990, 77.41000),
        currentSpeedKmh: 2.0,
        busCumulativeDistanceMeters: 1100.0,
        routeProgressFraction: 0.5,
      );
      expect(snapshot.stops[1].status, equals(StopStatus.arrived));

      // 4. Bus departs Stop B and continues forward (> 40m past)
      snapshot = fsm.updateTelemetry(
        busPosition: const LatLng(23.26050, 77.41000),
        currentSpeedKmh: 30.0,
        busCumulativeDistanceMeters: 1166.0,
        routeProgressFraction: 0.53,
      );
      expect(snapshot.stops[1].status, equals(StopStatus.departed));
      expect(snapshot.completedStopsCount, greaterThanOrEqualTo(1));
    });
  });
}
