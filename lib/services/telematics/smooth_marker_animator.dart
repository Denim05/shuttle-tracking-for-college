import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Represents animated physics state of a vehicle marker at any instant t
class VehicleMarkerPhysics {
  final LatLng position;
  final double bearingDegrees;
  final double speedKmh;
  final bool isStale;
  final bool isDeadReckoning;
  final Duration stalenessDuration;

  const VehicleMarkerPhysics({
    required this.position,
    required this.bearingDegrees,
    required this.speedKmh,
    this.isStale = false,
    this.isDeadReckoning = false,
    this.stalenessDuration = Duration.zero,
  });
}

/// Computes shortest angle difference between two bearings in degrees [-180, 180].
/// Guarantees that rotating from 355° to 5° results in +10°, not -350°.
double computeShortestAngleDelta(double fromDeg, double toDeg) {
  double diff = (toDeg - fromDeg) % 360.0;
  if (diff > 180.0) diff -= 360.0;
  if (diff < -180.0) diff += 360.0;
  return diff;
}

/// Interpolates between two bearings [fromDeg] and [toDeg] along the shortest arc
double slerpBearing(double fromDeg, double toDeg, double t) {
  final delta = computeShortestAngleDelta(fromDeg, toDeg);
  return (fromDeg + delta * t.clamp(0.0, 1.0)) % 360.0;
}

/// Linear interpolation between two coordinates
LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  final lat = a.latitude + (b.latitude - a.latitude) * clampedT;
  final lng = a.longitude + (b.longitude - a.longitude) * clampedT;
  return LatLng(lat, lng);
}

/// Micro-smoothed vehicle marker animator with Dead Reckoning and Shortest-Arc Slerp
class SmoothMarkerAnimator {
  final String busId;
  final TickerProvider vsync;
  final void Function(VehicleMarkerPhysics state)? onTick;

  late final AnimationController _controller;

  LatLng _startPos = const LatLng(0, 0);
  LatLng _targetPos = const LatLng(0, 0);
  double _startBearing = 0.0;
  double _targetBearing = 0.0;

  DateTime? _lastPacketTime;
  DateTime? _lastTelemetryTimestamp;
  Duration _observedPacketInterval = const Duration(seconds: 3);

  // Velocity vector for dead reckoning
  double _lastSpeedKmh = 0.0;
  LatLng _currentRenderedPos = const LatLng(0, 0);
  double _currentRenderedBearing = 0.0;

  bool _isDisposed = false;

  SmoothMarkerAnimator({
    required this.busId,
    required this.vsync,
    this.onTick,
  }) {
    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 900),
    )..addListener(_handleTick);
  }

  VehicleMarkerPhysics get currentPhysics {
    final now = DateTime.now();
    final isStale = _lastPacketTime != null && now.difference(_lastPacketTime!).inSeconds >= 30;
    final staleness = _lastPacketTime != null ? now.difference(_lastPacketTime!) : Duration.zero;

    return VehicleMarkerPhysics(
      position: _currentRenderedPos,
      bearingDegrees: _currentRenderedBearing,
      speedKmh: _lastSpeedKmh,
      isStale: isStale,
      isDeadReckoning: _controller.isCompleted && !isStale && _lastSpeedKmh > 5.0,
      stalenessDuration: staleness,
    );
  }

  void _handleTick() {
    if (_isDisposed) return;
    final t = _controller.value;

    _currentRenderedPos = lerpLatLng(_startPos, _targetPos, t);
    _currentRenderedBearing = slerpBearing(_startBearing, _targetBearing, t);

    onTick?.call(currentPhysics);
  }

  /// Ingests a new telemetry packet.
  /// Rejects out-of-order packets based on hardware GPS timestamp.
  bool ingestTelemetry({
    required LatLng newPosition,
    required double newBearing,
    required double speedKmh,
    required DateTime packetTimestamp,
  }) {
    if (_isDisposed) return false;

    // Out-of-order timestamp rejection
    if (_lastTelemetryTimestamp != null && packetTimestamp.isBefore(_lastTelemetryTimestamp!)) {
      debugPrint('[SmoothMarkerAnimator] Rejected out-of-order packet for bus $busId');
      return false;
    }
    _lastTelemetryTimestamp = packetTimestamp;

    final now = DateTime.now();
    if (_lastPacketTime != null) {
      final diff = now.difference(_lastPacketTime!);
      if (diff.inMilliseconds > 300 && diff.inMilliseconds < 15000) {
        _observedPacketInterval = diff;
      }
    }
    _lastPacketTime = now;
    _lastSpeedKmh = speedKmh;

    // First packet initialization
    if (_startPos.latitude == 0 && _startPos.longitude == 0) {
      _startPos = newPosition;
      _targetPos = newPosition;
      _startBearing = newBearing;
      _targetBearing = newBearing;
      _currentRenderedPos = newPosition;
      _currentRenderedBearing = newBearing;
      onTick?.call(currentPhysics);
      return true;
    }

    // Dynamic animation duration: 92% of the expected interval to guarantee smooth transition before next ping
    final animMs = (_observedPacketInterval.inMilliseconds * 0.92).round().clamp(400, 4500);
    final duration = Duration(milliseconds: animMs);

    // Suppress small heading changes if vehicle is almost stationary (avoid twitching)
    double effectiveTargetBearing = newBearing;
    if (speedKmh <= 2.0) {
      effectiveTargetBearing = _currentRenderedBearing;
    }

    _startPos = _currentRenderedPos;
    _targetPos = newPosition;
    _startBearing = _currentRenderedBearing;
    _targetBearing = effectiveTargetBearing;

    _controller.duration = duration;
    _controller.forward(from: 0.0);
    return true;
  }

  /// Dead Reckoning Step: Extrapolates position forward along current vector during packet drops
  void deadReckonStep(Duration elapsedSinceUpdate, {double maxExtrapolateSec = 4.5}) {
    if (_isDisposed || _lastSpeedKmh < 3.0) return;

    final double elapsedSec = elapsedSinceUpdate.inMilliseconds / 1000.0;
    if (elapsedSec > maxExtrapolateSec) return;

    // Graceful deceleration factor as extrapolation extends
    final double decayFactor = math.max(0.0, 1.0 - (elapsedSec / maxExtrapolateSec));
    final double speedMps = (_lastSpeedKmh * (1000.0 / 3600.0)) * decayFactor;
    final double distMeters = speedMps * 0.05; // 50ms tick distance

    // Project coordinates using current bearing
    const double degToRad = 0.017453292519943295;
    final double bearingRad = _currentRenderedBearing * degToRad;

    final double dLat = (distMeters * math.cos(bearingRad)) / 111139.0;
    final double midLatRad = _currentRenderedPos.latitude * degToRad;
    final double dLng = (distMeters * math.sin(bearingRad)) / (111139.0 * math.cos(midLatRad));

    _currentRenderedPos = LatLng(
      _currentRenderedPos.latitude + dLat,
      _currentRenderedPos.longitude + dLng,
    );

    onTick?.call(currentPhysics);
  }

  void dispose() {
    _isDisposed = true;
    _controller.dispose();
  }
}
