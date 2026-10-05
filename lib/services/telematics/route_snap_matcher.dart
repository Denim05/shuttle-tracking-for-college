import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Result of projecting a GPS coordinate onto a route polyline
class SnapResult {
  /// The snapped position on the road line (or original raw position if off-route)
  final LatLng point;

  /// The perpendicular (orthogonal) cross-track error distance in meters from the raw GPS point to the line
  final double crossTrackDistanceMeters;

  /// Whether the raw GPS point was within the snap threshold (e.g. 35m)
  final bool isSnapped;

  /// Cumulative distance in meters from the beginning of the polyline to the snapped point
  final double cumulativeDistanceMeters;

  /// Normalized progress along the route [0.0, 1.0]
  final double progressFraction;

  /// Index of the polyline segment [i, i+1] where the projection landed
  final int segmentIndex;

  /// True if vehicle has been detected outside snapping threshold for >= threshold count
  final bool isDetour;

  const SnapResult({
    required this.point,
    required this.crossTrackDistanceMeters,
    required this.isSnapped,
    required this.cumulativeDistanceMeters,
    required this.progressFraction,
    required this.segmentIndex,
    this.isDetour = false,
  });
}

/// Production-grade Geospatial Map-Matching & Cross-Track Error (XTE) Projection Engine
class RouteSnapMatcher {
  final double snapThresholdMeters;
  final int detourConsecutivePingsThreshold;

  int _consecutiveOffRoutePings = 0;
  double _lastMonotonicCumulativeMeters = 0.0;
  String? _currentRouteId;
  String? get currentRouteId => _currentRouteId;

  RouteSnapMatcher({
    this.snapThresholdMeters = 35.0,
    this.detourConsecutivePingsThreshold = 3,
  });

  /// Reset internal monotonic tracking when switching routes or shifts
  void resetRoute([String? newRouteId]) {
    _currentRouteId = newRouteId;
    _consecutiveOffRoutePings = 0;
    _lastMonotonicCumulativeMeters = 0.0;
  }

