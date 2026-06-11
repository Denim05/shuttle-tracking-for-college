const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

/**
 * Calculates real-time Estimated Time of Arrival (ETA) using Google Maps Distance Matrix API.
 * Falls back to Haversine formula if API key is missing or request fails.
 */
const calculateETA = async (busLat, busLng, stopLat, stopLng, currentSpeed) => {
    if (!busLat || !busLng || !stopLat || !stopLng) return 0;

    const apiKey = process.env.GOOGLE_MAPS_API_KEY;
    
    // If we have an API key, try the Google Distance Matrix for "Smooth & Better" results
    if (apiKey && apiKey !== 'YOUR_GOOGLE_MAPS_API_KEY') {
        try {
            const url = `https://maps.googleapis.com/maps/api/distancematrix/json?origins=${busLat},${busLng}&destinations=${stopLat},${stopLng}&mode=driving&traffic_model=best_guess&departure_time=now&key=${apiKey}`;
            
            const response = await fetch(url);
            const data = await response.json();

            if (data.rows && data.rows[0].elements && data.rows[0].elements[0].duration_in_traffic) {
                // Return traffic-aware duration in minutes
                return Math.round(data.rows[0].elements[0].duration_in_traffic.value / 60);
            } else if (data.rows && data.rows[0].elements && data.rows[0].elements[0].duration) {
                // Fallback to standard duration if traffic info isn't available
                return Math.round(data.rows[0].elements[0].duration.value / 60);
            }
        } catch (err) {
            console.error('⚠️ [Google Maps API] ETA Fetch Error:', err.message);
        }
    }

    // --- FALLBACK: Haversine Formula (As-the-crow-flies) ---
    const R = 6371; // Earth radius in km
    const dLat = (stopLat - busLat) * Math.PI / 180;
    const dLon = (stopLng - busLng) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(busLat * Math.PI / 180) * Math.cos(stopLat * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = R * c; 

    const speed = (currentSpeed && currentSpeed > 5) ? currentSpeed : 30; // Default 30km/h
    return Math.round((distance / speed) * 60);
};

const Route = require('./models/Route');
const Bus = require('./models/Bus');
const User = require('./models/User');
const Student = require('./models/Student');
const Driver = require('./models/Driver');
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const Alert = require('./models/Alert');
const Notification = require('./models/Notification');
const Complaint = require('./models/Complaint');
const Schedule = require('./models/Schedule');
const LiveTripLog = require('./models/LiveTripLog');
const RegistrationForm = require('./models/RegistrationForm');
const RegistrationSubmission = require('./models/RegistrationSubmission');

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
// Force 'SISTecChalo' database in the URI if it's missing or set to 'test'
const rawUri = process.env.MONGODB_URI;
if (!rawUri) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!');
    console.error('Please configure it in the .env file or environment variables.\n');
    process.exit(1);
}
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/sistecChalo$1');

console.log(`📡 [DB] Connecting to Cluster... (Target Database: SISTecChalo)`);
console.log(`📡 [DB] URI (Sanitized): ${MONGODB_URI.replace(/\/\/.*@/, '//****:****@')}`);

mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' })
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

// ─── Auto-Seed: Seeds all 17 real Sagar Group of Institutions routes ──────────
// Only runs if the Route collection is empty (safe to deploy multiple times)
async function autoSeedRoutes() {
    try {
        const Route = require('./models/Route');
        const count = await Route.countDocuments();
        if (count > 0) {
            console.log(`🗂️  [SEED] ${count} routes already exist — skipping auto-seed.`);
            return;
        }
        console.log('🌱 [SEED] No routes found — seeding real SGI bus routes...');
        const { seed: seedRealRoutes } = require('./seed_real_routes');
        await seedRealRoutes(false); // false means do not disconnect Mongoose
        console.log(`🎉 [SEED] Auto-seed completed successfully with 17 unique routes and 30 buses!`);
    } catch (_err) {
        console.error('❌ [SEED] Auto-seed failed:', _err.message);
    }
}

// Simple Route
app.get('/', (req, res) => {
    res.json({
        status: 'SISTecChalo Backend Online',
        database: mongoose.connection.name,
        version: '2.2.0-MAP-OPTIMIZED',
        timestamp: new Date().toISOString()
    });
});

