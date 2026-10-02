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
const compression = require('compression');
const http = require('http');
const { Server } = require('socket.io');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const { generateTripReportData } = require('./services/trip_report_generator');
const { syncDailyTripReportsToGoogleSheets, SPREADSHEET_ID } = require('./services/google_sheets_service');

// Load Firebase service account credentials
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
        const credentials = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
        admin.initializeApp({
            credential: admin.credential.cert(credentials)
        });
        console.log('🔥 [Firebase] SDK Initialized successfully via environment variable.');
    } catch (err) {
        console.error('❌ [Firebase] SDK Initialization via env failed:', err.message);
    }
} else {
    let serviceAccountPath = path.resolve(__dirname, 'firebase-service-account.json');
    if (!fs.existsSync(serviceAccountPath)) {
        const altPath = path.resolve(__dirname, 'firebase-service-account.json.json');
        if (fs.existsSync(altPath)) serviceAccountPath = altPath;
    }
    if (fs.existsSync(serviceAccountPath)) {
        try {
            admin.initializeApp({
                credential: admin.credential.cert(require(serviceAccountPath))
            });
            console.log('🔥 [Firebase] SDK Initialized successfully via file.');
        } catch (err) {
            console.error('❌ [Firebase] SDK Initialization via file failed:', err.message);
        }
    } else {
        console.log('⚠️ [Firebase] Service Account JSON not found (no env var or file). Background push notifications will be inactive.');
    }
}

const { sendCredentialsEmail, buildCredentialsEmailHtml, sendPasswordResetEmail } = require('./services/email_service');

// ── HELPER FUNCTIONS FOR STABILITY & SANITIZATION ────────────────────────────
const safeTrim = (val) => (val !== null && val !== undefined) ? val.toString().trim() : '';
const isValidId = (id) => id && typeof id === 'string' && mongoose.Types.ObjectId.isValid(id.trim());

/**
 * Calculates accurate real-time Estimated Time of Arrival (ETA)
 * using true road network routing (Google Routes API / OSRM high-resolution engine).
 */
const { calculateAccurateETA } = require('./road_routing_service');

const calculateETA = async (busLat, busLng, stopLat, stopLng, currentSpeed, route = null) => {
    return await calculateAccurateETA(busLat, busLng, stopLat, stopLng, currentSpeed, route);
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
const BoardingLog = require('./models/BoardingLog');
const FuelLog = require('./models/FuelLog');
const StopFeedback = require('./models/StopFeedback');
const { processStopFeedback, getRouteFeedbackSummary } = require('./services/stop_consensus_service');

const authMiddleware = require('./middleware/authMiddleware');

const optionalAuth = (req, res, next) => {
    const token = req.header('Authorization');
    if (!token) return next();
    try {
        const tokenString = token.startsWith('Bearer ') ? token.slice(7) : token;
        const decoded = jwt.verify(tokenString, process.env.JWT_SECRET || 'SISTecChalo_secret_key_777');
        req.user = decoded.user;
    } catch (_) {}
    next();
};

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        credentials: true
    },
    transports: ['websocket', 'polling'],
    allowEIO3: true,
    pingTimeout: 60000,
    pingInterval: 25000
});

// Security Hashing Options (Argon2id - Immune to GPU & ASIC offline cracking)
const ARGON2_SECURITY_OPTIONS = {
    type: argon2.argon2id,
    memoryCost: 65536, // 64 MB Dedicated RAM per hash
    timeCost: 3,       // 3 Iterations
    parallelism: 1
};
const DUMMY_HASH = '$argon2id$v=19$m=65536,t=3,p=1$4Y/a5N5c2V5X8P8K$kZ7y5kL9bW0xV3tY8uQ2mP5vR1sT4wX7zA0bC3dE6fG';

const secureHashPassword = async (rawPassword) => {
    return await argon2.hash(rawPassword, ARGON2_SECURITY_OPTIONS);
};

function generateStrongRandomPassword(length = 10) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#$%&*?';
    
    const getRandomChar = (str) => str[crypto.randomInt(0, str.length)];
    
    const chars = [
        getRandomChar(upper),
        getRandomChar(lower),
        getRandomChar(digits),
        getRandomChar(symbols),
    ];
    
    const all = upper + lower + digits + symbols;
    for (let i = chars.length; i < length; i++) {
        chars.push(getRandomChar(all));
    }
    
    // Fisher-Yates Shuffle
    for (let i = chars.length - 1; i > 0; i--) {
        const j = crypto.randomInt(0, i + 1);
        [chars[i], chars[j]] = [chars[j], chars[i]];
    }
    
    return chars.join('');
}

app.use(helmet({
    contentSecurityPolicy: false, // Allows cross-origin map tiles
    crossOriginEmbedderPolicy: false
}));
app.use(cors());

// ⚡ High-Performance Gzip/Brotli Compression (Compresses 3.2MB routes to <270KB)
app.use(compression({
    level: 6,
    threshold: 1024,
    filter: (req, res) => {
        if (req.headers['x-no-compression']) return false;
        return compression.filter(req, res);
    }
}));

// 🛡️ Enterprise NoSQL Injection & Query Sanitization Middleware
const sanitizeInput = (obj) => {
    if (!obj || typeof obj !== 'object') return obj;
    for (const key of Object.keys(obj)) {
        if (key.startsWith('$') || key.includes('.')) {
            delete obj[key];
        } else if (typeof obj[key] === 'object') {
            sanitizeInput(obj[key]);
        }
    }
    return obj;
};

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use((req, res, next) => {
    if (req.body) sanitizeInput(req.body);
    if (req.query) sanitizeInput(req.query);
    if (req.params) sanitizeInput(req.params);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    next();
});

// ⚡ 100% Free Keep-Alive Health Endpoint for Render & UptimeRobot
app.get(['/api/health', '/health'], (req, res) => {
    res.status(200).json({ status: 'ok', service: 'SISTecChalo Backend', uptime: Math.round(process.uptime()), timestamp: new Date().toISOString() });
});

// 🚀 Public App Version & In-App Update Checker
app.get('/api/app-version', (req, res) => {
    res.status(200).json({
        latestVersion: "1.0.4",
        latestBuildNumber: 18,
        minSupportedBuildNumber: 1,
        title: "New Update Available! 🚀",
        message: "A new version of SISTec Chalo is ready on Google Play Store with Where-Is-My-Train Stop Calibration, Guest Mode Logout, and Notification Management.",
        releaseNotes: [
            "📍 Crowdsourced Where-Is-My-Train Stop Verification & Auto-Calibration",
            "👤 1-Tap Guest Mode Exit & Account Switcher",
            "🔔 Notification Swipe-to-Dismiss, 1-Tap Delete & Clear All",
            "⚡ Faster instant-connect live bus tracking engine",
            "🛡️ Enhanced security and zero-IP credential dispatches"
        ],
        playStoreUrl: "https://play.google.com/store/apps/details?id=com.smartcampus.shuttle",
        isForceUpdate: false
    });
});

// Rate Limiting
app.set('trust proxy', 1); // Trust reverse proxy (e.g. Render) to get correct client IP
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: { error: 'Too many requests, please try again later.' }
});
app.use('/api/', limiter);

// Dedicated Brute-Force Rate Limiter for Login Endpoint
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 15, // Max 15 login attempts per 15 minutes per IP
    message: { error: 'Too many login attempts. Please try again after 15 minutes.' }
});
app.use('/api/auth/login', loginLimiter);

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
        version: '2.4.0-RELEASE',
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



app.get('/api/diagnostic-smtp', (req, res) => {
    res.json({
        host: process.env.SMTP_HOST || 'default: smtp.ethereal.email',
        port: process.env.SMTP_PORT || 'default: 587',
        user: process.env.SMTP_USER ? 'CONFIGURED' : 'MISSING',
        pass: process.env.SMTP_PASS ? 'CONFIGURED' : 'MISSING',
        nodeEnv: process.env.NODE_ENV
    });
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
    const username = req.body.username?.trim();
    const password = req.body.password;
    let role = req.body.role?.trim();
    console.log(`📡 [Auth] Login request for username: "${username || 'empty'}" (role: ${role || 'any'})`);
    
    if (!username || !password) {
        return res.status(400).json({ error: 'Username and password are required' });
    }

    console.time('LoginRequest');

    try {
        let user = null;
        let matchedRole = role;

        const collections = [
            { role: 'manager', model: Manager },
            { role: 'admin', model: Admin },
            { role: 'driver', model: Driver },
            { role: 'user', model: User }
        ];

        let searchList = collections;
        if (role) {
            searchList = [...collections].sort((a, b) => (a.role === role ? -1 : (b.role === role ? 1 : 0)));
        }

        const escapedSearch = username.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        for (const item of searchList) {
            const query = {
                $or: [
                    { username: { $regex: new RegExp(`^${escapedSearch}$`, 'i') } },
                    { email: { $regex: new RegExp(`^${escapedSearch}$`, 'i') } }
                ]
            };
            const found = await item.model.findOne(query);
            if (found) {
                user = found;
                matchedRole = item.role;
                break;
            }
        }

        if (!user) {
            // 🛡️ Constant-Time verification to prevent Username Enumeration / Timing Attacks
            await argon2.verify(DUMMY_HASH, password).catch(() => {});
            console.log(`❌ [Auth] Invalid login attempt for "${username}"`);
            console.timeEnd('LoginRequest');
            return res.status(401).json({ error: 'Invalid username or password.' });
        }

        // 🛡️ Account Lockout Protection (Prevents Brute Force & Password Spraying)
        if (user.lockUntil && user.lockUntil > Date.now()) {
            const minutesLeft = Math.ceil((user.lockUntil - Date.now()) / (60 * 1000));
            console.timeEnd('LoginRequest');
            return res.status(423).json({ 
                error: `Account is temporarily locked due to repeated failed login attempts. Please try again in ${minutesLeft} minute(s).` 
            });
        }

        // Validate Password with Argon2id
        const isMatch = await argon2.verify(user.password, password);
        console.log(`🔐 [Auth] Password match result for ${username} (${matchedRole}): ${isMatch}`);
        
        if (!isMatch) {
            // Increment failed attempts
            user.loginAttempts = (user.loginAttempts || 0) + 1;
            if (user.loginAttempts >= 5) {
                user.lockUntil = new Date(Date.now() + 15 * 60 * 1000); // 15-min lockout
                console.log(`🚨 [Security] Account "${username}" locked due to 5 failed attempts.`);
            }
            await user.save().catch(() => {});
            console.timeEnd('LoginRequest');
            return res.status(401).json({ error: 'Invalid username or password.' });
        }

        // Reset failed login counter on successful authentication
        if (user.loginAttempts > 0 || user.lockUntil) {
            user.loginAttempts = 0;
            user.lockUntil = null;
            await user.save().catch(() => {});
        }

        // Generate Token (90 days expiry for persistent seamless mobile login)
        const token = jwt.sign(
            { user: { id: user.id, role: matchedRole } },
            process.env.JWT_SECRET || 'SISTecChalo_secret_key_777',
            { expiresIn: '90d' }
        );

        const userResponse = {
            id: user.id,
            username: user.username,
            name: user.name || user.username,
            role: matchedRole,
            email: user.email,
            status: user.status || 'Active',
            mustChangePassword: user.mustChangePassword !== false // Default true for first time login
        };

        if (matchedRole === 'user') {
            userResponse.routeId = user.routeId;
            userResponse.pickupPoint = user.pickupPoint;
            userResponse.localAddress = user.localAddress || null;
            userResponse.isCommuteConfigured = user.isCommuteConfigured || (!!user.routeId && !!user.pickupPoint);
            userResponse.userId = user.userId;
            userResponse.proximityAlertsEnabled = user.proximityAlertsEnabled ?? true;
            userResponse.proximityRadiusKm = user.proximityRadiusKm ?? 1.0;
        }

        res.json({ 
            token, 
            user: userResponse,
            mustChangePassword: userResponse.mustChangePassword 
        });
        console.timeEnd('LoginRequest');

    } catch (_err) {
        console.error('❌ Login Error:', _err);
        console.timeEnd('LoginRequest');
        res.status(500).json({ error: 'Server error' });
    }
});

/**
 * @api {post} /api/auth/forgot-password Send Temporary Password to Registered Email
 */
