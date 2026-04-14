require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

// Helper for ETA calculation (Mock implementation)
/**
 * Calculates Estimated Time of Arrival (ETA) between two coordinates in minutes.
 * Uses the Haversine formula to determine distance.
 *
 * @param {number} busLat - Current latitude of the bus.
 * @param {number} busLng - Current longitude of the bus.
 * @param {number} stopLat - Latitude of the destination stop.
 * @param {number} stopLng - Longitude of the destination stop.
 * @param {number} [speed=30] - Speed of the bus in km/h. Defaults to 30.
 * @returns {number} The estimated arrival time in minutes.
 */
const calculateETA = (busLat, busLng, stopLat, stopLng, speed) => {
    if (!speed || speed < 5) speed = 30; // Default 30km/h
    const R = 6371; // Radius of earth in km
    const dLat = (stopLat - busLat) * Math.PI / 180;
    const dLon = (stopLng - busLng) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(busLat * Math.PI / 180) * Math.cos(stopLat * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = R * c; // in km
    const timeInHours = distance / speed;
    return Math.round(timeInHours * 60); // Return in minutes
};
const authMiddleware = require('./middleware/authMiddleware');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*", // Allow expo app to connect
        methods: ["GET", "POST"]
    }
});

app.use(helmet());
app.use(cors());
app.use(express.json());

// Rate Limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: { error: 'Too many requests, please try again later.' }
});
app.use('/api/', limiter);

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/sistec_chalo';

mongoose.connect(MONGODB_URI)
    .then(() => console.log('✅ MongoDB Connected!'))
    .catch(err => {
        console.error('❌ MongoDB Connection Error:', err);
        console.log('Ensure you have MongoDB installed and running locally on port 27017');
    });

// Simple Route
app.get('/', (req, res) => {
    res.send('Sistec Chalo Backend is Running 🚀');
});

// API Routes
const Route = require('./models/Route');
const Bus = require('./models/Bus');
const Student = require('./models/Student');
const Driver = require('./models/Driver');
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const User = require('./models/User');
const Alert = require('./models/Alert');
const Notification = require('./models/Notification');

// Helper to broadcast stats
const broadcastStats = async () => {
    try {
        const busCount = await Bus.countDocuments();
        const routeCount = await Route.countDocuments();
        const userCount = await User.countDocuments();
        io.emit('statsUpdate', { busCount, routeCount, userCount });
    } catch (err) {
        console.error('Stats broadcast error:', err);
    }
};

// --- AUTH ROUTES ---
/**
 * @api {post} /api/auth/login User Login
 * @apiName LoginUser
 * @apiGroup Authentication
 * @apiDescription Authenticates user and returns a JWT token.
 * 
 * @param {Object} req.body - The request body containing login credentials.
 * @param {string} req.body.username - User's username.
 * @param {string} req.body.password - User's password.
 * @param {string} req.body.role - User's role ('admin', 'manager', 'user').
 * @returns {Object} JSON response with JWT token and user details.
 */
app.post('/api/auth/login', async (req, res) => {
    console.time('LoginRequest');
    const { username, password, role } = req.body;

    try {
        let user;
        let Model;

        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'user': Model = User; break;
            case 'driver': Model = Driver; break;
            default:
                console.timeEnd('LoginRequest');
                return res.status(400).json({ error: 'Invalid role' });
        }

        user = await Model.findOne({ username });
        console.log(`🔍 [Auth] Attempting login for ${username} with role ${role}`);
        
        if (!user) {
            console.log(`❌ [Auth] User ${username} not found in ${role} collection`);
            console.timeEnd('LoginRequest');
            return res.status(400).json({ error: 'User not found' });
        }

        // Validate Password
        const isMatch = await argon2.verify(user.password, password);
        console.log(`🔐 [Auth] Password match result for ${username}: ${isMatch}`);
        
        if (!isMatch) {
            console.timeEnd('LoginRequest');
            return res.status(400).json({ error: 'Invalid credentials' });
        }

        // Generate Token
        const token = jwt.sign(
            { user: { id: user.id, role: role } },
            process.env.JWT_SECRET || 'sistec_secret_key_123',
            { expiresIn: '1d' }
        );

        const userResponse = {
            id: user.id,
            username: user.username,
            role,
            email: user.email,
            status: user.status
        };

        if (role === 'user') {
            userResponse.routeId = user.routeId;
            userResponse.pickupPoint = user.pickupPoint;
            userResponse.userId = user.userId; // If we add this to the model later
        }

        res.json({ token, user: userResponse });
        console.timeEnd('LoginRequest');

    } catch (err) {
        console.error(err);
        console.timeEnd('LoginRequest');
        res.status(500).json({ error: 'Server error' });
    }
});