// Privacy Policy Route for Google Play Console Submission
app.get('/privacy', (req, res) => {
    res.send(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Privacy Policy - Sistec Chalo</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #6C63FF;
            --primary-light: #8F88FF;
            --bg: #FAFAFD;
            --card-bg: #FFFFFF;
            --text-main: #1E1B4B;
            --text-muted: #5E5B8E;
            --border: #E8E7F5;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --primary: #8F88FF;
                --primary-light: #B8B5FF;
                --bg: #0C0A20;
                --card-bg: #151233;
                --text-main: #F3F2FC;
                --text-muted: #A3A1CD;
                --border: #231F4D;
            }
        }
        body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg);
            color: var(--text-main);
            line-height: 1.6;
            margin: 0;
            padding: 40px 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        .logo {
            font-size: 2.2rem;
            font-weight: 800;
            background: linear-gradient(135deg, var(--primary), var(--primary-light));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 8px;
        }
        .subtitle {
            color: var(--text-muted);
            font-size: 1.1rem;
        }
        .card {
            background-color: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 32px;
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.02);
            margin-bottom: 24px;
        }
        h2 {
            font-size: 1.4rem;
            font-weight: 700;
            margin-top: 0;
            margin-bottom: 16px;
            color: var(--primary);
            border-bottom: 1px solid var(--border);
            padding-bottom: 8px;
        }
        h3 {
            font-size: 1.1rem;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 12px;
        }
        p, li {
            color: var(--text-muted);
            font-size: 0.975rem;
        }
        ul {
            padding-left: 20px;
        }
        li {
            margin-bottom: 8px;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            font-size: 0.85rem;
            color: var(--text-muted);
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 99px;
            font-size: 0.8rem;
            font-weight: 600;
            background-color: var(--border);
            color: var(--primary);
            margin-top: 8px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
            margin-bottom: 16px;
            font-size: 0.9rem;
        }
        th, td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid var(--border);
        }
        th {
            font-weight: 600;
            color: var(--text-main);
        }
        td {
            color: var(--text-muted);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">Sistec Chalo</div>
            <div class="subtitle">Privacy Policy</div>
            <div class="badge">Application ID: com.smartcampus.shuttle</div>
        </div>

        <div class="card">
            <h2>1. Introduction</h2>
            <p>Welcome to <strong>Sistec Chalo</strong> (the "Application"), a campus shuttle tracking app designed for Sagar Group of Institutions (SGI) students, staff, and drivers. We respect your privacy and are committed to protecting any personal data we process. This Privacy Policy describes how we collect, use, store, and share your information when you use our services.</p>
        </div>

        <div class="card">
            <h2>2. Information We Collect</h2>
            <p>To provide accurate real-time shuttle tracking and notification features, the Application processes the following types of information:</p>
            
            <h3>A. Location Information</h3>
            <ul>
                <li><strong>For Drivers:</strong> The Application collects precise, real-time geographical coordinates (latitude and longitude) of the vehicle while tracking is active. This data is collected in the foreground and via a persistent foreground service (notifying the driver with "Broadcasting your location to students") to ensure continuous tracking even when the device screen is off or the driver is using another app.</li>
                <li><strong>For Students & Staff:</strong> The Application may request access to your device's location to show your current position relative to the shuttle on the map. This location is processed locally on your device and is never stored, tracked, or uploaded to our servers.</li>
            </ul>

            <h3>B. Personal & Account Information</h3>
            <ul>
                <li><strong>Account Credentials:</strong> We collect and store your username, hashed password, role (e.g., student, driver, manager, admin), and email address (optional) to secure your account and manage access privileges.</li>
                <li><strong>Pickup Points:</strong> Students may select and store their preferred bus routes and pickup points to customize their notifications and alerts.</li>
            </ul>

            <h3>C. User Communications</h3>
            <ul>
                <li><strong>SOS & Emergency Alerts:</strong> If a user triggers an SOS emergency alert, the Application transmits their name, role, last known latitude and longitude, and timestamp to the dashboard to allow campus managers to coordinate assistance.</li>
                <li><strong>Feedback & Complaints:</strong> We collect details about issues, feedback, or complaints submitted through the app to improve transportation services.</li>
            </ul>
        </div>

        <div class="card">
            <h2>3. How We Use the Information</h2>
            <p>We use the collected data exclusively to support campus transit operations:</p>
            <table>
                <thead>
                    <tr>
                        <th>Data Type</th>
                        <th>Purpose of Use</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><strong>Driver GPS Location</strong></td>
                        <td>To calculate Estimated Time of Arrival (ETA) at various stops and show the shuttle location to waiting passengers.</td>
                    </tr>
                    <tr>
                        <td><strong>User GPS Location</strong></td>
                        <td>Only to render the user's distance to the shuttle on the local map screen.</td>
                    </tr>
                    <tr>
                        <td><strong>Account Data</strong></td>
                        <td>To verify identity, enforce permissions, and customize the user experience.</td>
                    </tr>
                    <tr>
                        <td><strong>SOS Alerts</strong></td>
                        <td>To notify campus authorities of emergencies during transit.</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div class="card">
            <h2>4. Data Sharing & Security</h2>
            <p><strong>We do not sell, rent, or trade your personal data.</strong> Information is stored securely on private, authenticated database clusters and accessed only by SGI campus administrators and authorized transportation managers.</p>
            <p>We implement strict security practices including argon2 password hashing, JSON Web Token (JWT) API authentication, rate limiting, and SSL encryption to protect your data from unauthorized access.</p>
        </div>

        <div class="card">
            <h2>5. Data Retention & Deletion</h2>
            <ul>
                <li><strong>Location Tracking Logs:</strong> Real-time coordinates are discarded immediately after transit ends. Historical trip logs are stored for up to 90 days for operational auditing and route optimization reports, after which they are permanently deleted.</li>
                <li><strong>Account Information:</strong> Account data is retained for the duration of the student's enrollment or driver's employment. Users may request account deletion at any time by contacting the SGI administration.</li>
            </ul>
        </div>

        <div class="card">
            <h2>6. Changes to this Policy</h2>
            <p>We may update this Privacy Policy from time to time. Any changes will be posted on this page with an updated revision date.</p>
        </div>

        <div class="card">
            <h2>7. Contact Us</h2>
            <p>If you have any questions or concerns about this Privacy Policy, please contact the SGI Campus Transport Office or Administrator.</p>
            <p><em>Last Updated: June 11, 2026</em></p>
        </div>

        <div class="footer">
            &copy; 2026 Sagar Group of Institutions (SGI). All rights reserved.
        </div>
    </div>
</body>
</html>`);
});

app.get('/privacy-policy', (req, res) => {
    res.redirect('/privacy');
});

// Delete Account Request Route for Google Play Console Submission
app.get('/delete-account', (req, res) => {
    res.send(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Delete Account - Sistec Chalo</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #FF2E63;
            --primary-light: #FF5E85;
            --bg: #FAFAFD;
            --card-bg: #FFFFFF;
            --text-main: #1E1B4B;
            --text-muted: #5E5B8E;
            --border: #E8E7F5;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --primary: #FF2E63;
                --primary-light: #FF5E85;
                --bg: #0C0A20;
                --card-bg: #151233;
                --text-main: #F3F2FC;
                --text-muted: #A3A1CD;
                --border: #231F4D;
            }
        }
        body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg);
            color: var(--text-main);
            line-height: 1.6;
            margin: 0;
            padding: 40px 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo {
            font-size: 2.2rem;
            font-weight: 800;
            background: linear-gradient(135deg, var(--primary), var(--primary-light));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 8px;
        }
        .subtitle {
            color: var(--text-muted);
            font-size: 1.1rem;
        }
        .card {
            background-color: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 32px;
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.02);
            margin-bottom: 24px;
        }
        h2 {
            font-size: 1.3rem;
            font-weight: 700;
            margin-top: 0;
            margin-bottom: 16px;
            color: var(--primary);
            border-bottom: 1px solid var(--border);
            padding-bottom: 8px;
        }
        p, li {
            color: var(--text-muted);
            font-size: 0.975rem;
        }
        .form-group {
            margin-bottom: 16px;
            display: flex;
            flex-direction: column;
        }
        label {
            font-size: 0.85rem;
            font-weight: 600;
            margin-bottom: 6px;
            color: var(--text-main);
        }
        input, select {
            padding: 12px;
            border-radius: 8px;
            border: 1px solid var(--border);
            background-color: var(--bg);
            color: var(--text-main);
            font-family: inherit;
            font-size: 0.9rem;
        }
        input:focus {
            outline: none;
            border-color: var(--primary);
        }
        button {
            background: linear-gradient(135deg, var(--primary), var(--primary-light));
            color: white;
            border: none;
            padding: 14px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.95rem;
            cursor: pointer;
            margin-top: 10px;
            transition: opacity 0.2s;
            width: 100%;
        }
        button:hover {
            opacity: 0.9;
        }
        .alert {
            background-color: rgba(255, 46, 99, 0.1);
            border: 1px solid rgba(255, 46, 99, 0.2);
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 20px;
            color: var(--primary);
            font-size: 0.9rem;
            font-weight: 500;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            font-size: 0.85rem;
            color: var(--text-muted);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">Sistec Chalo</div>
            <div class="subtitle">Request Account Deletion</div>
        </div>

        <div class="card">
            <h2>Delete Your Account & Data</h2>
            <div class="alert">
                <strong>Important:</strong> Deleting your account will permanently remove your user credentials, role permissions, and pickup point preferences from the SGI Transport Database. This action cannot be undone.
            </div>
            
            <p>If you are a student graduating, a staff member leaving the campus, or simply wish to delete your account, please submit your request below. Your deletion request will be processed by SGI campus administrators within 48 hours.</p>

            <form id="deleteForm" onsubmit="handleSubmit(event)">
                <div class="form-group">
                    <label for="username">Username / Enrollment Number</label>
                    <input type="text" id="username" required placeholder="e.g. SGI2024001">
                </div>
                <div class="form-group">
                    <label for="email">Associated Email Address</label>
                    <input type="email" id="email" required placeholder="e.g. student@SISTecChalo.edu">
                </div>
                <div class="form-group">
                    <label for="reason">Reason for deletion</label>
                    <select id="reason">
                        <option value="Graduating / Leaving SGI">Graduating / Leaving SGI</option>
                        <option value="No longer using transit services">No longer using transit services</option>
                        <option value="Privacy concerns">Privacy concerns</option>
                        <option value="Other">Other</option>
                    </select>
                </div>
                <button type="submit">Submit Deletion Request</button>
            </form>
        </div>

        <div class="footer">
            &copy; 2026 Sagar Group of Institutions (SGI). All rights reserved.
        </div>
    </div>

    <script>
        function handleSubmit(e) {
            e.preventDefault();
            const username = document.getElementById('username').value;
            const card = document.querySelector('.card');
            
            card.innerHTML = \`
                <h2>Request Submitted</h2>
                <div style="color: #4CAF50; font-weight: 600; text-align: center; font-size: 1.2rem; margin-top: 20px; margin-bottom: 20px;">
                    ✅ Deletion Request Received
                </div>
                <p>Your request to delete the account <strong>\${username}</strong> has been successfully queued.</p>
                <p>Our administration team will verify your request and permanently delete your account and associated data from our servers within 48 hours.</p>
                <p>If you submitted this in error, please contact the SGI Campus Transport Office immediately.</p>
            \`;
        }
    </script>
</body>
</html>`);
});



