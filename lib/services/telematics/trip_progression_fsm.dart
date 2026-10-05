import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'route_snap_matcher.dart';

/// Status of a stop along an active trip
enum StopStatus {
  upcoming,
  approaching,
  arrived,
  departed,
}

/// Real-time telematics evaluation for an individual transit stop
class StopProgressState {
  final int stopIndex;
  final String stopName;
  final LatLng coordinate;
  final StopStatus status;
  final double distanceMeters;
  final int etaMinutes;
  final String formattedEta;
  final DateTime? arrivedTimestamp;
  final Duration dwellDuration;

  const StopProgressState({
    required this.stopIndex,
    required this.stopName,
    required this.coordinate,
    required this.status,
    required this.distanceMeters,
    required this.etaMinutes,
    required this.formattedEta,
    this.arrivedTimestamp,
    this.dwellDuration = Duration.zero,
  });

  bool get isCompleted => status == StopStatus.departed;
  bool get isCurrentActive => status == StopStatus.arrived || status == StopStatus.approaching;
}

/// Trip telematics snapshot for UI presentation
class TripSnapshot {
  final List<StopProgressState> stops;
  final int completedStopsCount;
  final int totalStopsCount;
  final StopProgressState? currentOrNextStop;
  final double routeProgressFraction; // [0.0, 1.0]
  final double rollingEmaSpeedKmh;
  final double distanceToDestinationMeters;
  final int totalEtaMinutes;

  const TripSnapshot({
    required this.stops,
    required this.completedStopsCount,
    required this.totalStopsCount,
    this.currentOrNextStop,
    required this.routeProgressFraction,
    required this.rollingEmaSpeedKmh,
    required this.distanceToDestinationMeters,
    required this.totalEtaMinutes,
  });
}

/// Production Finite-State Machine (FSM) & Rolling Distance Matrix Engine
class TripProgressionFSM {
  final List<Map<String, dynamic>> rawStops;
  final List<LatLng> routePolyline;
  final double arrivalGeofenceRadiusMeters;
  final double approachingThresholdMeters;
  final int minDwellSecondsForArrival;
  final int intermediateStopDwellBufferSeconds;

  // State per stop
  late final List<StopStatus> _stopStatuses;
  late final List<DateTime?> _arrivedTimes;
  late final List<double> _stopDistancesFromOrigin;

  // Rolling speed filter (Exponential Moving Average)
  double _emaSpeedKmh = 25.0;
  static const double _emaAlpha = 0.2; // 20% weight to new sample

  TripProgressionFSM({
    required this.rawStops,
    required this.routePolyline,
    this.arrivalGeofenceRadiusMeters = 45.0,
    this.approachingThresholdMeters = 200.0,
    this.minDwellSecondsForArrival = 10,
    this.intermediateStopDwellBufferSeconds = 45,
  }) {
    _stopStatuses = List.filled(rawStops.length, StopStatus.upcoming);
    _arrivedTimes = List.filled(rawStops.length, null);
    _calculateStopPolylineDistances();
  }

  void _calculateStopPolylineDistances() {
    _stopDistancesFromOrigin = [];
    final matcher = RouteSnapMatcher();

    for (int i = 0; i < rawStops.length; i++) {
      final s = rawStops[i];
      final lat = (s['lat'] as num?)?.toDouble() ?? 0.0;
      final lng = (s['lng'] as num?)?.toDouble() ?? 0.0;
      final snap = matcher.snap(LatLng(lat, lng), routePolyline, enforceMonotonic: false);
      _stopDistancesFromOrigin.add(snap.cumulativeDistanceMeters);
    }
  }

