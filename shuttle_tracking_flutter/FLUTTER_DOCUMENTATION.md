# SmartCampus Shuttle - Flutter App Documentation

Welcome to the comprehensive technical documentation for the **Sistec Chalo Flutter Client** (`shuttle_tracking_flutter`). 
This app acts as the native Android/iOS alternative to the React Native/Expo client, built with modern Dart 3.4+ and Flutter.

---

## 1. 🚀 Project Overview
The Flutter version replicates and enhances the shuttle tracking experience with fully native map integrations, robust local storage, and real-time Socket.IO telemetry.

**Key Features:**
- Real-time bus tracking with interpolated map markers.
- Four-role dashboard routing (User, Driver, Manager, Admin).
- Guest Mode for unauthenticated live tracking.
- Heavy use of Glassmorphism UI (Backdrop filters and gradients).
- Location tracking for drivers and distance calculations for users.

---

## 2. 🛠️ Tech Stack & Packages (`pubspec.yaml`)

- **State Management:** `provider` (v6.1+) using `ChangeNotifier` and `MultiProvider`.
- **Maps:** `flutter_map` (v6.1+) - An implementation of Leaflet in Flutter.
- **Networking:** 
  - `http` (HTTP client for REST calls).
  - `socket_io_client` (v2.0+) - WebSocket connections.
- **Location:** `geolocator` and `permission_handler` for GPS polling.
- **Storage:** `flutter_secure_storage` for token and profile caching.
- **UI/UX:** `google_fonts`, `shimmer` (Loading states), `flutter_animate` (Micro-animations).

---

## 3. 📂 Architecture & Folder Structure

The application follows a Service-Oriented Provider Architecture.

```text
lib/
 ├── components/       # Reusable UI (BusMap, LinearTrackingView)
 ├── constants/        # Centralized configurations (API endpoints, colors)
 ├── models/           # Strongly typed data definitions (User, Bus, Route)
 ├── screens/          # Page-level UI separated by Role
 ├── services/         # State singletons (AuthService, ApiService, SocketService)
 └── main.dart         # Entry point and Provider initialization
```

### Flow of Control (`main.dart`)
When the app launches, `WidgetsFlutterBinding.ensureInitialized()` is called. `MultiProvider` injects `AuthService` and `SocketService` strictly at the root. 
The app then renders an `AuthWrapper` which utilizes a `FutureBuilder` to await `tryAutoLogin()`.
- If `isAuthenticated == true`, it switches on `auth.currentUser?.role` to load the appropriate Dashboard (`AdminDashboard`, `ManagerDashboard`, `UserDashboard`).
- Otherwise, it loads `LoginScreen`.

---

## 4. 🧠 State Management & Services

### 1. `AuthService` (ChangeNotifier)
Manages the authentication loop and JSON Web Tokens.
- **`login(username, password, role)`**: Dispatches an HTTP POST to `/api/auth/login`. Unpacks the JWT and user profile, persisting them via `FlutterSecureStorage`.
- **`tryAutoLogin()`**: Silently executed on startup to immediately drop the user into their Dashboard if a token is valid on disk.
- **`loginAsGuest()`**: Failsafe/Public method. Configures a volatile user object without a token to let public users view the map.

### 2. `ApiService`
A generic HTTP wrapper.
- Intercepts requests to automatically attach the `Authorization: Bearer <token>` header dynamically fetched from `FlutterSecureStorage`.
- Catches socket timeout/server errors and maps them to generic Exception throws caught by UI layers.

### 3. `SocketService`
Maintains the real-time WebSocket lifecycle.
- Initiated upon entering a dashboard using `initSocket()`.
- Uses `_socket.on('busLocationUpdate')` to emit callbacks triggered whenever a bus moves.
- Allows Drivers to push data via `emitLocationUpdate()`.

---

## 5. 🗺️ Maps & Geolocation details

The mapping system replaces Google Maps APIs with `flutter_map` leveraging open-source `CartoCDN` tile layers (Dark & Standard Voyager formats).

### Inside `components/bus_map.dart`
- **Location Permissions**: Handled gracefully via `permission_handler`. Dialogs pop up dynamically requesting "When In Use" constraints.
- **TileLayer**: Fetches raster grid images for the base map.
- **PolylineLayer**: Renders static route boundaries using `LatLong2` coordinates fetched from the DB.
- **MarkerLayer**:
  - Displays dynamic `<Marker>` widgets for the User (Blue pulsating dot) and Buses (Green directional vectors).
  - Listens directly to the parent Widget's state. When `UserDashboard` receives a `busLocationUpdate` via Socket, the state is mutating and passing updated arguments into `BusMap`.
  - Markers employ `Transform.rotate` matching the bus's True North `heading`.

---

## 6. 📱 UI Rendering Details (Glassmorphism)

The Flutter iteration leans heavily on intensive `BackdropFilter` widgets with `ImageFilter.blur(sigmaX: 10, sigmaY: 10)` superimposed over dark gradient Canvas backgrounds.

### Animations
Micro-interactions are handled explicitly using `flutter_animate` extensions (`.animate().fadeIn().slideY()`). Lists, Bottom Sheets, and Markers spring into existence instead of snapping.

### Shimmers
While waiting for the REST API to resolve Routes and Fleets, a skeleton UI is presented using the `shimmer` package masking empty containers.

---

## 7. 🚌 The Tracking Lifecycle

1. **Dashboard Initialization**: `UserDashboard` executes `_fetchData()` hitting `/api/routes` and `/api/buses`. It populates `_buses` map logic locally.
2. **Socket Handshake**: `_initSocket()` is run immediately binding `busLocationUpdate`.
3. **Data Overwrite**: When the server broadcasts `busLocationUpdate`, the callback executes `setState()` passing the new `Bus.fromJson(data)` into `_buses[id]`.
4. **Re-render Pipeline**: Flutter natively redraws constraints, and the `flutter_map` shifts the `MarkerLayer` position seamlessly.

---

## Summary
The Flutter implementation of Sistec Chalo applies robust architecture patterns (`Provider`) and lightweight Open-Source map modules (`flutter_map`) to deliver an aggressive, high-refresh real-time shuttle tracker natively on Android and iOS while maximizing performance overheads through hardware-rendered UI blurs.
