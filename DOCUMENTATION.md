# SmartCampus Shuttle - Complete System Documentation

Welcome to the definitive documentation for the **SmartCampus Shuttle** project (also known as Sistec Chalo). This document dives deep into every aspect of the system, covering both the frontend logic and backend architecture in detail.

## 1. 🚀 Project Overview
SmartCampus Shuttle is a comprehensive transit tracking application for a campus environment. It eliminates the opacity of university transit by providing a fully transparent, real-time map of buses, routes, and ETAs.

**Four User Roles:**
1. **User (Commuter):** Can view buses live, select routes, and see stops and ETAs.
2. **Driver:** Provides live tracking data via device GPS. Selects a bus line and broadcasts their location.
3. **Manager:** Oversees fleet management. Needs a high-level view of active buses, routes, and notifications.
4. **Admin:** System administrator, manages credentials for managers.

---

## 2. 🛠️ Tech Stack & Configuration

### Frontend (User App)
- **Framework:** React Native v0.81 with Expo SDK 54.
- **Routing:** Expo Router (File-based routing using the `app/` directory).
- **State Management:** Zustand (Stores Auth Tokens, Mapped Entities, Bus states, User roles).
- **Components/UI:** 
  - Glassmorphic interface styled with `StyleSheet`.
  - Maps powered by `react-native-maps`.
  - Icons using `@expo/vector-icons` (Ionicons).
- **Network:** `socket.io-client` for real-time WebSocket connection.

### Backend (Server API)
- **Framework:** Node.js with Express.js.
- **Database:** MongoDB via Mongoose.
- **Real-Time Layer:** `Socket.io` attached to the HTTP server for broadcasting coordinate updates.
- **Security:** Helmet for headers, Express-Rate-Limit for brute force protection, Argon2 for password hashing, and JWT for session tokens.

---

## 3. 📂 Core Architectural Design

The system is a Hybrid Architecture that employs REST for CRUD & Authentication commands and WebSockets for real-time telemetry.

### Sequence of Operations (The Tracking Flow)
1. **Driver App:** The driver logs in and presses "Start Driving".
2. **GPS Polling:** The app uses `expo-location` (implied via component) to track location continuously.
3. **Emitting:** The `useAppStore` fires a `socket.emit('locationUpdate', data)` over WebSockets to the server.
4. **Server Relay:** The Express/Socket.io backend catches `'locationUpdate'`. It calculates ETAs for upcoming stops using a Haversine formula and saves the exact `currentLat`, `currentLng`, `speed`, and `heading` to MongoDB.
5. **Broadcasting:** The server immediately runs `socket.broadcast.emit('busLocationUpdate', data)`.
6. **Commuter App:** Users listening to `'busLocationUpdate'` have their Zustand store modified. The `<BusMap />` component re-renders `<Marker.Animated>` to smoothly glide the bus icon along the map.

---

## 4. 🗄️ Database Schemas (MongoDB)

All schemas reside in `backend/models/`.

### 1. `Bus` 
Tracks the physical vehicle's state.
- `routeId` (String): ID of the route.
- `currentLat`, `currentLng` (Number): GPS coordinates.
- `heading`, `speed` (Number): Direction angle and speed.
- `status` (String): 'On-time', 'Delayed', or 'Offline'.
- `occupancy` (String): 'Low', 'Medium', 'High'.
- `etas` (Array of sub-documents): Includes `{ stopName: String, minutes: Number }` calculated by the server.

### 2. `Route`
Static definition of a transit line.
- `name` (String): Name of the route (e.g., "Gandhinagar").
- `color` (String): Hex color for drawing the Map Polyline.
- `coordinates` (Array): Array of `{latitude, longitude}` dictating the path.
- `stops` (Array): Points along the route `{name, lat, lng}`.

### 3. User Models
- **`Admin` & `Manager` & `User`**: Standardized schemas containing `username` and `password` (hashed via Argon2).
- **`Student`**: Represents commuter profiles including `rollNumber`, `pickupPoint`.

---

## 5. 🌐 API Endpoints Reference

Base API URL is dynamically calculated via `Constants.expoConfig.hostUri` (running on Port 5000). 
All protected routes use `authMiddleware` verifying the JWT token.