  /// Ingests vehicle position, current speed, and snaps along route
  TripSnapshot updateTelemetry({
    required LatLng busPosition,
    required double currentSpeedKmh,
    required double busCumulativeDistanceMeters,
    required double routeProgressFraction,
  }) {
    final now = DateTime.now();

    // Update rolling EMA speed (clamp between 8 km/h and 60 km/h)
    if (currentSpeedKmh > 2.0) {
      _emaSpeedKmh = (_emaAlpha * currentSpeedKmh) + ((1.0 - _emaAlpha) * _emaSpeedKmh);
    }
    final effectiveSpeedKmh = _emaSpeedKmh.clamp(8.0, 60.0);

    final List<StopProgressState> evaluatedStops = [];
    int completedCount = 0;

    for (int i = 0; i < rawStops.length; i++) {
      final stopData = rawStops[i];
      final stopName = (stopData['name'] ?? 'Stop ${i + 1}').toString();
      final stopLat = (stopData['lat'] as num?)?.toDouble() ?? 0.0;
      final stopLng = (stopData['lng'] as num?)?.toDouble() ?? 0.0;
      final stopCoord = LatLng(stopLat, stopLng);

      final double straightDistMeters = RouteSnapMatcher.fastDistanceMeters(busPosition, stopCoord);
      final double stopCumulativeMeters = _stopDistancesFromOrigin.length > i
          ? _stopDistancesFromOrigin[i]
          : 0.0;

      // Distance along route from bus to this stop
      final double distanceAlongRouteMeters = math.max(0.0, stopCumulativeMeters - busCumulativeDistanceMeters);

      StopStatus currentStatus = _stopStatuses[i];

      // FSM Transition Logic
      if (currentStatus != StopStatus.departed) {
        // Check if vehicle has clearly passed beyond the stop along the polyline (> 30m past)
        final bool passedThreshold = (busCumulativeDistanceMeters - stopCumulativeMeters) > 30.0;

        if (passedThreshold) {
          currentStatus = StopStatus.departed;
          _stopStatuses[i] = StopStatus.departed;
        } else if (straightDistMeters <= arrivalGeofenceRadiusMeters) {
          // Inside station geofence
          if (currentStatus != StopStatus.arrived) {
            _arrivedTimes[i] ??= now;
            final dwellSec = now.difference(_arrivedTimes[i]!).inSeconds;

            // Arrived / Dwelling condition: in geofence AND low speed for >= dwell threshold
            if (currentSpeedKmh <= 6.0 && dwellSec >= minDwellSecondsForArrival) {
              currentStatus = StopStatus.arrived;
              _stopStatuses[i] = StopStatus.arrived;
            } else {
              currentStatus = StopStatus.approaching;
              _stopStatuses[i] = StopStatus.approaching;
            }
          }
        } else if (straightDistMeters <= approachingThresholdMeters || distanceAlongRouteMeters <= approachingThresholdMeters) {
          currentStatus = StopStatus.approaching;
          _stopStatuses[i] = StopStatus.approaching;
        } else {
          currentStatus = StopStatus.upcoming;
          _stopStatuses[i] = StopStatus.upcoming;
        }
      }

      if (currentStatus == StopStatus.departed) {
        completedCount++;
      }

      // Calculate ETA using road distance and rolling EMA speed + intermediate dwell buffers
      final double speedMps = (effectiveSpeedKmh * 1000.0) / 3600.0;
      final double travelTimeSec = distanceAlongRouteMeters / speedMps;
      
      // Add historical dwell buffer for any remaining intermediate stops before this one
      int intermediateStopsAhead = 0;
      for (int k = 0; k < i; k++) {
        if (_stopStatuses[k] != StopStatus.departed) intermediateStopsAhead++;
      }
      final double totalSec = travelTimeSec + (intermediateStopsAhead * intermediateStopDwellBufferSeconds);
      final int etaMins = (totalSec / 60.0).round().clamp(1, 999);

      String formattedEta;
      if (currentStatus == StopStatus.departed) {
        formattedEta = 'Departed';
      } else if (currentStatus == StopStatus.arrived) {
        formattedEta = 'At Station';
      } else if (currentStatus == StopStatus.approaching) {
        formattedEta = '< 1 min';
      } else {
        formattedEta = '$etaMins min';
      }

      final Duration dwell = (currentStatus == StopStatus.arrived && _arrivedTimes[i] != null)
          ? now.difference(_arrivedTimes[i]!)
          : Duration.zero;

      evaluatedStops.add(StopProgressState(
        stopIndex: i,
        stopName: stopName,
        coordinate: stopCoord,
        status: currentStatus,
        distanceMeters: distanceAlongRouteMeters,
        etaMinutes: etaMins,
        formattedEta: formattedEta,
        arrivedTimestamp: _arrivedTimes[i],
        dwellDuration: dwell,
      ));
    }

    // Find next active stop
    StopProgressState? nextStop;
    for (final s in evaluatedStops) {
      if (s.status != StopStatus.departed) {
        nextStop = s;
        break;
      }
    }

    final totalRouteDist = _stopDistancesFromOrigin.isNotEmpty ? _stopDistancesFromOrigin.last : 0.0;
    final remainingToDest = math.max(0.0, totalRouteDist - busCumulativeDistanceMeters);
    final totalEtaMins = evaluatedStops.isNotEmpty ? evaluatedStops.last.etaMinutes : 0;

    return TripSnapshot(
      stops: evaluatedStops,
      completedStopsCount: completedCount,
      totalStopsCount: rawStops.length,
      currentOrNextStop: nextStop,
      routeProgressFraction: routeProgressFraction,
      rollingEmaSpeedKmh: effectiveSpeedKmh,
      distanceToDestinationMeters: remainingToDest,
      totalEtaMinutes: totalEtaMins,
    );
  }
}