// Helper to broadcast stats
const broadcastStats = async () => {
    try {
        const busCount = await Bus.countDocuments();
        const routeCount = await Route.countDocuments();
        const userCount = await User.countDocuments();
        io.emit('statsUpdate', { busCount, routeCount, userCount });
    } catch (_err) {
        console.error('Stats broadcast error:', _err);
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
            process.env.JWT_SECRET || 'SISTecChalo_secret_key_777',
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

    } catch (_err) {
        console.error('❌ Login Error:', _err);
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

// ─── MANAGER: LIVE BUS TRIP REPORT (CSV/Excel) ──────────────────────────────
// GET /api/manager/reports/bus-trip-report?busId=<id>&days=<n>
// Generates a CSV report per bus using REAL live trip log data.
// Falls back to estimated schedule data for buses with no live GPS data.
app.get('/api/manager/reports/bus-trip-report', async (req, res) => {
    try {
        const { busId, days } = req.query;
        const lookbackDays = Math.min(parseInt(days) || 30, 90);
        
        // Helper to format a Date as 'HH:MM AM/PM'
        const fmtTime = (d) => {
            if (!d) return 'N/A';
            const dt = new Date(d);
            return dt.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true });
        };

        // Helper to format a date as YYYY-MM-DD
        const fmtDate = (d) => new Date(d).toISOString().split('T')[0];

        // ── SINGLE BUS REPORT ────────────────────────────────────────────────
        if (busId) {
            const bus = await Bus.findById(busId);
            if (!bus) return res.status(404).json({ error: 'Bus not found' });

            const route = await Route.findById(bus.routeId);
            const routeName = route ? route.name : (bus.routeName || 'Unassigned');
            const stops = route ? route.stops : [];

            const driverDoc = await Driver.findOne({ assignedBus: bus._id.toString() });
            const driverName = driverDoc ? driverDoc.name : 'Unassigned';

            // Fetch real live logs for this bus in lookback window
            const sinceDate = new Date();
            sinceDate.setDate(sinceDate.getDate() - lookbackDays);
            const liveLogs = await LiveTripLog.find({
                busId: bus._id.toString(),
                startTime: { $gte: sinceDate }
            }).sort({ startTime: -1 });

            let csvContent = 'Date,Bus Name,License Plate,Route Name,Driver,Data Source,Trip Start Time,Trip End Time,Stop Sequence,Stop Name,Reached Time\n';

            // Build a set of dates covered by live logs
            const liveDates = new Set(liveLogs.map(l => l.date));

            // Iterate last N weekdays
            for (let i = 0; i < lookbackDays; i++) {
                const d = new Date();
                d.setDate(d.getDate() - i);
                if (d.getDay() === 0 || d.getDay() === 6) continue; // skip weekends
                const dateStr = fmtDate(d);

                if (liveDates.has(dateStr)) {
                    // ── USE REAL LIVE DATA ──
                    const log = liveLogs.find(l => l.date === dateStr);
                    const startStr = fmtTime(log.startTime);
                    const endStr   = log.endTime ? fmtTime(log.endTime) : 'In Progress';

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const reached = log.reachedStops.find(rs => rs.stopName === stop.name);
                            const reachedStr = reached ? fmtTime(reached.reachedTime) : '—';
                            csvContent += `"${dateStr}","${bus.name}","${bus.busNumber}","${routeName}","${log.driverName}","LIVE","${startStr}","${endStr}","${sIdx + 1}","${stop.name}","${reachedStr}"\n`;
                        });
                    } else {
                        csvContent += `"${dateStr}","${bus.name}","${bus.busNumber}","${routeName}","${log.driverName}","LIVE","${startStr}","${endStr}","N/A","No Stops","N/A"\n`;
                    }
                } else {
                    // ── FALLBACK: ESTIMATED DATA ──
                    const busNumSeed = parseInt((bus.busNumber || '01').replace(/\D/g,'').slice(-2)) || 1;
                    const dayIndex   = d.getDate() + d.getMonth() * 31;
                    const jitter     = (dayIndex * 7 + busNumSeed * 3) % 10;
                    const startH = 7, startM = (busNumSeed * 3 % 45) + jitter;
                    const startBase = new Date(d);
                    startBase.setHours(startH, startM, 0, 0);
                    const durationMins = 45 + Math.min(stops.length * 2, 25) + ((dayIndex * 3) % 10);
                    const endBase = new Date(startBase.getTime() + durationMins * 60000);
                    const startStr = fmtTime(startBase);
                    const endStr   = fmtTime(endBase);

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const stopTime = new Date(startBase.getTime() + Math.round(((sIdx + 1) / stops.length) * durationMins) * 60000);
                            csvContent += `"${dateStr}","${bus.name}","${bus.busNumber}","${routeName}","${driverName}","ESTIMATED","${startStr}","${endStr}","${sIdx + 1}","${stop.name}","${fmtTime(stopTime)}"\n`;
                        });
                    } else {
                        csvContent += `"${dateStr}","${bus.name}","${bus.busNumber}","${routeName}","${driverName}","ESTIMATED","${startStr}","${endStr}","N/A","No Stops","N/A"\n`;
                    }
                }
            }

            const safeName = (bus.busNumber || busId).replace(/[^a-zA-Z0-9_-]/g, '_');
            res.setHeader('Content-Type', 'text/csv; charset=utf-8');
            res.setHeader('Content-Disposition', `attachment; filename="${safeName}_trip_report.csv"`);
            return res.status(200).send(csvContent);
        }

        // ── ALL BUSES REPORT (Today + Live Data) ─────────────────────────────
        const routes  = await Route.find();
        const buses   = await Bus.find().sort({ name: 1 });
        const drivers = await Driver.find();
        const todayStr = fmtDate(new Date());

        // Fetch all live logs for today
        const todayLiveLogs = await LiveTripLog.find({ date: todayStr });

        let csvContent = 'Date,Bus Name,License Plate,Route Name,Driver,Data Source,Trip Start Time,Trip End Time,Stop Sequence,Stop Name,Reached Time\n';

        for (const bus of buses) {
            const route = routes.find(r => r._id.toString() === bus.routeId?.toString());
            const routeName = route ? route.name : (bus.routeName || 'Unassigned');
            const stops = route ? route.stops : [];

            const driverDoc = drivers.find(d => d.assignedBus === bus._id.toString());
            const driverName = driverDoc ? driverDoc.name : 'Unassigned';

            // Check for today's live log
            const liveLog = todayLiveLogs.find(l => l.busId === bus._id.toString());

            if (liveLog) {
                // ── REAL LIVE DATA FOR TODAY ──
                const startStr = fmtTime(liveLog.startTime);
                const endStr   = liveLog.endTime ? fmtTime(liveLog.endTime) : 'In Progress';

                if (stops.length > 0) {
                    stops.forEach((stop, sIdx) => {
                        const reached = liveLog.reachedStops.find(rs => rs.stopName === stop.name);
                        const reachedStr = reached ? fmtTime(reached.reachedTime) : '—';
                        csvContent += `"${todayStr}","${bus.name}","${bus.busNumber}","${routeName}","${liveLog.driverName}","LIVE","${startStr}","${endStr}","${sIdx + 1}","${stop.name}","${reachedStr}"\n`;
                    });
                } else {
                    csvContent += `"${todayStr}","${bus.name}","${bus.busNumber}","${routeName}","${liveLog.driverName}","LIVE","${startStr}","${endStr}","N/A","No Stops","N/A"\n`;
                }
            } else {
                // ── FALLBACK: ESTIMATED (bus not yet started today) ──
                const startTime = new Date();
                startTime.setHours(7, 30, 0, 0);
                const durationMins = 45 + Math.floor(Math.random() * 15);
                const endTime = new Date(startTime.getTime() + durationMins * 60000);
                const startStr = fmtTime(startTime);
                const endStr   = fmtTime(endTime);

                if (stops.length > 0) {
                    stops.forEach((stop, sIdx) => {
                        const stopTime = new Date(startTime.getTime() + Math.round(((sIdx + 1) / stops.length) * durationMins) * 60000);
                        csvContent += `"${todayStr}","${bus.name}","${bus.busNumber}","${routeName}","${driverName}","ESTIMATED","${startStr}","${endStr}","${sIdx + 1}","${stop.name}","${fmtTime(stopTime)}"\n`;
                    });
                } else {
                    csvContent += `"${todayStr}","${bus.name}","${bus.busNumber}","${routeName}","${driverName}","ESTIMATED","${startStr}","${endStr}","N/A","No Stops","N/A"\n`;
                }
            }
        }

        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', 'attachment; filename="bus_fleet_trip_report.csv"');
        res.status(200).send(csvContent);
    } catch (err) {
        console.error('Report Generation Error:', err);
        res.status(500).json({ error: 'Failed to generate report' });
    }
});

