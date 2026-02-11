require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const authMiddleware = require('./middleware/authMiddleware');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*", // Allow expo app to connect
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/sistec_chalo';

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

// --- AUTH ROUTES ---
app.post('/api/auth/login', async (req, res) => {
    console.time('LoginRequest');
    const { username, password, role } = req.body;

    try {
        let user;
        let Model;

        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
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

app.get('/api/routes', async (req, res) => {
  try {
    const routes = await Route.find();
    res.json(routes);
  } catch (err) {
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
        const { username, password, email } = req.body;
        
        let existing = await Admin.findOne({ username });
        if(existing) return res.status(400).json({ error: 'Admin already exists' });

        const hashedPassword = await argon2.hash(password);
        const newAdmin = new Admin({ ...req.body, password: hashedPassword });
        
        await newAdmin.save();
        res.status(201).json(newAdmin);
    } catch (err) {
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
    } catch (err) {
        res.status(500).json({ error: 'Failed to create manager' });
    }
});

app.get('/api/managers', async (req, res) => {
    try {
        const managers = await Manager.find();
        res.json(managers);
    } catch (err) {
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
    } catch (err) {
        res.status(500).json({ error: 'Failed to create user' });
    }
});

app.get('/api/users', async (req, res) => {
    try {
        const users = await User.find();
        res.json(users);
    } catch (err) {
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
    } catch (err) {
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
    } catch (err) {
        res.status(500).json({ error: 'Failed to fetch students' });
    }
});

app.post('/api/students', async (req, res) => {
    try {
        const newStudent = new Student(req.body);
        await newStudent.save();
        res.status(201).json(newStudent);
    } catch (err) {
        res.status(500).json({ error: 'Failed to add student' });
    }
});

app.delete('/api/students/:id', async (req, res) => {
    try {
        await Student.findByIdAndDelete(req.params.id);
        res.json({ message: 'Student deleted' });
    } catch (err) {
        res.status(500).json({ error: 'Failed to delete student' });
    }
});

// Driver Management
app.get('/api/drivers', async (req, res) => {
    try {
        const drivers = await Driver.find();
        res.json(drivers);
    } catch (err) {
        res.status(500).json({ error: 'Failed to fetch drivers' });
    }
});

app.post('/api/drivers', async (req, res) => {
    try {
        const { username, password, driverId } = req.body;

        let existing = await Driver.findOne({ $or: [{ username }, { driverId }] });
        if (existing) return res.status(400).json({ error: 'Driver already exists' });

        const hashedPassword = await argon2.hash(password);
        const newDriver = new Driver({ ...req.body, password: hashedPassword });

        await newDriver.save();
        res.status(201).json(newDriver);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to add driver' });
    }
});

app.delete('/api/drivers/:id', async (req, res) => {
    try {
        await Driver.findByIdAndDelete(req.params.id);
        res.json({ message: 'Driver deleted' });
    } catch (err) {
        res.status(500).json({ error: 'Failed to delete driver' });
    }
});

// Bus Status Management
app.get('/api/buses', async (req, res) => {
    try {
        const buses = await Bus.find();
        res.json(buses);
    } catch (err) {
        res.status(500).json({ error: 'Failed to fetch buses' });
    }
});

app.put('/api/buses/:id/status', async (req, res) => {
    try {
        const { status } = req.body;
        const updatedBus = await Bus.findByIdAndUpdate(
            req.params.id, 
            { status }, 
            { new: true }
        );
        res.json(updatedBus);
    } catch (err) {
        res.status(500).json({ error: 'Failed to update bus status' });
    }
});

// Socket.io for Real-time Bus Updates
io.on('connection', (socket) => {
  console.log('🔌 New Client Connected:', socket.id);

  socket.on('driverLocationUpdate', (data) => {
      // Broadcast driver location to all users
      socket.broadcast.emit('busLocationUpdate', data);
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
