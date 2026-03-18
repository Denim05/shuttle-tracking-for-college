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
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/sistec_chalo_new';

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
// Driver model removed per user request

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
            default:
                console.timeEnd('LoginRequest');
                return res.status(400).json({ error: 'Invalid role' });
        }

        user = await Model.findOne({ username });
        if (!user) {
            console.timeEnd('LoginRequest');
            return res.status(400).json({ error: 'User not found' });
        }

        // Validate Password
        const isMatch = await argon2.verify(user.password, password);
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

        res.json({ token, user: { id: user.id, username: user.username, role } });
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

const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const User = require('./models/User');

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
    // Note: In real app, check req.user.role here
    const { message, type } = req.body;
    io.emit('notification', { message, type: type || 'info', timestamp: new Date() });
    res.json({ success: true });
});

// Manager: Get Students (Mock search for now)
app.get('/api/manager/students', async (req, res) => {
    // Note: In real app, check req.user.role here
    const students = [
        { id: 's1', name: 'Alok Singh', roll: '0101CS21', route: 'Gandhinagar' },
        { id: 's2', name: 'Priya Verma', roll: '0101EC22', route: 'Minal' },
        { id: 's3', name: 'Rohan Jha', roll: '0101IT21', route: 'Gandhinagar' },
    ];
    res.json(students);
});

// Socket.io for Real-time Bus Updates
/**
 * Initializes Socket.io connection listeners.
 * Handles continuous location updates from buses and broadcasts them.
 */
io.on('connection', (socket) => {
    console.log('🔌 New Client Connected:', socket.id);

    socket.on('locationUpdate', async (data) => {
        // data: { busId, latitude, longitude, speed, heading }
        try {
            if (data.busId) {
                const bus = await Bus.findById(data.busId);
                if (bus && bus.routeId) {
                    const route = await Route.findById(bus.routeId);

                    if (route && route.stops) {
                        const etas = route.stops.map(stop => {
                            return {
                                stopName: stop.name,
                                minutes: calculateETA(data.latitude, data.longitude, stop.lat, stop.lng, data.speed)
                            };
                        });

                        await Bus.findByIdAndUpdate(data.busId, {
                            currentLat: data.latitude,
                            currentLng: data.longitude,
                            speed: data.speed,
                            heading: data.heading,
                            etas: etas,
                            lastUpdated: new Date()
                        });

                        // Enrich broadcast data with ETAs
                        data.etas = etas;
                    } else {
                        await Bus.findByIdAndUpdate(data.busId, {
                            currentLat: data.latitude,
                            currentLng: data.longitude,
                            speed: data.speed,
                            heading: data.heading,
                            lastUpdated: new Date()
                        });
                    }
                } else {
                    await Bus.findByIdAndUpdate(data.busId, {
                        currentLat: data.latitude,
                        currentLng: data.longitude,
                        speed: data.speed,
                        heading: data.heading,
                        lastUpdated: new Date()
                    });
                }
            }
            socket.broadcast.emit('busLocationUpdate', data);
        } catch (err) {
            console.error('Socket update error:', err);
        }
    });

    socket.on('disconnect', () => {
        console.log('Clients disconnected');
    });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Server running on port ${PORT}`);
    console.log(`📡 Socket.io ready for connections`);
});