// Public routes for Guests (No auth required)
app.get('/api/guest/routes', async (req, res) => {
    try {
        const routes = await Route.find();
        res.json(routes);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch routes' });
    }
});

app.get('/api/guest/buses', async (req, res) => {
    try {
        const buses = await Bus.find();
        res.json(buses);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch buses' });
    }
});
app.get('/api/routes', authMiddleware, async (req, res) => {
    try {
        const routes = await Route.find();
        res.json(routes);
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch routes' });
    }
});

// --- User Management Routes (For Admin/Manager) ---

// --- ADMIN Management ---
app.post('/api/admins', async (req, res) => {
    try {
        const { username, password } = req.body;

        let existing = await Admin.findOne({ username });
        if (existing) return res.status(400).json({ error: 'Admin already exists' });

        const hashedPassword = await argon2.hash(password);
        const newAdmin = new Admin({ ...req.body, password: hashedPassword });

        await newAdmin.save();
        res.status(201).json(newAdmin);
    } catch (_) {
        res.status(500).json({ error: 'Failed to create admin' });
    }
});

// --- MANAGER Management ---
app.post('/api/managers', authMiddleware, async (req, res) => {
    try {
        const { username, password } = req.body;

        let existing = await Manager.findOne({ username });
        if (existing) return res.status(400).json({ error: 'Manager already exists' });

        const hashedPassword = await argon2.hash(password);
        const newManager = new Manager({ ...req.body, password: hashedPassword });

        await newManager.save();
        res.status(201).json(newManager);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create manager' });
    }
});

app.get('/api/managers', async (req, res) => {
    try {
        const managers = await Manager.find();
        res.json(managers);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch managers' });
    }
});

// --- USER Management (Standard Users) ---
app.post('/api/users', async (req, res) => {
    try {
        const { username, password } = req.body;

        let existing = await User.findOne({ username });
        if (existing) return res.status(400).json({ error: 'User already exists' });

        const hashedPassword = await argon2.hash(password);
        const newUser = new User({ ...req.body, password: hashedPassword });

        await newUser.save();
        broadcastStats(); // Emit live update
        res.status(201).json(newUser);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create user' });
    }
});