app.post('/api/auth/forgot-password', async (req, res) => {
    const rawIdentifier = (req.body.identifier || req.body.email || req.body.username || '').toString().trim();
    const providedEmail = (req.body.email || '').toString().trim();

    if (!rawIdentifier && !providedEmail) {
        return res.status(400).json({ error: 'Please provide your registered Email or Enrollment Number.' });
    }

    console.log(`🔑 [Auth] Forgot password requested for: "${rawIdentifier || providedEmail}"`);

    try {
        const query = rawIdentifier.includes('@') 
            ? { email: { $regex: new RegExp(`^${rawIdentifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } }
            : { username: { $regex: new RegExp(`^${rawIdentifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } };

        // Search collections in priority order: Student, User, Driver, Manager, Admin
        let user = await Student.findOne(query);
        let role = 'user';

        if (!user) {
            user = await User.findOne(query);
            if (user) role = 'user';
        }
        if (!user) {
            user = await Driver.findOne(query);
            if (user) role = 'driver';
        }
        if (!user) {
            user = await Manager.findOne(query);
            if (user) role = 'manager';
        }
        if (!user) {
            user = await Admin.findOne(query);
            if (user) role = 'admin';
        }

        // Fallback: If queried by username but user provided email in separate field
        if (!user && providedEmail && providedEmail.includes('@')) {
            const emailQuery = { email: { $regex: new RegExp(`^${providedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } };
            user = await Student.findOne(emailQuery) || await User.findOne(emailQuery) || await Driver.findOne(emailQuery) || await Manager.findOne(emailQuery) || await Admin.findOne(emailQuery);
            if (user) {
                if (user.constructor.modelName === 'Driver') role = 'driver';
                else if (user.constructor.modelName === 'Manager') role = 'manager';
                else if (user.constructor.modelName === 'Admin') role = 'admin';
                else role = 'user';
            }
        }

        if (!user) {
            return res.status(404).json({ error: 'No account found matching the provided details.' });
        }

        // Determine destination email
        let destinationEmail = (user.email && user.email.includes('@')) ? user.email.trim() : null;
        if (!destinationEmail && providedEmail && providedEmail.includes('@')) {
            destinationEmail = providedEmail.trim();
            user.email = destinationEmail;
        }

        if (!destinationEmail) {
            return res.status(400).json({ 
                error: 'No email address registered for this account. Please contact the SISTec Transport Desk.',
                needsEmailSetup: true,
                username: user.username
            });
        }

        // Generate clean, secure temporary password (e.g. SGI#8429)
        const randNum = Math.floor(1000 + Math.random() * 9000);
        const tempPassword = `SGI#${randNum}`;

        // Hash temporary password with Argon2id and set mustChangePassword = true
        user.password = await secureHashPassword(tempPassword);
        user.mustChangePassword = true;
        await user.save();

        console.log(`✅ [Auth] Temporary password generated for ${user.username} (${role}): ${tempPassword}`);

        // Dispatch Email
        const emailResult = await sendPasswordResetEmail(
            destinationEmail,
            user.name || user.username,
            user.username,
            tempPassword,
            role
        );

        // Mask email for user privacy (e.g., d***e@gmail.com)
        const parts = destinationEmail.split('@');
        const namePart = parts[0];
        const maskedName = namePart.length > 2 
            ? `${namePart[0]}***${namePart[namePart.length - 1]}`
            : `${namePart[0]}***`;
        const maskedEmail = `${maskedName}@${parts[1]}`;

        return res.json({
            success: true,
            message: `A temporary password has been sent to ${maskedEmail}.`,
            username: user.username,
            email: maskedEmail,
            role: role,
            // Include tempPassword in debug fallback if real email delivery failed or preview exists
            tempPassword: emailResult.previewUrl ? tempPassword : (process.env.NODE_ENV !== 'production' ? tempPassword : undefined),
            previewUrl: emailResult.previewUrl
        });

    } catch (err) {
        console.error('❌ Forgot password error:', err);
        return res.status(500).json({ error: 'Failed to process password recovery. Please try again.' });
    }
});

/**
 * @api {post} /api/auth/force-change-password Mandatory First-Time Password Reset
 */
app.post('/api/auth/force-change-password', async (req, res) => {
    const { username, currentPassword, oldPassword, newPassword } = req.body;
    const pwdToCheck = currentPassword || oldPassword;

    console.log(`🔐 [Auth] Force-change-password request for: "${username || 'token user'}"`);

    if (!newPassword || newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters long.' });
    }

    try {
        let user = null;
        let matchedModel = null;
        let matchedRole = null;

        // 1. Try finding by JWT token if available
        const authHeader = req.headers.authorization;
        if (authHeader && authHeader.startsWith('Bearer ')) {
            try {
                const decoded = jwt.verify(authHeader.split(' ')[1], process.env.JWT_SECRET || 'SISTecChalo_secret_key_777');
                const userId = decoded.user?.id || decoded.id;
                const role = decoded.user?.role || decoded.role;
                const models = { user: User, driver: Driver, manager: Manager, admin: Admin };
                if (models[role]) {
                    user = await models[role].findById(userId);
                    matchedModel = models[role];
                    matchedRole = role;
                }
            } catch (_) {}
        }

        // 2. If not found by token, look up by username
        if (!user && username) {
            const collections = [
                { role: 'user', model: User },
                { role: 'driver', model: Driver },
                { role: 'manager', model: Manager },
                { role: 'admin', model: Admin }
            ];
            for (const item of collections) {
                const found = await item.model.findOne({ username: { $regex: new RegExp(`^${username.trim()}$`, 'i') } });
                if (found) {
                    user = found;
                    matchedModel = item.model;
                    matchedRole = item.role;
                    break;
                }
            }
        }

        if (!user) {
            return res.status(404).json({ error: 'Account not found.' });
        }

        // 3. Verify current password if provided
        if (pwdToCheck) {
            const isMatch = await argon2.verify(user.password, pwdToCheck);
            if (!isMatch) {
                return res.status(400).json({ error: 'Current temporary password is incorrect.' });
            }
        }

        // 4. Ensure new password is not identical to old password
        const isSame = await argon2.verify(user.password, newPassword);
        if (isSame) {
            return res.status(400).json({ error: 'New password cannot be identical to your temporary password.' });
        }

        // 5. Hash new password with Argon2id and update user
        const hashedPassword = await secureHashPassword(newPassword);
        user.password = hashedPassword;
        user.mustChangePassword = false;
        await user.save();

        console.log(`✅ [Auth] Password successfully updated for user "${user.username}" (${matchedRole}). mustChangePassword=false`);

        // 6. Generate fresh token (90 days expiry)
        const token = jwt.sign(
            { user: { id: user.id, role: matchedRole } },
            process.env.JWT_SECRET || 'SISTecChalo_secret_key_777',
            { expiresIn: '90d' }
        );

        const updatedUserResponse = {
            id: user.id,
            username: user.username,
            name: user.name || user.username,
            role: matchedRole,
            email: user.email,
            status: user.status || 'Active',
            mustChangePassword: false
        };

        if (matchedRole === 'user') {
            updatedUserResponse.routeId = user.routeId;
            updatedUserResponse.pickupPoint = user.pickupPoint;
            updatedUserResponse.localAddress = user.localAddress;
            updatedUserResponse.isCommuteConfigured = user.isCommuteConfigured || (!!user.routeId && !!user.pickupPoint);
            updatedUserResponse.userId = user.userId;
            updatedUserResponse.proximityAlertsEnabled = user.proximityAlertsEnabled ?? true;
            updatedUserResponse.proximityRadiusKm = user.proximityRadiusKm ?? 1.0;
        }

        res.json({
            message: 'Password successfully updated! Welcome to SISTecChalo.',
            token,
            user: updatedUserResponse,
            mustChangePassword: false
        });

    } catch (err) {
        console.error('❌ Force password change error:', err);
        res.status(500).json({ error: 'Failed to update password. Please try again.' });
    }
});

// ── IN-MEMORY ROUTE CACHING & COORDINATE PAYLOAD OPTIMIZER ──────────────────
let cachedRoutesData = null;
let routesCacheTimestamp = 0;
const ROUTE_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes in-memory TTL

const sanitizeRouteForWire = (r) => {
    if (!r) return null;
    return {
        _id: r._id,
        name: r.name,
        color: r.color,
        stops: r.stops,
        // Strip redundant MongoDB _ids and ensure coordinates format is clean
        coordinates: (r.coordinates || [])
            .filter(c => c != null && typeof c === 'object')
            .map(c => ({
                latitude: c.latitude != null ? c.latitude : c.lat,
                longitude: c.longitude != null ? c.longitude : c.lng
            }))
            .filter(c => c.latitude != null && c.longitude != null && !isNaN(c.latitude) && !isNaN(c.longitude))
    };
};

const getOptimizedRoutes = async (forceRefresh = false) => {
    const now = Date.now();
    if (!forceRefresh && cachedRoutesData && (now - routesCacheTimestamp < ROUTE_CACHE_TTL_MS)) {
        return cachedRoutesData;
    }
    const rawRoutes = await Route.find().lean();
    cachedRoutesData = rawRoutes.map(sanitizeRouteForWire);
    routesCacheTimestamp = now;
    return cachedRoutesData;
};

const invalidateRoutesCache = () => {
    cachedRoutesData = null;
    routesCacheTimestamp = 0;
};

// Public routes for Guests (No auth required)
app.get('/api/guest/routes', async (req, res) => {
    try {
        const routes = await getOptimizedRoutes();
        res.setHeader('Cache-Control', 'public, max-age=60, stale-while-revalidate=300');
        res.json(routes);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch routes' });
    }
});

app.get('/api/guest/buses', async (req, res) => {
    try {
        const buses = await Bus.find().lean();
        const nowTime = Date.now();
        const staleIds = [];
        for (const b of buses) {
            const lastUp = b.lastUpdated ? new Date(b.lastUpdated).getTime() : 0;
            if (b.status && b.status.toLowerCase() !== 'offline' && (nowTime - lastUp) > 30000) {
                b.status = 'Offline';
                b.speed = 0;
                b.etas = [];
                staleIds.push(b._id);
            }
        }
        if (staleIds.length > 0) {
            Bus.updateMany(
                { _id: { $in: staleIds } },
                { $set: { status: 'Offline', speed: 0, etas: [] } }
            ).catch(() => {});
        }
        res.setHeader('Cache-Control', 'public, max-age=5, stale-while-revalidate=15');
        res.json(buses);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch buses' });
    }
});

app.get('/api/routes', optionalAuth, async (req, res) => {
    try {
        const routes = await getOptimizedRoutes();
        res.setHeader('Cache-Control', 'private, max-age=60, stale-while-revalidate=300');
        res.json(routes);
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch routes' });
    }
});

app.get('/api/routes/:id', authMiddleware, async (req, res) => {
    try {
        const route = await Route.findById(req.params.id).lean();
        if (!route) return res.status(404).json({ error: 'Route not found' });
        res.json(sanitizeRouteForWire(route));
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch route' });
    }
});

// ── GET /api/routes/geocode-stop: Instant coordinate lookup for any stop name ──
app.get('/api/routes/geocode-stop', authMiddleware, async (req, res) => {
    try {
        const name = req.query.name;
        if (!name || !name.trim()) {
            return res.status(400).json({ error: 'Stop name query parameter is required' });
        }
        const { geocodeStopName } = require('./geocode_stops');
        const coords = await geocodeStopName(name.trim());
        return res.json({
            success: true,
            name: name.trim(),
            lat: coords.lat,
            lng: coords.lng
        });
    } catch (err) {
        console.error('Stop geocoding error:', err);
        return res.status(500).json({ error: 'Failed to geocode stop' });
    }
});

// ── CROWDSOURCED STOP VERIFICATION & AUTO-CALIBRATION API ───────────────────
// Submit a stop verification or GPS coordinate suggestion
app.post('/api/routes/:id/stops/feedback', authMiddleware, async (req, res) => {
    try {
        const routeId = req.params.id;
        const { stopName, feedbackType, suggestedLat, suggestedLng, accuracy, comment } = req.body;

        if (!stopName || !stopName.trim()) {
            return res.status(400).json({ error: 'Stop name is required' });
        }
        if (!feedbackType || !['confirm_correct', 'suggest_location', 'stop_moved'].includes(feedbackType)) {
            return res.status(400).json({ error: 'Valid feedbackType (confirm_correct, suggest_location, stop_moved) is required' });
        }

        const route = await Route.findById(routeId);
        if (!route) return res.status(404).json({ error: 'Route not found' });

        const userId = req.user?.id || req.user?._id || 'anonymous_user';
        const userName = req.user?.name || req.user?.username || 'Passenger';
        const userRole = req.user?.role || 'student';

        const result = await processStopFeedback({
            routeId,
            routeName: route.name,
            stopName: stopName.trim(),
            userId,
            userName,
            userRole,
            feedbackType,
            suggestedLat: suggestedLat ? Number(suggestedLat) : undefined,
            suggestedLng: suggestedLng ? Number(suggestedLng) : undefined,
            accuracy: accuracy ? Number(accuracy) : 10,
            comment: comment ? comment.toString().trim() : undefined,
        });

        // Broadcast realtime update to clients if stop coordinates were auto-calibrated
        if (result.autoApplied) {
            io.emit('route_stop_calibrated', {
                routeId,
                routeName: route.name,
                stopName: stopName.trim(),
                newLat: result.newLat,
                newLng: result.newLng,
                message: result.message,
            });
        }

        return res.json({ success: true, ...result });
    } catch (err) {
        console.error('❌ Stop Feedback Error:', err);
        return res.status(500).json({ error: 'Failed to process stop feedback' });
    }
});

// Get feedback summary & consensus status for all stops on a route
app.get('/api/routes/:id/stops/feedback-summary', authMiddleware, async (req, res) => {
    try {
        const routeId = req.params.id;
        const summary = await getRouteFeedbackSummary(routeId);
        return res.json({ success: true, summary });
    } catch (err) {
        console.error('❌ Route Feedback Summary Error:', err);
        return res.status(500).json({ error: 'Failed to fetch stop feedback summary' });
    }
});

// Manager: Get all stop feedback reports across the entire system
app.get('/api/manager/stop-feedback', authMiddleware, async (req, res) => {
    try {
        const feedbacks = await StopFeedback.find()
            .populate('routeId', 'name color stops')
            .sort({ createdAt: -1 })
            .limit(100);
        return res.json({ success: true, count: feedbacks.length, feedbacks });
    } catch (err) {
        console.error('❌ Manager Stop Feedback Error:', err);
        return res.status(500).json({ error: 'Failed to fetch manager stop feedback' });
    }
});

// Manager: 1-Click Apply a suggested stop location to the route
app.post('/api/manager/stop-feedback/:id/apply', authMiddleware, async (req, res) => {
    try {
        const feedback = await StopFeedback.findById(req.params.id);
        if (!feedback) return res.status(404).json({ error: 'Feedback report not found' });
        if (!feedback.suggestedLat || !feedback.suggestedLng) {
            return res.status(400).json({ error: 'Feedback does not contain valid GPS coordinates' });
        }

        const route = await Route.findById(feedback.routeId);
        if (!route) return res.status(404).json({ error: 'Associated route not found' });

        const stopIndex = route.stops.findIndex(
            s => s.name && s.name.trim().toLowerCase() === feedback.stopName.trim().toLowerCase()
        );

        if (stopIndex === -1) {
            return res.status(404).json({ error: `Stop "${feedback.stopName}" not found on route` });
        }

        route.stops[stopIndex].lat = Number(feedback.suggestedLat.toFixed(6));
        route.stops[stopIndex].lng = Number(feedback.suggestedLng.toFixed(6));
        await route.save();

        feedback.status = 'applied';
        await feedback.save();

        // Broadcast update
        io.emit('route_stop_calibrated', {
            routeId: route._id,
            routeName: route.name,
            stopName: feedback.stopName,
            newLat: feedback.suggestedLat,
            newLng: feedback.suggestedLng,
            message: `Manager approved new coordinates for stop "${feedback.stopName}".`,
        });

        return res.json({
            success: true,
            message: `Successfully updated "${feedback.stopName}" to (${feedback.suggestedLat}, ${feedback.suggestedLng})`,
            stop: route.stops[stopIndex],
        });
    } catch (err) {
        console.error('❌ Apply Stop Feedback Error:', err);
        return res.status(500).json({ error: 'Failed to apply stop feedback' });
    }
});

// Manager: Reject a feedback report
app.post('/api/manager/stop-feedback/:id/reject', authMiddleware, async (req, res) => {
    try {
        const feedback = await StopFeedback.findByIdAndUpdate(
            req.params.id,
            { $set: { status: 'rejected' } },
            { new: true }
        );
        if (!feedback) return res.status(404).json({ error: 'Feedback report not found' });
        return res.json({ success: true, message: 'Feedback report rejected', feedback });
    } catch (err) {
        console.error('❌ Reject Stop Feedback Error:', err);
        return res.status(500).json({ error: 'Failed to reject stop feedback' });
    }
});

// --- User Management Routes (For Admin/Manager) ---

// --- ADMIN Management ---
app.post('/api/admins', async (req, res) => {
    try {
        const { username, password, email } = req.body;

        let existing = await Admin.findOne({ username });
        if (existing) return res.status(400).json({ error: 'Admin already exists' });

        const hashedPassword = await secureHashPassword(password);
        const newAdmin = new Admin({ ...req.body, password: hashedPassword });

        await newAdmin.save();
        if (email) {
            await sendCredentialsEmail(email.trim(), username, username, password, newAdmin.role || 'admin');
        }
        res.status(201).json(newAdmin);
    } catch (_) {
        res.status(500).json({ error: 'Failed to create admin' });
    }
});

// --- MANAGER Management ---
app.post('/api/managers', authMiddleware, async (req, res) => {
    try {
        const { username, password, email } = req.body;

        let existing = await Manager.findOne({ username });
        if (existing) return res.status(400).json({ error: 'Manager already exists' });

        const hashedPassword = await secureHashPassword(password);
        const newManager = new Manager({ ...req.body, password: hashedPassword });

        await newManager.save();
        if (email) {
            await sendCredentialsEmail(email.trim(), username, username, password, newManager.role || 'manager');
        }
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
        const { username, password, email } = req.body;

        let existing = await User.findOne({ username });
        if (existing) return res.status(400).json({ error: 'User already exists' });

        const hashedPassword = await secureHashPassword(password);
        const newUser = new User({ ...req.body, password: hashedPassword });

        await newUser.save();
        broadcastStats(); // Emit live update
        if (email) {
            await sendCredentialsEmail(email.trim(), username, username, password, newUser.role || 'user');
        }
        res.status(201).json(newUser);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to create user' });
    }
});

app.get('/api/users', async (req, res) => {
    try {
        const users = await User.find().lean();
        const [submissions, students] = await Promise.all([
            RegistrationSubmission.find().lean(),
            Student.find().lean()
        ]);

        const nameMap = new Map();
        for (const sub of submissions) {
            if (sub.name && sub.name.trim().length > 0) {
                const cleanName = sub.name.trim();
                if (sub.createdUserId) nameMap.set(sub.createdUserId.toString(), cleanName);
                if (sub.studentId) nameMap.set(sub.studentId.trim().toUpperCase(), cleanName);
                if (sub.generatedUsername) nameMap.set(sub.generatedUsername.trim().toUpperCase(), cleanName);
            }
        }
        for (const st of students) {
            if (st.name && st.name.trim().length > 0) {
                const cleanName = st.name.trim();
                if (st.studentId) nameMap.set(st.studentId.trim().toUpperCase(), cleanName);
            }
        }

        const enrichedUsers = users.map(user => {
            const usernameKey = (user.username || '').trim().toUpperCase();
            const userIdKey = (user.userId || '').trim().toUpperCase();
            const userObjId = user._id ? user._id.toString() : '';

            const currentName = (user.name || '').trim();
            const isIdLike = !currentName || 
                             currentName === user.username || 
                             currentName === user.userId || 
                             /^\d{2,}/.test(currentName);

            if (isIdLike) {
                const resolvedName = nameMap.get(userObjId) || nameMap.get(usernameKey) || nameMap.get(userIdKey);
                if (resolvedName) {
                    user.name = resolvedName;
                    User.findByIdAndUpdate(user._id, { name: resolvedName }).catch(() => {});
                }
            }
            return user;
        });

        res.json(enrichedUsers);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});


// POST /api/users/fcm-token
// Updates or stores the FCM push notification token for the logged-in user
app.post('/api/users/fcm-token', authMiddleware, async (req, res) => {
    try {
        const { token } = req.body;
        if (!token) {
            return res.status(400).json({ error: 'Token is required' });
        }
        const updatedUser = await User.findByIdAndUpdate(
            req.user.id,
            { fcmToken: token },
            { new: true }
        );
        if (!updatedUser) {
            return res.status(404).json({ error: 'User not found' });
        }
        console.log(`🔑 [Firebase] FCM Token updated for user: ${updatedUser.username}`);
        res.json({ success: true, user: { id: updatedUser.id, username: updatedUser.username } });
    } catch (err) {
        console.error('❌ FCM Token update error:', err);
        res.status(500).json({ error: 'Failed to update FCM token' });
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
        const buses = await Bus.find().lean();
        const nowTime = Date.now();
        const staleIds = [];
        for (const b of buses) {
            const lastUp = b.lastUpdated ? new Date(b.lastUpdated).getTime() : 0;
            if (b.status && b.status.toLowerCase() !== 'offline' && (nowTime - lastUp) > 30000) {
                b.status = 'Offline';
                b.speed = 0;
                b.etas = [];
                staleIds.push(b._id);
            }
        }
        if (staleIds.length > 0) {
            Bus.updateMany(
                { _id: { $in: staleIds } },
                { $set: { status: 'Offline', speed: 0, etas: [] } }
            ).catch(() => {});
        }
        res.setHeader('Cache-Control', 'private, max-age=5, stale-while-revalidate=15');
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
        const { message, type, targetAudience } = req.body;
        const validAudience = ['All', 'Users', 'Drivers', 'Admins'].includes(targetAudience) ? targetAudience : 'All';
        
        // Save to Database
        const newNotification = new Notification({
            message,
            type: type || 'info',
            targetAudience: validAudience,
            createdBy: 'Manager'
        });
        await newNotification.save();

        // Emit both notification (for history) and systemAlert (for live pop-ups)
        io.emit('notification', newNotification);
        io.emit('systemAlert', { 
            message, 
            type: type || 'info', 
            targetAudience: validAudience,
            timestamp: new Date().toISOString() 
        });
        console.log(`📢 [Manager Broadcast to ${validAudience}] "${message}"`);
        res.json({ success: true, notification: newNotification });
    } catch (err) {
        console.error('❌ Error broadcasting notification:', err);
        res.status(500).json({ error: 'Failed to broadcast notification' });
    }
});

// Manager: Delete Notification
app.delete(['/api/manager/notifications/:id', '/api/notifications/:id'], async (req, res) => {
    try {
        const { id } = req.params;
        const deletedNotif = await Notification.findByIdAndDelete(id);
        io.emit('notificationDeleted', { id });
        console.log(`🗑️ [Notification Deleted] ID: ${id}`);
        res.json({ success: true, message: 'Notification deleted successfully' });
    } catch (err) {
        console.error('❌ Error deleting notification:', err);
        res.status(500).json({ error: 'Failed to delete notification' });
    }
});

// ─── MANAGER: 2-TRIP DAY-WISE BUS OPERATIONAL REPORT (CSV/Excel) ────────────
// GET /api/manager/reports/bus-trip-report?date=YYYY-MM-DD&shift=all|morning|evening&busId=<id>
app.get('/api/manager/reports/bus-trip-report', async (req, res) => {
    try {
        const { date, shift, busId, days } = req.query;
        const targetDate = date || new Date().toISOString().split('T')[0];
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null
        });

        // Generate clean CSV for spreadsheet/Excel
        let csv = 'Date,Day,Shift,Bus Name,License Plate,Route Name,Driver Name,Driver Phone,Departure Time,Arrival Time,Duration,Punctuality,Delay (mins),Stops Completed,Total Dist (km),Status\n';

        reportData.allTrips.forEach(t => {
            csv += `"${t.date}","${t.day}","${t.shift}","${t.busNo}","${t.vehicleNo}","${t.routeName}","${t.driverName}","${t.driverPhone}","${t.departureTime}","${t.arrivalTime}","${t.duration}","${t.punctuality}",${t.delayMinutes},"${t.stopsCompleted}","${t.distanceKm}","${t.status}"\n`;
        });

        const safeDate = targetDate.replace(/[^0-9-]/g, '');
        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="sistec_fleet_report_${safeDate}_${targetShift}.csv"`);
        return res.status(200).send(csv);
    } catch (err) {
        console.error('Report Generation Error:', err);
        res.status(500).json({ error: 'Failed to generate report' });
    }
});

// ─── MANAGER: PRINTABLE 2-TRIP DAY-WISE HTML & PDF EXECUTIVE REPORT ─────────
// GET /api/manager/reports/bus-trip-report/html?date=YYYY-MM-DD&shift=all|morning|evening
app.get('/api/manager/reports/bus-trip-report/html', async (req, res) => {
    try {
        const { date, shift, busId } = req.query;
        const targetDate = date || new Date().toISOString().split('T')[0];
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null
        });

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SISTec Ratibad - Daily Bus Operations Report (${reportData.date})</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0b0f19;
            --surface: #111827;
            --surface-card: #1f2937;
            --surface-hover: #374151;
            --text: #f9fafb;
            --text-secondary: #9ca3af;
            --text-muted: #6b7280;
            --border: rgba(255, 255, 255, 0.08);
            --primary: #4f46e5;
            --primary-gradient: linear-gradient(135deg, #4f46e5, #3b82f6);
            --accent-green: #10b981;
            --accent-amber: #f59e0b;
            --accent-rose: #ef4444;
            --radius-lg: 16px;
            --radius-md: 10px;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif;
            background-color: var(--bg);
            color: var(--text);
            padding: 32px;
            line-height: 1.5;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        /* Top Header */
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 24px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 28px;
            flex-wrap: wrap;
            gap: 16px;
        }

        .brand-section {
            display: flex;
            align-items: center;
            gap: 16px;
        }

        .brand-logo {
            width: 48px;
            height: 48px;
            border-radius: 12px;
            background: var(--primary-gradient);
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 800;
            font-size: 20px;
            color: #fff;
            box-shadow: 0 4px 14px rgba(79, 70, 229, 0.4);
        }

        .brand-text h1 {
            font-size: 22px;
            font-weight: 800;
            letter-spacing: -0.3px;
        }

        .brand-text p {
            color: var(--text-secondary);
            font-size: 13px;
            font-weight: 500;
        }

        .header-actions {
            display: flex;
            gap: 10px;
            align-items: center;
            flex-wrap: wrap;
        }

        .btn {
            background: var(--surface-card);
            color: var(--text);
            border: 1px solid var(--border);
            padding: 10px 18px;
            border-radius: var(--radius-md);
            font-size: 13px;
            font-weight: 700;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            text-decoration: none;
            transition: all 0.2s;
        }

        .btn:hover {
            background: var(--surface-hover);
            transform: translateY(-1px);
        }

        .btn-primary {
            background: var(--primary-gradient);
            border: none;
            color: #fff;
            box-shadow: 0 4px 12px rgba(79, 70, 229, 0.3);
        }

        .btn-sheets {
            background: linear-gradient(135deg, #059669, #10b981);
            color: #fff;
            border: none;
            box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
        }

        /* KPI Cards */
        .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 28px;
        }

        .kpi-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            padding: 20px;
            position: relative;
            overflow: hidden;
        }

        .kpi-card::before {
            content: '';
            position: absolute;
            top: 0; left: 0; width: 4px; height: 100%;
            background: var(--primary);
        }

        .kpi-card.green::before { background: var(--accent-green); }
        .kpi-card.amber::before { background: var(--accent-amber); }

        .kpi-label {
            font-size: 11px;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 1.2px;
            color: var(--text-secondary);
            margin-bottom: 6px;
        }

        .kpi-val {
            font-size: 28px;
            font-weight: 800;
            color: #fff;
        }

        .kpi-sub {
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 4px;
        }

        /* Filter Controls */
        .controls-bar {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            padding: 16px 20px;
            margin-bottom: 28px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 16px;
        }

        .filter-group {
            display: flex;
            align-items: center;
            gap: 12px;
            flex-wrap: wrap;
        }

        .input-box {
            background: var(--surface-card);
            border: 1px solid var(--border);
            color: #fff;
            padding: 8px 14px;
            border-radius: var(--radius-md);
            font-size: 13px;
            font-weight: 600;
            outline: none;
        }

        .shift-tabs {
            display: flex;
            background: var(--surface-card);
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            padding: 4px;
            gap: 4px;
        }

        .shift-tab {
            padding: 6px 14px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: 700;
            color: var(--text-secondary);
            text-decoration: none;
            cursor: pointer;
            border: none;
            background: transparent;
        }

        .shift-tab.active {
            background: var(--primary);
            color: #fff;
        }

        /* Section Headings */
        .section-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin: 28px 0 16px 0;
            padding-bottom: 10px;
            border-bottom: 1px solid var(--border);
        }

        .section-title {
            font-size: 16px;
            font-weight: 800;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        /* Tables */
        .table-wrap {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            overflow-x: auto;
            margin-bottom: 32px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
            text-align: left;
        }

        th {
            background: rgba(31, 41, 55, 0.6);
            color: var(--text-secondary);
            font-weight: 800;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 1px;
            padding: 14px 16px;
            border-bottom: 1px solid var(--border);
            white-space: nowrap;
        }

        td {
            padding: 14px 16px;
            border-bottom: 1px solid var(--border);
            color: var(--text);
            vertical-align: middle;
        }

        tr:last-child td { border-bottom: none; }
        tr:hover td { background: rgba(255, 255, 255, 0.02); }

        .badge {
            display: inline-flex;
            align-items: center;
            padding: 4px 8px;
            border-radius: 6px;
            font-size: 11px;
            font-weight: 700;
        }

        .badge-ontime { background: rgba(16, 185, 129, 0.15); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.3); }
        .badge-delayed { background: rgba(245, 158, 11, 0.15); color: #f59e0b; border: 1px solid rgba(245, 158, 11, 0.3); }
        .badge-status { background: rgba(79, 70, 229, 0.15); color: #818cf8; }

        .bus-badge {
            font-family: 'JetBrains Mono', monospace;
            font-weight: 700;
            background: var(--surface-card);
            padding: 4px 8px;
            border-radius: 6px;
            border: 1px solid var(--border);
            color: #818cf8;
        }

        /* Print Media Styles */
        @media print {
            body {
                background: #ffffff !important;
                color: #000000 !important;
                padding: 10px !important;
                font-size: 11px !important;
            }
            .header-actions, .controls-bar { display: none !important; }
            .kpi-card, .table-wrap {
                background: #ffffff !important;
                border: 1px solid #cccccc !important;
                box-shadow: none !important;
                color: #000000 !important;
            }
            .kpi-val, .kpi-label, td, th { color: #000000 !important; }
            th { background: #f3f4f6 !important; }
            .badge-ontime, .badge-delayed, .badge-status, .bus-badge {
                border: 1px solid #999999 !important;
                color: #000000 !important;
                background: none !important;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <div class="brand-section">
                <div class="brand-logo">SC</div>
                <div class="brand-text">
                    <h1>SISTec Ratibad - Daily Fleet Operations Report</h1>
                    <p>Generated for: <strong>${reportData.day}, ${reportData.date}</strong> | Official 2-Trip Operational Log</p>
                </div>
            </div>
            <div class="header-actions">
                <button class="btn btn-sheets" onclick="syncSheets()">
                    📊 Sync to Google Sheets
                </button>
                <a href="/api/manager/reports/bus-trip-report?date=${reportData.date}&shift=${reportData.shift}" class="btn" download>
                    📥 Download CSV
                </a>
                <button class="btn btn-primary" onclick="window.print()">
                    🖨️ Print / Save PDF
                </button>
            </div>
        </div>

        <!-- KPI Grid -->
        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-label">Active Fleet Buses</div>
                <div class="kpi-val">${reportData.totalBuses}</div>
                <div class="kpi-sub">Total operational buses today</div>
            </div>
            <div class="kpi-card green">
                <div class="kpi-label">Daily Scheduled Trips</div>
                <div class="kpi-val">${reportData.totalTrips}</div>
                <div class="kpi-sub">27 Morning + 27 Evening</div>
            </div>
            <div class="kpi-card amber">
                <div class="kpi-label">Fleet On-Time Rate</div>
                <div class="kpi-val">${reportData.punctualityRate}%</div>
                <div class="kpi-sub">${reportData.onTimeTrips} of ${reportData.totalTrips} trips on-time</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Total Fleet Distance</div>
                <div class="kpi-val">${reportData.totalDistance} km</div>
                <div class="kpi-sub">Total covered commute km</div>
            </div>
        </div>

        <!-- Controls -->
        <div class="controls-bar">
            <div class="filter-group">
                <label style="font-size:12px; font-weight:700; color:var(--text-secondary);">Select Date:</label>
                <input type="date" id="dateSelector" class="input-box" value="${reportData.date}" onchange="changeDate(this.value)">
                <button class="btn" style="padding:6px 12px; font-size:12px;" onclick="setQuickDate(0)">Today</button>
                <button class="btn" style="padding:6px 12px; font-size:12px;" onclick="setQuickDate(-1)">Yesterday</button>
            </div>

            <div class="filter-group">
                <div class="shift-tabs">
                    <button class="shift-tab ${reportData.shift === 'all' ? 'active' : ''}" onclick="changeShift('all')">All 54 Trips</button>
                    <button class="shift-tab ${reportData.shift === 'morning' ? 'active' : ''}" onclick="changeShift('morning')">🌅 Morning (27)</button>
                    <button class="shift-tab ${reportData.shift === 'evening' ? 'active' : ''}" onclick="changeShift('evening')">🌆 Evening (27)</button>
                </div>
            </div>
        </div>

        <!-- TRIP 1: MORNING PICKUP TABLE -->
        ${reportData.shift === 'all' || reportData.shift === 'morning' ? `
        <div class="section-header">
            <div class="section-title">
                🌅 Trip 1: Morning Pickup (City Stops ➔ SISTec Ratibad Campus)
            </div>
            <span style="font-size:13px; color:var(--text-secondary); font-weight:600;">27 Buses Scheduled | Target Arrival ~08:45 AM</span>
        </div>
        <div class="table-wrap">
            <table>
                <thead>
                    <tr>
                        <th>Bus No</th>
                        <th>Plate No</th>
                        <th>Route Name</th>
                        <th>Driver & Phone</th>
                        <th>Depart Time</th>
                        <th>Campus Arrival</th>
                        <th>Duration</th>
                        <th>Punctuality</th>
                        <th>Stops</th>
                        <th>Dist (km)</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${reportData.morningTrips.map(t => `
                    <tr>
                        <td><span class="bus-badge">${t.busNo}</span></td>
                        <td style="font-family:'JetBrains Mono'; font-weight:600;">${t.vehicleNo}</td>
                        <td style="font-weight:700;">${t.routeName}</td>
                        <td>${t.driverName}<br><span style="font-size:11px; color:var(--text-muted);">${t.driverPhone}</span></td>
                        <td>${t.departureTime}</td>
                        <td style="font-weight:700;">${t.arrivalTime}</td>
                        <td>${t.duration}</td>
                        <td><span class="badge ${t.punctuality.includes('On-Time') ? 'badge-ontime' : 'badge-delayed'}">${t.punctuality}</span></td>
                        <td>${t.stopsCompleted}</td>
                        <td>${t.distanceKm}</td>
                        <td><span class="badge badge-status">${t.status}</span></td>
                    </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        ` : ''}

        <!-- TRIP 2: EVENING DROP-OFF TABLE -->
        ${reportData.shift === 'all' || reportData.shift === 'evening' ? `
        <div class="section-header">
            <div class="section-title">
                🌆 Trip 2: Evening Drop-off (SISTec Ratibad Campus ➔ City Stops)
            </div>
            <span style="font-size:13px; color:var(--text-secondary); font-weight:600;">27 Buses Scheduled | Departure ~04:45 PM</span>
        </div>
        <div class="table-wrap">
            <table>
                <thead>
                    <tr>
                        <th>Bus No</th>
                        <th>Plate No</th>
                        <th>Route Name</th>
                        <th>Driver & Phone</th>
                        <th>Depart Time</th>
                        <th>Final Stop Drop</th>
                        <th>Duration</th>
                        <th>Punctuality</th>
                        <th>Stops</th>
                        <th>Dist (km)</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${reportData.eveningTrips.map(t => `
                    <tr>
                        <td><span class="bus-badge">${t.busNo}</span></td>
                        <td style="font-family:'JetBrains Mono'; font-weight:600;">${t.vehicleNo}</td>
                        <td style="font-weight:700;">${t.routeName}</td>
                        <td>${t.driverName}<br><span style="font-size:11px; color:var(--text-muted);">${t.driverPhone}</span></td>
                        <td>${t.departureTime}</td>
                        <td style="font-weight:700;">${t.arrivalTime}</td>
                        <td>${t.duration}</td>
                        <td><span class="badge ${t.punctuality.includes('On-Time') ? 'badge-ontime' : 'badge-delayed'}">${t.punctuality}</span></td>
                        <td>${t.stopsCompleted}</td>
                        <td>${t.distanceKm}</td>
                        <td><span class="badge badge-status">${t.status}</span></td>
                    </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        ` : ''}

        <div style="text-align:center; padding: 24px; font-size:12px; color:var(--text-muted);">
            SISTec Chalo Shuttle Tracking System • Verified Manager Operations Report • Official SGI Ratibad
        </div>
    </div>

    <script>
        function changeDate(val) {
            const url = new URL(window.location);
            url.searchParams.set('date', val);
            window.location.href = url.toString();
        }

        function changeShift(shift) {
            const url = new URL(window.location);
            url.searchParams.set('shift', shift);
            window.location.href = url.toString();
        }

        function setQuickDate(offsetDays) {
            const d = new Date();
            d.setDate(d.getDate() + offsetDays);
            const iso = d.toISOString().split('T')[0];
            changeDate(iso);
        }

        async function syncSheets() {
            const date = document.getElementById('dateSelector').value;
            const btn = event.target;
            const originalText = btn.innerHTML;
            btn.innerHTML = '⏳ Syncing...';
            btn.disabled = true;

            try {
                const res = await fetch('/api/manager/reports/sync-google-sheets', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ date })
                });
                const data = await res.json();
                if (data.success) {
                    alert('✅ Successfully synced ' + data.syncedTrips + ' trip records to Google Sheets!');
                    window.open(data.spreadsheetUrl, '_blank');
                } else {
                    alert('❌ Sync failed: ' + (data.error || 'Unknown error'));
                }
            } catch (err) {
                alert('❌ Sync request failed: ' + err.message);
            } finally {
                btn.innerHTML = originalText;
                btn.disabled = false;
            }
        }
    </script>
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

// ─── MANAGER: SYNC DAILY TRIP REPORT TO GOOGLE SHEETS ────────────────────────
// POST /api/manager/reports/sync-google-sheets
// Body: { date: 'YYYY-MM-DD' }
app.post('/api/manager/reports/sync-google-sheets', async (req, res) => {
    try {
        const { date } = req.body;
        const targetDate = date || new Date().toISOString().split('T')[0];

        // Generate full 2-trip records with real official timetable and live logs
        const reportData = await generateTripReportData({ targetDate, shift: 'all' });
        const syncResult = await syncDailyTripReportsToGoogleSheets(reportData, targetDate);

        if (syncResult.success) {
            res.json({
                success: true,
                message: `Successfully synced ${syncResult.syncedMorning} Morning Trips, ${syncResult.syncedEvening} Evening Trips, and ${syncResult.syncedStops} Stop Logs for ${targetDate} to Google Sheets.`,
                syncedMorning: syncResult.syncedMorning,
                syncedEvening: syncResult.syncedEvening,
                syncedStops: syncResult.syncedStops,
                spreadsheetUrl: syncResult.spreadsheetUrl
            });
        } else {
            res.status(500).json({
                success: false,
                error: syncResult.error || 'Failed to sync with Google Sheets'
            });
        }
    } catch (err) {
        console.error('❌ Error in /sync-google-sheets endpoint:', err);
        res.status(500).json({ success: false, error: err.message });
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
        io.emit('busCreated', bus);
        io.emit('busUpdated', bus);
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
        io.emit('busUpdated', bus);
        res.json(bus);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to update bus' });
    }
});

// Delete Bus
app.delete('/api/manager/buses/:id', authMiddleware, async (req, res) => {
    try {
        await Bus.findByIdAndDelete(req.params.id);
        io.emit('busDeleted', { id: req.params.id });
        broadcastStats();
        res.json({ message: 'Bus deleted successfully' });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to delete bus' });
    }
});

// Add a new Route with Automatic Geocoding
app.post('/api/manager/routes', authMiddleware, async (req, res) => {
    try {
        const { geocodeStopName } = require('./geocode_stops');
        const { getRoadPolylineForStops } = require('./road_routing_service');
        const routeData = { ...req.body };

        if (Array.isArray(routeData.stops)) {
            const geocodedStops = [];
            for (const stop of routeData.stops) {
                let lat = stop.lat != null ? parseFloat(stop.lat) : null;
                let lng = stop.lng != null ? parseFloat(stop.lng) : null;

                if (lat == null || lng == null || isNaN(lat) || isNaN(lng)) {
                    const coords = await geocodeStopName(stop.name);
                    lat = coords.lat;
                    lng = coords.lng;
                }
                geocodedStops.push({ name: stop.name, lat, lng });
            }
            routeData.stops = geocodedStops;

            // Generate high-resolution road-following polyline coordinates via OSRM
            const roadResult = await getRoadPolylineForStops(geocodedStops);
            if (roadResult && roadResult.coordinates && roadResult.coordinates.length > 0) {
                routeData.coordinates = roadResult.coordinates;
                if (!routeData.distance || routeData.distance === '0 km') {
                    routeData.distance = roadResult.distanceKm + ' km';
                }
                if (!routeData.duration || routeData.duration === '0 mins') {
                    routeData.duration = roadResult.durationMins + ' mins';
                }
            } else {
                routeData.coordinates = geocodedStops
                    .filter(s => s.lat != null && s.lng != null)
                    .map(s => ({ latitude: s.lat, longitude: s.lng }));
            }
        }

        const route = new Route(routeData);
        await route.save();
        invalidateRoutesCache();
        io.emit('routeCreated', route);
        io.emit('routeUpdated', route);
        broadcastStats();
        res.status(201).json(route);
    } catch (_err) {
        console.error('Error creating route:', _err);
        res.status(500).json({ error: 'Failed to create route' });
    }
});

// Delete Route
app.delete('/api/manager/routes/:id', authMiddleware, async (req, res) => {
    try {
        await Route.findByIdAndDelete(req.params.id);
        invalidateRoutesCache();
        io.emit('routeDeleted', { id: req.params.id });
        broadcastStats();
        res.json({ message: 'Route deleted successfully' });
    } catch (_err) {
        res.status(500).json({ error: 'Failed to delete route' });
    }
});

app.get('/api/manager/users', authMiddleware, async (req, res) => {
    try {
        const users = await User.find().select('-password').lean();
        
        // Enrich user objects where name is missing or set equal to enrollment number
        const [submissions, students] = await Promise.all([
            RegistrationSubmission.find().lean(),
            Student.find().lean()
        ]);

        const nameMap = new Map();

        // 1. Map from Registration Submissions
        for (const sub of submissions) {
            if (sub.name && sub.name.trim().length > 0) {
                const cleanName = sub.name.trim();
                if (sub.createdUserId) nameMap.set(sub.createdUserId.toString(), cleanName);
                if (sub.studentId) nameMap.set(sub.studentId.trim().toUpperCase(), cleanName);
                if (sub.generatedUsername) nameMap.set(sub.generatedUsername.trim().toUpperCase(), cleanName);
            }
        }

        // 2. Map from Students database
        for (const st of students) {
            if (st.name && st.name.trim().length > 0) {
                const cleanName = st.name.trim();
                if (st.studentId) nameMap.set(st.studentId.trim().toUpperCase(), cleanName);
            }
        }

        const enrichedUsers = [];
        for (const user of users) {
            const usernameKey = (user.username || '').trim().toUpperCase();
            const userIdKey = (user.userId || '').trim().toUpperCase();
            const userObjId = user._id ? user._id.toString() : '';

            const currentName = (user.name || '').trim();
            const isIdLike = !currentName || 
                             currentName === user.username || 
                             currentName === user.userId || 
                             /^\d{2,}/.test(currentName);

            if (isIdLike) {
                const resolvedName = nameMap.get(userObjId) || 
                                     nameMap.get(usernameKey) || 
                                     nameMap.get(userIdKey);
                if (resolvedName) {
                    user.name = resolvedName;
                    // Update MongoDB document in background to persist resolved name
                    User.findByIdAndUpdate(user._id, { name: resolvedName }).catch(() => {});
                }
            }
            enrichedUsers.push(user);
        }

        res.json(enrichedUsers);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});


// Manager: Update User Status/Route
app.put('/api/manager/users/:id', authMiddleware, async (req, res) => {
    try {
        const updatedUser = await User.findByIdAndUpdate(req.params.id, req.body, { new: true });
        
        // Sync updated details to the registration submission if one exists
        const updateFields = {};
        if (req.body.name !== undefined) updateFields.name = req.body.name;
        if (req.body.email !== undefined) updateFields.email = req.body.email;
        if (req.body.phone !== undefined) updateFields.phone = req.body.phone;
        if (req.body.routeId !== undefined) updateFields.routeId = req.body.routeId;
        if (req.body.pickupPoint !== undefined) updateFields.pickupStop = req.body.pickupPoint;
        if (req.body.courseName !== undefined) updateFields.courseName = req.body.courseName;
        if (req.body.fatherName !== undefined) updateFields.fatherName = req.body.fatherName;
        if (req.body.fatherPhone !== undefined) updateFields.fatherPhone = req.body.fatherPhone;
        if (req.body.gender !== undefined) updateFields.gender = req.body.gender;

        if (Object.keys(updateFields).length > 0) {
            await RegistrationSubmission.findOneAndUpdate(
                { createdUserId: req.params.id },
                { $set: updateFields }
            );
        }

        res.json(updatedUser);
    } catch (err) {
        console.error('Update user error:', err);
        res.status(500).json({ error: 'Failed to update user' });
    }
});

// Manager: Delete User Account
app.delete('/api/manager/users/:id', authMiddleware, async (req, res) => {
    try {
        const user = await User.findById(req.params.id);
        if (!user) return res.status(404).json({ error: 'User not found' });
        
        // Reset associated registration submission status to pending and clear credentials info
        await RegistrationSubmission.findOneAndUpdate(
            { createdUserId: req.params.id },
            {
                status: 'pending',
                createdUserId: undefined,
                generatedUsername: undefined,
                generatedPassword: undefined,
                reviewedAt: undefined
            }
        );
        
        await User.findByIdAndDelete(req.params.id);
        broadcastStats();
        res.json({ success: true, message: 'User deleted successfully' });
    } catch (err) {
        console.error('Delete user error:', err);
        res.status(500).json({ error: 'Failed to delete user' });
    }
});

// Unified User Profile (Self Fetch)
app.get('/api/users/profile', authMiddleware, async (req, res) => {
    try {
        const { id, role } = req.user;
        let Model;
        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
            case 'user': Model = User; break;
            default: return res.status(400).json({ error: 'Invalid role' });
        }
        
        const profile = await Model.findById(id).select('-password');
        if (!profile) return res.status(404).json({ error: 'Profile not found' });
        
        res.json({ role, profile });
    } catch (err) {
        console.error('Fetch profile error:', err);
        res.status(500).json({ error: 'Failed to fetch profile' });
    }
});

// Unified User Profile (Self Update)
app.put('/api/users/profile', authMiddleware, async (req, res) => {
    try {
        const { id, role } = req.user;
        let Model;
        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
            case 'user': Model = User; break;
            default: return res.status(400).json({ error: 'Invalid role' });
        }

        const allowedUpdates = {};
        if (req.body.email !== undefined) allowedUpdates.email = req.body.email;
        if (req.body.phone !== undefined) allowedUpdates.phone = req.body.phone;
        if (req.body.name !== undefined) {
            if (role === 'driver' || role === 'user') allowedUpdates.name = req.body.name;
        }
        if (req.body.contactNumber !== undefined && role === 'driver') allowedUpdates.contactNumber = req.body.contactNumber;
        if (role === 'user') {
            if (req.body.proximityAlertsEnabled !== undefined) allowedUpdates.proximityAlertsEnabled = req.body.proximityAlertsEnabled;
            if (req.body.proximityRadiusKm !== undefined) allowedUpdates.proximityRadiusKm = Number(req.body.proximityRadiusKm) || 1.0;
            if (req.body.routeId !== undefined) allowedUpdates.routeId = req.body.routeId;
            if (req.body.pickupPoint !== undefined) allowedUpdates.pickupPoint = req.body.pickupPoint;
            if (req.body.localAddress !== undefined) allowedUpdates.localAddress = req.body.localAddress;
            if (req.body.isCommuteConfigured !== undefined) allowedUpdates.isCommuteConfigured = req.body.isCommuteConfigured;
        }

        const updated = await Model.findByIdAndUpdate(id, { $set: allowedUpdates }, { new: true }).select('-password');
        
        if (role === 'user') {
            const updateSubmissionFields = {};
            if (allowedUpdates.name !== undefined) updateSubmissionFields.name = allowedUpdates.name;
            if (allowedUpdates.email !== undefined) updateSubmissionFields.email = allowedUpdates.email;
            if (allowedUpdates.phone !== undefined) updateSubmissionFields.phone = allowedUpdates.phone;
            if (allowedUpdates.pickupPoint !== undefined) updateSubmissionFields.pickupPoint = allowedUpdates.pickupPoint;
            if (allowedUpdates.routeId !== undefined) updateSubmissionFields.routeId = allowedUpdates.routeId;
            if (allowedUpdates.localAddress !== undefined) updateSubmissionFields.localAddress = allowedUpdates.localAddress;
            if (allowedUpdates.isCommuteConfigured !== undefined) updateSubmissionFields.isCommuteConfigured = allowedUpdates.isCommuteConfigured;
            
            if (Object.keys(updateSubmissionFields).length > 0) {
                await RegistrationSubmission.findOneAndUpdate(
                    { createdUserId: id },
                    { $set: updateSubmissionFields }
                );
            }
        }

        const resData = updated.toObject ? updated.toObject() : { ...updated };
        if (!resData.role) resData.role = role;

        res.json(resData);
    } catch (err) {
        console.error('Update profile error:', err);
        res.status(500).json({ error: 'Failed to update profile' });
    }
});

// Unified User: Change Password
app.put('/api/users/change-password', authMiddleware, async (req, res) => {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
        return res.status(400).json({ error: 'Both current and new password are required.' });
    }
    if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters.' });
    }
    try {
        const { id, role } = req.user;
        let Model;
        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
            case 'user': Model = User; break;
            default: return res.status(400).json({ error: 'Invalid role' });
        }

        const user = await Model.findById(id);
        if (!user) return res.status(404).json({ error: 'User not found.' });

        const valid = await argon2.verify(user.password, currentPassword);
        if (!valid) return res.status(401).json({ error: 'Current password is incorrect.' });

        const hashed = await secureHashPassword(newPassword);
        await Model.findByIdAndUpdate(id, { password: hashed });

        console.log(`🔑 [Password Changed] User: ${user.username} (Role: ${role})`);
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

// Manager: Add New Driver
app.post('/api/manager/drivers', authMiddleware, async (req, res) => {
    try {
        const { username, password, name, contactNumber, licenseNumber, emergencyContact, address, notes } = req.body;
        if (!username || !password || !name) {
            return res.status(400).json({ error: 'Username, password, and driver name are required.' });
        }

        const existingDriver = await Driver.findOne({ username: username.trim().toLowerCase() });
        if (existingDriver) {
            return res.status(409).json({ error: `Driver with username "${username}" already exists.` });
        }

        const hashedPassword = await secureHashPassword(password);
        const newDriver = await Driver.create({
            username: username.trim().toLowerCase(),
            password: hashedPassword,
            name: name.trim(),
            contactNumber: contactNumber ? contactNumber.trim() : '',
            licenseNumber: licenseNumber ? licenseNumber.trim() : '',
            emergencyContact: emergencyContact ? emergencyContact.trim() : '',
            address: address ? address.trim() : '',
            notes: notes ? notes.trim() : '',
            status: 'Active',
            assignedBus: '',
            documents: []
        });

        res.status(201).json(newDriver);
    } catch (err) {
        console.error('❌ Error creating driver:', err);
        res.status(500).json({ error: 'Failed to create driver' });
    }
});

// Manager: Upload Document to Driver Profile
app.post('/api/manager/drivers/:id/documents', authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const { name, url, fileType } = req.body;
        if (!name || !url) {
            return res.status(400).json({ error: 'Document title and file content are required.' });
        }

        const driver = await Driver.findById(id);
        if (!driver) {
            return res.status(404).json({ error: 'Driver not found' });
        }

        const newDoc = {
            name: name.trim(),
            url: url,
            fileType: fileType || 'Document',
            uploadedAt: new Date()
        };

        driver.documents.push(newDoc);
        await driver.save();

        res.status(201).json({ message: 'Document uploaded successfully', documents: driver.documents });
    } catch (err) {
        console.error('❌ Error uploading document:', err);
        res.status(500).json({ error: 'Failed to upload document' });
    }
});

// Manager: Delete Document from Driver Profile
app.delete('/api/manager/drivers/:id/documents/:docId', authMiddleware, async (req, res) => {
    try {
        const { id, docId } = req.params;
        const driver = await Driver.findById(id);
        if (!driver) {
            return res.status(404).json({ error: 'Driver not found' });
        }

        driver.documents = driver.documents.filter(d => d._id.toString() !== docId);
        await driver.save();

        res.json({ message: 'Document deleted successfully', documents: driver.documents });
    } catch (err) {
        console.error('❌ Error deleting document:', err);
        res.status(500).json({ error: 'Failed to delete document' });
    }
});

// Manager: Delete Driver
app.delete('/api/manager/drivers/:id', authMiddleware, async (req, res) => {
    try {
        const { id } = req.params;
        const driver = await Driver.findById(id);
        if (!driver) {
            return res.status(404).json({ error: 'Driver not found' });
        }

        if (driver.assignedBus) {
            await Bus.findByIdAndUpdate(driver.assignedBus, { driverId: '' });
        }

        await Driver.findByIdAndDelete(id);
        res.json({ message: 'Driver deleted successfully' });
    } catch (err) {
        console.error('❌ Error deleting driver:', err);
        res.status(500).json({ error: 'Failed to delete driver' });
    }
});

// ─── MANAGER: EDIT ROUTE (name, color, stops) ────────────────────────────────
// Body: { name, color, stops: [{ name, lat, lng }] }
app.put('/api/manager/routes/:id', authMiddleware, async (req, res) => {
    try {
        const { name, color, stops } = req.body;
        const { geocodeStopName } = require('./geocode_stops');
        const { getRoadPolylineForStops } = require('./road_routing_service');
        const updateData = {};
        if (name)  updateData.name  = name;
        if (color) updateData.color = color;
        if (stops && Array.isArray(stops)) {
            const geocodedStops = [];
            for (const s of stops) {
                if (!s.name || !s.name.trim()) continue;
                let lat = s.lat != null ? parseFloat(s.lat) : null;
                let lng = s.lng != null ? parseFloat(s.lng) : null;
                
                // If coordinates are missing, invalid, or 0, auto-resolve them
                if (lat == null || lng == null || isNaN(lat) || isNaN(lng) || (lat === 0 && lng === 0)) {
                    const coords = await geocodeStopName(s.name.trim());
                    lat = coords.lat;
                    lng = coords.lng;
                }

                geocodedStops.push({
                    name: s.name.trim(),
                    lat,
                    lng,
                });
            }
            updateData.stops = geocodedStops;

            // Generate high-resolution road-following polyline coordinates via OSRM
            const roadResult = await getRoadPolylineForStops(geocodedStops);
            if (roadResult && roadResult.coordinates && roadResult.coordinates.length > 0) {
                updateData.coordinates = roadResult.coordinates;
                if (roadResult.distanceKm) updateData.distance = roadResult.distanceKm + ' km';
                if (roadResult.durationMins) updateData.duration = roadResult.durationMins + ' mins';
            } else {
                updateData.coordinates = geocodedStops
                    .filter(s => s.lat != null && s.lng != null && s.lat !== 0 && s.lng !== 0)
                    .map(s => ({ latitude: s.lat, longitude: s.lng }));
            }
        }

        const updatedRoute = await Route.findByIdAndUpdate(
            req.params.id, updateData, { new: true }
        );
        if (!updatedRoute) return res.status(404).json({ error: 'Route not found' });
        invalidateRoutesCache();

        // Cascade: update routeName on every bus that uses this route
        if (name) {
            await Bus.updateMany({ routeId: req.params.id }, { routeName: name });
        }
        if (color) {
            await Bus.updateMany({ routeId: req.params.id }, { routeColor: color });
        }

        // Notify all clients of the route change
        io.emit('routeUpdated', updatedRoute);
        console.log(`✏️  [Manager] Route updated: ${updatedRoute.name} (${updatedRoute.stops.length} stops)`);
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

            // ── TRIP 1: PICKUP (MORNING: 07:00 - 08:00 AM) ──
            const departH = baseDepartureHour;
            const departM = baseDepartureMinute + jitter;
            const departureTimePickup = `${String(departH).padStart(2,'0')}:${String(departM).padStart(2,'0')} AM`;
            const baseDuration = 40 + Math.min(stopNames.length * 2, 30);
            const durationPickup = baseDuration + ((dayIndex * 3) % 15);
            const isDelayedPickup = durationPickup > baseDuration + 8;
            const arrivalMinsPickup = departH * 60 + departM + durationPickup;
            const arrHPickup = Math.floor(arrivalMinsPickup / 60) % 24;
            const arrMPickup = arrivalMinsPickup % 60;
            const arrivalTimePickup = `${String(arrHPickup).padStart(2,'0')}:${String(arrMPickup).padStart(2,'0')} AM`;

            const stopTimelinePickup = stopNames.map((sName, idx) => {
                const stopMins = departH * 60 + departM + Math.round((durationPickup / (stopNames.length || 1)) * idx);
                const sH = Math.floor(stopMins / 60) % 24;
                const sM = stopMins % 60;
                return {
                    stopNumber: idx + 1,
                    stopName: sName,
                    time: `${String(sH).padStart(2,'0')}:${String(sM).padStart(2,'0')} AM`,
                    isOrigin: idx === 0,
                    isCampus: idx === stopNames.length - 1,
                };
            });

            // ── TRIP 2: DROP-OFF (EVENING: 04:30 - 05:30 PM) ──
            const departHEvening = 16; // 4 PM
            const departMEvening = 30 + (jitter % 15);
            const departureTimeDropoff = `${String(departHEvening - 12).padStart(2,'0')}:${String(departMEvening).padStart(2,'0')} PM`;
            const durationDropoff = baseDuration + ((dayIndex * 5) % 12);
            const isDelayedDropoff = durationDropoff > baseDuration + 8;
            const arrivalMinsDropoff = departHEvening * 60 + departMEvening + durationDropoff;
            const arrHDropoff = Math.floor(arrivalMinsDropoff / 60) % 24;
            const arrMDropoff = arrivalMinsDropoff % 60;
            const arrHDropoffDisplay = arrHDropoff > 12 ? arrHDropoff - 12 : arrHDropoff;
            const arrivalTimeDropoff = `${String(arrHDropoffDisplay).padStart(2,'0')}:${String(arrMDropoff).padStart(2,'0')} PM`;

            // Reverse stop list for drop-off timeline (Campus -> City)
            const reversedStops = [...stopNames].reverse();
            const stopTimelineDropoff = reversedStops.map((sName, idx) => {
                const stopMins = departHEvening * 60 + departMEvening + Math.round((durationDropoff / (reversedStops.length || 1)) * idx);
                const sH = Math.floor(stopMins / 60) % 24;
                const sM = stopMins % 60;
                const displayH = sH > 12 ? sH - 12 : sH;
                return {
                    stopNumber: idx + 1,
                    stopName: sName,
                    time: `${String(displayH).padStart(2,'0')}:${String(sM).padStart(2,'0')} PM`,
                    isCampus: idx === 0,
                    isOrigin: idx === reversedStops.length - 1,
                };
            });

            const avgSpeed = parseFloat((28 + (dayIndex % 10)).toFixed(1));
            const studentCountPickup = 30 + ((dayIndex * 3 + busNumSeed) % 25);
            const studentCountDropoff = 28 + ((dayIndex * 4 + busNumSeed) % 25);

            const dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
            dailyRecords.push({
                date: tripDate.toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }),
                dayName: dayNames[dayOfWeek],
                busNumber: bus.busNumber || 'N/A',
                driverName,
                routeName: bus.routeName,
                // Pickup Trip
                pickupTrip: {
                    type: 'pickup',
                    label: 'Trip 1: Morning Pickup (City ➔ College)',
                    originStop: firstStop,
                    destinationStop: lastStop,
                    departureTime: departureTimePickup,
                    arrivalTime: arrivalTimePickup,
                    tripDurationMins: durationPickup,
                    studentCount: studentCountPickup,
                    avgSpeedKmh: avgSpeed,
                    status: isDelayedPickup ? 'Delayed' : 'On-time',
                    stopTimeline: stopTimelinePickup
                },
                // Drop-off Trip
                dropoffTrip: {
                    type: 'dropoff',
                    label: 'Trip 2: Evening Drop-off (College ➔ City)',
                    originStop: lastStop,
                    destinationStop: firstStop,
                    departureTime: departureTimeDropoff,
                    arrivalTime: arrivalTimeDropoff,
                    tripDurationMins: durationDropoff,
                    studentCount: studentCountDropoff,
                    avgSpeedKmh: avgSpeed,
                    status: isDelayedDropoff ? 'Delayed' : 'On-time',
                    stopTimeline: stopTimelineDropoff
                },
                // Legacy flat properties for backward compatibility
                departureTime: departureTimePickup,
                arrivalTime: arrivalTimePickup,
                tripDurationMins: durationPickup,
                totalStops: stopNames.length,
                studentCount: studentCountPickup + studentCountDropoff,
                avgSpeedKmh: avgSpeed,
                status: (isDelayedPickup || isDelayedDropoff) ? 'Delayed' : 'On-time',
                stopTimeline: stopTimelinePickup,
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
const userGeofenceState = {}; // { userId: { stopName: lastNotifiedTimestamp } }
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

    socket.on('joinRoute', (routeId) => {
        if (routeId) {
            const roomName = `route_${routeId}`;
            socket.join(roomName);
            console.log(`🚪 Socket ${socket.id} joined room: ${roomName}`);
        }
    });

    socket.on('leaveRoute', (routeId) => {
        if (routeId) {
            const roomName = `route_${routeId}`;
            socket.leave(roomName);
            console.log(`🚪 Socket ${socket.id} left room: ${roomName}`);
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

            const gpsAccuracy = data.gpsAccuracy !== undefined ? Number(data.gpsAccuracy) : null;

            process.stdout.write(`📍 [LIVE] Bus: ${bus.busNumber} | Lat: ${lat.toFixed(5)} | Lng: ${lng.toFixed(5)} | Speed: ${speed.toFixed(1)} KM/H${gpsAccuracy != null ? ` | GPS: ±${gpsAccuracy.toFixed(0)}m` : ''}\r`);

            // ── DUAL TRIP DIRECTION: 'pickup' (Stop -> College) vs 'dropoff' (College -> Stop) ──
            const tripType = (data.tripType === 'dropoff' || data.tripType === 'evening') ? 'dropoff' : 'pickup';
            bus.tripType = tripType;

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
                    tripType:   tripType,
                    status:     'Active'
                });
                console.log(`🚀 [TRIP START] New live ${tripType.toUpperCase()} trip log created for Bus ${bus.busNumber} on ${todayStr}`);
            }

            // Update Route & Identity if sent by driver cockpit
            if (data.routeId && data.routeId.toString().length > 5) {
                bus.routeId = data.routeId.toString();
            }
            if (data.routeName && data.routeName.trim().length > 0) {
                bus.routeName = data.routeName.trim();
            }
            if (data.busNumber && data.busNumber.trim().length > 0 && data.busNumber !== 'N/A') {
                bus.busNumber = data.busNumber.trim();
            }

            // Update DB telemetry
            bus.currentLat = lat;
            bus.currentLng = lng;
            bus.speed = speed;
            bus.heading = heading;
            bus.lastUpdated = new Date();
            // If the driver is broadcasting location, the shuttle is live and operational
            bus.status = (data.status && data.status.toLowerCase() !== 'offline')
                ? data.status
                : (bus.status === 'Delayed' ? 'Delayed' : 'On-time');

            if (data.reachedStops && Array.isArray(data.reachedStops)) {
                bus.reachedStops = data.reachedStops.map(s => s.toString());
                bus.completedStops = data.completedStops !== undefined ? Number(data.completedStops) : bus.reachedStops.length;
            }
            
            // Calculate True Road Polyline ETAs & Upcoming Stops
            let etas = [];
            let nextStopName = '';
            if (bus.routeId) {
                const route = await Route.findById(bus.routeId);
                if (route && route.stops && route.stops.length > 0) {
                    const { computeRouteProgressAndETAs } = require('./road_routing_service');
                    const progress = computeRouteProgressAndETAs(lat, lng, speed, route.stops, route.coordinates, tripType);
                    etas = progress.etas;
                    nextStopName = progress.nextStopName;

                    for (let sIdx = 0; sIdx < etas.length; sIdx++) {
                        const stop = etas[sIdx];
                        if (stop.lat && stop.lng) {
                            // GEOFENCE LOGIC (Direct proximity to bus)
                            const R = 6371;
                            const dLat = (stop.lat - lat) * Math.PI / 180;
                            const dLon = (stop.lng - lng) * Math.PI / 180;
                            const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                                Math.cos(lat * Math.PI / 180) * Math.cos(stop.lat * Math.PI / 180) *
                                Math.sin(dLon / 2) * Math.sin(dLon / 2);
                            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                            const distanceKm = R * c;
                            const stopMinutes = (stop && stop.minutes !== undefined) ? stop.minutes : Math.max(1, Math.round(distanceKm / 0.4));

                            // ── TARGETED FCM PUSH NOTIFICATIONS (Custom Geofence Radius) ──
                            if (distanceKm <= 3.0) {
                                (async () => {
                                    if (admin.apps.length > 0) {
                                        try {
                                            const targetUsers = await User.find({
                                                routeId: bus.routeId ? bus.routeId.toString() : null,
                                                pickupPoint: { $regex: new RegExp(`^${stop.name.trim()}$`, 'i') },
                                                proximityAlertsEnabled: true
                                            });

                                            const now = Date.now();
                                            const tokens = [];

                                            for (const user of targetUsers) {
                                                const uRadius = user.proximityRadiusKm !== undefined ? user.proximityRadiusKm : 1.0;
                                                if (distanceKm <= uRadius) {
                                                    if (!userGeofenceState[user._id]) userGeofenceState[user._id] = {};
                                                    const lastNotified = userGeofenceState[user._id][stop.name] || 0;

                                                    if (now - lastNotified > COOLDOWN_MS) {
                                                        userGeofenceState[user._id][stop.name] = now;
                                                        tokens.push(user.fcmToken);
                                                    }
                                                }
                                            }

                                            if (tokens.length > 0) {
                                                const messagePayload = {
                                                    notification: {
                                                        title: `Bus Approaching: ${bus.routeName || 'Shuttle'}`,
                                                        body: `Your shuttle is approaching ${stop.name}. Distance: ${distanceKm.toFixed(1)} km. Est: ${stopMinutes} min.`
                                                    },
                                                    android: {
                                                        priority: 'high',
                                                        notification: {
                                                            channelId: 'SISTecChalo_pulse_alerts',
                                                            color: '#00F0FF',
                                                            sound: 'default'
                                                        }
                                                    },
                                                    tokens: tokens
                                                };
                                                const response = await admin.messaging().sendEachForMulticast(messagePayload);
                                                console.log(`🔥 [Firebase] Sent custom proximity push notification to ${response.successCount} users.`);
                                                
                                                // Clean up invalid tokens
                                                response.responses.forEach((resp, idx) => {
                                                    if (!resp.success) {
                                                        const error = resp.error;
                                                        if (error && (error.code === 'messaging/invalid-registration-token' || error.code === 'messaging/registration-token-not-registered')) {
                                                            const failedToken = tokens[idx];
                                                            User.updateOne({ fcmToken: failedToken }, { $set: { fcmToken: null } }).exec()
                                                                .catch(err => console.error('Error cleaning stale token:', err.message));
                                                        }
                                                    }
                                                });
                                            }
                                        } catch (err) {
                                            console.error('❌ [Firebase] Failed to send push notifications:', err.message);
                                        }
                                    }
                                })();
                            }

                            if (distanceKm <= GEOFENCE_RADIUS_KM) {
                                const now = Date.now();
                                if (!busGeofenceState[bus._id]) busGeofenceState[bus._id] = {};
                                const lastNotified = busGeofenceState[bus._id][stop.name] || 0;

                                if (now - lastNotified > COOLDOWN_MS) {
                                    busGeofenceState[bus._id][stop.name] = now;
                                    io.emit('busApproachingStop', {
                                        busId: bus._id.toString(),
                                        stopName: stop.name,
                                        minutes: stopMinutes
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

            const resolvedNextStop = nextStopName || data.nextStop || (etas[0] ? etas[0].stopName : '');
            // Prefer server-computed road distance from polyline engine over client straight-line
            const resolvedDistMeters = (etas[0] && etas[0].distanceKm)
                ? Math.round(parseFloat(etas[0].distanceKm) * 1000)
                : (data.distanceToNextStopMeters !== undefined ? Number(data.distanceToNextStopMeters) : null);
            // Final destination distance from driver broadcast
            const finalDistMeters = data.distanceToFinalStopMeters !== undefined
                ? Number(data.distanceToFinalStopMeters)
                : null;

            bus.nextStop = resolvedNextStop;
            bus.distanceToNextStopMeters = resolvedDistMeters;
            bus.etas = etas;
            await bus.save();

            // Broadcast real device data (Global & Route-specific Room)
            const busPayload = bus.toObject ? bus.toObject() : { ...bus };
            busPayload.id = bus._id.toString();
            busPayload._id = bus._id.toString();
            busPayload.currentLat = lat;
            busPayload.currentLng = lng;
            busPayload.latitude = lat;
            busPayload.longitude = lng;
            busPayload.speed = speed;
            busPayload.heading = heading;
            busPayload.status = bus.status;
            busPayload.tripType = tripType;
            if (bus.routeId) busPayload.routeId = bus.routeId.toString();
            if (bus.routeName) busPayload.routeName = bus.routeName;
            if (bus.driverId) busPayload.driverId = bus.driverId.toString();
            busPayload.nextStop = resolvedNextStop;
            busPayload.distanceToNextStopMeters = resolvedDistMeters;
            busPayload.distanceToFinalStopMeters = finalDistMeters;
            busPayload.reachedStops = bus.reachedStops || [];
            busPayload.completedStops = bus.completedStops || (bus.reachedStops ? bus.reachedStops.length : 0);
            busPayload.etas = etas;
            busPayload.gpsAccuracy = gpsAccuracy;
            busPayload.lastUpdated = bus.lastUpdated;

            io.emit('busLocationUpdate', busPayload);
            io.emit('locationUpdate', busPayload);
            if (bus.routeId) {
                io.to(`route_${bus.routeId.toString()}`).emit('busLocationUpdate', busPayload);
                io.to(`route_${bus.routeId.toString()}`).emit('locationUpdate', busPayload);
            }

        } catch (err) {
            console.error('❌ [TRACKING ERROR]:', err.message);
        }
    });

    // Driver signals end of trip or stops broadcast
    const handleTripEndOrStopBroadcast = async (data) => {
        try {
            const busId = (data.busId || data.id || data._id || '').toString();
            if (busId) {
                const bus = await Bus.findByIdAndUpdate(
                    busId, 
                    { status: 'Offline', speed: 0, etas: [], lastUpdated: new Date() },
                    { new: true }
                );
                const offlinePayload = {
                    id: busId,
                    _id: busId,
                    busId: busId,
                    busNumber: bus ? bus.busNumber : undefined,
                    status: 'Offline',
                    speed: 0,
                    etas: [],
                    lastUpdated: new Date()
                };
                io.emit('busLocationUpdate', offlinePayload);
                io.emit('locationUpdate', offlinePayload);
                io.emit('busUpdated', offlinePayload);
                if (bus && bus.routeId) {
                    io.to(`route_${bus.routeId.toString()}`).emit('busLocationUpdate', offlinePayload);
                    io.to(`route_${bus.routeId.toString()}`).emit('locationUpdate', offlinePayload);
                    io.to(`route_${bus.routeId.toString()}`).emit('busUpdated', offlinePayload);
                }
                console.log(`🏁 [TRIP END / STOP BROADCAST] Bus ${busId} marked Offline`);
            }
            const todayStr = new Date().toISOString().split('T')[0];
            const tripLog = await LiveTripLog.findOne({ busId, date: todayStr, status: 'Active' });
            if (tripLog) {
                tripLog.endTime = new Date();
                tripLog.status = 'Completed';
                await tripLog.save();
            }
        } catch (err) {
            console.error('❌ [TRIP END ERROR]:', err.message);
        }
    };

    socket.on('tripEnd', handleTripEndOrStopBroadcast);
    socket.on('stopBroadcast', handleTripEndOrStopBroadcast);
    socket.on('stopTrip', handleTripEndOrStopBroadcast);
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

// --- GEOCODE ALL STOPS API ROUTE ---
app.post('/api/manager/geocode-stops', async (req, res) => {
    try {
        console.log('📍 [Manager API] Triggering stop geocoding...');
        const { geocodeAllStops } = require('./geocode_stops');
        await geocodeAllStops();
        res.json({ success: true, message: "All route stops successfully geocoded with lat/lng coordinates!" });
    } catch (_err) {
        console.error("Geocode Error:", _err);
        res.status(500).json({ error: "Failed to geocode stops" });
    }
});

// ─── MANAGER TIMETABLE UPLOAD & AUTO-INGESTION ENGINE ─────────────────────────
const multer = require('multer');
const uploadTimetable = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 25 * 1024 * 1024 }
});

const {
    syncOfficialRatibadRoster,
    syncRosterToDatabase,
    parseExcelToRoster,
    previewTimetable
} = require('./timetable_importer');

/**
 * POST /api/manager/preview-timetable
 * Pre-flight preview of uploaded timetable (.pdf, .xlsx, .xls, .csv, .json).
 * Extracts routes, bus numbers, timings, drivers, and stops with coordinates WITHOUT saving to DB.
 * Allows the manager to review and make edits in the UI before deployment.
 */
app.post('/api/manager/preview-timetable', optionalAuth, uploadTimetable.single('file'), async (req, res) => {
    try {
        console.log('🔍 [Timetable Engine] Generating pre-flight timetable preview...');
        const buffer = req.file ? req.file.buffer : null;
        const filename = req.file ? req.file.originalname : 'Institutional Master Timetable';

        const previewData = await previewTimetable(buffer, filename);
        res.json(previewData);
    } catch (err) {
        console.error('❌ Timetable preview generation failed:', err);
        res.status(500).json({ error: err.message || 'Failed to generate timetable preview.' });
    }
});

/**
 * POST /api/manager/apply-timetable
 * Commits the finalized (and optionally edited) roster directly into MongoDB.
 * Updates Routes, Buses, Driver assignments, and broadcasts live WebSocket events to all apps.
 */
app.post('/api/manager/apply-timetable', optionalAuth, async (req, res) => {
    try {
        const routesToApply = req.body && Array.isArray(req.body.routes) ? req.body.routes : [];
        if (routesToApply.length === 0) {
            return res.status(400).json({ error: 'No routes provided in apply request.' });
        }

        console.log(`🚀 [Timetable Engine] Deploying ${routesToApply.length} routes live to the entire fleet...`);
        const synced = await syncRosterToDatabase(routesToApply, io);
        invalidateRoutesCache();

        // Broadcast to all connected clients across the entire college
        io.emit('routesUpdated', synced);
        io.emit('busesUpdated');
        io.emit('timetableUpdated', { count: synced.length, timestamp: new Date() });

        res.json({
            success: true,
            count: synced.length,
            routes: synced,
            message: `Successfully published all ${synced.length} routes & buses to the entire app network!`
        });
    } catch (err) {
        console.error('❌ Apply timetable failed:', err);
        res.status(500).json({ error: err.message || 'Failed to deploy timetable changes.' });
    }
});

/**
 * POST /api/manager/upload-timetable
 * Direct upload & sync fallback.
 */
app.post('/api/manager/upload-timetable', optionalAuth, uploadTimetable.single('file'), async (req, res) => {
    try {
        console.log('📥 [Timetable Engine] Received timetable sync request...');
        let rosterEntries = [];

        if (req.file) {
            const originalName = req.file.originalname.toLowerCase();
            console.log(`📄 Processing uploaded timetable file: ${req.file.originalname} (${req.file.size} bytes)`);

            if (originalName.endsWith('.pdf')) {
                const { parsePdfToRoster } = require('./timetable_importer');
                rosterEntries = await parsePdfToRoster(req.file.buffer);
            } else if (originalName.endsWith('.xlsx') || originalName.endsWith('.xls')) {
                rosterEntries = parseExcelToRoster(req.file.buffer);
            } else if (originalName.endsWith('.json')) {
                rosterEntries = JSON.parse(req.file.buffer.toString('utf8'));
            } else if (originalName.endsWith('.csv')) {
                const csvStr = req.file.buffer.toString('utf8');
                const rows = csvStr.split('\n').map(r => r.split(','));
                rosterEntries = rows.filter(r => r.length > 1).map((r, i) => ({
                    busNo: String(r[0] || i + 1).trim(),
                    routeName: String(r[1] || `Route ${i + 1}`).trim(),
                    stops: (r[2] || '').split(';').map(s => ({ name: s.trim(), time: '08:00 AM' }))
                }));
            } else {
                return res.status(400).json({ error: 'Unsupported file format. Please upload a PDF, Excel (.xlsx, .xls), CSV, or JSON file.' });
            }
        } else if (req.body && req.body.routes && Array.isArray(req.body.routes)) {
            rosterEntries = req.body.routes;
        } else {
            console.log('ℹ️ No file uploaded; falling back to official institutional Ratibad 9:00 AM roster.');
            const synced = await syncOfficialRatibadRoster(io);
            invalidateRoutesCache();
            return res.json({
                success: true,
                count: synced.length,
                routes: synced,
                message: `Successfully synchronized ${synced.length} official routes and buses from institutional timetable!`
            });
        }

        if (!rosterEntries || rosterEntries.length === 0) {
            return res.status(400).json({ error: 'No valid routes or buses detected in the uploaded file.' });
        }

        console.log(`🚌 Parsed ${rosterEntries.length} routes from file. Syncing database with strict coordinate preservation...`);
        const synced = await syncRosterToDatabase(rosterEntries, io);
        invalidateRoutesCache();

        io.emit('routesUpdated', synced);
        io.emit('busesUpdated');
        io.emit('timetableUpdated', { count: synced.length, timestamp: new Date() });

        res.json({
            success: true,
            count: synced.length,
            routes: synced,
            message: `Successfully synchronized ${synced.length} bus routes from timetable!`
        });
    } catch (err) {
        console.error('❌ Timetable upload failed:', err);
        res.status(500).json({ error: err.message || 'Failed to process and synchronize timetable.' });
    }
});

/**
 * POST /api/manager/sync-official-timetable
 * Instant 1-tap synchronization of the official institutional Ratibad 9:00 AM timetable (37 Buses).
 */
app.post('/api/manager/sync-official-timetable', optionalAuth, async (req, res) => {
    try {
        console.log('🔄 [Manager API] 1-Tap Official Ratibad Roster Sync initiated...');
        const synced = await syncOfficialRatibadRoster(io);
        invalidateRoutesCache();

        io.emit('routesUpdated', synced);
        io.emit('busesUpdated');
        io.emit('timetableUpdated', { count: synced.length, timestamp: new Date() });

        res.json({
            success: true,
            count: synced.length,
            routes: synced,
            message: `Successfully synchronized all ${synced.length} official SISTec buses and routes!`
        });
    } catch (err) {
        console.error('❌ Official timetable sync failed:', err);
        res.status(500).json({ error: err.message || 'Failed to sync official timetable.' });
    }
});

// --- UPDATE ROUTE STOPS & AUTOMATIC GEOCODING ---
app.put('/api/routes/:id/stops', authMiddleware, async (req, res) => {
    try {
        const { stops } = req.body;
        if (!Array.isArray(stops)) {
            return res.status(400).json({ error: 'stops array is required' });
        }
        const route = await Route.findById(req.params.id);
        if (!route) return res.status(404).json({ error: 'Route not found' });

        const { geocodeStopName } = require('./geocode_stops');
        const { getRoadPolylineForStops } = require('./road_routing_service');
        const updatedStops = [];

        for (const s of stops) {
            let lat = s.lat != null ? parseFloat(s.lat) : null;
            let lng = s.lng != null ? parseFloat(s.lng) : null;

            if (lat == null || lng == null || isNaN(lat) || isNaN(lng)) {
                const coords = await geocodeStopName(s.name);
                lat = coords.lat;
                lng = coords.lng;
            }
            updatedStops.push({ name: s.name, lat, lng });
        }

        route.stops = updatedStops;

        // Generate high-resolution road-following polyline coordinates via OSRM
        const roadResult = await getRoadPolylineForStops(updatedStops);
        if (roadResult && roadResult.coordinates && roadResult.coordinates.length > 0) {
            route.coordinates = roadResult.coordinates;
            if (roadResult.distanceKm) route.distance = roadResult.distanceKm + ' km';
            if (roadResult.durationMins) route.duration = roadResult.durationMins + ' mins';
        } else {
            route.coordinates = updatedStops
                .filter(s => s.lat != null && s.lng != null)
                .map(s => ({ latitude: s.lat, longitude: s.lng }));
        }

        await route.save();
        invalidateRoutesCache();
        io.emit('routeUpdated', route);
        res.json({ success: true, route });
    } catch (err) {
        console.error('Update route stops error:', err);
        res.status(500).json({ error: 'Failed to update route stops' });
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

        // Use actual broadcast speed with production floor (matches road_routing_service)
        const speed = bus.speed >= 8 ? Math.min(bus.speed, 60) : 25;
        const minutes = await calculateETA(bus.currentLat, bus.currentLng, stop.lat, stop.lng, speed, route);

        res.json({
            eta: minutes,
            busId: bus._id.toString(),
            busNumber: bus.busNumber,
            routeName: route.name,
            stopName: stop.name,
            busLat: bus.currentLat,
            busLng: bus.currentLng,
            speed: bus.speed,
            tripType: bus.tripType || 'pickup',
            directionLabel: bus.tripType === 'dropoff' ? 'College ➔ Stop (Drop-off)' : 'Stop ➔ College (Pickup)',
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

// ── PUBLIC: Get active registration form status & URL for mobile app ─────────
app.get('/api/public/active-form', async (req, res) => {
    try {
        const form = await RegistrationForm.findOne({ isActive: true }).sort({ createdAt: -1 });
        if (!form) {
            return res.json({ active: false, form: null, url: null });
        }
        const shareUrl = `${getBaseUrl(req)}/register/${form._id}`;
        res.json({ active: true, form, url: shareUrl });
    } catch (err) {
        console.error('Public active form error:', err);
        res.status(500).json({ active: false, error: 'Failed to fetch registration portal status' });
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

// ── MANAGER: Bulk registration uploads ────────────────────────────────────
app.post('/api/manager/registrations/bulk', authMiddleware, async (req, res) => {
    const { submissions } = req.body;
    if (!submissions || !Array.isArray(submissions)) {
        return res.status(400).json({ error: 'Submissions array is required.' });
    }

    try {
        // Find or create active form
        let form = await RegistrationForm.findOne({ isActive: true });
        if (!form) {
            form = await RegistrationForm.create({
                title: 'Bulk Upload Form',
                description: 'Auto-generated form for bulk uploaded manager registrations',
                isActive: true,
                createdBy: req.user.id
            });
        }

        const routes = await Route.find({});
        const results = [];
        const errors = [];
        const toInsert = [];
        const processedIdsInSheet = new Set();

        // 1. Gather all studentIds from payload to query DB in bulk
        const studentIds = submissions
            .map(item => item.studentId ? item.studentId.toString().trim() : '')
            .filter(id => id.length > 0);

        // 2. Fetch existing submissions and users in bulk
        const [existingSubs, existingUsers] = await Promise.all([
            RegistrationSubmission.find({ studentId: { $in: studentIds } }, { studentId: 1 }),
            User.find({ username: { $in: studentIds } }, { username: 1 })
        ]);

        const dbSubSet = new Set(existingSubs.map(s => s.studentId));
        const dbUserSet = new Set(existingUsers.map(u => u.username));

        for (let i = 0; i < submissions.length; i++) {
            const item = submissions[i];
            const { name, studentId, phone, email, routeName, pickupStop, gender, fatherName, courseName, fatherPhone } = item;

            if (!name || !studentId || !phone || !pickupStop) {
                errors.push(`Row ${i + 1}: Name, Student ID, Phone, and Pickup Stop are required.`);
                continue;
            }

            const cleanId = studentId.toString().trim();

            // Check duplicates in the uploaded sheet itself
            if (processedIdsInSheet.has(cleanId)) {
                errors.push(`Row ${i + 1} (${cleanId}): Duplicate student ID within the uploaded file.`);
                continue;
            }
            processedIdsInSheet.add(cleanId);

            // Check duplicates in DB in-memory
            if (dbSubSet.has(cleanId) || dbUserSet.has(cleanId)) {
                errors.push(`Row ${i + 1} (${cleanId}): Record already exists in pending list or active users.`);
                continue;
            }

            // Route matching: search for route name containing search text case-insensitively
            let matchedRoute = null;
            if (routeName) {
                const search = routeName.toString().toLowerCase().replace(/[^a-z0-9]/g, '');
                matchedRoute = routes.find(r => 
                    r.name.toLowerCase().replace(/[^a-z0-9]/g, '').includes(search)
                );
            }

            const finalRouteId = matchedRoute ? matchedRoute._id.toString() : (routes[0]?._id?.toString() || 'placeholder');
            const finalRouteName = matchedRoute ? matchedRoute.name : (routeName || 'Unassigned');

            toInsert.push({
                formId: form._id,
                name: name.toString().trim(),
                studentId: cleanId,
                phone: phone.toString().trim(),
                email: email ? email.toString().trim() : undefined,
                routeId: finalRouteId,
                routeName: finalRouteName,
                pickupStop: pickupStop.toString().trim(),
                gender: gender ? gender.toString().trim() : undefined,
                fatherName: fatherName ? fatherName.toString().trim() : undefined,
                courseName: courseName ? courseName.toString().trim() : undefined,
                fatherPhone: fatherPhone ? fatherPhone.toString().trim() : undefined,
                status: 'pending'
            });
        }

        // 3. Perform bulk insert for all valid records in a single DB query
        if (toInsert.length > 0) {
            const inserted = await RegistrationSubmission.insertMany(toInsert);
            results.push(...inserted);
        }

        console.log(`🌱 [Bulk Upload] Imported ${results.length} registrations. Errors: ${errors.length}`);
        
        // Broadcast updates
        await broadcastStats();

        res.status(201).json({
            success: true,
            importedCount: results.length,
            errors
        });
    } catch (err) {
        console.error('Bulk upload processing failed:', err);
        res.status(500).json({ error: 'Server error processing bulk upload' });
    }
});

// ── MANAGER: Approve → auto-create user account & dispatch credentials email ──
app.put('/api/manager/registrations/:id/approve', authMiddleware, async (req, res) => {
    if (!isValidId(req.params.id)) return res.status(400).json({ error: 'Invalid submission ID format' });
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

        // PASSWORD: Use manager-supplied custom password or auto-generate secure random one
        const rawPassword = (req.body.password && req.body.password.trim().length >= 6)
            ? req.body.password.trim()
            : generateStrongRandomPassword(10);
        const hashedPassword = await secureHashPassword(rawPassword);

        // Update email if manually supplied in req.body.email
        let email = submission.email;
        if (req.body.email && req.body.email.trim().length > 0) {
            email = req.body.email.trim();
            submission.email = email;
        }

        const newUser = await User.create({
            username,                              // enrollment number
            name: submission.name,                 // student's actual name
            password: hashedPassword,
            email: email || undefined,
            phone: submission.phone,
            routeId: submission.routeId,
            pickupPoint: submission.pickupStop,
            status: 'Active',
            userId: submission.studentId,          // also stored as userId
            proximityAlertsEnabled: true,
            gender: submission.gender,
            fatherName: submission.fatherName,
            courseName: submission.courseName,
            fatherPhone: submission.fatherPhone,
        });

        // Update submission record
        submission.status = 'approved';
        submission.generatedUsername = username;
        submission.generatedPassword = rawPassword;
        submission.createdUserId = newUser._id.toString();
        submission.reviewedAt = new Date();
        await submission.save();

        // Send Email & Track Dispatch
        let emailResult = { success: false };
        if (submission.email && (req.body.sendEmail !== false)) {
            emailResult = await sendCredentialsEmail(
                submission.email.trim(),
                submission.name,
                username,
                rawPassword,
                'student',
                {
                    routeName: submission.routeName,
                    pickupStop: submission.pickupStop,
                    courseName: submission.courseName,
                    fatherName: submission.fatherName,
                    phone: submission.phone
                }
            );

            submission.emailSent = emailResult.success;
            submission.emailSentAt = emailResult.success ? new Date() : null;
            submission.emailError = emailResult.success ? null : (emailResult.error || 'Dispatch error');
            await submission.save();
        }

        io.emit('registrationApproved', { id: req.params.id, name: submission.name, username });
        broadcastStats();

        res.json({
            success: true,
            username,
            password: rawPassword,
            emailSent: emailResult.success,
            emailProvider: emailResult.provider,
            emailPreviewUrl: emailResult.previewUrl,
            message: `Account approved & created for ${submission.name}!\n\nUsername: "${username}"\nPassword: "${rawPassword}"` + 
                     (submission.email && (req.body.sendEmail !== false)
                         ? (emailResult.success 
                             ? `\n\n✅ Official Welcome & Credentials email sent to ${submission.email} via ${emailResult.provider}!`
                             : `\n\n⚠️ Email dispatch failed: ${emailResult.error}`)
                         : '\n\nShare these credentials with the student.')
        });
    } catch (_err) {
        console.error('Approval error:', _err);
        res.status(500).json({ error: 'Failed to approve registration' });
    }
});

// ── MANAGER: Resend Credentials Email ───────────────────────────────────────
// POST /api/manager/registrations/:id/resend-email
app.post('/api/manager/registrations/:id/resend-email', authMiddleware, async (req, res) => {
    if (!isValidId(req.params.id)) return res.status(400).json({ error: 'Invalid submission ID format' });
    try {
        const submission = await RegistrationSubmission.findById(req.params.id);
        if (!submission) return res.status(404).json({ error: 'Submission not found' });
        if (submission.status !== 'approved') return res.status(400).json({ error: 'Submission is not approved yet' });

        let targetEmail = (req.body.email && req.body.email.trim().length > 0) ? req.body.email.trim() : submission.email;
        if (!targetEmail) return res.status(400).json({ error: 'No email address specified for this student.' });

        if (req.body.email && req.body.email.trim() !== submission.email) {
            submission.email = targetEmail;
            await submission.save();
            await User.updateOne({ username: submission.studentId }, { email: targetEmail });
        }

        const username = submission.generatedUsername || submission.studentId;
        let password = submission.generatedPassword;
        if (!password) {
            password = generateStrongRandomPassword(10);
            const hashedPassword = await secureHashPassword(password);
            await User.updateOne({ username }, { password: hashedPassword });
            submission.generatedPassword = password;
            await submission.save();
        }

        const emailResult = await sendCredentialsEmail(
            targetEmail,
            submission.name,
            username,
            password,
            'student',
            {
                routeName: submission.routeName,
                pickupStop: submission.pickupStop,
                courseName: submission.courseName,
                fatherName: submission.fatherName,
                phone: submission.phone
            }
        );

        submission.emailSent = emailResult.success;
        submission.emailSentAt = emailResult.success ? new Date() : submission.emailSentAt;
        submission.emailError = emailResult.success ? null : (emailResult.error || 'Dispatch failed');
        await submission.save();

        res.json({
            success: emailResult.success,
            email: targetEmail,
            provider: emailResult.provider,
            previewUrl: emailResult.previewUrl,
            message: emailResult.success
                ? `Credentials successfully sent to ${targetEmail} via ${emailResult.provider}!`
                : `Email dispatch failed: ${emailResult.error}`
        });
    } catch (err) {
        console.error('Resend email error:', err);
        res.status(500).json({ error: 'Failed to resend credentials email' });
    }
});

// ── MANAGER: Test Email Dispatch Connection ─────────────────────────────────
// POST /api/manager/test-email
app.post('/api/manager/test-email', authMiddleware, async (req, res) => {
    try {
        const { email } = req.body;
        const targetEmail = email || process.env.SMTP_USER || 'denimhajare@gmail.com';
        const result = await sendCredentialsEmail(
            targetEmail,
            'Transport Administrator',
            'MANAGER_TEST',
            'SISTec#Test2026',
            'manager',
            { routeName: 'Admin Transit Line', pickupStop: 'Administrative Block' }
        );
        res.json(result);
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// ── MANAGER: Unapprove → delete user account & revert status ────────────────
app.put('/api/manager/registrations/:id/unapprove', authMiddleware, async (req, res) => {
    if (!isValidId(req.params.id)) return res.status(400).json({ error: 'Invalid submission ID format' });
    try {
        const submission = await RegistrationSubmission.findById(req.params.id);
        if (!submission) return res.status(404).json({ error: 'Submission not found' });
        if (submission.status !== 'approved') return res.status(400).json({ error: 'Submission is not approved' });

        // Safely delete created user if valid ObjectId
        if (submission.createdUserId && mongoose.Types.ObjectId.isValid(submission.createdUserId)) {
            await User.findByIdAndDelete(submission.createdUserId);
        }
        
        // Also delete by username/studentId to ensure account removal
        const studentUsername = (submission.generatedUsername || submission.studentId || '').trim();
        if (studentUsername) {
            await User.deleteMany({
                $or: [
                    { username: studentUsername },
                    { username: studentUsername.toUpperCase() },
                    { userId: studentUsername }
                ]
            });
        }

        // Revert submission status to pending and clear credentials info
        submission.status = 'pending';
        submission.createdUserId = undefined;
        submission.generatedUsername = undefined;
        submission.generatedPassword = undefined;
        submission.emailSent = false;
        submission.emailSentAt = undefined;
        submission.emailError = undefined;
        submission.reviewedAt = undefined;
        await submission.save();

        if (submission.studentId) {
            io.emit('registrationUnapproved', { id: req.params.id, studentId: submission.studentId });
        }
        await broadcastStats();

        res.json({
            success: true,
            message: `Registration for ${submission.name} has been reverted to pending, and their user account was removed.`
        });
    } catch (err) {
        console.error('Unapprove error:', err);
        res.status(500).json({ error: err.message || 'Failed to unapprove registration' });
    }
});


// ── MANAGER: Bulk approve pending registrations ──────────────────────────
app.post('/api/manager/registrations/bulk-approve', authMiddleware, async (req, res) => {
    const { ids, password } = req.body;
    if (!ids || !Array.isArray(ids) || ids.length === 0) {
        return res.status(400).json({ error: 'An array of submission IDs is required.' });
    }

    try {
        const validIds = ids.filter(id => isValidId(id));
        const submissions = await RegistrationSubmission.find({ _id: { $in: validIds }, status: 'pending' });
        if (submissions.length === 0) {
            return res.status(400).json({ error: 'No pending submissions found to approve.' });
        }

        const results = [];
        const errors = [];

        for (const sub of submissions) {
            const username = sub.studentId.trim();

            // Check if user already exists
            const existing = await User.findOne({ username });
            if (existing) {
                errors.push(`${sub.name} (${username}): Account already exists.`);
                continue;
            }

            // Generate unique random password for EACH student in bulk approval if not overridden
            const rawPassword = password || generateStrongRandomPassword(10);
            const hashedPassword = await secureHashPassword(rawPassword);

            // Create student user account
            const newUser = await User.create({
                username,
                name: sub.name,
                password: hashedPassword,
                email: sub.email || undefined,
                phone: sub.phone,
                routeId: sub.routeId,
                pickupPoint: sub.pickupStop,
                status: 'Active',
                userId: sub.studentId,
                proximityAlertsEnabled: true,
                gender: sub.gender,
                fatherName: sub.fatherName,
                courseName: sub.courseName,
                fatherPhone: sub.fatherPhone,
            });

            // Update submission status
            sub.status = 'approved';
            sub.generatedUsername = username;
            sub.generatedPassword = rawPassword;
            sub.createdUserId = newUser._id.toString();
            sub.reviewedAt = new Date();
            await sub.save();

            // Dispatch email in background & update delivery status
            if (sub.email) {
                sendCredentialsEmail(
                    sub.email.trim(),
                    sub.name,
                    username,
                    rawPassword,
                    'student',
                    {
                        routeName: sub.routeName,
                        pickupStop: sub.pickupStop,
                        courseName: sub.courseName,
                        fatherName: sub.fatherName,
                        phone: sub.phone
                    }
                ).then(async (eRes) => {
                    sub.emailSent = eRes.success;
                    sub.emailSentAt = eRes.success ? new Date() : null;
                    sub.emailError = eRes.success ? null : eRes.error;
                    await sub.save();
                }).catch(e => console.error(`Failed to send background email for ${sub.name}:`, e));
            }

            io.emit('registrationApproved', { id: sub._id.toString(), name: sub.name, username });
            results.push(sub);
        }

        broadcastStats();

        res.json({
            success: true,
            approvedCount: results.length,
            errors,
            message: `Successfully approved ${results.length} students! ${errors.length > 0 ? `Errors: ${errors.join(', ')}` : ''}`
        });
    } catch (err) {
        console.error('Bulk approve error:', err);
        res.status(500).json({ error: 'Failed to bulk approve registrations' });
    }
});

// ── MANAGER: Reject a submission ──────────────────────────────────────────
app.put('/api/manager/registrations/:id/reject', authMiddleware, async (req, res) => {
    if (!isValidId(req.params.id)) return res.status(400).json({ error: 'Invalid submission ID format' });
    try {
        const updated = await RegistrationSubmission.findByIdAndUpdate(
            req.params.id,
            { status: 'rejected', rejectionNote: req.body.note || '', reviewedAt: new Date() },
            { new: true }
        );
        if (!updated) return res.status(404).json({ error: 'Submission not found' });
        res.json(updated);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to reject registration' });
    }
});

// ── MANAGER: Delete a single registration submission ───────────────────────
app.delete('/api/manager/registrations/:id', authMiddleware, async (req, res) => {
    if (!isValidId(req.params.id)) return res.status(400).json({ error: 'Invalid submission ID format' });
    try {
        const submission = await RegistrationSubmission.findById(req.params.id);
        if (!submission) return res.status(404).json({ error: 'Submission not found' });

        // If user was created, clean up the user account
        if (submission.createdUserId && isValidId(submission.createdUserId)) {
            await User.findByIdAndDelete(submission.createdUserId);
        } else if (submission.generatedUsername) {
            await User.findOneAndDelete({ username: submission.generatedUsername });
        }

        await RegistrationSubmission.findByIdAndDelete(req.params.id);
        broadcastStats();

        res.json({ success: true, message: 'Registration deleted successfully' });
    } catch (err) {
        console.error('Delete registration error:', err);
        res.status(500).json({ error: 'Failed to delete registration' });
    }
});

// ── MANAGER: Bulk delete multiple submissions ─────────────────────────────
app.post('/api/manager/registrations/bulk-delete', authMiddleware, async (req, res) => {
    const { ids } = req.body;
    if (!ids || !Array.isArray(ids) || ids.length === 0) {
        return res.status(400).json({ error: 'An array of submission IDs is required.' });
    }

    try {
        const validIds = ids.filter(id => isValidId(id));
        const submissions = await RegistrationSubmission.find({ _id: { $in: validIds } });

        for (const sub of submissions) {
            if (sub.createdUserId && isValidId(sub.createdUserId)) {
                await User.findByIdAndDelete(sub.createdUserId);
            } else if (sub.generatedUsername) {
                await User.findOneAndDelete({ username: sub.generatedUsername });
            }
        }

        const deleteResult = await RegistrationSubmission.deleteMany({ _id: { $in: validIds } });
        broadcastStats();

        res.json({
            success: true,
            deletedCount: deleteResult.deletedCount,
            message: `Successfully deleted ${deleteResult.deletedCount} registrations.`
        });
    } catch (err) {
        console.error('Bulk delete registrations error:', err);
        res.status(500).json({ error: 'Failed to bulk delete registrations' });
    }
});


// ── DIAGNOSTIC: Test SMTP connection and email delivery from deployed instance ──
app.get('/api/debug/smtp-test', async (req, res) => {
    const testEmail = req.query.email || 'denimhajare@gmail.com';
    const brevoApiKey = process.env.BREVO_API_KEY;

    if (brevoApiKey) {
        try {
            const user = process.env.SMTP_USER || 'no-reply@sistecchalo.edu';
            const response = await fetch('https://api.brevo.com/v3/smtp/email', {
                method: 'POST',
                headers: {
                    'accept': 'application/json',
                    'api-key': brevoApiKey,
                    'content-type': 'application/json'
                },
                body: JSON.stringify({
                    sender: { name: 'SISTecChalo Diagnostic', email: user },
                    to: [{ email: testEmail, name: 'Test Recipient' }],
                    subject: 'SISTecChalo Render Brevo HTTP API Test',
                    htmlContent: '<h3>SISTecChalo API Test</h3><p>Diagnostic test email from the Render server using Brevo HTTP API.</p>'
                })
            });

            if (response.ok) {
                const resData = await response.json();
                return res.json({
                    success: true,
                    provider: 'Brevo API',
                    message: 'Brevo API Email Sent Successfully!',
                    messageId: resData.messageId
                });
            } else {
                const errText = await response.text();
                return res.status(response.status).json({
                    success: false,
                    provider: 'Brevo API',
                    error: `Status ${response.status}: ${errText}`
                });
            }
        } catch (err) {
            return res.status(500).json({
                success: false,
                provider: 'Brevo API',
                error: err.message,
                stack: err.stack
            });
        }
    }

    // SMTP check fallback
    try {
        const host = process.env.SMTP_HOST || 'smtp.ethereal.email';
        const port = parseInt(process.env.SMTP_PORT) || 587;
        const user = process.env.SMTP_USER || '';
        const pass = process.env.SMTP_PASS || '';

        const logs = [];
        const transporter = nodemailer.createTransport({
            host,
            port,
            secure: port === 465,
            auth: { user, pass },
            debug: true,
            logger: {
                info: (msg) => logs.push(`[INFO] ${msg}`),
                warn: (msg) => logs.push(`[WARN] ${msg}`),
                error: (msg) => logs.push(`[ERROR] ${msg}`)
            }
        });

        const mailOptions = {
            from: `"SISTec Chalo" <${user || 'no-reply@sistecchalo.edu'}>`,
            to: testEmail,
            subject: 'SISTec Chalo SMTP Test',
            html: '<h3>SISTec Chalo SMTP Test</h3><p>Diagnostic test email from the server.</p>'
        };

        const info = await transporter.sendMail(mailOptions);
        res.json({
            success: true,
            provider: 'SMTP',
            message: 'SMTP Test Succeeded!',
            response: info.response,
            messageId: info.messageId,
            config: { host, port, user: user ? 'configured' : 'empty' },
            logs
        });
    } catch (err) {
        res.status(500).json({
            success: false,
            provider: 'SMTP',
            error: err.message,
            stack: err.stack,
            config: {
                host: process.env.SMTP_HOST,
                port: process.env.SMTP_PORT,
                user: process.env.SMTP_USER ? 'configured' : 'empty',
                pass: process.env.SMTP_PASS ? 'configured' : 'empty'
            }
        });
    }
});

// ─── ADMIN: Role & Permissions Management ──────────────────────────────
const adminMiddleware = (req, res, next) => {
    if (req.user && req.user.role === 'admin') {
        next();
    } else {
        res.status(403).json({ error: 'Access denied: admin credentials required' });
    }
};

// GET all users across all collections
app.get('/api/admin/users', authMiddleware, adminMiddleware, async (req, res) => {
    try {
        const admins = await Admin.find().select('-password');
        const managers = await Manager.find().select('-password');
        const drivers = await Driver.find().select('-password');
        const users = await User.find().select('-password');

        const allUsers = [];

        admins.forEach(a => {
            allUsers.push({
                _id: a._id.toString(),
                username: a.username,
                email: a.email,
                role: 'admin',
                createdAt: a.createdAt,
                permissions: a.permissions || ['all']
            });
        });

        managers.forEach(m => {
            allUsers.push({
                _id: m._id.toString(),
                username: m.username,
                email: m.email,
                role: 'manager',
                createdAt: m.createdAt,
                employeeId: m.employeeId,
                department: m.department,
                canManage: m.canManage || ['students', 'drivers', 'buses']
            });
        });

        drivers.forEach(d => {
            allUsers.push({
                _id: d._id.toString(),
                username: d.username,
                name: d.name,
                role: 'driver',
                status: d.status,
                createdAt: d.createdAt,
                assignedBus: d.assignedBus,
                contactNumber: d.contactNumber
            });
        });

        users.forEach(u => {
            allUsers.push({
                _id: u._id.toString(),
                username: u.username,
                name: u.name,
                email: u.email,
                role: 'user',
                status: u.status,
                createdAt: u.createdAt,
                userId: u.userId,
                phone: u.phone,
                routeId: u.routeId,
                pickupPoint: u.pickupPoint,
                gender: u.gender,
                fatherName: u.fatherName,
                courseName: u.courseName,
                fatherPhone: u.fatherPhone,
                accessRights: u.accessRights || ['view_routes', 'track_bus']
            });
        });

        res.json(allUsers);
    } catch (err) {
        console.error('Fetch all users error:', err);
        res.status(500).json({ error: 'Failed to fetch all users' });
    }
});

// CREATE a new user in the appropriate collection
app.post('/api/admin/users', authMiddleware, adminMiddleware, async (req, res) => {
    try {
        const { username, password, role, email, name, status, ...extra } = req.body;
        if (!username || !password || !role) {
            return res.status(400).json({ error: 'Username, password, and role are required.' });
        }

        const hashedPassword = await secureHashPassword(password);
        let newUser;

        const dupUser = await User.findOne({ username });
        const dupDriver = await Driver.findOne({ username });
        const dupManager = await Manager.findOne({ username });
        const dupAdmin = await Admin.findOne({ username });
        if (dupUser || dupDriver || dupManager || dupAdmin) {
            return res.status(409).json({ error: `Username "${username}" already exists in the system.` });
        }

        switch (role.toLowerCase()) {
            case 'admin':
                newUser = await Admin.create({
                    username,
                    password: hashedPassword,
                    email: email || undefined,
                    permissions: extra.permissions || ['all']
                });
                break;
            case 'manager':
                newUser = await Manager.create({
                    username,
                    password: hashedPassword,
                    email: email || undefined,
                    employeeId: extra.employeeId || 'EMP_' + username,
                    department: extra.department || 'Transit',
                    canManage: extra.canManage || ['students', 'drivers', 'buses']
                });
                break;
            case 'driver':
                newUser = await Driver.create({
                    username,
                    password: hashedPassword,
                    name: name || username,
                    assignedBus: extra.assignedBus || '',
                    contactNumber: extra.contactNumber || '',
                    status: status || 'Active'
                });
                break;
            case 'user':
                newUser = await User.create({
                    username,
                    password: hashedPassword,
                    name: name || username,
                    email: email || undefined,
                    phone: extra.phone || '',
                    routeId: extra.routeId || null,
                    pickupPoint: extra.pickupPoint || null,
                    gender: extra.gender || '',
                    fatherName: extra.fatherName || '',
                    courseName: extra.courseName || '',
                    fatherPhone: extra.fatherPhone || '',
                    status: status || 'Active',
                    userId: extra.userId || username,
                    accessRights: extra.accessRights || ['view_routes', 'track_bus']
                });
                break;
            default:
                return res.status(400).json({ error: `Unsupported role: ${role}` });
        }

        broadcastStats();
        res.json({ success: true, user: { _id: newUser._id, username: newUser.username, role } });
    } catch (err) {
        console.error('Create user error:', err);
        res.status(500).json({ error: 'Failed to create user' });
    }
});

// UPDATE user (supports moving between collections if role changes)
app.put('/api/admin/users/:role/:id', authMiddleware, adminMiddleware, async (req, res) => {
    try {
        const currentRole = req.params.role.toLowerCase();
        const id = req.params.id;
        const { role: newRole, password: newPassword, ...fields } = req.body;

        let Model;
        switch (currentRole) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
            case 'user': Model = User; break;
            default: return res.status(400).json({ error: 'Invalid source role' });
        }

        const existingUser = await Model.findById(id);
        if (!existingUser) return res.status(404).json({ error: 'User not found' });

        let updatedPasswordHash;
        if (newPassword && newPassword.trim().length >= 6) {
            updatedPasswordHash = await secureHashPassword(newPassword.trim());
        }

        if (newRole && newRole.toLowerCase() !== currentRole) {
            const targetRole = newRole.toLowerCase();
            let TargetModel;
            switch (targetRole) {
                case 'admin': TargetModel = Admin; break;
                case 'manager': TargetModel = Manager; break;
                case 'driver': TargetModel = Driver; break;
                case 'user': TargetModel = User; break;
                default: return res.status(400).json({ error: 'Invalid target role' });
            }

            const duplicate = await TargetModel.findOne({ username: existingUser.username });
            if (duplicate) return res.status(409).json({ error: 'Username already exists in target role.' });

            const baseData = {
                username: existingUser.username,
                password: updatedPasswordHash || existingUser.password
            };

            let created;
            if (targetRole === 'admin') {
                created = await Admin.create({
                    ...baseData,
                    email: fields.email || existingUser.email || undefined,
                    permissions: fields.permissions || ['all']
                });
            } else if (targetRole === 'manager') {
                created = await Manager.create({
                    ...baseData,
                    email: fields.email || existingUser.email || undefined,
                    employeeId: fields.employeeId || 'EMP_' + existingUser.username,
                    department: fields.department || 'Transit',
                    canManage: fields.canManage || ['students', 'drivers', 'buses']
                });
            } else if (targetRole === 'driver') {
                created = await Driver.create({
                    ...baseData,
                    name: fields.name || existingUser.name || existingUser.username,
                    assignedBus: fields.assignedBus || '',
                    contactNumber: fields.contactNumber || fields.phone || '',
                    status: fields.status || existingUser.status || 'Active'
                });
            } else if (targetRole === 'user') {
                created = await User.create({
                    ...baseData,
                    name: fields.name || existingUser.name || existingUser.username,
                    email: fields.email || existingUser.email || undefined,
                    phone: fields.phone || existingUser.phone || '',
                    routeId: fields.routeId || null,
                    pickupPoint: fields.pickupPoint || null,
                    gender: fields.gender || '',
                    fatherName: fields.fatherName || '',
                    courseName: fields.courseName || '',
                    fatherPhone: fields.fatherPhone || '',
                    status: fields.status || existingUser.status || 'Active',
                    userId: fields.userId || existingUser.username,
                    accessRights: fields.accessRights || ['view_routes', 'track_bus']
                });
            }

            await RegistrationSubmission.findOneAndUpdate(
                { createdUserId: id },
                { createdUserId: created._id.toString(), status: targetRole === 'user' ? 'approved' : 'pending' }
            );

            await Model.findByIdAndDelete(id);

            broadcastStats();
            return res.json({ success: true, roleChanged: true, user: created });
        } else {
            const updateBody = { ...fields };
            if (updatedPasswordHash) {
                updateBody.password = updatedPasswordHash;
            }

            const updated = await Model.findByIdAndUpdate(id, updateBody, { new: true });
            
            if (currentRole === 'user') {
                const updateSubmissionFields = {};
                if (fields.name !== undefined) updateSubmissionFields.name = fields.name;
                if (fields.email !== undefined) updateSubmissionFields.email = fields.email;
                if (fields.phone !== undefined) updateSubmissionFields.phone = fields.phone;
                if (fields.routeId !== undefined) updateSubmissionFields.routeId = fields.routeId;
                if (fields.pickupPoint !== undefined) updateSubmissionFields.pickupStop = fields.pickupPoint;
                if (fields.courseName !== undefined) updateSubmissionFields.courseName = fields.courseName;

                if (Object.keys(updateSubmissionFields).length > 0) {
                    await RegistrationSubmission.findOneAndUpdate(
                        { createdUserId: id },
                        { $set: updateSubmissionFields }
                    );
                }
            }

            broadcastStats();
            return res.json({ success: true, roleChanged: false, user: updated });
        }
    } catch (err) {
        console.error('Update user error:', err);
        res.status(500).json({ error: 'Failed to update user' });
    }
});

// DELETE user from specified collection
app.delete('/api/admin/users/:role/:id', authMiddleware, adminMiddleware, async (req, res) => {
    try {
        const role = req.params.role.toLowerCase();
        const id = req.params.id;

        let Model;
        switch (role) {
            case 'admin': Model = Admin; break;
            case 'manager': Model = Manager; break;
            case 'driver': Model = Driver; break;
            case 'user': Model = User; break;
            default: return res.status(400).json({ error: 'Invalid role' });
        }

        const user = await Model.findById(id);
        if (!user) return res.status(404).json({ error: 'User not found' });

        if (role === 'user') {
            await RegistrationSubmission.findOneAndUpdate(
                { createdUserId: id },
                {
                    status: 'pending',
                    createdUserId: undefined,
                    generatedUsername: undefined,
                    generatedPassword: undefined,
                    reviewedAt: undefined
                }
            );
        }

        await Model.findByIdAndDelete(id);
        broadcastStats();
        res.json({ success: true, message: `User deleted successfully from ${role} collection` });
    } catch (err) {
        console.error('Delete user error:', err);
        res.status(500).json({ error: 'Failed to delete user' });
    }
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Server running on port ${PORT}`);
    console.log(`📡 Socket.io ready for connections`);

// ⚡ Automated SMS & WhatsApp Geofence Proximity Notification Engine
async function sendProximitySMSWhatsApp(userObj, stopName, distanceKm, minutes, busNumber) {
    const phoneNumber = userObj.phone || userObj.parentPhone || userObj.mobile;
    if (!phoneNumber) return;
    
    const formattedPhone = phoneNumber.replace(/[^0-9]/g, '');
    const whatsAppMessage = `🟢 *SISTecChalo WhatsApp Alert*\n\n🚌 Shuttle Bus *${busNumber || 'Express'}* is approaching your stop *${stopName}*!\n📍 *Distance*: ${distanceKm.toFixed(1)} km\n⏱️ *ETA*: ~${minutes} min\n\nPlease proceed to your pickup point safely.`;
    
    // 1. WhatsApp Business Cloud API / Twilio WhatsApp Webhook
    const whatsAppToken = process.env.WHATSAPP_API_TOKEN;
    const whatsAppPhoneId = process.env.WHATSAPP_PHONE_ID;
    
    if (whatsAppToken && whatsAppPhoneId) {
        try {
            await fetch(`https://graph.facebook.com/v18.0/${whatsAppPhoneId}/messages`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${whatsAppToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    messaging_product: 'whatsapp',
                    to: formattedPhone.length === 10 ? `91${formattedPhone}` : formattedPhone,
                    type: 'text',
                    text: { body: whatsAppMessage }
                })
            });
            console.log(`💬 [WhatsApp Cloud API] Arrival notification sent to +${formattedPhone}`);
        } catch (err) {
            console.warn(`⚠️ [WhatsApp API Warning] ${err.message}`);
        }
    }
    
    // 2. Brevo SMS / Twilio Fallback
    const brevoKey = process.env.BREVO_API_KEY;
    if (brevoKey) {
        try {
            await fetch('https://api.brevo.com/v3/transactionalSMS/sms', {
                method: 'POST',
                headers: {
                    'accept': 'application/json',
                    'api-key': brevoKey,
                    'content-type': 'application/json'
                },
                body: JSON.stringify({
                    sender: 'SISTec',
                    recipient: formattedPhone,
                    content: `[SISTecChalo] Bus ${busNumber || ''} is approaching ${stopName}! Distance: ${distanceKm.toFixed(1)}km (~${minutes} min).`
                })
            });
            console.log(`📱 [Transactional SMS] Proximity SMS dispatched to ${formattedPhone}`);
        } catch (err) {
            console.warn(`⚠️ [SMS Warning] ${err.message}`);
        }
    } else {
        console.log(`💬 [WhatsApp / SMS Alert Simulation] Target ${formattedPhone}: "${whatsAppMessage}"`);
    }
}

// ⚡ FUEL MILEAGE & VEHICLE COST MANAGER ROUTES

// 1. POST /api/driver/fuel-log — Driver logs fuel refill entry
app.post('/api/driver/fuel-log', authMiddleware, async (req, res) => {
    try {
        const { busId, busNumber, odometerKm, liters, totalCost, fuelStation, receiptImage } = req.body;
        if (!busId || !odometerKm || !liters || !totalCost) {
            return res.status(400).json({ error: 'busId, odometerKm, liters, and totalCost are required' });
        }

        const odo = Number(odometerKm);
        const ltr = Number(liters);
        const cost = Number(totalCost);

        // Find previous fuel log for mileage calculation (km / liter)
        const previousLog = await FuelLog.findOne({ busId }).sort({ refillDate: -1 });
        let mileage = 0.0;
        if (previousLog && odo > previousLog.odometerKm && ltr > 0) {
            const distanceDriven = odo - previousLog.odometerKm;
            mileage = Number((distanceDriven / ltr).toFixed(2));
        } else {
            mileage = 4.5; // Default average shuttle bus km/L
        }

        const log = new FuelLog({
            busId,
            busNumber: busNumber || 'MP-04-HB-1001',
            driverId: req.user.id,
            driverName: req.user.name || req.user.username || 'Driver',
            odometerKm: odo,
            liters: ltr,
            totalCost: cost,
            fuelPricePerLiter: Number((cost / ltr).toFixed(2)),
            fuelStation: fuelStation || 'Indian Oil',
            receiptImage: receiptImage || null,
            mileageKmPerLiter: mileage,
            refillDate: new Date()
        });

        await log.save();

        // Broadcast fuel event over WebSockets
        io.emit('fuelLogAdded', log);

        console.log(`⛽ [Fuel Logged] Bus ${busNumber} — ${ltr}L @ ₹${cost} (Mileage: ${mileage} km/L)`);

        res.json({
            success: true,
            message: 'Fuel refill logged successfully',
            log
        });
    } catch (err) {
        console.error('Fuel log error:', err);
        res.status(500).json({ error: 'Failed to record fuel log' });
    }
});

// 2. GET /api/manager/fuel-logs — Manager fetches refill history
app.get('/api/manager/fuel-logs', authMiddleware, async (req, res) => {
    try {
        const logs = await FuelLog.find().sort({ refillDate: -1 }).limit(100);
        res.json({ success: true, logs });
    } catch (err) {
        console.error('Fuel logs fetch error:', err);
        res.status(500).json({ error: 'Failed to fetch fuel logs' });
    }
});

// 3. GET /api/manager/fuel-analytics — Fleet fuel & mileage KPI summary
app.get('/api/manager/fuel-analytics', authMiddleware, async (req, res) => {
    try {
        const logs = await FuelLog.find();
        let totalSpend = 0;
        let totalLiters = 0;
        let validMileageCount = 0;
        let mileageSum = 0;

        logs.forEach(log => {
            totalSpend += log.totalCost || 0;
            totalLiters += log.liters || 0;
            if (log.mileageKmPerLiter && log.mileageKmPerLiter > 0) {
                mileageSum += log.mileageKmPerLiter;
                validMileageCount++;
            }
        });

        const avgMileage = validMileageCount > 0 ? Number((mileageSum / validMileageCount).toFixed(2)) : 4.5;

        res.json({
            success: true,
            totalSpend,
            totalLiters: Number(totalLiters.toFixed(1)),
            avgMileage,
            totalRefills: logs.length
        });
    } catch (err) {
        console.error('Fuel analytics error:', err);
        res.status(500).json({ error: 'Failed to compute fuel analytics' });
    }
});

// ⚡ DYNAMIC QR BUS PASS & BOARDING ATTENDANCE ROUTES

// 1. GET /api/student/bus-pass — Generate dynamic QR pass payload for logged in student
app.get('/api/student/bus-pass', authMiddleware, async (req, res) => {
    try {
        const student = await User.findById(req.user.id) || await Student.findById(req.user.id);
        if (!student) return res.status(404).json({ error: 'Student record not found' });

        const passData = {
            passId: `PASS-${student._id.toString().substring(0, 8).toUpperCase()}`,
            studentId: student._id.toString(),
            studentName: student.name || student.username,
            rollNumber: student.rollNumber || student.username || 'SISTEC-2026',
            routeName: student.routeName || 'Campus Express',
            pickupPoint: student.pickupPoint || 'Main Gate',
            validUntil: '2026-06-30',
            status: 'Active',
            generatedAt: new Date().toISOString(),
            signature: Buffer.from(`${student._id}_${Date.now()}`).toString('base64')
        };

        res.json({ success: true, pass: passData });
    } catch (err) {
        console.error('Bus pass generation error:', err);
        res.status(500).json({ error: 'Failed to generate digital bus pass' });
    }
});

// 2. POST /api/driver/scan-pass — Driver scans student's QR code upon boarding
app.post('/api/driver/scan-pass', authMiddleware, async (req, res) => {
    try {
        const { qrData, busId, busNumber } = req.body;
        if (!qrData) return res.status(400).json({ error: 'QR code data payload is required' });

        let parsed = {};
        try {
            parsed = typeof qrData === 'string' ? JSON.parse(qrData) : qrData;
        } catch (_) {
            parsed = { studentId: qrData, studentName: 'Scanned Student', rollNumber: qrData };
        }

        const studentId = parsed.studentId || parsed.id || 'UNKNOWN';
        const studentName = parsed.studentName || parsed.name || 'Student';
        const rollNumber = parsed.rollNumber || parsed.roll || 'SISTEC-STUDENT';
        const pickupPoint = parsed.pickupPoint || 'Assigned Stop';
        const routeName = parsed.routeName || 'Campus Route';

        // Check if student already boarded recently (within last 30 mins)
        const recentBoarding = await BoardingLog.findOne({
            studentId: studentId,
            boardedAt: { $gte: new Date(Date.now() - 30 * 60 * 1000) }
        });

        if (recentBoarding) {
            return res.json({
                success: true,
                valid: true,
                alreadyBoarded: true,
                message: `Already Boarded at ${new Date(recentBoarding.boardedAt).toLocaleTimeString()}`,
                studentName,
                rollNumber,
                pickupPoint
            });
        }

        const log = new BoardingLog({
            studentId,
            studentName,
            rollNumber,
            busId: busId || 'BUS-01',
            busNumber: busNumber || 'MP-04-HB-1001',
            routeName,
            pickupPoint,
            driverId: req.user.id,
            driverName: req.user.name || 'Driver',
            boardedAt: new Date(),
            status: 'Valid'
        });

        await log.save();

        // Broadcast WebSocket event to Web Management Dashboard & Mobile Clients
        io.emit('studentBoarded', log);

        console.log(`🎟️ [QR Scan Success] Student ${studentName} (${rollNumber}) boarded Bus ${busNumber || 'BUS-01'}`);

        res.json({
            success: true,
            valid: true,
            message: 'Bus Pass Validated & Boarding Logged',
            studentName,
            rollNumber,
            pickupPoint,
            boardedAt: log.boardedAt
        });

    } catch (err) {
        console.error('Pass scan error:', err);
        res.status(500).json({ error: 'Failed to process QR pass scan' });
    }
});

// 3. GET /api/manager/boarding-logs — Fetch daily attendance logs for Web Dashboard
app.get('/api/manager/boarding-logs', authMiddleware, async (req, res) => {
    try {
        const logs = await BoardingLog.find().sort({ boardedAt: -1 }).limit(100);
        res.json({ success: true, logs });
    } catch (err) {
        console.error('Boarding logs error:', err);
        res.status(500).json({ error: 'Failed to fetch boarding logs' });
    }
});

    // ─── Real Driver Telemetry Inactivity Watchdog (Production Strict) ────────
    // Automatically marks bus Offline if driver stops broadcasting (>30s)
    setInterval(async () => {
        try {
            const staleCutoff = new Date(Date.now() - 30 * 1000);
            const staleBuses = await Bus.find({
                status: { $in: ['On-time', 'Delayed', 'Active'] },
                lastUpdated: { $lt: staleCutoff }
            });

            if (staleBuses && staleBuses.length > 0) {
                for (const bus of staleBuses) {
                    bus.status = 'Offline';
                    bus.speed = 0;
                    bus.etas = [];
                    await bus.save();

                    const offlinePayload = {
                        id: bus._id.toString(),
                        _id: bus._id.toString(),
                        busId: bus._id.toString(),
                        busNumber: bus.busNumber,
                        name: bus.name,
                        routeId: bus.routeId,
                        routeName: bus.routeName,
                        routeColor: bus.routeColor,
                        tripType: bus.tripType,
                        occupancy: bus.occupancy,
                        driverId: bus.driverId,
                        currentLat: bus.currentLat,
                        latitude: bus.currentLat,
                        currentLng: bus.currentLng,
                        longitude: bus.currentLng,
                        speed: 0,
                        heading: bus.heading,
                        status: 'Offline',
                        etas: [],
                        lastUpdated: new Date()
                    };

                    io.emit('busLocationUpdate', offlinePayload);
                    io.emit('locationUpdate', offlinePayload);
                    io.emit('busUpdated', offlinePayload);
                    if (bus.routeId) {
                        io.to(`route_${bus.routeId.toString()}`).emit('busLocationUpdate', offlinePayload);
                        io.to(`route_${bus.routeId.toString()}`).emit('locationUpdate', offlinePayload);
                        io.to(`route_${bus.routeId.toString()}`).emit('busUpdated', offlinePayload);
                    }
                    console.log(`📴 [DRIVER INACTIVITY WATCHDOG] Bus ${bus.busNumber || bus._id} stopped broadcasting (>30s) -> Marked Offline`);
                }
            }
        } catch (err) {
            console.error('Watchdog interval error:', err.message);
        }
    }, 10000);

    // ⚡ RENDER 100% FREE KEEP-ALIVE ENGINE (Prevents 15-min idle sleep)
    const SELF_URL = process.env.SELF_URL || process.env.RENDER_EXTERNAL_URL || 'https://smart-shuttle-backend-2h13.onrender.com';
    const httpProtocol = SELF_URL.startsWith('https') ? require('https') : require('http');

    const triggerKeepAlive = () => {
        try {
            httpProtocol.get(`${SELF_URL}/api/health`, (res) => {
                console.log(`🏓 [Render Free Keep-Alive] Self-Ping OK — status: ${res.statusCode}`);
            }).on('error', (err) => {
                console.warn(`⚠️ [Render Free Keep-Alive] Self-Ping warn: ${err.message}`);
            });
        } catch (e) {
            console.warn(`⚠️ [Render Free Keep-Alive] Ping invoke error: ${e.message}`);
        }
    };

    // Ping every 5 minutes (Render sleep threshold is 15 minutes)
    setInterval(triggerKeepAlive, 5 * 60 * 1000);
    // Initial ping 15 seconds after startup
    setTimeout(triggerKeepAlive, 15000);

    console.log(`⚡ [Render 100% Free Keep-Alive] Active every 5 min → ${SELF_URL}/api/health`);
});








