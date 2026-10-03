import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class MapMath {
  static const double earthRadius = 6371000; // in meters

  /// Calculates the distance between two LatLng points in meters
  static double distance(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, p1, p2);
  }

  /// Snaps a GPS point to the closest point on a polyline route.
  /// If the closest point on the route is further than [maxDistanceMeters], 
  /// it returns the original point.
  static LatLng snapToRoute(LatLng point, List<LatLng> route, {double maxDistanceMeters = 200.0}) {
    if (route.isEmpty || route.length < 2) return point;

    double minDist = double.infinity;
    LatLng snappedPos = point;

    for (int i = 0; i < route.length - 1; i++) {
      final LatLng a = route[i];
      final LatLng b = route[i + 1];

      final LatLng closestOnSegment = _closestPointOnSegment(point, a, b);
      final double dist = distance(point, closestOnSegment);

      if (dist < minDist) {
        minDist = dist;
        snappedPos = closestOnSegment;
      }
    }

    if (minDist <= maxDistanceMeters) {
      return snappedPos;
    }

    return point;
  }

  /// Finds the closest point on a line segment [a, b] to a point [p]
  /// using approximate flat earth projection for very short distances.
  static LatLng _closestPointOnSegment(LatLng p, LatLng a, LatLng b) {
    // Convert to radians for equirectangular approximation
    final double latP = p.latitudeInRad;
    final double lonP = p.longitudeInRad;
    final double latA = a.latitudeInRad;
    final double lonA = a.longitudeInRad;
    final double latB = b.latitudeInRad;
    final double lonB = b.longitudeInRad;

    // Equirectangular projection (good enough for short stretches)
    final double dLatAB = latB - latA;
    final double dLonAB = (lonB - lonA) * math.cos((latA + latB) / 2);
    
    final double dLatAP = latP - latA;
    final double dLonAP = (lonP - lonA) * math.cos((latA + latP) / 2);

    final double dotProduct = (dLonAP * dLonAB) + (dLatAP * dLatAB);
    final double lengthSquareWalk = (dLonAB * dLonAB) + (dLatAB * dLatAB);

    if (lengthSquareWalk == 0) return a;

    double t = dotProduct / lengthSquareWalk;
    t = t.clamp(0.0, 1.0);


    final double projLat = a.latitude + (b.latitude - a.latitude) * t;
    final double projLon = a.longitude + (b.longitude - a.longitude) * t;

    return LatLng(projLat, projLon);
  }

  /// Calculates the progress percentage (0.0 to 1.0) along a polyline route
  static double calculateRouteProgress(LatLng point, List<LatLng> route) {
    if (route.isEmpty || route.length < 2) return 0.0;

    double totalDist = 0;
    for (int i = 0; i < route.length - 1; i++) {
      totalDist += distance(route[i], route[i + 1]);
    }

    if (totalDist == 0) return 0.0;

    double minDist = double.infinity;
    double progressDist = 0;
    double bestProgressDist = 0;

    for (int i = 0; i < route.length - 1; i++) {
      final LatLng a = route[i];
      final LatLng b = route[i + 1];
      final double segmentDist = distance(a, b);

      final LatLng closest = _closestPointOnSegment(point, a, b);
      final double distToSegment = distance(point, closest);

      if (distToSegment < minDist) {
        minDist = distToSegment;
        final double distInSegment = distance(a, closest);
        bestProgressDist = progressDist + distInSegment;
      }
      progressDist += segmentDist;
    }

    return (bestProgressDist / totalDist).clamp(0.0, 1.0);
  }

  /// Estimates road distance from straight-line Haversine distance.
  /// Indian mixed roads (urban + highway) typically have 1.4–1.6× straight-line ratio.
  /// Default factor: 1.5 (calibrated for Bhopal/Indian mixed terrain).
  static double estimateRoadDistance(LatLng p1, LatLng p2, {double roadFactor = 1.5}) {
    return distance(p1, p2) * roadFactor;
  }

  /// Calculates distance along a polyline from the bus position to a target stop.
  /// Returns actual road distance in meters if polyline coordinates are available,
  /// otherwise falls back to estimated road distance (1.5× Haversine).
  static double distanceAlongRoute(LatLng busPos, LatLng stopPos, List<LatLng> route) {
    if (route.isEmpty || route.length < 2) {
      return estimateRoadDistance(busPos, stopPos);
    }

    // Find nearest point on route for bus and stop
    double minBusDist = double.infinity;
    int busIdx = 0;
    double minStopDist = double.infinity;
    int stopIdx = 0;

    for (int i = 0; i < route.length; i++) {
      final dBus = distance(busPos, route[i]);
      if (dBus < minBusDist) {
        minBusDist = dBus;
        busIdx = i;
      }
      final dStop = distance(stopPos, route[i]);
      if (dStop < minStopDist) {
        minStopDist = dStop;
        stopIdx = i;
      }
    }

    // If stop is behind bus on the route, use estimated distance
    if (stopIdx <= busIdx) {
      return estimateRoadDistance(busPos, stopPos);
    }

    // Sum polyline segments between bus and stop positions
    double totalDist = 0;
    for (int i = busIdx; i < stopIdx; i++) {
      totalDist += distance(route[i], route[i + 1]);
    }
    return totalDist;
  }

  /// Calculate ETA in minutes given road distance (meters) and speed (km/h).
  /// Uses production speed floor of 8 km/h and ceiling of 60 km/h.
  static int calculateRoadETA(double roadDistanceMeters, double speedKmH) {
    final clampedSpeed = speedKmH.clamp(8.0, 60.0);
    // If speed is too low (< 5 km/h), use default 25 km/h
    final effectiveSpeed = speedKmH < 5 ? 25.0 : clampedSpeed;
    final speedMps = (effectiveSpeed * 1000) / 3600;
    final travelSec = roadDistanceMeters / speedMps;
    return (travelSec / 60).round().clamp(1, 999);
  }
}

/// Tween for smooth interpolation of LatLng coordinates
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end}) 
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    final lat = begin!.latitude + (end!.latitude - begin!.latitude) * t;
    final lng = begin!.longitude + (end!.longitude - begin!.longitude) * t;
    return LatLng(lat, lng);
  }
}

