# 📡 ChaloCampus Connectivity & Data Flow Guide

This document provides a comprehensive technical overview of how the **ChaloCampus** ecosystem connects, synchronizes, and manages real-time transit telemetry across its Distributed Architecture.

---

## 1. Architectural Overview
ChaloCampus operates on a **Hybrid Communication Model** designed for high availability and low-latency tracking.

*   **Asynchronous REST (HTTP/S)**: Handles "Structural Data" (Login, User Profiles, Route Lists, History).
*   **Synchronous WebSockets (Socket.io)**: Handles "Live Telemetry" (GPS coordinates, SOS alerts, system-wide broadcasts).
*   **State Management (Provider)**: Acts as the internal glue, distributing network data to UI components.

---

## 2. Real-Time Telemetry (Socket.io)
The tracking engine relies on a persistent TCP connection between the Flutter clients and the Node.js backend.

### A. The Telemetry Loop
1.  **Driver Broadcast**: The Driver App captures GPS coordinates using the `Geolocator` package every **800ms**.
2.  **Socket Emission**: The app calls `socket.emit('locationUpdate', data)`.
3.  **Server Relay**: The Node.js server receives the packet and identifies the `routeId`. It immediately broadcasts this to all clients in that specific "Route Room."
4.  **Client Smoothing**: The User App receives the packet and uses a **Linear Interpolation Algorithm** in `BusMap` to glide the marker smoothly over 1 second.

### B. Core Socket Events
| Event Name | Direction | Payload Description |
| :--- | :--- | :--- |
| `locationUpdate` | Driver → Server → User | Lat/Lng, Heading, Speed, BusID |
| `busApproach` | Server → User | Triggered when a bus is within 500m of user stop |
| `systemAlert` | Manager → Server → All | High-priority text broadcast from management |
| `sosAlert` | User/Driver → Server → Manager | Emergency coordinates and user details |
| `busDelayed` | Server → User | Triggered if a bus falls behind its scheduled ETA |

---

## 3. Data Management (REST API)
The `ApiService` in Flutter acts as the centralized interface for all HTTP communication.

### A. Authentication Flow
1.  User submits credentials to `/api/auth/login`.
2.  Server validates against **MongoDB** and signs a **JWT (JSON Web Token)**.
3.  Flutter App stores this token in `FlutterSecureStorage`.
4.  **Middleware**: Every subsequent request attaches this token in the `Authorization` header.

### B. Fetching Strategy (Seed & Update)
To optimize performance, the app uses a "Seed" pattern:
*   **On Init**: App performs a single `GET /api/buses` to populate the initial fleet state.
*   **Ongoing**: The app never "re-fetches" the fleet. It only listens to Socket updates to "patch" the specific buses in the local `BusStore`.

---

## 4. Database Layer (MongoDB)
All persistent data is stored in **MongoDB Atlas** using the **Mongoose ODM**.

*   **Persistence**: Routes, Bus Stops, and Notification History are stored as Documents.
*   **Relationships**: `Buses` are linked to `Routes` via `routeId`, allowing for efficient filtering in the tracking engine.
*   **Telemetry Logging**: While live movement is transient (Socket), the server periodically saves "Trip Snapshots" to the DB for generating Admin Reports.

---

## 5. Connection Resilience & Failover
Tracking is mission-critical; the app includes several guards against connectivity loss:

1.  **Connection Monitor**: `SocketService` uses a `ValueNotifier<bool>` to alert the UI when the internet drops.
2.  **Auto-Reconnect**: Socket.io is configured with an exponential backoff strategy to reconnect as soon as signal returns.
3.  **Synchronizing Overlay**: Users are visually notified when data is stale via a "📡 SYNCHRONIZING" banner.
4.  **Heartbeat**: The Driver App sends a keep-alive pulse even when stationary to prevent the session from timing out.

---

## 6. Security Standards
*   **TLS/SSL**: All REST and Socket traffic is encrypted.
*   **Payload Scrubbing**: Driver identification is sanitized before broadcasting to users to protect privacy.
*   **Role-Based Access (RBAC)**: APIs are protected by middleware that checks if the JWT belongs to an `Admin`, `Manager`, `Driver`, or `Student`.

---

> [!IMPORTANT]
> **Production Note**: For optimal tracking, the Backend URL is centralized in `lib/services/api_service.dart`. Changing the `baseUrl` there will update all REST and Socket connections across the entire ecosystem.
