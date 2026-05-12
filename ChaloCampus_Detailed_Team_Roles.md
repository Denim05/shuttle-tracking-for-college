# 🛠️ ChaloCampus: Technical Roles & Responsibilities Matrix
## 📋 Detailed 7-Member Team Execution Guide

This document provides a granular breakdown of the project modules (Frontend, Backend, Connectivity, and Mapping) assigned to each of the 7 team members.

---

## 1. 👑 Project Manager & Full-Stack Team Leader
**Primary Module: Architectural Oversight & Integration**

*   **Frontend Contribution:** Approves the UI/UX design tokens and ensures the Flutter widget tree is optimized for scalability.
*   **Backend Contribution:** Designs the initial API schema and oversees the Node.js project structure.
*   **Connectivity Contribution:** Finalizes the Socket.IO event naming conventions to ensure consistency across the stack.
*   **Mapping Contribution:** Verifies the mathematical logic for Haversine distance calculations and ETA estimation.
*   **Role Focus:** Ensures all 7 members are synchronized and that the "Next-Gen Pulse" vision is maintained in every line of code.

---

## 2. 📱 Lead Frontend Developer (Flutter Architect)
**Primary Module: Core App Logic & State Management**

*   **Frontend Tasks:** 
    *   Implements the `lib/` directory structure.
    *   Manages Global State using `Provider` or `ChangeNotifier`.
    *   Builds the Auth Guard and Role-Based navigation flow.
*   **Connectivity Integration:** Connects the Frontend services to the Backend REST API using the `http` package.
*   **Mapping UI:** Handles the integration of the `flutter_map` widget into the dashboard screens.

---

## 3. ⚙️ Lead Backend Developer (Server Architect)
**Primary Module: REST API & Business Logic**

*   **Backend Tasks:**
    *   Builds the Express.js server and handles environment configurations (`.env`).
    *   Develops REST endpoints for user authentication, bus management, and route CRUD operations.
    *   Implements the `authMiddleware` to protect sensitive routes.
*   **Connectivity Integration:** Works with the Connectivity Specialist to attach the Socket.IO server to the HTTP instance.
*   **Data Logic:** Implements the server-side logic for filtering active buses based on route IDs.

---

## 4. 🗄️ Database & Security Engineer
**Primary Module: Data Integrity & Cybersecurity**

*   **Backend Tasks:**
    *   Designs MongoDB schemas using Mongoose (Users, Buses, Routes, Notifications).
    *   Optimizes database queries and indexing for real-time performance.
    *   Implements `Argon2` password hashing and `JWT` token generation.
*   **Connectivity Security:** Ensures WebSocket connections are authenticated via JWT to prevent unauthorized telemetry broadcasts.
*   **Data Reliability:** Manages the `seed_real_routes.js` scripts to ensure the system starts with accurate geographical data.

---

## 5. 🎨 UI/UX Designer & Animation Specialist
**Primary Module: Visual Design & Interactive Elements**

*   **Frontend Tasks:**
    *   Defines the "Next-Gen Pulse" color palette (Neon Purple, Cyan, Dark Violet).
    *   Designs custom icons and glassmorphic UI components (`NeonButtons`, `TelemetryCards`).
    *   Implements micro-animations using `flutter_animate` for a premium feel.
*   **Mapping Aesthetics:** Customizes the `CartoDB.DarkMatter` map tiles and selects neon colors for route polylines.
*   **User Flow:** Maps out the journey from Login -> Dashboard -> Live Tracking to ensure zero friction.

---

## 6. 🔌 Connectivity & Real-Time Specialist
**Primary Module: Socket.IO & Telemetry Stream**

*   **Connectivity Tasks:**
    *   Develops the `SocketService` in Flutter for bi-directional communication.
    *   Implements the `locationUpdate` emit logic in the Driver Dashboard.
    *   Handles "rooms" and "namespaces" in Socket.IO to manage traffic by route or role.
*   **Backend Integration:** Manages the real-time event listeners on the server to relay coordinates between Drivers and Users.
*   **Mapping Sync:** Ensures that incoming coordinate packets are correctly parsed and passed to the Mapping module.

---

## 7. 🗺️ Mapping & GIS Engineer
**Primary Module: Geospatial Visualization & Precision**

*   **Mapping Tasks:**
    *   Implements the `flutter_map` implementation with high-performance tile rendering.
    *   Develops the **Marker Smoothing** logic (interpolation) to prevent bus icons from jumping.
    *   Renders complex `Polyline` geometries representing shuttle routes.
*   **Backend Contribution:** Works with the Database Engineer to store GeoJSON-formatted coordinates for routes and stops.
*   **Connectivity Integration:** Listens for `busLocationUpdate` events to move markers dynamically based on incoming telemetry.

---

## 📊 Summary of Technical Coverage

| Feature | Primary Responsible Member | Secondary Support |
| :--- | :--- | :--- |
| **Frontend UI** | UI/UX Designer | Flutter Architect |
| **Backend API** | Backend Architect | Database Engineer |
| **Database** | Database Engineer | Team Leader |
| **Real-time Sockets** | Connectivity Specialist | Backend Architect |
| **Map Rendering** | Mapping Engineer | Flutter Architect |
| **Security/Auth** | Database Engineer | Team Leader |
| **Animations** | UI/UX Designer | Mapping Engineer |

---
**ChaloCampus: One Team, One Pulse.**