app.get('/api/users', async (req, res) => {
    try {
        const users = await User.find();
        res.json(users);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});

// Grant Rights/Update User
app.put('/api/users/:id/rights', async (req, res) => {
    try {
        const { accessRights, status } = req.body;
        const updateData = {};
        if (accessRights) updateData.accessRights = accessRights;
        if (status) updateData.status = status;

        const updatedUser = await User.findByIdAndUpdate(req.params.id, updateData, { new: true });
        res.json(updatedUser);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update user rights' });
    }
});

// --- EXISTING DRIVER ROUTES (Enhanced for Auth) ---
// (Keeping existing GET /api/drivers)

// Student Management (Existing)
app.get('/api/students', async (req, res) => {
    try {
        const students = await Student.find();
        res.json(students);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch students' });
    }
});

app.post('/api/students', async (req, res) => {
    try {
        const newStudent = new Student(req.body);
        await newStudent.save();
        res.status(201).json(newStudent);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to add student' });
    }
});

app.delete('/api/students/:id', async (req, res) => {
    try {
        await Student.findByIdAndDelete(req.params.id);
        res.json({ message: 'Student deleted' });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to delete student' });
    }
});

// Driver Management removed/simplified (Managers handle buses now)
// app.get('/api/drivers', ...) removed

// Driver Management removed/simplified (Managers handle buses now)
// app.get('/api/drivers', ...) removed

// Bus Status Management
app.get('/api/buses', async (req, res) => {
    try {
        const buses = await Bus.find();
        res.json(buses);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch buses' });
    }
});

app.put('/api/buses/:id/status', async (req, res) => {
    try {
        const { status, routeId, routeName, routeColor } = req.body;
        const updateData = { status };
        if (routeId) updateData.routeId = routeId;
        if (routeName) updateData.routeName = routeName;
        if (routeColor) updateData.routeColor = routeColor;
        updateData.lastUpdated = new Date();

        const updatedBus = await Bus.findByIdAndUpdate(
            req.params.id,
            updateData,
            { new: true }
        );
        io.emit('busUpdate', updatedBus); // Broadcast change
        res.json(updatedBus);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update bus status' });
    }
});

// Manager: Broadcast Notification
app.post('/api/manager/notifications', async (req, res) => {
    try {
        const { message, type } = req.body;
        
        // Save to Database
        const newNotification = new Notification({
            message,
            type: type || 'info'
        });
        await newNotification.save();

        io.emit('notification', newNotification);
        res.json({ success: true, notification: newNotification });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to broadcast notification' });
    }
});

// Notifications: Get History
app.get('/api/notifications', async (req, res) => {
    try {
        const notifications = await Notification.find().sort({ createdAt: -1 }).limit(50);
        res.json(notifications);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch notifications' });
    }
});

// Alerts: Get History
app.get('/api/alerts', async (req, res) => {
    try {
        const alerts = await Alert.find().sort({ timestamp: -1 }).limit(50);
        res.json(alerts);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch alerts' });
    }
});

// Manager: Get Users
app.get('/api/manager/users', authMiddleware, async (req, res) => {
    try {
        const users = await User.find().select('-password');
        console.log(`📦 Sending ${users.length} users to Manager`);
        res.json(users);
    } catch (err) {
        console.error('❌ Error fetching manager users:', err);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});

// Manager: Update User Status/Route
app.put('/api/manager/users/:id', authMiddleware, async (req, res) => {
    try {
        const updatedUser = await User.findByIdAndUpdate(req.params.id, req.body, { new: true });
        res.json(updatedUser);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update user' });
    }
});

// Manager: Get Drivers
app.get('/api/manager/drivers', authMiddleware, async (req, res) => {
    try {
        const drivers = await Driver.find();
        console.log(`📦 Sending ${drivers.length} drivers to Manager`);
        res.json(drivers);
    } catch (err) {
        console.error('❌ Error fetching manager drivers:', err);
        res.status(500).json({ error: 'Failed to fetch drivers' });
    }
});

// Manager: Update Driver
app.put('/api/manager/drivers/:id', async (req, res) => {
    try {
        const updatedDriver = await Driver.findByIdAndUpdate(req.params.id, req.body, { new: true });
        res.json(updatedDriver);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update driver' });
    }
});

// Socket.io for Real-time Bus Updates
const busGeofenceState = {}; // { busId: { stopName: lastNotifiedTimestamp } }
const GEOFENCE_RADIUS_KM = 0.5; // 500 meters
const COOLDOWN_MS = 30 * 60 * 1000; // 30 minutes

/**
 * Initializes Socket.io connection listeners.
 * Handles continuous location updates from buses and broadcasts them.
 */
io.on('connection', (socket) => {
    console.log('🔌 New Client Connected:', socket.id);

    // Send initial stats to the newly connected client
    broadcastStats();

    socket.on('triggerSOS', async (data) => {
        console.log('🚨 \x1b[31mACTIVE SOS EMERGENCY RECEIVED\x1b[0m:', data);
        
        try {
            const newAlert = new Alert({
                userId: data.userId || 'unknown',
                name: data.name || 'Unknown',
                role: data.role || 'user',
                latitude: data.latitude || 0,
                longitude: data.longitude || 0,
                routeId: data.routeId,
                routeName: data.routeName,
                busId: data.busId,
                timestamp: data.timestamp ? new Date(data.timestamp) : new Date()
            });

            await newAlert.save();
            socket.broadcast.emit('sosAlert', newAlert);
        } catch (err) {
            console.error('Failed to save SOS alert:', err);
            // Fallback: emit without saving if DB fails
            socket.broadcast.emit('sosAlert', data);
        }
    });

    socket.on('locationUpdate', async (data) => {
        // data: { busId, latitude, longitude, speed, heading }
        let updatedBus = null;
        try {
            if (data.busId) {
                const bus = await Bus.findById(data.busId);
                if (bus && bus.routeId) {
                    const route = await Route.findById(bus.routeId);

                    if (route && route.stops) {
                        const etas = [];
                        for (const stop of route.stops) {
                            // Calculate exact distance inline for geofencing
                            const R = 6371; // Radius of earth in km
                            const dLat = (stop.lat - data.latitude) * Math.PI / 180;
                            const dLon = (stop.lng - data.longitude) * Math.PI / 180;
                            const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                                Math.cos(data.latitude * Math.PI / 180) * Math.cos(stop.lat * Math.PI / 180) *
                                Math.sin(dLon / 2) * Math.sin(dLon / 2);
                            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                            const distanceKm = R * c; // in km

                            const minutes = calculateETA(data.latitude, data.longitude, stop.lat, stop.lng, data.speed);

                            // Geofence check
                            if (distanceKm <= GEOFENCE_RADIUS_KM) {
                                if (!busGeofenceState[data.busId]) {
                                    busGeofenceState[data.busId] = {};
                                }
                                
                                const now = Date.now();
                                const lastNotified = busGeofenceState[data.busId][stop.name] || 0;
                                
                                if (now - lastNotified > COOLDOWN_MS) {
                                    busGeofenceState[data.busId][stop.name] = now;
                                    const alertMessage = `Bus ${data.busId} (${route.name}) is approaching ${stop.name}. Estimated arrival: ${minutes} mins.`;

                                    try {
                                        const newNotif = new Notification({
                                            message: alertMessage,
                                            type: 'arrival_alert',
                                            createdBy: `Bus ${data.busId}`
                                        });
                                        await newNotif.save();
                                    } catch (err) {
                                        console.error('Error saving geofence notification:', err);
                                    }
                                    
                                    io.emit('busApproachingStop', {
                                        busId: data.busId,
                                        routeId: route._id.toString(),
                                        routeName: route.name,
                                        stopName: stop.name,
                                        minutes: minutes,
                                        distanceKm: distanceKm,
                                        message: alertMessage
                                    });
                                    console.log(`📍 Geofence Alert: ${alertMessage} (${distanceKm.toFixed(2)} km)`);
                                }
                            }

                            etas.push({
                                stopName: stop.name,
                                minutes: minutes
                            });
                        }

                        updatedBus = await Bus.findByIdAndUpdate(data.busId, {
                            currentLat: data.latitude,
                            currentLng: data.longitude,
                            speed: data.speed,
                            heading: data.heading,
                            etas: etas,
                            lastUpdated: new Date()
                        }, { new: true });
                    } else {
                        updatedBus = await Bus.findByIdAndUpdate(data.busId, {
                            currentLat: data.latitude,
                            currentLng: data.longitude,
                            speed: data.speed,
                            heading: data.heading,
                            lastUpdated: new Date()
                        }, { new: true });
                    }
                } else {
                    updatedBus = await Bus.findByIdAndUpdate(data.busId, {
                        currentLat: data.latitude,
                        currentLng: data.longitude,
                        speed: data.speed,
                        heading: data.heading,
                        lastUpdated: new Date()
                    }, { new: true });
                }
            }
            if (updatedBus) {
                socket.broadcast.emit('busLocationUpdate', updatedBus);
            } else {
                socket.broadcast.emit('busLocationUpdate', data);
            }
        } catch (err) {
            console.error('Socket update error:', err);
        }
    });

    socket.on('disconnect', () => {
        console.log('Clients disconnected');
    });
});

// --- SEED DATABASE ROUTE ---
app.post('/api/manager/seed', async (req, res) => {
    try {
        // 1. Clear existing data (Optional, but good for fresh seed)
        await Route.deleteMany({});
        await Bus.deleteMany({});

        // 2. Create Routes
        const route1 = new Route({
            name: "Route 1 - MP Nagar",
            color: "#1A4CFF",
            stops: [
                { name: "SISTec Main Gate", lat: 23.2333, lng: 77.4333 },
                { name: "Chetak Bridge", lat: 23.2350, lng: 77.4380 },
                { name: "MP Nagar Zone 1", lat: 23.2310, lng: 77.4280 }
            ]
        });
        const route2 = new Route({
            name: "Route 2 - Indrapuri",
            color: "#38ef7d",
            stops: [
                { name: "SISTec Main Gate", lat: 23.2333, lng: 77.4333 },
                { name: "Indrapuri C-Sector", lat: 23.2510, lng: 77.4680 },
                { name: "Piplani Petrol Pump", lat: 23.2550, lng: 77.4780 }
            ]
        });
        await route1.save();
        await route2.save();

        // 3. Create Buses
        const bus1 = new Bus({
            busNumber: "MP-04-AB-1234",
            routeId: route1._id,
            routeName: route1.name,
            routeColor: route1.color,
            currentLat: 23.2333,
            currentLng: 77.4333,
            status: "On-time",
            occupancy: "Low",
            lastUpdated: new Date()
        });
        const bus2 = new Bus({
            busNumber: "MP-04-XY-5678",
            routeId: route2._id,
            routeName: route2.name,
            routeColor: route2.color,
            currentLat: 23.2333,
            currentLng: 77.4333,
            status: "Delayed",
            occupancy: "Medium",
            lastUpdated: new Date()
        });
        await bus1.save();
        await bus2.save();

        res.json({ message: "Database seeded successfully with 2 routes and 2 buses!" });
        broadcastStats();
    } catch (err) {
        console.error("Seed Error:", err);
        res.status(500).json({ error: "Failed to seed database" });
    }
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Server running on port ${PORT}`);
    console.log(`📡 Socket.io ready for connections`);
});