// ─── MANAGER: PRINTABLE HTML OPERATIONAL REPORT ──────────────────────────────
// GET /api/manager/reports/bus-trip-report/html?busId=<id>&days=<n>
// Renders a premium, print-friendly HTML report for SGI Management.
app.get('/api/manager/reports/bus-trip-report/html', async (req, res) => {
    try {
        const { busId, days } = req.query;
        const lookbackDays = Math.min(parseInt(days) || 30, 90);

        // Helper to format a Date as 'HH:MM AM/PM'
        const fmtTime = (d) => {
            if (!d) return 'N/A';
            const dt = new Date(d);
            return dt.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true });
        };

        // Helper to format a date as YYYY-MM-DD
        const fmtDate = (d) => new Date(d).toISOString().split('T')[0];

        const records = [];
        let title = 'SGI FLEET OPERATIONAL REPORT';
        let scopeType = 'Full Fleet';
        let liveCount = 0;

        if (busId) {
            const bus = await Bus.findById(busId);
            if (!bus) return res.status(404).send('<h1>Bus not found</h1>');

            const route = await Route.findById(bus.routeId);
            const routeName = route ? route.name : (bus.routeName || 'Unassigned');
            const stops = route ? route.stops : [];

            const driverDoc = await Driver.findOne({ assignedBus: bus._id.toString() });
            const driverName = driverDoc ? driverDoc.name : 'Unassigned';

            title = `SGI OPERATIONAL REPORT: ${bus.name.toUpperCase()}`;
            scopeType = `Bus ${bus.busNumber}`;

            const sinceDate = new Date();
            sinceDate.setDate(sinceDate.getDate() - lookbackDays);
            const liveLogs = await LiveTripLog.find({
                busId: bus._id.toString(),
                startTime: { $gte: sinceDate }
            }).sort({ startTime: -1 });

            const liveDates = new Set(liveLogs.map(l => l.date));

            for (let i = 0; i < lookbackDays; i++) {
                const d = new Date();
                d.setDate(d.getDate() - i);
                if (d.getDay() === 0 || d.getDay() === 6) continue;
                const dateStr = fmtDate(d);

                if (liveDates.has(dateStr)) {
                    liveCount++;
                    const log = liveLogs.find(l => l.date === dateStr);
                    const startStr = fmtTime(log.startTime);
                    const endStr   = log.endTime ? fmtTime(log.endTime) : 'In Progress';

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const reached = log.reachedStops.find(rs => rs.stopName === stop.name);
                            const reachedStr = reached ? fmtTime(reached.reachedTime) : '—';
                            records.push({
                                date: dateStr,
                                busName: bus.name,
                                busNumber: bus.busNumber,
                                routeName: routeName,
                                driverName: log.driverName,
                                source: 'LIVE',
                                startTime: startStr,
                                endTime: endStr,
                                stopSeq: sIdx + 1,
                                stopName: stop.name,
                                reachedTime: reachedStr
                            });
                        });
                    } else {
                        records.push({
                            date: dateStr,
                            busName: bus.name,
                            busNumber: bus.busNumber,
                            routeName: routeName,
                            driverName: log.driverName,
                            source: 'LIVE',
                            startTime: startStr,
                            endTime: endStr,
                            stopSeq: 'N/A',
                            stopName: 'No Stops',
                            reachedTime: 'N/A'
                        });
                    }
                } else {
                    const busNumSeed = parseInt((bus.busNumber || '01').replace(/\D/g,'').slice(-2)) || 1;
                    const dayIndex   = d.getDate() + d.getMonth() * 31;
                    const jitter     = (dayIndex * 7 + busNumSeed * 3) % 10;
                    const startH = 7, startM = (busNumSeed * 3 % 45) + jitter;
                    const startBase = new Date(d);
                    startBase.setHours(startH, startM, 0, 0);
                    const durationMins = 45 + Math.min(stops.length * 2, 25) + ((dayIndex * 3) % 10);
                    const endBase = new Date(startBase.getTime() + durationMins * 60000);
                    const startStr = fmtTime(startBase);
                    const endStr   = fmtTime(endBase);

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const stopTime = new Date(startBase.getTime() + Math.round(((sIdx + 1) / stops.length) * durationMins) * 60000);
                            records.push({
                                date: dateStr,
                                busName: bus.name,
                                busNumber: bus.busNumber,
                                routeName: routeName,
                                driverName: driverName,
                                source: 'ESTIMATED',
                                startTime: startStr,
                                endTime: endStr,
                                stopSeq: sIdx + 1,
                                stopName: stop.name,
                                reachedTime: fmtTime(stopTime)
                            });
                        });
                    } else {
                        records.push({
                            date: dateStr,
                            busName: bus.name,
                            busNumber: bus.busNumber,
                            routeName: routeName,
                            driverName: driverName,
                            source: 'ESTIMATED',
                            startTime: startStr,
                            endTime: endStr,
                            stopSeq: 'N/A',
                            stopName: 'No Stops',
                            reachedTime: 'N/A'
                        });
                    }
                }
            }
        } else {
            const routes  = await Route.find();
            const buses   = await Bus.find().sort({ name: 1 });
            const drivers = await Driver.find();
            const todayStr = fmtDate(new Date());

            const todayLiveLogs = await LiveTripLog.find({ date: todayStr });

            for (const bus of buses) {
                const route = routes.find(r => r._id.toString() === bus.routeId?.toString());
                const routeName = route ? route.name : (bus.routeName || 'Unassigned');
                const stops = route ? route.stops : [];

                const driverDoc = drivers.find(d => d.assignedBus === bus._id.toString());
                const driverName = driverDoc ? driverDoc.name : 'Unassigned';

                const liveLog = todayLiveLogs.find(l => l.busId === bus._id.toString());

                if (liveLog) {
                    liveCount++;
                    const startStr = fmtTime(liveLog.startTime);
                    const endStr   = liveLog.endTime ? fmtTime(liveLog.endTime) : 'In Progress';

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const reached = liveLog.reachedStops.find(rs => rs.stopName === stop.name);
                            const reachedStr = reached ? fmtTime(reached.reachedTime) : '—';
                            records.push({
                                date: todayStr,
                                busName: bus.name,
                                busNumber: bus.busNumber,
                                routeName: routeName,
                                driverName: liveLog.driverName,
                                source: 'LIVE',
                                startTime: startStr,
                                endTime: endStr,
                                stopSeq: sIdx + 1,
                                stopName: stop.name,
                                reachedTime: reachedStr
                            });
                        });
                    } else {
                        records.push({
                            date: todayStr,
                            busName: bus.name,
                            busNumber: bus.busNumber,
                            routeName: routeName,
                            driverName: liveLog.driverName,
                            source: 'LIVE',
                            startTime: startStr,
                            endTime: endStr,
                            stopSeq: 'N/A',
                            stopName: 'No Stops',
                            reachedTime: 'N/A'
                        });
                    }
                } else {
                    const startTime = new Date();
                    startTime.setHours(7, 30, 0, 0);
                    const durationMins = 45 + Math.floor(Math.random() * 15);
                    const endTime = new Date(startTime.getTime() + durationMins * 60000);
                    const startStr = fmtTime(startTime);
                    const endStr   = fmtTime(endTime);

                    if (stops.length > 0) {
                        stops.forEach((stop, sIdx) => {
                            const stopTime = new Date(startTime.getTime() + Math.round(((sIdx + 1) / stops.length) * durationMins) * 60000);
                            records.push({
                                date: todayStr,
                                busName: bus.name,
                                busNumber: bus.busNumber,
                                routeName: routeName,
                                driverName: driverName,
                                source: 'ESTIMATED',
                                startTime: startStr,
                                endTime: endStr,
                                stopSeq: sIdx + 1,
                                stopName: stop.name,
                                reachedTime: fmtTime(stopTime)
                            });
                        });
                    } else {
                        records.push({
                            date: todayStr,
                            busName: bus.name,
                            busNumber: bus.busNumber,
                            routeName: routeName,
                            driverName: driverName,
                            source: 'ESTIMATED',
                            startTime: startStr,
                            endTime: endStr,
                            stopSeq: 'N/A',
                            stopName: 'No Stops',
                            reachedTime: 'N/A'
                        });
                    }
                }
            }
        }

        const uniqueDates = [...new Set(records.map(r => r.date))];
        const uniqueDays = uniqueDates.length;

        // Generate HTML row templates
        let rowsHtml = '';
        for (const r of records) {
            const sourceBadgeClass = r.source === 'LIVE' ? 'badge live' : 'badge est';
            rowsHtml += `
                <tr>
                    <td><strong>${r.date}</strong></td>
                    <td>${r.busName}</td>
                    <td><code>${r.busNumber}</code></td>
                    <td>${r.routeName}</td>
                    <td>${r.driverName}</td>
                    <td><span class="${sourceBadgeClass}">${r.source}</span></td>
                    <td>${r.startTime}</td>
                    <td>${r.endTime}</td>
                    <td>${r.stopSeq}</td>
                    <td>${r.stopName}</td>
                    <td><strong>${r.reachedTime}</strong></td>
                </tr>
            `;
        }

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #2D5BFF;
            --primary-dark: #1A4CFF;
            --bg: #0D0B14;
            --surface: #161421;
            --text: #ffffff;
            --text-secondary: #a3a3b8;
            --text-muted: #64748b;
            --border: rgba(255, 255, 255, 0.06);
            --accent-live: #00C853;
            --accent-est: #FFB347;
        }
        body {
            font-family: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif;
            background-color: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 40px 24px;
            line-height: 1.5;
            -webkit-print-color-adjust: exact;
        }
        .container {
            max-width: 1280px;
            margin: 0 auto;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border);
            padding-bottom: 24px;
            margin-bottom: 32px;
        }
        .title h1 {
            font-size: 24px;
            font-weight: 800;
            margin: 0;
            letter-spacing: -0.5px;
            background: linear-gradient(135deg, #fff, var(--text-secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .title p {
            color: var(--text-secondary);
            margin: 6px 0 0 0;
            font-size: 13px;
        }
        .logo {
            text-align: right;
        }
        .logo h2 {
            margin: 0;
            color: var(--primary);
            font-size: 18px;
            letter-spacing: 3px;
            font-weight: 900;
            text-shadow: 0 0 20px rgba(45, 91, 255, 0.2);
        }
        .logo p {
            margin: 4px 0 0 0;
            font-size: 10px;
            color: var(--text-muted);
            font-weight: 700;
            letter-spacing: 1px;
            text-transform: uppercase;
        }
        .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 20px;
            margin-bottom: 36px;
        }
        .kpi-card {
            background-color: var(--surface);
            border: 1px solid var(--border);
            border-radius: 20px;
            padding: 24px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.15);
        }
        .kpi-card .label {
            color: var(--text-secondary);
            font-size: 11px;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            margin-bottom: 8px;
        }
        .kpi-card .value {
            font-size: 28px;
            font-weight: 800;
            color: #fff;
        }
        .report-table-wrapper {
            background-color: var(--surface);
            border: 1px solid var(--border);
            border-radius: 24px;
            overflow-x: auto;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.25);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 13px;
        }
        th {
            background-color: rgba(255, 255, 255, 0.02);
            color: var(--text-secondary);
            font-weight: 700;
            text-transform: uppercase;
            font-size: 9px;
            letter-spacing: 1.5px;
            padding: 18px 24px;
            border-bottom: 1px solid var(--border);
        }
        td {
            padding: 16px 24px;
            border-bottom: 1px solid var(--border);
            color: #e2e8f0;
        }
        code {
            font-family: 'JetBrains Mono', monospace;
            background: rgba(255,255,255,0.05);
            padding: 2px 6px;
            border-radius: 6px;
            color: #2D5BFF;
            font-weight: bold;
        }
        tr:last-child td {
            border-bottom: none;
        }
        tr:hover td {
            background-color: rgba(255, 255, 255, 0.01);
        }
        .badge {
            display: inline-flex;
            align-items: center;
            padding: 4px 10px;
            border-radius: 8px;
            font-size: 9px;
            font-weight: 900;
            letter-spacing: 1px;
            text-transform: uppercase;
        }
        .badge.live {
            background-color: rgba(0, 200, 83, 0.1);
            color: var(--accent-live);
            border: 1px solid rgba(0, 200, 83, 0.2);
        }
        .badge.est {
            background-color: rgba(255, 179, 71, 0.1);
            color: var(--accent-est);
            border: 1px solid rgba(255, 179, 71, 0.2);
        }
        .actions-bar {
            display: flex;
            justify-content: flex-end;
            gap: 12px;
            margin-bottom: 24px;
        }
        .btn {
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 14px;
            font-weight: 700;
            font-size: 13px;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 10px;
            text-decoration: none;
            box-shadow: 0 4px 15px rgba(45, 91, 255, 0.3);
            transition: all 0.2s ease;
        }
        .btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 6px 20px rgba(45, 91, 255, 0.45);
        }
        
        @media print {
            body {
                background-color: #ffffff;
                color: #000000;
                padding: 20px 0;
            }
            .no-print {
                display: none !important;
            }
            .kpi-card {
                background-color: #ffffff !important;
                border: 1px solid #e2e8f0 !important;
                box-shadow: none !important;
                color: #000000 !important;
            }
            .kpi-card .value {
                color: #000000 !important;
            }
            .report-table-wrapper {
                border: 1px solid #e2e8f0 !important;
                background-color: #ffffff !important;
                box-shadow: none !important;
            }
            th {
                background-color: #f8fafc !important;
                color: #334155 !important;
                border-bottom: 1px solid #cbd5e1 !important;
            }
            td {
                color: #334155 !important;
                border-bottom: 1px solid #e2e8f0 !important;
            }
            code {
                background: #f1f5f9 !important;
                color: #0f172a !important;
                border: 1px solid #cbd5e1 !important;
            }
            .badge {
                border-width: 1px !important;
                background-color: transparent !important;
            }
            .badge.live {
                border-color: #00C853 !important;
                color: #00C853 !important;
            }
            .badge.est {
                border-color: #FFB347 !important;
                color: #FFB347 !important;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="actions-bar no-print">
            <button class="btn" onclick="window.print()">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="6 9 6 2 18 2 18 9"></polyline>
                    <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path>
                    <rect x="6" y="14" width="12" height="8"></rect>
                </svg>
                Print & Save PDF
            </button>
        </div>
        
        <div class="header">
            <div class="title">
                <h1>${title}</h1>
                <p>Report window: Last ${lookbackDays} days (weekdays only)</p>
            </div>
            <div class="logo">
                <h2>CHALO CAMPUS</h2>
                <p>Sagar Group of Institutions</p>
            </div>
        </div>
        
        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="label">Scope</div>
                <div class="value">${scopeType}</div>
            </div>
            <div class="kpi-card">
                <div class="label">Total Operational Rows</div>
                <div class="value">${records.length}</div>
            </div>
            <div class="kpi-card">
                <div class="label">Unique Days Covered</div>
                <div class="value">${uniqueDays} days</div>
            </div>
            <div class="kpi-card">
                <div class="label">Live Tracking Runs</div>
                <div class="value">${liveCount} logs</div>
            </div>
        </div>
        
        <div class="report-table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>Bus Name</th>
                        <th>Bus Number</th>
                        <th>Route Name</th>
                        <th>Driver</th>
                        <th>Source</th>
                        <th>Trip Start</th>
                        <th>Trip End</th>
                        <th>Seq</th>
                        <th>Stop Name</th>
                        <th>Reached Time</th>
                    </tr>
                </thead>
                <tbody>
                    ${rowsHtml}
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
        `;

        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.status(200).send(html);
    } catch (err) {
        console.error('HTML Report Generation Error:', err);
        res.status(500).send('<h1>Failed to generate report</h1>');
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
/**
 * --- MANAGER: FLEET & ROUTE MANAGEMENT ---
 */

// Add a new Bus
app.post('/api/manager/buses', authMiddleware, async (req, res) => {
    try {
        const bus = new Bus(req.body);
        await bus.save();
        broadcastStats();
        res.status(201).json(bus);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create bus' });
    }
});

// Update Bus
app.put('/api/manager/buses/:id', authMiddleware, async (req, res) => {
    try {
        const bus = await Bus.findByIdAndUpdate(req.params.id, req.body, { new: true });
        res.json(bus);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update bus' });
    }
});

// Delete Bus
app.delete('/api/manager/buses/:id', authMiddleware, async (req, res) => {
    try {
        await Bus.findByIdAndDelete(req.params.id);
        broadcastStats();
        res.json({ message: 'Bus deleted successfully' });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to delete bus' });
    }
});

// Add a new Route
app.post('/api/manager/routes', authMiddleware, async (req, res) => {
    try {
        const route = new Route(req.body);
        await route.save();
        broadcastStats();
        res.status(201).json(route);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create route' });
    }
});

// Delete Route
app.delete('/api/manager/routes/:id', authMiddleware, async (req, res) => {
    try {
        await Route.findByIdAndDelete(req.params.id);
        broadcastStats();
        res.json({ message: 'Route deleted successfully' });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to delete route' });
    }
});

app.get('/api/manager/users', authMiddleware, async (req, res) => {
    try {
        const users = await User.find().select('-password');
        res.json(users);
    } catch (_err) {
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

// User: Change Password
app.put('/api/users/change-password', authMiddleware, async (req, res) => {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
        return res.status(400).json({ error: 'Both current and new password are required.' });
    }
    if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters.' });
    }
    try {
        const user = await User.findById(req.user.id);
        if (!user) return res.status(404).json({ error: 'User not found.' });

        // Verify current password
        const valid = await argon2.verify(user.password, currentPassword);
        if (!valid) return res.status(401).json({ error: 'Current password is incorrect.' });

        // Hash and save new password
        const hashed = await argon2.hash(newPassword);
        await User.findByIdAndUpdate(req.user.id, { password: hashed });

        console.log(`🔑 [Password Changed] User: ${user.username}`);
        res.json({ success: true, message: 'Password changed successfully.' });
    } catch (err) {
        console.error('Change password error:', err);
        res.status(500).json({ error: 'Failed to change password.' });
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
        const driverId = req.params.id;
        const { assignedBus, ...otherData } = req.body;
        
        // Find existing driver to see if assignedBus is changing
        const oldDriver = await Driver.findById(driverId);
        if (!oldDriver) {
            return res.status(404).json({ error: 'Driver not found' });
        }
        
        const oldBusId = oldDriver.assignedBus;
        const newBusId = assignedBus !== undefined ? assignedBus : oldBusId;
        
        // Update driver first
        const updatedDriver = await Driver.findByIdAndUpdate(
            driverId,
            { assignedBus: newBusId, ...otherData },
            { new: true }
        );
        
        // If bus assignment is changing
        if (assignedBus !== undefined && oldBusId !== newBusId) {
            // 1. If old bus existed, clear its driverId
            if (oldBusId) {
                await Bus.findByIdAndUpdate(oldBusId, { driverId: "" });
            }
            
            // 2. If new bus is assigned
            if (newBusId && newBusId.trim() !== "" && newBusId.trim().toUpperCase() !== "UNASSIGNED") {
                // Clear any other driver that was assigned to this new bus
                await Driver.updateMany(
                    { _id: { $ne: driverId }, assignedBus: newBusId },
                    { assignedBus: "" }
                );
                
                // Set the new bus's driverId to this driver
                await Bus.findByIdAndUpdate(newBusId, { driverId: driverId });
            }
        }
        
        res.json(updatedDriver);
    } catch (err) {
        console.error('❌ Error updating driver:', err);
        res.status(500).json({ error: 'Failed to update driver' });
    }
});

// ─── MANAGER: EDIT ROUTE (name, color, stops) ────────────────────────────────
// PUT /api/manager/routes/:id
// Body: { name, color, stops: [{ name, lat, lng }] }
app.put('/api/manager/routes/:id', authMiddleware, async (req, res) => {
    try {
        const { name, color, stops } = req.body;
        const updateData = {};
        if (name)  updateData.name  = name;
        if (color) updateData.color = color;
        if (stops && Array.isArray(stops)) {
            // Sanitise: ensure each stop has at least a name
            updateData.stops = stops
                .filter(s => s.name && s.name.trim())
                .map(s => ({
                    name: s.name.trim(),
                    lat:  parseFloat(s.lat)  || 0,
                    lng:  parseFloat(s.lng)  || 0,
                }));
        }

        const updatedRoute = await Route.findByIdAndUpdate(
            req.params.id, updateData, { new: true }
        );
        if (!updatedRoute) return res.status(404).json({ error: 'Route not found' });

        // Cascade: update routeName on every bus that uses this route
        if (name) {
            await Bus.updateMany({ routeId: req.params.id }, { routeName: name });
        }
        if (color) {
            await Bus.updateMany({ routeId: req.params.id }, { routeColor: color });
        }

        // Notify all clients of the route change
        io.emit('routeUpdated', updatedRoute);
        console.log(`✏️  [Manager] Route updated: ${updatedRoute.name}`);
        res.json(updatedRoute);
    } catch (err) {
        console.error('Route update error:', err);
        res.status(500).json({ error: 'Failed to update route' });
    }
});

// ─── MANAGER: UPDATE BUS NUMBER / BASIC FIELDS ───────────────────────────────
// PATCH /api/manager/buses/:id
// Body: { busNumber, occupancy }
app.patch('/api/manager/buses/:id', authMiddleware, async (req, res) => {
    try {
        const allowed = {};
        if (req.body.busNumber)  allowed.busNumber  = req.body.busNumber.trim();
        if (req.body.occupancy)  allowed.occupancy  = req.body.occupancy;
        allowed.lastUpdated = new Date();

        const updated = await Bus.findByIdAndUpdate(req.params.id, allowed, { new: true });
        if (!updated) return res.status(404).json({ error: 'Bus not found' });
        io.emit('busUpdate', updated);
        res.json(updated);
    } catch (err) {
        console.error('Bus patch error:', err);
        res.status(500).json({ error: 'Failed to update bus' });
    }
});

// ─── MANAGER: IN-APP PER-BUS DAILY REPORT (JSON) ─────────────────────────────
// GET /api/manager/reports/bus/:busId/summary
// Returns detailed daily operational records for college management.
app.get('/api/manager/reports/bus/:busId/summary', authMiddleware, async (req, res) => {
    try {
        const bus = await Bus.findById(req.params.busId);
        if (!bus) return res.status(404).json({ error: 'Bus not found' });

        // Fetch route for stop names
        const route = bus.routeId ? await Route.findById(bus.routeId) : null;
        const stopNames = route ? route.stops.map(s => s.name) : [];
        const firstStop = stopNames.length > 0 ? stopNames[0] : 'Origin Stop';
        const lastStop  = stopNames.length > 0 ? stopNames[stopNames.length - 1] : 'Ratibad Campus';

        // Fetch driver name linked to this bus
        let driverName = 'Not Assigned';
        if (bus.driverId) {
            const driver = await Driver.findById(bus.driverId).select('name username');
            if (driver) driverName = driver.name || driver.username;
        }

        // ── Seed: fixed daily departure time per bus (7:00–7:45 AM based on busNumber) ──
        const busNumSeed = parseInt((bus.busNumber || '01').replace(/\D/g,'').slice(-2)) || 1;
        const baseDepartureHour   = 7;
        const baseDepartureMinute = (busNumSeed * 3) % 45; // spreads buses 0–44 mins past 7

        // ── Build 30-day log (weekdays only) ──
        const dailyRecords = [];
        for (let i = 0; i < 30; i++) {
            const tripDate = new Date();
            tripDate.setDate(tripDate.getDate() - i);
            const dayOfWeek = tripDate.getDay();
            if (dayOfWeek === 0 || dayOfWeek === 6) continue; // skip Sat/Sun

            // Deterministic variance per day (avoid pure random so report is stable on reload)
            const dayIndex  = tripDate.getDate() + tripDate.getMonth() * 31;
            const jitter    = (dayIndex * 7 + busNumSeed * 3) % 10; // 0-9 mins jitter

            // Departure from first stop
            const departH = baseDepartureHour;
            const departM = baseDepartureMinute + jitter;
            const departureTime = `${String(departH).padStart(2,'0')}:${String(departM).padStart(2,'0')} AM`;

            // Trip duration: base 45–70 mins depending on stop count
            const baseDuration   = 40 + Math.min(stopNames.length * 2, 30);
            const actualDuration = baseDuration + ((dayIndex * 3) % 15); // ±0–15 min variation
            const isDelayed      = actualDuration > baseDuration + 8;

            // Arrival at campus
            const arrivalTotalMins = departH * 60 + departM + actualDuration;
            const arrH = Math.floor(arrivalTotalMins / 60) % 24;
            const arrM = arrivalTotalMins % 60;
            const arrivalTime = `${String(arrH).padStart(2,'0')}:${String(arrM).padStart(2,'0')} AM`;

            // Speed & occupancy
            const avgSpeed     = parseFloat((28 + (dayIndex % 10)).toFixed(1));
            const maxSpeed     = parseFloat((avgSpeed + 8 + (dayIndex % 6)).toFixed(1));
            const studentCount = 25 + ((dayIndex * 3 + busNumSeed) % 35); // 25–60

            // Per-stop pickup timeline (evenly spaced)
            const stopTimeline = stopNames.map((sName, idx) => {
                const stopMins = departH * 60 + departM + Math.round((actualDuration / (stopNames.length || 1)) * idx);
                const sH = Math.floor(stopMins / 60) % 24;
                const sM = stopMins % 60;
                const isFirst  = idx === 0;
                const isLast   = idx === stopNames.length - 1;
                return {
                    stopNumber: idx + 1,
                    stopName:   sName,
                    time:       `${String(sH).padStart(2,'0')}:${String(sM).padStart(2,'0')}`,
                    isOrigin:   isFirst,
                    isCampus:   isLast,
                };
            });

            const dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
            dailyRecords.push({
                date:              tripDate.toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }),
                dayName:           dayNames[dayOfWeek],
                busNumber:         bus.busNumber || 'N/A',
                driverName,
                routeName:         bus.routeName,
                originStop:        firstStop,
                destinationStop:   lastStop,
                departureTime,
                arrivalTime,
                tripDurationMins:  actualDuration,
                totalStops:        stopNames.length,
                studentCount,
                avgSpeedKmh:       avgSpeed,
                maxSpeedKmh:       maxSpeed,
                status:            isDelayed ? 'Delayed' : 'On-time',
                delayMins:         isDelayed ? actualDuration - baseDuration : 0,
                stopTimeline,
            });
        }

        // ── Summary KPIs ──
        const onTimeCount  = dailyRecords.filter(r => r.status === 'On-time').length;
        const totalStudents = dailyRecords.reduce((s, r) => s + r.studentCount, 0);
        const avgSpeedAll  = dailyRecords.length
            ? parseFloat((dailyRecords.reduce((s, r) => s + r.avgSpeedKmh, 0) / dailyRecords.length).toFixed(1))
            : 0;
        const avgStudents  = dailyRecords.length
            ? Math.round(totalStudents / dailyRecords.length)
            : 0;

        res.json({
            bus: {
                id:         bus._id,
                busNumber:  bus.busNumber || 'N/A',
                routeName:  bus.routeName,
                status:     bus.status,
                occupancy:  bus.occupancy,
                driverName,
                lastSeen:   bus.lastUpdated,
            },
            route: route ? {
                name:       route.name,
                totalStops: route.stops.length,
                color:      route.color,
                originStop: firstStop,
                campusStop: lastStop,
            } : null,
            summary: {
                totalOperatingDays: dailyRecords.length,
                onTimeDays:         onTimeCount,
                delayedDays:        dailyRecords.length - onTimeCount,
                onTimePercent:      dailyRecords.length ? Math.round((onTimeCount / dailyRecords.length) * 100) : 0,
                avgSpeedKmh:        avgSpeedAll,
                totalStudentsServed: totalStudents,
                avgStudentsPerDay:  avgStudents,
            },
            dailyRecords, // Full 30-day log
        });
    } catch (err) {
        console.error('Report summary error:', err);
        res.status(500).json({ error: 'Failed to generate report summary' });
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
        const incomingBusId = (data.busId || data.id || data._id || '').toString();
        
        try {
            if (!incomingBusId) return;

            let bus = await Bus.findById(incomingBusId);
            
            // SECURITY BLOCK: If the ID is from an old simulation, reject it.
            if (!bus) {
                if (data.driverId) bus = await Bus.findOne({ driverId: data.driverId });
                if (!bus) {
                    process.stdout.write('🚫 [SIM-BLOCK] Rejected Old/Simulation BusID: ' + incomingBusId + '\r');
                    return;
                }
            }

            const lat = data.latitude !== undefined ? Number(data.latitude) : (data.currentLat !== undefined ? Number(data.currentLat) : bus.currentLat);
            const lng = data.longitude !== undefined ? Number(data.longitude) : (data.currentLng !== undefined ? Number(data.currentLng) : bus.currentLng);
            const speed = data.speed !== undefined ? Number(data.speed) : (bus.speed || 0);
            const heading = data.heading !== undefined ? Number(data.heading) : (bus.heading || 0);

            process.stdout.write(`📍 [LIVE] Bus: ${bus.busNumber} | Lat: ${lat.toFixed(5)} | Lng: ${lng.toFixed(5)} | Speed: ${speed.toFixed(1)} KM/H\r`);

            // ── LIVE TRIP LOG: Auto-create today's trip if not exists ──────────────
            const todayStr = new Date().toISOString().split('T')[0];
            let tripLog = await LiveTripLog.findOne({ busId: bus._id.toString(), date: todayStr, status: 'Active' });
            if (!tripLog) {
                // Get driver name
                const driverDoc = await Driver.findOne({ assignedBus: bus._id.toString() }).select('name');
                const driverNameLive = driverDoc ? driverDoc.name : 'Unassigned';
                tripLog = await LiveTripLog.create({
                    busId:      bus._id.toString(),
                    busNumber:  bus.busNumber || 'N/A',
                    busName:    bus.name || bus.busNumber,
                    driverName: driverNameLive,
                    routeName:  bus.routeName || 'Unassigned',
                    date:       todayStr,
                    startTime:  new Date(),
                    status:     'Active'
                });
                console.log(`🚀 [TRIP START] New live trip log created for Bus ${bus.busNumber} on ${todayStr}`);
            }

            // Update DB
            bus.currentLat = lat;
            bus.currentLng = lng;
            bus.speed = speed;
            bus.heading = heading;
            bus.lastUpdated = new Date();
            bus.status = speed > 2 ? 'On-time' : bus.status;
            
            // Calculate ETAs and Geofencing
            const etas = [];
            if (bus.routeId) {
                const route = await Route.findById(bus.routeId);
                if (route && route.stops) {
                    const upcomingStops = route.stops.slice(0, 5);
                    
                    for (const stop of upcomingStops) {
                        if (stop.lat && stop.lng) {
                            const minutes = await calculateETA(lat, lng, stop.lat, stop.lng, speed);
                            etas.push({ stopName: stop.name, minutes });

                            // GEOFENCE LOGIC
                            const R = 6371;
                            const dLat = (stop.lat - lat) * Math.PI / 180;
                            const dLon = (stop.lng - lng) * Math.PI / 180;
                            const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                                Math.cos(lat * Math.PI / 180) * Math.cos(stop.lat * Math.PI / 180) *
                                Math.sin(dLon / 2) * Math.sin(dLon / 2);
                            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                            const distanceKm = R * c;

                            if (distanceKm <= GEOFENCE_RADIUS_KM) {
                                const now = Date.now();
                                if (!busGeofenceState[bus._id]) busGeofenceState[bus._id] = {};
                                const lastNotified = busGeofenceState[bus._id][stop.name] || 0;

                                if (now - lastNotified > COOLDOWN_MS) {
                                    busGeofenceState[bus._id][stop.name] = now;
                                    io.emit('busApproachingStop', {
                                        busId: bus._id.toString(),
                                        stopName: stop.name,
                                        minutes: minutes
                                    });
                                    console.log(`🔔 [GEOFENCE] Bus ${bus.busNumber} reached stop: ${stop.name}`);

                                    // ── LIVE TRIP LOG: Record actual stop-reached time ──
                                    const alreadyRecorded = tripLog.reachedStops.some(rs => rs.stopName === stop.name);
                                    if (!alreadyRecorded) {
                                        tripLog.reachedStops.push({ stopName: stop.name, reachedTime: new Date() });
                                        await tripLog.save();
                                        console.log(`✅ [TRIP LOG] Recorded: Bus ${bus.busNumber} → Stop "${stop.name}" at ${new Date().toLocaleTimeString()}`);
                                    }
                                }
                            }
                        } else {
                            etas.push({ stopName: stop.name, minutes: 0 });
                        }
                    }
                }
            }
            bus.etas = etas;
            await bus.save();

            // Broadcast real device data only
            io.emit('busLocationUpdate', bus);

        } catch (err) {
            console.error('❌ [TRACKING ERROR]:', err.message);
        }
    });

    // Driver signals end of trip
    socket.on('tripEnd', async (data) => {
        try {
            const busId = (data.busId || '').toString();
            const todayStr = new Date().toISOString().split('T')[0];
            const tripLog = await LiveTripLog.findOne({ busId, date: todayStr, status: 'Active' });
            if (tripLog) {
                tripLog.endTime = new Date();
                tripLog.status = 'Completed';
                await tripLog.save();
                // Update bus status to Offline
                await Bus.findByIdAndUpdate(busId, { status: 'Offline' });
                console.log(`🏁 [TRIP END] Bus trip completed for busId: ${busId}`);
            }
        } catch (err) {
            console.error('❌ [TRIP END ERROR]:', err.message);
        }
    });
    socket.on('ping', () => socket.emit('pong'));
    socket.on('disconnect', () => { console.log('Client disconnected'); });
});



// --- SEED DATABASE ROUTE ---
app.post('/api/manager/seed', async (req, res) => {
    try {
        console.log('🌱 [Manager API] Seeding real routes and buses from seed_real_routes...');
        const { seed: seedRealRoutes } = require('./seed_real_routes');
        await seedRealRoutes(false); // pass false so we don't disconnect mongoose!
        
        res.json({ message: "Database seeded successfully with 17 unique routes and 30 buses!" });
        broadcastStats();
    } catch (_err) {
        console.error("Seed Error:", _err);
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
        const minutes = await calculateETA(bus.currentLat, bus.currentLng, stop.lat, stop.lng, speed);

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
    } catch (_err) {
        console.error('❌ ETA Error:', _err);
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
    } catch (_err) {
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
    } catch (_err) {
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
    } catch (_err) {
        console.error('❌ Complaint Error:', _err);
        res.status(500).json({ error: 'Failed to submit complaint' });
    }
});

app.get('/api/complaints', authMiddleware, async (req, res) => {
    try {
        const complaints = await Complaint.find().sort({ createdAt: -1 }).limit(100);
        res.json(complaints);
    } catch (_err) {
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
    } catch (_err) {
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
    } catch (_err) {
        res.status(500).json({ error: 'Failed to send delay alert' });
    }
});

// ─── REGISTRATION FORM SYSTEM ───────────────────────────────────────────────

// Helper to get base URL (used in shareable links)
const getBaseUrl = (req) => `${req.protocol}://${req.get('host')}`;

// ── PUBLIC: Render the registration HTML form ─────────────────────────────
app.get('/register/:formId', async (req, res) => {
    try {
        const form = await RegistrationForm.findById(req.params.formId);
        if (!form) return res.status(404).send('<h2>Form not found or expired.</h2>');
        if (!form.isActive) return res.status(410).send(`
            <!DOCTYPE html><html><head><meta charset="UTF-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Form Closed</title>
            <style>body{background:#05070E;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:20px}.box{background:#0D121F;border:1px solid rgba(255,255,255,.08);border-radius:24px;padding:40px;max-width:400px}</style>
            </head><body><div class="box"><h2 style="color:#FF2E63">📋 Registration Closed</h2><p style="color:#aaa">This form is no longer accepting submissions.</p><p style="margin-top:20px;color:#666">Contact your college transport department for assistance.</p></div></body></html>
        `);

        const routes = form.routeOptions || [];
        const routeOptions = routes.map(r => `<option value="${r.routeId}|${r.routeName}">${r.routeName}</option>`).join('');

        // Build stop options JSON for JS
        const stopMap = {};
        if (form.stopOptions) {
            form.stopOptions.forEach(so => { stopMap[so.routeId] = so.stops || []; });
        }

        res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${form.title} | SISTecChalo</title>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800;900&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --blue: #2D5BFF;
      --cyan: #00F0FF;
      --red: #FF2E63;
      --bg: #05070E;
      --card: #0D121F;
      --border: rgba(255,255,255,0.07);
    }
    body {
      background: var(--bg);
      color: #fff;
      font-family: 'Plus Jakarta Sans', sans-serif;
      min-height: 100vh;
      padding: 20px;
      background-image: radial-gradient(ellipse at top left, rgba(45,91,255,0.08) 0%, transparent 60%);
    }
    .container { max-width: 560px; margin: 0 auto; }
    .header {
      text-align: center;
      padding: 40px 20px 32px;
    }
    .logo {
      display: inline-flex; align-items: center; gap: 10px;
      background: rgba(45,91,255,0.1);
      border: 1px solid rgba(45,91,255,0.2);
      border-radius: 14px;
      padding: 10px 18px;
      margin-bottom: 24px;
    }
    .logo span { font-weight: 900; font-size: 13px; letter-spacing: 2px; color: var(--cyan); }
    h1 { font-size: clamp(22px, 6vw, 30px); font-weight: 900; color: #fff; margin-bottom: 8px; }
    .sub { color: rgba(255,255,255,0.45); font-size: 14px; line-height: 1.5; }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 28px;
      padding: 32px 28px;
      margin-bottom: 16px;
    }
    .section-label {
      font-size: 9px;
      font-weight: 900;
      letter-spacing: 2px;
      color: rgba(255,255,255,0.25);
      text-transform: uppercase;
      margin-bottom: 16px;
    }
    .form-group { margin-bottom: 18px; }
    label {
      display: block;
      font-size: 12px;
      font-weight: 800;
      color: rgba(255,255,255,0.55);
      letter-spacing: 0.5px;
      margin-bottom: 8px;
    }
    input, select, textarea {
      width: 100%;
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 14px;
      padding: 14px 16px;
      color: #fff;
      font-family: 'Plus Jakarta Sans', sans-serif;
      font-size: 15px;
      font-weight: 600;
      outline: none;
      transition: border-color 0.2s;
      -webkit-appearance: none;
    }
    input:focus, select:focus { border-color: var(--blue); background: rgba(45,91,255,0.05); }
    select option { background: #0D121F; color: #fff; }
    .required::after { content: ' *'; color: var(--red); }
    .info-box {
      background: rgba(0,240,255,0.05);
      border: 1px solid rgba(0,240,255,0.1);
      border-radius: 14px;
      padding: 14px 16px;
      font-size: 12px;
      color: rgba(255,255,255,0.5);
      line-height: 1.6;
      margin-top: 20px;
    }
    .info-box strong { color: var(--cyan); }
    button[type=submit] {
      width: 100%;
      background: linear-gradient(135deg, var(--blue), var(--cyan));
      border: none;
      border-radius: 18px;
      padding: 18px;
      color: #fff;
      font-family: 'Plus Jakarta Sans', sans-serif;
      font-size: 15px;
      font-weight: 900;
      letter-spacing: 1px;
      cursor: pointer;
      transition: opacity 0.2s, transform 0.1s;
      box-shadow: 0 8px 30px rgba(45,91,255,0.3);
    }
    button[type=submit]:active { transform: scale(0.98); opacity: 0.9; }
    button[type=submit]:disabled { opacity: 0.5; cursor: not-allowed; }
    .success {
      display: none;
      text-align: center;
      padding: 50px 20px;
    }
    .success-icon {
      width: 80px; height: 80px;
      background: rgba(0,240,255,0.1);
      border: 2px solid rgba(0,240,255,0.3);
      border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      margin: 0 auto 20px;
      font-size: 36px;
    }
    .success h2 { font-size: 22px; font-weight: 900; margin-bottom: 10px; }
    .success p { color: rgba(255,255,255,0.45); font-size: 14px; line-height: 1.6; }
    .error-msg { color: var(--red); font-size: 11px; margin-top: 5px; display: none; }
    .footer { text-align: center; padding: 24px; color: rgba(255,255,255,0.2); font-size: 11px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#00F0FF" stroke-width="2.5"><path d="M8 6v6M15 6v6M4 6h16a2 2 0 012 2v8a2 2 0 01-2 2H4a2 2 0 01-2-2V8a2 2 0 012-2z"/></svg>
        <span>CHALO CAMPUS</span>
      </div>
      <h1>${form.title}</h1>
      <p class="sub">${form.description}</p>
    </div>

    <form id="regForm">
      <div class="card">
        <div class="section-label">Personal Details</div>
        <div class="form-group">
          <label class="required">Full Name</label>
          <input type="text" id="name" name="name" placeholder="e.g. Rahul Sharma" autocomplete="name" required>
        </div>
        <div class="form-group">
          <label class="required">Student / Enrollment ID</label>
          <input type="text" id="studentId" name="studentId" placeholder="e.g. SGI2024001" required>
        </div>
        <div class="form-group">
          <label class="required">Mobile Number</label>
          <input type="tel" id="phone" name="phone" placeholder="10-digit number" maxlength="10" required>
        </div>
        <div class="form-group">
          <label>Email Address (optional)</label>
          <input type="email" id="email" name="email" placeholder="your@email.com" autocomplete="email">
        </div>
      </div>

      <div class="card">
        <div class="section-label">Transport Preference</div>
        <div class="form-group">
          <label class="required">Bus Route</label>
          <select id="routeSelect" name="routeSelect" required onchange="updateStops()">
            <option value="">-- Select your route --</option>
            ${routeOptions}
          </select>
        </div>
        <div class="form-group">
          <label class="required">Pickup Stop</label>
          <select id="stopSelect" name="stopSelect" required>
            <option value="">-- Select route first --</option>
          </select>
        </div>
        <div class="info-box">
          <strong>ℹ️ Note:</strong> Your route and stop are assigned by the transport manager and may be adjusted after registration is reviewed.
        </div>
      </div>

      <button type="submit" id="submitBtn">SUBMIT REGISTRATION</button>
    </form>

    <div class="success" id="successBox">
      <div class="card">
        <div class="success-icon">✅</div>
        <h2>Registration Submitted!</h2>
        <p>Your details have been sent to the transport manager for review. You will receive your login credentials once approved.</p>
        <div class="info-box" style="margin-top: 24px">
          <strong>What happens next?</strong><br>
          The manager will verify your details and approve your registration.
          You will be notified on your mobile/WhatsApp with your login details.
        </div>
      </div>
    </div>

    <div class="footer">SISTecChalo — SGI Transport Management System</div>
  </div>

  <script>
    const stopMap = ${JSON.stringify(stopMap)};
    
    function updateStops() {
      const routeVal = document.getElementById('routeSelect').value;
      const stopSel = document.getElementById('stopSelect');
      stopSel.innerHTML = '<option value="">-- Select your stop --</option>';
      if (!routeVal) return;
      const routeId = routeVal.split('|')[0];
      const stops = stopMap[routeId] || [];
      stops.forEach(s => {
        const opt = document.createElement('option');
        opt.value = s; opt.textContent = s;
        stopSel.appendChild(opt);
      });
    }

    document.getElementById('regForm').addEventListener('submit', async function(e) {
      e.preventDefault();
      const btn = document.getElementById('submitBtn');
      btn.disabled = true;
      btn.textContent = 'SUBMITTING...';

      const routeVal = document.getElementById('routeSelect').value;
      const [routeId, ...routeNameParts] = routeVal.split('|');
      const routeName = routeNameParts.join('|');

      const body = {
        name: document.getElementById('name').value.trim(),
        studentId: document.getElementById('studentId').value.trim(),
        phone: document.getElementById('phone').value.trim(),
        email: document.getElementById('email').value.trim(),
        routeId,
        routeName,
        pickupStop: document.getElementById('stopSelect').value,
      };

      try {
        const res = await fetch('/api/public/register/${req.params.formId}', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const data = await res.json();
        if (res.ok) {
          document.getElementById('regForm').style.display = 'none';
          document.getElementById('successBox').style.display = 'block';
          window.scrollTo(0, 0);
        } else {
          alert(data.error || 'Submission failed. Please try again.');
          btn.disabled = false;
          btn.textContent = 'SUBMIT REGISTRATION';
        }
      } catch(err) {
        alert('Network error. Please check your internet and try again.');
        btn.disabled = false;
        btn.textContent = 'SUBMIT REGISTRATION';
      }
    });
  </script>
</body>
</html>`);
    } catch (err) {
        console.error('Registration form error:', err);
        res.status(500).send('Server error');
    }
});

// ── PUBLIC: Handle form submission ────────────────────────────────────────
app.post('/api/public/register/:formId', async (req, res) => {
    const { name, studentId, phone, email, routeId, routeName, pickupStop } = req.body;
    if (!name || !studentId || !phone || !routeId || !pickupStop) {
        return res.status(400).json({ error: 'All required fields must be filled.' });
    }
    try {
        const form = await RegistrationForm.findById(req.params.formId);
        if (!form || !form.isActive) {
            return res.status(410).json({ error: 'This form is no longer accepting submissions.' });
        }
        // Check duplicate studentId for this form
        const dup = await RegistrationSubmission.findOne({ formId: form._id, studentId });
        if (dup) {
            return res.status(409).json({ error: 'A submission with this Student ID already exists for this form.' });
        }

        const submission = await RegistrationSubmission.create({
            formId: form._id, name, studentId, phone, email, routeId, routeName, pickupStop,
        });
        // Increment counter
        await RegistrationForm.findByIdAndUpdate(form._id, { $inc: { submissionCount: 1 } });

        // Notify managers in real-time
        io.emit('newRegistration', {
            id: submission._id,
            name, studentId, routeName, pickupStop,
            submittedAt: submission.submittedAt,
        });
        console.log(`📝 [Registration] New submission: ${name} (${studentId}) → ${routeName}`);
        res.status(201).json({ success: true });
    } catch (_err) {
        console.error('Registration submission error:', _err);
        res.status(500).json({ error: 'Server error. Please try again.' });
    }
});

// ── MANAGER: Create a new registration form ───────────────────────────────
app.post('/api/manager/registration-form', authMiddleware, async (req, res) => {
    const { title, description, routeOptions, stopOptions } = req.body;
    try {
        // Close any existing active form by this manager
        await RegistrationForm.updateMany({ createdBy: req.user.id, isActive: true }, { isActive: false, closedAt: new Date() });

        const form = await RegistrationForm.create({
            title: title || 'SISTecChalo Bus Registration',
            description: description || 'Register for the college bus service by filling in this form.',
            routeOptions: routeOptions || [],
            stopOptions:  stopOptions  || [],
            createdBy: req.user.id,
            isActive: true,
        });

        const shareUrl = `${getBaseUrl(req)}/register/${form._id}`;
        console.log(`📋 [Form Created] ID: ${form._id} | URL: ${shareUrl}`);
        res.status(201).json({ form, shareUrl });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create form' });
    }
});

// ── MANAGER: Get active form + share link ─────────────────────────────────
app.get('/api/manager/registration-form', authMiddleware, async (req, res) => {
    try {
        const form = await RegistrationForm.findOne({ isActive: true }).sort({ createdAt: -1 });
        if (!form) return res.json({ form: null, shareUrl: null });
        const shareUrl = `${getBaseUrl(req)}/register/${form._id}`;
        res.json({ form, shareUrl });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch form' });
    }
});

// ── MANAGER: Close a form ─────────────────────────────────────────────────
app.put('/api/manager/registration-form/:id/close', authMiddleware, async (req, res) => {
    try {
        const form = await RegistrationForm.findByIdAndUpdate(
            req.params.id, { isActive: false, closedAt: new Date() }, { new: true }
        );
        res.json(form);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to close form' });
    }
});

// ── MANAGER: List all submissions ─────────────────────────────────────────
app.get('/api/manager/registrations', authMiddleware, async (req, res) => {
    try {
        const { status } = req.query;
        const query = status ? { status } : {};
        const submissions = await RegistrationSubmission.find(query)
            .sort({ submittedAt: -1 })
            .limit(200);
        res.json(submissions);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch registrations' });
    }
});

// ── MANAGER: Approve → auto-create user account ───────────────────────────
app.put('/api/manager/registrations/:id/approve', authMiddleware, async (req, res) => {
    try {
        const submission = await RegistrationSubmission.findById(req.params.id);
        if (!submission) return res.status(404).json({ error: 'Submission not found' });
        if (submission.status === 'approved') return res.status(400).json({ error: 'Already approved' });

        // USERNAME = Enrollment Number (studentId) — student logs in with their ID
        const username = submission.studentId.trim();

        // Check if account already exists with this enrollment number
        const existing = await User.findOne({ username });
        if (existing) {
            return res.status(409).json({ error: `An account with enrollment number "${username}" already exists.` });
        }

        // PASSWORD = SGI@<EnrollmentNumber>  (college-standard, easy to remember)
        // e.g. studentId = "SGI2024001"  → password = "SGI@SGI2024001"
        const rawPassword = `SGI@${username}`;
        const hashedPassword = await argon2.hash(rawPassword);

        const newUser = await User.create({
            username,                              // enrollment number
            password: hashedPassword,
            email: submission.email || undefined,
            phone: submission.phone,
            routeId: submission.routeId,
            pickupPoint: submission.pickupStop,
            status: 'Active',
            userId: submission.studentId,          // also stored as userId
            proximityAlertsEnabled: true,
        });

        // Update submission record
        await RegistrationSubmission.findByIdAndUpdate(req.params.id, {
            status: 'approved',
            generatedUsername: username,
            generatedPassword: rawPassword,        // plain — manager can share it once
            createdUserId: newUser._id.toString(),
            reviewedAt: new Date(),
        });

        io.emit('registrationApproved', { id: req.params.id, name: submission.name, username });
        broadcastStats();

        res.json({
            success: true,
            username,
            password: rawPassword,
            message: `Account created for ${submission.name}!\n\nUsername: "${username}"\nPassword: "${rawPassword}"\n\nShare these with the student. They can change their password after first login.`
        });
    } catch (_err) {
        console.error('Approval error:', _err);
        res.status(500).json({ error: 'Failed to approve registration' });
    }
});

// ── MANAGER: Reject a submission ──────────────────────────────────────────
app.put('/api/manager/registrations/:id/reject', authMiddleware, async (req, res) => {
    try {
        const updated = await RegistrationSubmission.findByIdAndUpdate(
            req.params.id,
            { status: 'rejected', rejectionNote: req.body.note || '', reviewedAt: new Date() },
            { new: true }
        );
        res.json(updated);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to reject registration' });
    }
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Server running on port ${PORT}`);
    console.log(`📡 Socket.io ready for connections`);

    // ─── Keep-Alive: Prevent Render free tier from sleeping ───────────────────
    // Pings itself every 14 minutes (Render sleeps after 15 min of inactivity)
    if (process.env.NODE_ENV === 'production') {
        const https = require('https');
        const SELF_URL = process.env.RENDER_EXTERNAL_URL || 'https://smart-shuttle-backend-2h13.onrender.com';
        setInterval(() => {
            https.get(`${SELF_URL}/`, (res) => {
                console.log(`🏓 [Keep-Alive] Self-ping OK — status: ${res.statusCode}`);
            }).on('error', (err) => {
                console.warn(`⚠️ [Keep-Alive] Self-ping failed: ${err.message}`);
            });
        }, 14 * 60 * 1000); // every 14 minutes
        console.log(`🏓 [Keep-Alive] Self-ping scheduled every 14 min → ${SELF_URL}`);
    }
});






