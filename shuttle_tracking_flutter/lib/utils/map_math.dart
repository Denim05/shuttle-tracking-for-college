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
