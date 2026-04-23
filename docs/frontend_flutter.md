# Flutter Tracking Application Documentation

The Flutter application (`shuttle_tracking_flutter`) is primarily designated as the **Driver/Bus Tracking node**. Its core responsibility is to continuously sample the device's GPS hardware and broadcast coordinates to the Node.js backend via Socket.io.

## Directory Structure

```text
lib/
├── main.dart             # Application entry point and Root widget
├── screens/              # UI screens (Login, Tracking, Dashboard)
├── services/             # Background tasks and API connectivity
├── models/               # Dart data classes for JSON serialization
├── constants/            # API URLs and style definitions
└── components/           # Reusable Flutter widgets
```

## Core Screens

### 1. `LoginScreen` (`lib/screens/login_screen.dart`)

- Provides a simple authentication form for the driver.
- Saves the session token locally via `shared_preferences`.

### 2. `TrackingScreen` (`lib/screens/tracking_screen.dart`)

- **Visuals:** Shows a map (Google Maps) centered on the device's current location.
- **Controls:** Features a "Start/Stop Tracking" toggle.
- **Logic:** Once tracking is "Active", it invokes the `LocationService` to begin listening to continuous GPS updates.

## Core Services

### `LocationService`

- Uses packages like `geolocator` or `location` to fetch High-Accuracy GPS data.
- **Stream:** Listens to position streams.
- Upon receiving a new coordinate (latitude, longitude, speed, heading), it formats the payload and passes it to the `SocketService`.

### `SocketService`

- Connects to the Node.js backend using `socket_io_client`.
- On connection, authenticates the socket session.
- Exposes an `emitLocationUpdate(Map<String, dynamic> data)` method which transmits `locationUpdate` events immediately to the server.

## Background Execution Strategy

To ensure tracking continues when minimizing the app, it utilizes a background task executor (such as `flutter_background_service`).

- **Android:** Uses a Foreground Service with a persistent notification ("Shuttle Tracker is running").
- **iOS:** Uses background location entitlements.

## Data Flow

1. Driver Submits Login -> Server returns Token + Bus ID.
2. Driver hits "Start Tracking".
3. `LocationService` requests OS permissions.
4. OS returns `Position` data.
5. Flutter formats data: `{ busId: "...", latitude: 23.X, longitude: 77.Y, speed: 45, heading: 90 }`
6. `SocketService` emits `locationUpdate` -> Node.js Backend.
