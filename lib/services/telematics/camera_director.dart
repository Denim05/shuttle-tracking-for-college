import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Camera motion and target framing parameters
class CameraTargetFraming {
  final LatLng target;
  final double zoom;
  final double tilt;
  final double bearing;

  const CameraTargetFraming({
    required this.target,
    required this.zoom,
    required this.tilt,
    required this.bearing,
  });
}

/// Intelligent Camera Director for real-time vehicle tracking
class CameraDirector {
  final GoogleMapController? Function() getMapController;
  final Duration userInactivityAutoRecenterDuration;
  final Duration minCameraThrottleDuration;

  // State notifiers
  final ValueNotifier<bool> isFollowingBusNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showRecenterFabNotifier = ValueNotifier<bool>(false);

  Timer? _inactivityTimer;
  DateTime? _lastCameraMoveTime;
  bool _isDriveMode = false;

  CameraDirector({
    required this.getMapController,
    this.userInactivityAutoRecenterDuration = const Duration(seconds: 8),
    this.minCameraThrottleDuration = const Duration(milliseconds: 350),
  });

  bool get isFollowing => isFollowingBusNotifier.value;

  void setDriveMode(bool enabled) {
    _isDriveMode = enabled;
  }

  /// Calculates dynamic speed-adaptive zoom and framing
  static CameraTargetFraming computeFraming({
    required ll.LatLng busPos,
    required double speedKmh,
    required double bearingDeg,
    required bool isDriveMode,
  }) {
    double targetZoom;
    double targetTilt;
    double targetBearing;

    if (isDriveMode) {
      targetZoom = 18.0;
      targetTilt = 52.0;
      targetBearing = bearingDeg;
    } else {
      if (speedKmh > 40.0) {
        // High speed cruising: broader view, subtle tilt
        targetZoom = 15.0;
        targetTilt = 25.0;
        targetBearing = 0.0;
      } else if (speedKmh >= 10.0) {
        // City driving speed
        targetZoom = 15.8;
        targetTilt = 10.0;
        targetBearing = 0.0;
      } else {
        // Slow or stopped at station: tight focus on stop
        targetZoom = 17.0;
        targetTilt = 0.0;
        targetBearing = 0.0;
      }
    }

    return CameraTargetFraming(
      target: LatLng(busPos.latitude, busPos.longitude),
      zoom: targetZoom,
      tilt: targetTilt,
      bearing: targetBearing,
    );
  }

  /// Called whenever the user manually drags, touches, or interacts with the map surface
  void onUserManualPan() {
    if (isFollowingBusNotifier.value) {
      isFollowingBusNotifier.value = false;
      showRecenterFabNotifier.value = true;
    }

    // Reset 8-second auto-recenter timer
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(userInactivityAutoRecenterDuration, () {
      recenterOnBus();
    });
  }

  /// User tapped the "Recenter on Bus" FAB or auto-recenter fired
  void recenterOnBus([ll.LatLng? currentBusPos, double speedKmh = 0.0, double bearingDeg = 0.0]) {
    _inactivityTimer?.cancel();
    isFollowingBusNotifier.value = true;
    showRecenterFabNotifier.value = false;

    if (currentBusPos != null) {
      final framing = computeFraming(
        busPos: currentBusPos,
        speedKmh: speedKmh,
        bearingDeg: bearingDeg,
        isDriveMode: _isDriveMode,
      );

      final controller = getMapController();
      controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: framing.target,
            zoom: framing.zoom,
            tilt: framing.tilt,
            bearing: framing.bearing,
          ),
        ),
      );
    }
  }

  /// Throttled camera follow execution during active vehicle motion
  void updateCameraForVehicle({
    required ll.LatLng busPos,
    required double speedKmh,
    required double bearingDeg,
  }) {
    if (!isFollowingBusNotifier.value) return;

    final now = DateTime.now();
    if (_lastCameraMoveTime != null &&
        now.difference(_lastCameraMoveTime!) < minCameraThrottleDuration) {
      return; // Respect JNI platform channel bandwidth
    }
    _lastCameraMoveTime = now;

    final framing = computeFraming(
      busPos: busPos,
      speedKmh: speedKmh,
      bearingDeg: bearingDeg,
      isDriveMode: _isDriveMode,
    );

    final controller = getMapController();
    controller?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: framing.target,
          zoom: framing.zoom,
          tilt: framing.tilt,
          bearing: framing.bearing,
        ),
      ),
    );
  }

  void dispose() {
    _inactivityTimer?.cancel();
    isFollowingBusNotifier.dispose();
    showRecenterFabNotifier.dispose();
  }
}
