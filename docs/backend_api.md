# Backend API Documentation

The backend is built with Node.js, Express, and MongoDB. It handles RESTful API endpoints and real-time Socket.io connections for location tracking.

## Base URL

`/api`

## Authentication

### Login

- **Endpoint:** `POST /api/auth/login`
- **Description:** Authenticates a user based on their role and returns a JWT token.
- **Request Body:**

  ```json
  {
    "username": "admin123",
    "password": "mypassword",
    "role": "admin" // "admin", "manager", or "user"
  }
  ```

- **Response (200 OK):**

  ```json
  {
    "token": "eyJhbGciOi...",
    "user": {
      "id": "60d0fe4f5311236168a109ca",
      "username": "admin123",
      "role": "admin"
    }
  }
  ```

---

## Guest Routes (Public)

### Get All Routes

- **Endpoint:** `GET /api/guest/routes`
- **Description:** Fetches all available bus routes. No authentication required.

### Get All Buses

- **Endpoint:** `GET /api/guest/buses`
- **Description:** Fetches all current buses and their details. No authentication required.

---

## Route Management

### Get Routes (Authenticated)

- **Endpoint:** `GET /api/routes`
- **Headers:** `Authorization: Bearer <token>`
- **Description:** Fetches all routes. Requires valid JWT token.

---

## User Management

### Create Admin

- **Endpoint:** `POST /api/admins`
- **Description:** Creates a new Admin user.
- **Request Body:** `{ "username": "...", "password": "..." }`

### Create Manager

- **Endpoint:** `POST /api/managers`
- **Headers:** `Authorization: Bearer <token>`
- **Description:** Creates a new Manager.

### Get Managers

- **Endpoint:** `GET /api/managers`
- **Description:** Fetches all registered managers.

### Create User

- **Endpoint:** `POST /api/users`
- **Description:** Creates a standard user account.

### Get Users

- **Endpoint:** `GET /api/users`
- **Description:** Retrieves all standard users.

### Update User Rights

- **Endpoint:** `PUT /api/users/:id/rights`
- **Description:** Updates the access rights or status of a user.
- **Request Body:** `{ "accessRights": [...], "status": "active" }`

---

## Student Management

### Get Students

- **Endpoint:** `GET /api/students`
- **Description:** Retrieve all registered students.

### Add Student

- **Endpoint:** `POST /api/students`
- **Request Body:** Student details (name, roll, route, etc.)

### Delete Student

- **Endpoint:** `DELETE /api/students/:id`
- **Description:** Deletes a specific student record.

---

## Bus Management

### Get Buses

- **Endpoint:** `GET /api/buses`
- **Description:** Retrieve all buses.

### Update Bus Status

- **Endpoint:** `PUT /api/buses/:id/status`
- **Description:** Update bus assignment and operational status.
- **Request Body:**

  ```json
  {
    "status": "Active",
    "routeId": "...",
    "routeName": "...",
    "routeColor": "..."
  }
  ```

---

## Manager Actions

### Send Notification

- **Endpoint:** `POST /api/manager/notifications`
- **Description:** Broadcasts a notification to all connected clients via Socket.io.
- **Request Body:**

  ```json
  {
    "message": "Bus delayed by 10 mins",
    "type": "warning"
  }
  ```

### Get Students (Manager View)

- **Endpoint:** `GET /api/manager/students`
- **Description:** Mock endpoint returning assigned students.

---

## Real-Time Events (Socket.io)

### Connection

Clients connect to the base URL using standard Socket.io client.

### Events Emitted by Backend

- `busLocationUpdate`: Broadcasts whenever a bus sends a location update.
  - Payload: `{ busId, latitude, longitude, speed, heading, etas: [] }`
- `busUpdate`: Emitted when a bus's metadata (route, status) is updated via the REST API.
- `notification`: Emitted when a manager sends a broadcast notification.
  - Payload: `{ message, type, timestamp }`

### Events Listened by Backend

- `locationUpdate`: Sent by the tracking flutter app (or simulated source) to update the current bus location. Calculates new ETAs based on speed and predefined stops.
  - Payload: `{ busId, latitude, longitude, speed, heading }`
