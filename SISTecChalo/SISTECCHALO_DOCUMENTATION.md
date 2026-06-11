# SISTecChalo - Flutter App Documentation

Welcome to the comprehensive technical documentation for the **SISTecChalo Flutter Client** (`SISTecChalo`). 
This app delivers a "Next-Gen Pulse" aesthetic for campus transit, built with modern Dart 3.4+ and Flutter.

---

## 1. ðŸš€ Project Overview
SISTecChalo provides a futuristic shuttle tracking experience with fully native map integrations, robust local storage, and real-time Socket.IO telemetry.

**Key Features:**
- **Next-Gen Pulse UI**: High-contrast dark theme with Neon Purple, Cyan, and Pink accents.
- **Real-time Tracking**: Bus tracking with interpolated map markers and live speed/occupancy telemetry.
- **Four-role Architecture**: Custom "Command Center" dashboards for User, Driver, Manager, and Admin.
- **Guest Mode**: Failsafe public access for live tracking without authentication.
- **Precision Maps**: Custom `flutter_map` implementation with dark-themed tiles and route polylines.

---

## 2. ðŸ› ï¸ Tech Stack & Packages (`pubspec.yaml`)

- **State Management:** `provider` (v6.1+) using `ChangeNotifier` and `MultiProvider`.
- **Typography:** `Plus Jakarta Sans` (mandatory global font).
- **Maps:** `flutter_map` (v6.1+) - High-performance OpenStreetMap implementation.
- **Networking:** 
  - `http` for RESTful API communication.
  - `socket_io_client` (v2.0+) for real-time bi-directional telemetry.
- **Location:** `geolocator` and `permission_handler` for GPS precision.
- **Storage:** `flutter_secure_storage` for encrypted JWT and profile caching.
- **UI/UX:** `google_fonts`, `shimmer`, `flutter_animate` (Micro-animations).

---

## 3. ðŸ“‚ Architecture & Folder Structure

The application follows a Service-Oriented Provider Architecture.

```text
lib/
 â”œâ”€â”€ components/       # Pulse-themed UI components (BusMap, NeonButtons, TelemetryCards)
 â”œâ”€â”€ constants/        # Global constants (Colors, API endpoints, Typography)
 â”œâ”€â”€ models/           # Strongly typed data models (User, Bus, Route)
 â”œâ”€â”€ screens/          # Role-specific Dashboards (Core Architect, Command Center, Captain Command)
 â”œâ”€â”€ services/         # State singletons (AuthService, ApiService, SocketService)
 â””â”€â”€ main.dart         # Entry point and Global Provider tree
```

### Flow of Control (`main.dart`)
1. **Initialize**: Sets up system UI overlays (transparent status bars).
2. **Provider Injection**: Wraps the app in `MultiProvider` for `AuthService` and `SocketService`.
3. **Theme Engine**: Applies the "Next-Gen Pulse" `ThemeData` globally.
4. **Auth Guard**: `AuthWrapper` determines the landing page based on `tryAutoLogin()` and user roles.

---

## 4. ðŸ§  Core Services

### 1. `AuthService`
Manages the security lifecycle.
- **`login()`**: Authenticates against `SISTecChalo-backend`, stores JWT, and triggers role-based routing.
- **`tryAutoLogin()`**: Restores sessions from secure storage.
- **`loginAsGuest()`**: Provides limited "Pulse" access for public tracking.

### 2. `SocketService`
The heartbeat of the "Pulse" system.
- Maintains persistent WebSocket connections.
- Listens for `busLocationUpdate` to refresh the global tracking state.
- Enables "Captain Command" (Driver) to broadcast real-time coordinates.

---

## 5. ðŸ—ºï¸ Next-Gen Mapping

Leverages `flutter_map` with `CartoDB.DarkMatter` tiles to match the dark aesthetic.
- **Dynamic Markers**: Custom-rendered vectors representing buses with real-time rotation (heading).
- **Route Polylines**: Neon-colored paths representing active shuttle routes.
- **Telemetry Layer**: Overlaying live speed and ETA data directly on the map interface.

---

## 6. ðŸ“± Visual Identity: "Next-Gen Pulse"

- **Primary**: Purple (`#6C63FF`)
- **Accent**: Cyan (`#00F0FF`)
- **Alert**: Pink/Red (`#FF2E63`)
- **Background**: Dark Violet (`#0D0B14`) / Black (`#050505`)
- **Typography**: `Plus Jakarta Sans` for all headings and body text.

---

## 7. ðŸšŒ System Lifecycle

1. **Pulse Sync**: App connects to backend and initializes Socket.IO.
2. **Telemetry Stream**: Buses broadcast location; the backend computes ETA/Status.
3. **Dashboard Update**: Reactively updates UI cards and map markers without full-page reloads.
4. **Security**: JWT-based authorization ensures role-specific command access (e.g., Managers managing fleet).

---

## Summary
SISTecChalo represents a complete overhaul of the "SISTec Chalo" legacy, migrating to a high-performance, futuristic Flutter architecture. It prioritizes real-time precision, sleek "Pulse" visuals, and a modular service layer for campus-wide transit orchestration.