### Authentication
- `POST /api/auth/login`
  - **Body:** `{ username, password, role }`
  - **Logic:** Matches role to Admin/Manager/User collection. Uses Argon2 verify. Sign JWT token.

### Data Aggregation
- `GET /api/buses` & `/api/guest/buses` - Fetches current fleet status.
- `GET /api/routes` & `/api/guest/routes` - Fetches static route lines.
- `PUT /api/buses/:id/status` - Updates bus status ('On-time', 'Delayed') and broadcasts `busUpdate`.

### Management (Admin/Manager use)
- `POST /api/admins`, `POST /api/managers`, `POST /api/users` - Creates accounts (Argon2 hashes passwords).
- `GET /api/students`, `POST /api/students`, `DELETE /api/students/:id` - CRUD for student data.
- `PUT /api/users/:id/rights` - Modifies user access privileges.
- `POST /api/manager/notifications` - Emits global WebSocket notifications manually.

---

## 6. 📱 Frontend Implementation Details

### Configuration (`app.json`, `package.json`)
- Uses `expo-router` for routing structure.
- Main entry relies on `app/index.tsx` serving as the Auth Gatewall.

### 1. The Gatewall (`app/index.tsx`)
This screen manages role-based access control.
- **UI:** Rendered with a Deep Space Dark Theme gradient. Contains glassmorphic (blurred transparent) cards.
- **Logic:** Takes credentials -> calls `useAppStore().login()`. Depending on the returned role, router paths switch:
  - `user` -> `/user` (Or `/(tabs)`)
  - `driver` -> `/driver`
  - `manager` -> `/manager`
  - `admin` -> `/admin/dashboard`

### 2. The Global Store (`hooks/useAppStore.ts`)
The `Zustand` store operates as the brain of the app, heavily minimizing component re-renders.
- **`login()`**: Makes REST HTTP Post to `/api/auth/login`. Saves `authToken` to `expo-secure-store`. Fallbacks to mock login on network failures.
- **`fetchInitialData()`**: Grabs `MOCK_ROUTES`, `MOCK_STOPS`, `MOCK_BUSES`. Initiates the Socket.io WebSocket connection to `API_URL`. Listeners update state directly.
- **Driver Logic**: `startDriving(busNumber)` isolates a driver bus entity. `updateDriverLocation` pushes coordinates directly to WebSockets.

### 3. The Map Rendering (`components/BusMap.tsx`)
- Maps are built natively for iOS/Android using `react-native-maps`.
- Static boundaries are rendered via `<Polyline>` connecting Route Data.
- Dynamic entities are rendered using `<Marker.Animated>`, binding to the Zustand Store. As `busLocationUpdate` WebSocket events overwrite store coordinates, React Native Reanimated natively interpolates the bus marker sliding from Point A to Point B.

---

## 7. 🎨 UI & Design System

The platform applies a uniform, high-fidelity **Modern Glassmorphism** design.

- **Color Palette & Theme**: Controlled via inline styling and `constants/theme.ts`.
  - **Backgrounds:** Deep space themes (`#0f2027`, `#203a43`, `#2c5364`).
  - **Accents:** Neon Green/Teal (`#38ef7d`, `#11998e`).
- **Input Fields:** Uses animated borders natively controlled via Reanimated `useSharedValue`.
- **Containers:** Heavily uses `rgba(255, 255, 255, 0.1)` on black backgrounds with Drop Shadows to simulate glass transparency.

---

## 8. 🚀 Setup & Deployment

### Environment
1. Setup a local MongoDB database (`mongodb://localhost:27017/sistec_chalo_new`) or provide a `MONGODB_URI` environment variable.
2. Expo requires `LAN_IP` configurations to appropriately test the app on a physical device.

### Commands
```bash
# Install Modules
npm install

# Start Backend (Terminal 1)
npm run server 

# Start Expo Builder (Terminal 2)
npx expo start --tunnel
```
_Note: Database can be seeded rapidly by running `npm run seed` which scripts `backend/seedAll.js`._

---

## Summary
SmartCampus Shuttle uses a highly sophisticated combination of REST for security boundaries and WebSockets for real-time efficiency. By completely decoupling the App state (Zustand) from the UI components, it allows massive scale without dropping frames during map animations.
