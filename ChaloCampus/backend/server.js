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
// Force 'chalocampus' database in the URI if it's missing or set to 'test'
const rawUri = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus';
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/chalocampus$1');

console.log(`📡 [DB] Connecting to Cluster... (Target Database: chalocampus)`);
console.log(`📡 [DB] URI (Sanitized): ${MONGODB_URI.replace(/\/\/.*@/, '//****:****@')}`);

mongoose.connect(MONGODB_URI, { dbName: 'chalocampus' })
    .then(async () => {
        const dbName = mongoose.connection.name;
        process.stdout.write(`\n\x1b[32m✅ [DB] SUCCESSFULLY CONNECTED!\x1b[0m\n`);
        process.stdout.write(`\x1b[32m✅ [DB] ACTIVE DATABASE: ${dbName}\x1b[0m\n`);
        console.log(`✅ MongoDB Connected! Database: ${dbName}`);
        // Auto-seed real SGI routes on first boot if DB is empty
        await autoSeedRoutes();
    })
    .catch(err => {
        console.error('❌ MongoDB Connection Error:', err);
    });

// ─── Auto-Seed: Seeds all 13 real Sagar Group of Institutions routes ──────────
// Only runs if the Route collection is empty (safe to deploy multiple times)
async function autoSeedRoutes() {
    try {
        const Route = require('./models/Route');
        const Bus   = require('./models/Bus');
        const count = await Route.countDocuments();
        if (count > 0) {
            console.log(`🗂️  [SEED] ${count} routes already exist — skipping auto-seed.`);
            return;
        }
        console.log('🌱 [SEED] No routes found — seeding real SGI bus routes...');

        const SGI_ROUTES = [
            { busNo:'01', vehicle:'MP04 PA 3497', name:'Gandinagar Route',              color:'#6C63FF', driver:'Ghanshyam Nagar',       stops:['Gandinagar','Pul Bogda','Roshanpura','Manavseva Square','Bharat Mata Square','Ashoka Garden Chouraha','Nehru Nagar','Ratibad Campus'] },
            { busNo:'02', vehicle:'MP04 PA 3498', name:'Ashoka Garden Route (Bus 02)',   color:'#FF6B6B', driver:'Rahul Verma',            stops:['Bhopal Railway Station Platform-1','Pushpa Nagar','Sangam Tent House','80-feet Road','Ashoka Garden Pani ki Tanki','Prabhat Square','Bogda Pull','Jinsi Square','Roshanpura','Dipo','Ratibad Campus'] },
            { busNo:'03', vehicle:'MP04 PA 3501', name:'Karond Route',                   color:'#00F0FF', driver:'Praveen Pal',            stops:['DwarkaDham SPS Campus','Lambakheda','Karond','Bhanpur','Chhola Mandir','Best Prize','Kalyan Nagar','Shiv Mandir','Karond Sabzi Mandi','DIG Bungla','Nadra Bus Stand','Bharat Talkies','Jahangirabad','PHQ','Roshanpura','Bharat Mata Square','Ratibad Campus'] },
            { busNo:'04', vehicle:'MP04 PA 3504', name:'Kolar Road Route',               color:'#FFB347', driver:'Mukesh Shisodiya',       stops:['DPS School','Bairagarh','610 Kolar','Babadiya Kala','Aura Mall','Shivay Complex','10 No Shop','Arera Petrol Pump','Patrakar Colony','Pancheel Nagar','Vaishali Nagar','Nehru Nagar','Ratibad Campus'] },
            { busNo:'05', vehicle:'MP04 PA 3510', name:'Ashoka Garden Route (Bus 05)',   color:'#FF2E63', driver:'Babloo Meena',           stops:['Bhopal Railway Station Platform-1','Pushpa Nagar','Sangam Tent House','80-feet Road','Ashoka Garden Pani ki Tanki','Prabhat Square','Ratibad Campus'] },
            { busNo:'06', vehicle:'MP04 PA 3511', name:'Ashta Route',                    color:'#A8FF78', driver:'Raj Kumar',             stops:['Alipur','Old Bus Stand','Bhopal Naka','Bajaranga Colony','Colony Square','Banjari Mata','Kachanariya Jod','Kotri','Jat Khedi Jod','Amlaha','Bhadakhedi Jod','Goodwela','Jhagriya By-pass Sehore','Jhagriya','Ratibad Campus'] },
            { busNo:'07', vehicle:'MP04 PA 3512', name:'Kolar Route (Bus 07)',            color:'#F7971E', driver:'Virendra',              stops:['Gehnu Kheda','D-Mart','Lalita Nagar','Naya Pura','Mandakini','J.K. Hospital','Bansal Hospital','10 Number','Arera Petrol Pump','Kolar Tiraha','Panchsil Nagar','Vaishali Nagar','Nehru Nagar Chauraha','Nehru Nagar Naya Basera','Dipo 100 Daily Office','Ratibad Campus'] },
            { busNo:'09', vehicle:'MP04 PA 3513', name:'Mandideep Route',                color:'#2D5BFF', driver:'Satish Tomar',           stops:['Satlapur','Vardhman','Sarakiya','HEG/Mandideep','Samardha','Radhapuram','Pal Dhaba','Indus Town','11 Meal','Misrod','Ashima Mall','Danish Nagar','Bagsawaniya Thana','SP Office','Narayan Nagar','Ganesh Mandir','BJP Office','Nutan College','Durga Petrol Pump','Narmada Bhawan','Panchsil Nagar','Mata Mandir','PNT','Nehru Nagar New Basti','Nehru Nagar Square','Ratibad Campus'] },
            { busNo:'10', vehicle:'MP04 PA 3523', name:'Ashoka Garden Route (Bus 10)',   color:'#B721FF', driver:'Devendra Parmar',        stops:['Bhopal Railway Station Platform-1','Pushpa Nagar','Sangam Tent House','80-feet Road','Ashoka Garden Pani ki Tanki','Prabhat Square','Bogda Pull','Jinsi Square','Roshanpura','Dipo','Ratibad Campus'] },
            { busNo:'11', vehicle:'MP04 PA 3522', name:'SLV Route',                      color:'#21D4FD', driver:'Tulsi Das',             stops:['SOS','Transport Nagar','Patel Nagar','Anand Nagar Police Choki','Ratna Giri Chourha','Viranda Van Nagar','Tanatan Daba','Narela Chouraha','Ayodhya Nagar Square','Piplani Chouraha','Indrapuri','ITI','Bijli Gate','Subhash Nagar','Vallabh Bhavan','Ratibad Campus'] },
            { busNo:'12', vehicle:'MP04 PA 3521', name:'Neelbad Route',                  color:'#43E97B', driver:'Arjun Maran',           stops:['Neelbad','Ratibad Campus'] },
            { busNo:'13', vehicle:'MP04 PA 2288', name:'Sehore Route',                   color:'#FA709A', driver:'Mukesh Verma',          stops:['Bishan Khedi','Bhav Khedi','Khakar Kheda','Daite Colony','Kodiya','Ganesh Mandir Sehore','Moti Baba Mandir','Reliance Petrol Pump','Kohli Pura','Ganga Ashram','Bhopal Naka','Chanakya Puri','Chanakya Puri Vishal Mega Mart','Ratibad Campus'] },
            { busNo:'14', vehicle:'MP04 PA 2290', name:'Fanda Route',                    color:'#FEE140', driver:'Sunil Kumar Prajapati', stops:['Fanda','Pipaliya','Padli Jod','Kolas','Naya Gano','Sastakhedi','Tilakhedi','Deheriya','Mundla','Narela','Khokariya','Kodiya','Kajlash','Nanni','Ratibad Campus'] },
        ];

        for (const r of SGI_ROUTES) {
            const route = await Route.create({
                name: r.name,
                color: r.color,
                stops: r.stops.map(name => ({ name })),
                coordinates: [], // No fake polyline
            });
            await Bus.create({
                busNumber: r.vehicle,
                name: `Bus ${r.busNo} - ${r.name}`,
                routeId: route._id.toString(),
                routeName: r.name,
                routeColor: r.color,
                currentLat: 23.1270,
                currentLng: 77.3494,
                heading: 0, speed: 0,
                status: 'On-time',
                occupancy: 'Low',
                etas: [],
                lastUpdated: new Date(),
            });
            console.log(`  ✅ [SEED] Bus ${r.busNo}: ${r.name}`);
        }
        console.log(`🎉 [SEED] Done! Seeded ${SGI_ROUTES.length} routes & buses.`);
    } catch (err) {
        console.error('❌ [SEED] Auto-seed failed:', err.message);
    }
}

