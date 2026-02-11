# SmartCampus Shuttle - Frontend Onboarding Guide

Welcome to the **SmartCampus Shuttle** project! This guide is designed to help new team members understand the frontend architecture, key workflows, and how to get started.

## 🚀 Project Overview

> **Our Vision: From Opacity to Transparency**

**SmartCampus Shuttle** is a real-time shuttle tracking application for a campus environment. It serves four distinct user roles:

1.  **User (Commuter)**: View live shuttle locations, routes, and schedules.
2.  **Driver**: Broadcasts real-time location while driving a route.
3.  **Manager**: Manages buses, drivers, and students.
4.  **Admin**: Global administrator for the system.

## 🛠️ Tech Stack

- **Framework**: [React Native](https://reactnative.dev/) (v0.81) with [Expo](https://expo.dev/) (SDK 54).
- **Routing**: [Expo Router](https://docs.expo.dev/router/introduction/) (v6).
- **State Management**: [Zustand](https://github.com/pmndrs/zustand) (Simple, scalable store).
- **Maps**: `react-native-maps` for tracking and route display.
- **Styling**: `StyleSheet` with a custom Design System (Glassmorphism, Dark Theme).
- **Backend**: Node.js/Express with MongoDB (located in `/backend`).
- **Real-time**: Socket.IO (implied for location updates).

## 📂 Project Structure

The project follows a monorepo-style structure where both frontend and backend code reside in the same repository.

### Key Directories

- **`app/`**: Contains the **Expo Router** file-based routing.
  - `index.tsx`: The entry point. Handles **Role Selection** (Login).
  - `(tabs)/`: Main tab navigation for Commuters (Users).
  - `driver/`: Screens specific to the Driver interface.
  - `admin/`: Dashboard for Admins.
  - `manager/`: Dashboard for Managers.
- **`components/`**: Reusable UI components (e.g., Maps, Cards, Buttons).
- **`constants/`**: Global configuration.
  - `theme.ts`: Defines the **Dark/Glassmorphic** color palette and shadows.
- **`hooks/`**: Custom React hooks.
  - `useAppStore.ts`: Global state (Auth, Data fetching) using **Zustand**.
- **`backend/`**: The Core API server.
  - `server.js`: Entry point for the backend.
  - `models/`: MongoDB Schemas (Users, Drivers, etc.).

## 🏗️ System Architecture

The project is built as a cohesive Real-time Tracking System.

### 1. High-Level Overview

- **Frontend (App)**: Built with **Expo** & **React Native**. Handles UI, Role logic, and Maps.
- **Backend (Server)**: **Node.js/Express** server that manages data and real-time sockets.
- **Database**: **MongoDB** stores persistent data (Users, Routes, Bus status).

### 2. Connectivity Flow

The app uses a **Hybrid Communication Model**:

- **REST API (`http`)**: Used for "Slow" operations.
  - _Login_: `/api/auth/login`
  - _Fetching Routes_: `/api/routes`
  - _Admin Actions_: Creating users/drivers.
- **WebSockets (`ws`)**: Used for "Fast" operations.
  - **Driver** emits `driverLocationUpdate` (Lat/Lng/Speed) every few seconds.
  - **Server** relays this as `busLocationUpdate`.
  - **User App** listens and animates the bus marker.

## 🗺️ Map & Location Implementation

The map logic is centralized in `components/BusMap.tsx` and powered by `react-native-maps`.

### Key Components

- **Route Paths**: Rendered using `<Polyline>` with coordinates from `constants/mockData.ts` (or DB).
- **Bus Markers**: Rendered using `<Marker.Animated>` for smooth movement.
  - _Logic_: The marker's coordinate prop is bound to `bus.currentLat/Lng` in the Zustand store. When the store updates (via Socket), the marker moves.
- **Stops**: Static `<Marker>` elements.

### For Drivers (`app/driver/index.tsx`)

- Uses `expo-location` to track GPS position.
- Updates the global store (`updateDriverLocation`).
- Store emits the new position to the server via Socket.IO.

## 🗄️ Database Models (MongoDB)

The backend uses **Mongoose** schemas located in `backend/models`.

### 1. **Users & Roles**

- **User (Commuter)**: Standard app users. Fields: `username`, `password`, `email`.
- **Driver**: Shuttle drivers. Fields: `driverId`, `status`, `assignedBusId`.
- **Manager**: Fleet managers. Fields: `employeeId`, `department`.
- **Admin**: System administrators.

### 2. **Transport Data**

- **Bus**: Represents a vehicle. Fields: `routeId`, `currentLat`, `currentLng`, `speed`.
- **Route**: Static path. Fields: `coordinates` (Lat/Lng array), `stops`.
- **Student**: Transport users. Fields: `pickupPoint`.

## 🔑 Key Workflows

### 1. Authentication & Role Selection

- **Entry**: `app/index.tsx`
- **Flow**: Login -> Select Role -> Navigate to specific Dashboard.

### 2. Live Tracking

- **User View**: `(tabs)/index.tsx`. Fetches active buses and listens for socket updates to move icons.

### 3. Driver Broadcasting

- **Driver View**: `app/driver/index.tsx`.
- **Action**: Driver selects a bus number -> Clicks "Initiate Broadcasting".
- **Result**: App starts background location tracking and emits events to server.

## 🎨 Design System

The app features a **modern, detailed, glassmorphism design**.

- **Theme**: Dark mode by default (`#0f2027` background).
- **Primary Color**: Neon Green/Teal (`#38ef7d`).
- **Components**: Use transparency and blurs (`rgba(255,255,255,0.1)`) for card backgrounds found in `constants/theme.ts`.

## 💻 How to Run

### Prerequisites

- Node.js installed.
- Expo Go app on your phone (or an Emulator).
- MongoDB instance (local or cloud).

### Steps

1.  **Install Dependencies**:
    ```bash
    npm install
    ```
2.  **Start Backend**:
    ```bash
    npm run server
    ```
    _(Runs `node backend/server.js`)_
3.  **Seed Database** (Optional):
    ```bash
    npm run seed
    ```
    _(Resets DB with Users, Routes, Buses, and Students)_
4.  **Start Frontend**:
    ```bash
    npx expo start --tunnel
    ```
    _(Scan the QR code with Expo Go)_

## ⚠️ Common Gotchas for New Members

- **Network Errors**: Ensure your phone handles the `tunnel` URL correctly. If backend calls fail, check if the `API_URL` in `constants` or `useAppStore` matches your server address.
- **Expo Router**: We use file-based routing.

## 🛠️ Code Trace & Implementation Sources

This section details exactly **where** each feature is implemented in the codebase.

### 1. Authentication System

- **UI (Frontend)**: `app/index.tsx` (LoginScreen)
  - _Role Selection_: Controlled by `setRole` state.
  - _Action_: Calls `useAppStore.login()`.
- **Logic (Frontend)**: `hooks/useAppStore.ts`
  - _Function_: `login(username, password, role)`
  - _API Call_: POST to `/api/auth/login`.
  - _Token Storage_: Uses `expo-secure-store`.
- **API (Backend)**: `backend/server.js` (`/api/auth/login`)
  - _Validation_: Checks user against DB using `argon2` to verify password.
  - _Response_: Returns JWT token.

### 2. Map Rendering

- **Component**: `components/BusMap.tsx`
  - _Library_: `react-native-maps`.
  - _State_: Consumes `buses`, `routes`, `stops` from `useAppStore`.
- **Routes (Polylines)**: `constants/mockData.ts` (Initially) -> Fetched from DB.
- **Bus Markers**: Custom `BusMarkerView` component inside `BusMap.tsx`.
  - _Animation_: Uses `Marker.Animated` for smooth updates when `bus.currentLat` changes.

### 3. Real-time Tracking (The "Magic")

- **Sender (Driver)**: `app/driver/index.tsx`
  - _Trigger_: `Location.watchPositionAsync` inside `startDriving` logic.
  - _Flow_: GPS Update -> `updateDriverLocation` (Store) -> `socket.emit('driverLocationUpdate')`.
- **Relay (Server)**: `backend/server.js`
  - _Listener_: `socket.on('driverLocationUpdate')`
  - _Action_: Broadcasts via `socket.broadcast.emit('busLocationUpdate')`.
- **Receiver (User)**: `hooks/useAppStore.ts`
  - _Listener_: `socket.on('busLocationUpdate')` inside `fetchInitialData`.
  - _Action_: Updates `state.buses` array, causing `BusMap.tsx` to re-render the marker position.