  /// Calculates fast equirectangular distance in meters between two coordinates.
  /// 100x faster than trigonometric haversine on high-frequency mobile ticks.
  static double fastDistanceMeters(LatLng p1, LatLng p2) {
    const double degToRad = 0.017453292519943295; // pi / 180
    final double dLat = (p2.latitude - p1.latitude) * 111139.0;
    final double midLatRad = ((p1.latitude + p2.latitude) * 0.5) * degToRad;
    final double dLng = (p2.longitude - p1.longitude) * 111139.0 * math.cos(midLatRad);
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// Total length of a polyline in meters
  static double calculatePolylineLength(List<LatLng> polyline) {
    if (polyline.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < polyline.length - 1; i++) {
      total += fastDistanceMeters(polyline[i], polyline[i + 1]);
    }
    return total;
  }

  /// Projects raw GPS (lat, lng) onto the nearest segment of [polyline]
  /// and maintains monotonic progress guarantees.
  SnapResult snap(LatLng rawGps, List<LatLng> polyline, {bool enforceMonotonic = true}) {
    if (polyline.isEmpty) {
      return SnapResult(
        point: rawGps,
        crossTrackDistanceMeters: 0.0,
        isSnapped: false,
        cumulativeDistanceMeters: 0.0,
        progressFraction: 0.0,
        segmentIndex: 0,
      );
    }

    if (polyline.length == 1) {
      final d = fastDistanceMeters(rawGps, polyline.first);
      return SnapResult(
        point: polyline.first,
        crossTrackDistanceMeters: d,
        isSnapped: d <= snapThresholdMeters,
        cumulativeDistanceMeters: 0.0,
        progressFraction: 1.0,
        segmentIndex: 0,
      );
    }

    double minXte = double.infinity;
    LatLng bestProjPoint = polyline.first;
    int bestSegmentIndex = 0;
    double cumulativeBeforeBestSegment = 0.0;
    double bestProjDistOnSegment = 0.0;

    double runningCumulativeMeters = 0.0;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final segLength = fastDistanceMeters(a, b);

      if (segLength < 1e-4) {
        continue;
      }

      // Orthogonal projection scalar t
      final proj = _projectOntoSegment(rawGps, a, b);
      final xte = fastDistanceMeters(rawGps, proj.snapped);

      if (xte < minXte) {
        minXte = xte;
        bestProjPoint = proj.snapped;
        bestSegmentIndex = i;
        cumulativeBeforeBestSegment = runningCumulativeMeters;
        bestProjDistOnSegment = proj.t * segLength;
      }

      runningCumulativeMeters += segLength;
    }

    final totalRouteLength = runningCumulativeMeters > 0 ? runningCumulativeMeters : 1.0;
    double rawCumulativeDist = cumulativeBeforeBestSegment + bestProjDistOnSegment;

    // Detour check: if outside threshold
    final bool withinThreshold = minXte <= snapThresholdMeters;
    if (!withinThreshold) {
      _consecutiveOffRoutePings++;
    } else {
      _consecutiveOffRoutePings = 0;
    }

    final bool isDetour = _consecutiveOffRoutePings >= detourConsecutivePingsThreshold;

    // Monotonic guard: vehicle should never jump backwards on jitter unless a large loop/detour occurs
    double effectiveCumulativeMeters = rawCumulativeDist;
    if (enforceMonotonic && !isDetour) {
      if (effectiveCumulativeMeters < _lastMonotonicCumulativeMeters) {
        // If backward delta is minor jitter (< 35m), hold previous forward mark
        if ((_lastMonotonicCumulativeMeters - effectiveCumulativeMeters) < 35.0) {
          effectiveCumulativeMeters = _lastMonotonicCumulativeMeters;
        } else {
          // Significant jump back (e.g. route restart / loop)
          _lastMonotonicCumulativeMeters = effectiveCumulativeMeters;
        }
      } else {
        _lastMonotonicCumulativeMeters = effectiveCumulativeMeters;
      }
    } else {
      _lastMonotonicCumulativeMeters = effectiveCumulativeMeters;
    }

    final progressFraction = (effectiveCumulativeMeters / totalRouteLength).clamp(0.0, 1.0);

    return SnapResult(
      point: withinThreshold ? bestProjPoint : rawGps,
      crossTrackDistanceMeters: minXte,
      isSnapped: withinThreshold,
      cumulativeDistanceMeters: effectiveCumulativeMeters,
      progressFraction: progressFraction,
      segmentIndex: bestSegmentIndex,
      isDetour: isDetour,
    );
  }

  /// Internal projection helper using planar approximation for local coordinates
  static _SegmentProjection _projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    const double degToRad = 0.017453292519943295;
    final double midLatRad = ((a.latitude + b.latitude) * 0.5) * degToRad;

    final double dX = (b.longitude - a.longitude) * 111139.0 * math.cos(midLatRad);
    final double dY = (b.latitude - a.latitude) * 111139.0;
    final double lengthSq = dX * dX + dY * dY;

    if (lengthSq == 0) {
      return _SegmentProjection(snapped: a, t: 0.0);
    }

    final double pX = (p.longitude - a.longitude) * 111139.0 * math.cos(midLatRad);
    final double pY = (p.latitude - a.latitude) * 111139.0;

    final double dot = pX * dX + pY * dY;
    final double t = (dot / lengthSq).clamp(0.0, 1.0);

    final double snappedLat = a.latitude + (b.latitude - a.latitude) * t;
    final double snappedLng = a.longitude + (b.longitude - a.longitude) * t;

    return _SegmentProjection(
      snapped: LatLng(snappedLat, snappedLng),
      t: t,
    );
  }
}

class _SegmentProjection {
  final LatLng snapped;
  final double t;
  const _SegmentProjection({required this.snapped, required this.t});
}