// Simple Route
app.get('/', (req, res) => {
    res.json({
        status: 'ChaloCampus Backend Online',
        database: mongoose.connection.name,
        version: '2.1.0-AUTOSEED',
        timestamp: new Date().toISOString()
    });
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
const Complaint = require('./models/Complaint');
const Schedule = require('./models/Schedule');

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
    console.log(`📡 [Auth] Login request: ${JSON.stringify(req.body)}`);
    const username = req.body.username?.trim();
    const password = req.body.password;
    const role = req.body.role?.trim();
    
    if (role) {
        console.log(`🔍 [Auth] Role: ${JSON.stringify(role)} (Length: ${role.length})`);
    }
    
    console.time('LoginRequest');

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
                return res.status(400).json({ 
                    error: `Invalid role: "${role}"`,
                    received_body: req.body 
                });
        }

        // Find user case-insensitively
        const query = { username: { $regex: new RegExp(`^${username}$`, 'i') } };
        user = await Model.findOne(query);
        console.log(`🔍 [Auth] Collection: ${Model.collection.name} | Query: ${JSON.stringify(query)} | Resolved: ${user?.username || 'none'}`);
        
        if (!user) {
            console.log(`❌ [Auth] User ${username} not found in ${Model.collection.name} collection`);
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
            process.env.JWT_SECRET || 'chalocampus_secret_key_777',
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
            userResponse.userId = user.userId;
            userResponse.proximityAlertsEnabled = user.proximityAlertsEnabled;
        }

        res.json({ token, user: userResponse });
        console.timeEnd('LoginRequest');

    } catch (err) {
        console.error('❌ Login Error:', err);
        console.timeEnd('LoginRequest');
        res.status(500).json({ error: 'Server error' });
    }
});

// Public routes for Guests (No auth required)
app.get('/api/guest/routes', async (req, res) => {
    try {
        const routes = await Route.find();
        res.json({ 
            version: '1.0.10-VERIFY',
            database: mongoose.connection.name,
            routes 
        });
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

app.get('/api/routes/:id', authMiddleware, async (req, res) => {
    try {
        const route = await Route.findById(req.params.id);
        if (!route) return res.status(404).json({ error: 'Route not found' });
        res.json(route);
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch route' });
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

        // Emit both notification (for history) and systemAlert (for live pop-ups)
        io.emit('notification', newNotification);
        io.emit('systemAlert', { message, type: type || 'info', timestamp: new Date().toISOString() });
        console.log(`📢 [Manager Broadcast] "${message}"`);
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

// User: Update Profile (Self)
app.put('/api/users/profile', authMiddleware, async (req, res) => {
    try {
        const { proximityAlertsEnabled } = req.body;
        const updatedUser = await User.findByIdAndUpdate(req.user.id, { proximityAlertsEnabled }, { new: true });
        res.json(updatedUser);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update profile' });
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

// Driver: Get Assigned Bus
app.get('/api/drivers/my-bus', authMiddleware, async (req, res) => {
    try {
        const bus = await Bus.findOne({ driverId: req.user.id });
        if (!bus) return res.status(404).json({ error: 'No bus assigned to this driver' });
        res.json(bus);
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch assigned bus' });
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
const GEOFENCE_RADIUS_KM = 1.0; // 1.0 km as per request
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
        // ── Immediate arrival log (always visible, even on DB error) ──
        const incomingBusId = (data.busId || data.id || data._id || '').toString();
        const incomingSpeed = (data.speed !== undefined ? Number(data.speed) : 0).toFixed(1);
        console.log(`\n📍 [LOCATION RECEIVED] BusID: ${incomingBusId} | Driver: ${data.driverId || 'N/A'} | Lat: ${data.latitude} | Lng: ${data.longitude} | Speed: ${incomingSpeed} KM/H`);

        try {
            let busId = incomingBusId;
            if (!busId) {
                console.log('⚠️ [LOCATION] No busId in payload — ignoring.');
                return;
            }

            let bus = await Bus.findById(busId);
            
            // FALLBACK Logic
            if (!bus && data.driverId) {
                bus = await Bus.findOne({ driverId: data.driverId });
                if (bus) {
                    busId = bus._id.toString();
                    console.log(`🔄 Fallback: Matched Driver ${data.driverId} to Bus ${busId}`);
                }
            }

            if (!bus) {
                // Last resort broadcast of raw data, ensuring IDs are strings
                const rawBroadcast = {
                    ...data,
                    id: busId,
                    latitude: data.latitude !== undefined ? data.latitude : (data.currentLat !== undefined ? data.currentLat : 0),
                    longitude: data.longitude !== undefined ? data.longitude : (data.currentLng !== undefined ? data.currentLng : 0),
                    status: data.status || 'On-time'
                };
                socket.broadcast.emit('busLocationUpdate', rawBroadcast);
                return;
            }

            const etas = [];
            const lat = data.latitude !== undefined ? data.latitude : (data.currentLat !== undefined ? data.currentLat : bus.currentLat);
            const lng = data.longitude !== undefined ? data.longitude : (data.currentLng !== undefined ? data.currentLng : bus.currentLng);
            const speed = data.speed !== undefined ? data.speed : bus.speed;

            // Perform Geofencing & ETA calculation if route is known
            if (bus.routeId) {
                const route = await Route.findById(bus.routeId);
                if (route && route.stops) {
                    for (const stop of route.stops) {
                        const R = 6371; // km
                        const dLat = (stop.lat - lat) * Math.PI / 180;
                        const dLon = (stop.lng - lng) * Math.PI / 180;
                        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                            Math.cos(lat * Math.PI / 180) * Math.cos(stop.lat * Math.PI / 180) *
                            Math.sin(dLon / 2) * Math.sin(dLon / 2);
                        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                        const distanceKm = R * c;

                        const minutes = calculateETA(lat, lng, stop.lat, stop.lng, speed);
                        
                        // Geofence Notification logic
                        if (distanceKm <= GEOFENCE_RADIUS_KM) {
                            if (!busGeofenceState[busId]) busGeofenceState[busId] = {};
                            const now = Date.now();
                            const lastNotified = busGeofenceState[busId][stop.name] || 0;
                            
                            if (now - lastNotified > COOLDOWN_MS) {
                                busGeofenceState[busId][stop.name] = now;
                                const alertMessage = `Pulse Alert: Your bus is arriving in ${minutes} minutes.`;
                                io.emit('busApproachingStop', {
                                    busId: busId,
                                    routeId: route._id.toString(),
                                    routeName: route.name,
                                    stopName: stop.name,
                                    minutes: minutes,
                                    message: alertMessage
                                });
                                console.log(`📍 Geofence Alert: ${alertMessage}`);
                            }
                        }
                        etas.push({ stopName: stop.name, minutes: minutes });
                    }
                }
            }

            // Update Database
            bus.currentLat = lat;
            bus.currentLng = lng;
            bus.speed = speed;
            bus.heading = data.heading !== undefined ? data.heading : bus.heading;
            bus.status = data.status || "On-time";
            bus.etas = etas;
            bus.lastUpdated = new Date();
            await bus.save();

            // Broadcast standardized data (CRITICAL: Normalize IDs to Strings)
            const busObj = bus.toObject();
            const broadcastData = {
                ...busObj,
                id: bus._id.toString(),
                _id: bus._id.toString(),
                routeId: bus.routeId ? bus.routeId.toString() : null,
                latitude: bus.currentLat,
                longitude: bus.currentLng,
                status: bus.status,
                timestamp: new Date().toISOString()
            };

            socket.broadcast.emit('busLocationUpdate', broadcastData);
            console.log(`✅ [TRACKING SAVED] Bus ${bus.busNumber || bus.routeName || busId} | ${bus.status} | Speed: ${speed.toFixed(1)} KM/H | Route: ${bus.routeName || 'None'}`);
        } catch (err) {
            console.error('❌ [TRACKING ERROR] locationUpdate handler failed:', err.message);
        }
    });

    // ── Manager Broadcast via socket ─────────────────────────────────────────
    socket.on('managerBroadcast', async (data) => {
        const message = data?.message || data?.toString() || '';
        if (!message) return;
        try {
            const newNotification = new Notification({ message, type: data.type || 'info' });
            await newNotification.save();
            socket.broadcast.emit('notification', newNotification);
            socket.broadcast.emit('systemAlert', { message, type: data.type || 'info', timestamp: new Date().toISOString() });
            console.log(`📢 [Socket Broadcast] "${message}"`);
        } catch (_e) {
            socket.broadcast.emit('systemAlert', { message, type: 'info', timestamp: new Date().toISOString() });
        }
    });

    // ── Latency ping/pong ────────────────────────────────────────────────────
    socket.on('ping', () => socket.emit('pong'));

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
            color: "#6C63FF",
            stops: [
                { name: "ChaloCampus Hub", lat: 23.2333, lng: 77.4333 },
                { name: "Chetak Bridge", lat: 23.2350, lng: 77.4380 },
                { name: "MP Nagar Zone 1", lat: 23.2310, lng: 77.4280 }
            ]
        });
        const route2 = new Route({
            name: "Route 2 - Indrapuri",
            color: "#00F0FF",
            stops: [
                { name: "ChaloCampus Hub", lat: 23.2333, lng: 77.4333 },
                { name: "Indrapuri C-Sector", lat: 23.2510, lng: 77.4680 },
                { name: "Piplani Petrol Pump", lat: 23.2550, lng: 77.4780 }
            ]
        });
        await route1.save();
        await route2.save();

        // 3. Create Buses
        const bus1 = new Bus({
            busNumber: "MP-04-AB-1234",
            name: "MP-04-AB-1234",
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
            name: "MP-04-XY-5678",
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

// ─── ETA TO MY STOP ─────────────────────────────────────────────────────────
// GET /api/eta?routeId=...&stopName=...
// Returns minutes until the active bus on a route reaches the named stop.
app.get('/api/eta', async (req, res) => {
    const { routeId, stopName } = req.query;
    if (!routeId || !stopName) {
        return res.status(400).json({ error: 'routeId and stopName are required' });
    }
    try {
        const buses = await Bus.find({ routeId }).sort({ lastUpdated: -1 }).limit(1);
        if (!buses.length) return res.json({ eta: null, message: 'No active bus on this route' });

        const bus = buses[0];
        const route = await Route.findById(routeId);
        if (!route) return res.status(404).json({ error: 'Route not found' });

        const stop = route.stops.find(
            s => s.name.toLowerCase().trim() === stopName.toLowerCase().trim()
        );
        if (!stop) return res.status(404).json({ error: 'Stop not found on route' });

        // Use stop coords if they exist; else return null ETA
        if (stop.lat == null || stop.lng == null) {
            return res.json({ eta: null, message: 'Stop coordinates not yet configured', stopName: stop.name });
        }

        const speed = bus.speed > 5 ? bus.speed : 30; // default 30 km/h
        const minutes = calculateETA(bus.currentLat, bus.currentLng, stop.lat, stop.lng, speed);

        res.json({
            eta: minutes,
            busId: bus._id.toString(),
            busNumber: bus.busNumber,
            routeName: route.name,
            stopName: stop.name,
            busLat: bus.currentLat,
            busLng: bus.currentLng,
            speed: bus.speed,
            lastUpdated: bus.lastUpdated,
        });
    } catch (err) {
        console.error('❌ ETA Error:', err);
        res.status(500).json({ error: 'Failed to calculate ETA' });
    }
});

// ─── SCHEDULE ────────────────────────────────────────────────────────────────
// GET  /api/schedule?routeId=...   → all schedule entries for a route
// POST /api/schedule               → create/upsert schedule entry (admin/manager)
app.get('/api/schedule', async (req, res) => {
    const { routeId } = req.query;
    try {
        const query = routeId ? { routeId } : {};
        const schedules = await Schedule.find(query).sort({ stopName: 1 });
        res.json(schedules);
    } catch (err) {
        res.status(500).json({ error: 'Failed to fetch schedules' });
    }
});

app.post('/api/schedule', authMiddleware, async (req, res) => {
    const { routeId, routeName, stopName, times, daysActive } = req.body;
    if (!routeId || !stopName || !times) {
        return res.status(400).json({ error: 'routeId, stopName and times are required' });
    }
    try {
        const entry = await Schedule.findOneAndUpdate(
            { routeId, stopName },
            { routeId, routeName, stopName, times, daysActive: daysActive || ['Mon','Tue','Wed','Thu','Fri','Sat'] },
            { upsert: true, new: true }
        );
        res.json(entry);
    } catch (err) {
        res.status(500).json({ error: 'Failed to save schedule' });
    }
});

// ─── COMPLAINTS ──────────────────────────────────────────────────────────────
// POST /api/complaints           → user submits a complaint
// GET  /api/complaints           → manager/admin lists complaints
// PUT  /api/complaints/:id       → manager updates status
app.post('/api/complaints', authMiddleware, async (req, res) => {
    const { routeId, routeName, driverName, busNumber, category, description } = req.body;
    if (!description) return res.status(400).json({ error: 'description is required' });
    try {
        const complaint = await Complaint.create({
            userId:      req.user.id,
            userName:    req.body.userName || 'User',
            routeId,
            routeName,
            driverName,
            busNumber,
            category:    category || 'other',
            description,
        });

        // Notify managers via socket
        io.emit('newComplaint', complaint);
        console.log(`🚨 [Complaint] New from user ${req.user.id}: "${description.substring(0,60)}..."`);

        res.status(201).json(complaint);
    } catch (err) {
        console.error('❌ Complaint Error:', err);
        res.status(500).json({ error: 'Failed to submit complaint' });
    }
});

app.get('/api/complaints', authMiddleware, async (req, res) => {
    try {
        const complaints = await Complaint.find().sort({ createdAt: -1 }).limit(100);
        res.json(complaints);
    } catch (err) {
        res.status(500).json({ error: 'Failed to fetch complaints' });
    }
});

app.put('/api/complaints/:id', authMiddleware, async (req, res) => {
    try {
        const updated = await Complaint.findByIdAndUpdate(
            req.params.id,
            { status: req.body.status },
            { new: true }
        );
        res.json(updated);
    } catch (err) {
        res.status(500).json({ error: 'Failed to update complaint' });
    }
});

// ─── DELAY ALERT SUBSCRIPTION ────────────────────────────────────────────────
// POST /api/subscribe-delay  { routeId, userId }
// Stores intent server-side; when manager marks a bus delayed or ETA drift > 5min,
// the server emits a 'busDelayed' event to all connected sockets (clients filter by routeId).
app.post('/api/subscribe-delay', authMiddleware, async (req, res) => {
    const { routeId } = req.body;
    if (!routeId) return res.status(400).json({ error: 'routeId is required' });
    // Simple in-memory subscription store (could be upgraded to Redis/DB)
    if (!global.delaySubscribers) global.delaySubscribers = {};
    if (!global.delaySubscribers[routeId]) global.delaySubscribers[routeId] = new Set();
    global.delaySubscribers[routeId].add(req.user.id);
    res.json({ success: true, message: `Subscribed to delay alerts for route ${routeId}` });
});

// Manager or server can POST to this to fire a delay alert to all subscribers
app.post('/api/notify-delay', authMiddleware, async (req, res) => {
    const { routeId, routeName, message, delayMinutes } = req.body;
    if (!routeId || !message) return res.status(400).json({ error: 'routeId and message required' });
    try {
        const payload = {
            routeId,
            routeName: routeName || routeId,
            message,
            delayMinutes: delayMinutes || 0,
            timestamp: new Date().toISOString(),
        };
        io.emit('busDelayed', payload);

        // Also persist as a notification so it appears in the alerts feed
        const notif = await Notification.create({ message, type: 'critical' });
        io.emit('notification', notif);
        io.emit('systemAlert', { message, type: 'critical', timestamp: payload.timestamp });

        console.log(`⚠️ [Delay Alert] Route ${routeName}: ${message}`);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: 'Failed to send delay alert' });
    }
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Server running on port ${PORT}`);
    console.log(`📡 Socket.io ready for connections`);
});

