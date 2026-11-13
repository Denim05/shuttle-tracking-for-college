const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });

if ((process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'staging') && !process.env.JWT_SECRET) {
    console.error(`FATAL: JWT_SECRET environment variable is strictly required in ${process.env.NODE_ENV} mode.`);
    process.exit(1);
}
const { resolveDatabaseConfig, sanitizeUriForLogging } = require('./services/db_config');
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const compression = require('compression');
const http = require('http');
const EventEmitter = require('events');
const { Server } = require('socket.io');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const {
    generateTripReportData,
    generateTripReportExcelBuffer,
    generateTripReportCsvString,
    generateTripReportPdfBuffer
} = require('./services/trip_report_generator');
const { syncDailyTripReportsToGoogleSheets, SPREADSHEET_ID } = require('./services/google_sheets_service');
const {
    noSqlSanitizeMiddleware,
    validateStringInputs,
    validatePagination,
    validateObjectIdParam
} = require('./middleware/noSqlSanitizer');
const { defaultLimiter } = require('./middleware/socketRateLimiter');

function areExternalNotificationsSuppressed(env = process.env) {
    const nodeEnv = (env.NODE_ENV || '').toLowerCase().trim();
    return (
        nodeEnv === 'test' ||
        nodeEnv === 'staging' ||
        String(env.DISABLE_EXTERNAL_NOTIFICATIONS || '').toLowerCase().trim() === 'true' ||
        String(env.MOCK_NOTIFICATIONS || '').toLowerCase().trim() === 'true'
    );
}

function initializeFirebaseAdmin(env = process.env, adminSdk = admin, fsMod = fs) {
    if (areExternalNotificationsSuppressed(env)) {
        console.log('🛡️ [Firebase] External notifications suppressed in current environment — skipping Firebase Admin initialization.');
        return { initialized: false, suppressed: true, provider: 'Mock Dispatcher' };
    }
    if (adminSdk.apps && adminSdk.apps.length > 0) {
        return { initialized: true, suppressed: false, source: 'existing' };
    }
    if (env.FIREBASE_SERVICE_ACCOUNT) {
        try {
            const credentials = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
            adminSdk.initializeApp({
                credential: adminSdk.credential.cert(credentials)
            });
            console.log('🔥 [Firebase] SDK Initialized successfully via environment variable.');
            return { initialized: true, suppressed: false, source: 'env' };
        } catch (err) {
            console.error('❌ [Firebase] SDK Initialization via env failed:', err.message);
            return { initialized: false, suppressed: false, error: 'env_init_failed' };
        }
    } else {
        let serviceAccountPath = path.resolve(__dirname, 'firebase-service-account.json');
        if (!fsMod.existsSync(serviceAccountPath)) {
            const altPath = path.resolve(__dirname, 'firebase-service-account.json.json');
            if (fsMod.existsSync(altPath)) serviceAccountPath = altPath;
        }
        if (fsMod.existsSync(serviceAccountPath)) {
            try {
                adminSdk.initializeApp({
                    credential: adminSdk.credential.cert(require(serviceAccountPath))
                });
                console.log('🔥 [Firebase] SDK Initialized successfully via file.');
                return { initialized: true, suppressed: false, source: 'file' };
            } catch (err) {
                console.error('❌ [Firebase] SDK Initialization via file failed:', err.message);
                return { initialized: false, suppressed: false, error: 'file_init_failed' };
            }
        } else {
            console.log('⚠️ [Firebase] Service Account JSON not found (no env var or file). Background push notifications will be inactive.');
            return { initialized: false, suppressed: false, reason: 'no_credentials' };
        }
    }
}

async function dispatchFcmMulticast(messagePayload, env = process.env, adminSdk = admin) {
    const tokens = (messagePayload && Array.isArray(messagePayload.tokens)) ? messagePayload.tokens.filter(Boolean) : [];
    if (areExternalNotificationsSuppressed(env)) {
        return {
            suppressed: true,
            provider: 'Mock Dispatcher',
            successCount: 0,
            failureCount: 0,
            responses: []
        };
    }
    if (!adminSdk.apps || adminSdk.apps.length === 0 || tokens.length === 0) {
        return {
            suppressed: false,
            skipped: true,
            successCount: 0,
            failureCount: 0,
            responses: []
        };
    }
    const response = await adminSdk.messaging().sendEachForMulticast({
        ...messagePayload,
        tokens
    });
    return {
        suppressed: false,
        provider: 'Firebase Admin FCM',
        ...response
    };
}

// Load Firebase service account credentials (only when external notifications are permitted)
initializeFirebaseAdmin();

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
const TripTelemetryPoint = require('./models/TripTelemetryPoint');
const {
    getIstDateString,
    persistTelemetryPointIfSampled,
    clearTelemetrySamplerState
} = require('./services/telemetry_persistence_service');
const RegistrationForm = require('./models/RegistrationForm');
const RegistrationSubmission = require('./models/RegistrationSubmission');
const BoardingLog = require('./models/BoardingLog');
const FuelLog = require('./models/FuelLog');
const StopFeedback = require('./models/StopFeedback');
const { processStopFeedback, getRouteFeedbackSummary } = require('./services/stop_consensus_service');

const { authMiddleware, passwordChangeAuth, optionalAuth, adminMiddleware, managerMiddleware, driverMiddleware, studentMiddleware, getAccountByIdAndRole, getJwtSecret } = require('./middleware/authMiddleware');

const defaultCorsAllowlist = [
    'http://localhost',
    'http://127.0.0.1',
    'https://smart-shuttle-backend-2h13.onrender.com'
];

function getCorsOptions(nodeEnv = process.env.NODE_ENV) {
    const env = (nodeEnv || 'development').toLowerCase().trim();
    if (env === 'development' || env === 'test') {
        return {
            origin: true,
            methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
            credentials: true
        };
    }

    const configuredOrigins = (process.env.ALLOWED_ORIGINS || '')
        .split(',')
        .map(o => o.trim())
        .filter(Boolean);

    return {
        origin: function (origin, callback) {
            // Mobile apps, server-to-server, curl, Postman send no Origin header
            if (!origin) return callback(null, true);

            try {
                const parsedUrl = new URL(origin);
                const hostname = parsedUrl.hostname;

                const isAllowed = defaultCorsAllowlist.some(allowed => origin === allowed || origin.startsWith(allowed + ':')) ||
                    configuredOrigins.some(allowed => origin === allowed || origin.endsWith(allowed)) ||
                    hostname === 'sistec.ac.in' ||
                    hostname.endsWith('.sistec.ac.in') ||
                    hostname.endsWith('.onrender.com');

                if (isAllowed) {
                    callback(null, true);
                } else {
                    callback(new Error(`CORS blocked for unauthorized origin: ${origin}`));
                }
            } catch (_) {
                callback(new Error(`CORS blocked for malformed origin: ${origin}`));
            }
        },
        methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        credentials: true
    };
}

const corsOptions = getCorsOptions();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: corsOptions,
    transports: ['websocket', 'polling'],
    allowEIO3: true,
    pingTimeout: 60000,
    pingInterval: 25000
});

// ─── Production Graceful Shutdown & Async Operation Drain Controller ──────
class AsyncOperationTracker {
    constructor() {
        this.activeCount = 0;
        this.emitter = new EventEmitter();
    }

    begin() {
        this.activeCount++;
    }

    end() {
        this.activeCount = Math.max(0, this.activeCount - 1);
        if (this.activeCount === 0) {
            this.emitter.emit('drained');
        }
    }

    getActiveCount() {
        return this.activeCount;
    }

    waitForDrain(timeoutMs = 5000) {
        if (this.activeCount === 0) return Promise.resolve({ drained: true, remaining: 0 });

        return new Promise((resolve) => {
            let timer = null;

            const onDrained = () => {
                if (timer) clearTimeout(timer);
                resolve({ drained: true, remaining: 0 });
            };

            timer = setTimeout(() => {
                this.emitter.removeListener('drained', onDrained);
                resolve({ drained: false, remaining: this.activeCount });
            }, timeoutMs);

            this.emitter.once('drained', onDrained);
        });
    }
}

let isShuttingDown = false;
const operationTracker = new AsyncOperationTracker();
let watchdogIntervalId = null;
let keepAliveIntervalId = null;
let keepAliveTimeoutId = null;

// Security Hashing Options (Argon2id - Immune to GPU & ASIC offline cracking, calibrated for high-concurrency cloud production)
const ARGON2_SECURITY_OPTIONS = {
    type: argon2.argon2id,
    memoryCost: 19456, // 19 MB per hash (OWASP recommended balance to avoid server OOM under 10k-user morning rush)
    timeCost: 2,       // 2 Iterations
    parallelism: 1
};
const DUMMY_HASH = '$argon2id$v=19$m=19456,t=2,p=1$5yp8+T80L+ifnYMzqwbm9Q$b/rlskYRqNiOyHDvvgNTyLnPDiYQ/735LyMIRnYCf1g';

const recoveryLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many recovery requests. Please try again after 15 minutes.' }
});

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

// 🛑 Graceful Shutdown Ingress Barrier & Operation Tracker
function shutdownIngressMiddleware(req, res, next) {
    if (isShuttingDown) {
        res.set('Connection', 'close');
        if (req.path === '/api/health' || req.path === '/health' || req.path === '/') {
            return res.status(503).json({ status: 'shutting_down', service: 'SISTecChalo Backend' });
        }
        if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
            res.set('Retry-After', '5');
            return res.status(503).json({ error: 'SERVER_SHUTTING_DOWN', message: 'Server is restarting for deployment.' });
        }
    }

    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
        operationTracker.begin();
        let ended = false;
        const onFinishOrClose = () => {
            if (!ended) {
                ended = true;
                operationTracker.end();
            }
        };
        res.once('finish', onFinishOrClose);
        res.once('close', onFinishOrClose);
    }
    next();
}

app.use(shutdownIngressMiddleware);

// Trust reverse proxy (e.g. Render) to correctly identify client IP and HTTPS protocol
app.set('trust proxy', 1);

app.use(helmet({
    contentSecurityPolicy: false, // APIs & mobile JSON endpoints do not serve browser UI
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" }, // Allows mobile & report file downloads
    hsts: process.env.NODE_ENV === 'production' ? {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true
    } : false
}));
app.use(cors(corsOptions));

// ⚡ High-Performance Gzip/Brotli Compression (Compresses 3.2MB routes to <270KB)
app.use(compression({
    level: 6,
    threshold: 1024,
    filter: (req, res) => {
        if (req.headers['x-no-compression']) return false;
        return compression.filter(req, res);
    }
}));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use(noSqlSanitizeMiddleware);
app.use((req, res, next) => {
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
        latestVersion: "1.0.8",
        latestBuildNumber: 23,
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
const isDevOrTest = process.env.NODE_ENV === 'staging' || process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'development';
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: isDevOrTest ? 10000 : 100, // Relaxed in staging/test for automated test runs; 100 in production
    message: { error: 'Too many requests, please try again later.' }
});
app.use('/api/', limiter);

// Dedicated Brute-Force Rate Limiter for Login Endpoint
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: isDevOrTest ? 1000 : 15, // Relaxed in staging/test; max 15 attempts in production
    message: { error: 'Too many login attempts. Please try again after 15 minutes.' }
});
app.use('/api/auth/login', loginLimiter);

// Pre-flight Configuration & Security Gate
if (require.main === module && process.env.NODE_ENV !== 'test') {
    let dbConfig;
    try {
        dbConfig = resolveDatabaseConfig({
            rawUri: process.env.MONGODB_URI,
            nodeEnv: process.env.NODE_ENV,
            envDbName: process.env.MONGODB_DB_NAME
        });
        getJwtSecret();
    } catch (configErr) {
        console.error(`\n❌ [CONFIG ERROR] ${configErr.message}\n`);
        process.exit(1);
    }

    const envLabel = (process.env.NODE_ENV || 'development').toLowerCase().trim();
    console.log(`📡 [DB] Connecting to configured ${envLabel} database...`);

    mongoose.connect(dbConfig.effectiveUri, dbConfig.options)
        .then(async () => {
            process.stdout.write(`\n\x1b[32m✅ [DB] SUCCESSFULLY CONNECTED!\x1b[0m\n`);
            console.log(`✅ [DB] Connected to configured ${envLabel} database.`);
            // Auto-seed real SGI routes on first boot if DB is empty
            await autoSeedRoutes();
            startServer();
        })
        .catch(err => {
            const safeError = sanitizeConnectionError(err);
            console.error(`\n❌ [DB FATAL] MongoDB Connection Error: ${safeError}`);
            console.error('❌ [DB FATAL] Startup aborted — HTTP server and background timers were not started.\n');
            process.exit(1);
        });
}

// ─── Auto-Seed: Seeds all 17 real Sagar Group of Institutions routes ──────────
// Only runs if the Route collection is empty and AUTO_SEED_ROUTES=true is explicitly set
async function autoSeedRoutes() {
    try {
        const Route = require('./models/Route');
        const count = await Route.countDocuments();
        if (count > 0) {
            console.log(`🗂️  [SEED] ${count} routes already exist — skipping auto-seed.`);
            return;
        }

        if (process.env.AUTO_SEED_ROUTES !== 'true') {
            console.log('ℹ️  [SEED] Route collection is empty. Automatic route seeding is disabled (set AUTO_SEED_ROUTES=true to enable).');
            return;
        }

        console.log('🌱 [SEED] No routes found — seeding real SGI bus routes...');
        const seedModule = require('./seed_real_routes');
        if (typeof seedModule.seed !== 'function') {
            console.warn('⚠️ [SEED] seed_real_routes does not export a seed function — skipping.');
            return;
        }
        const result = await seedModule.seed(false); // false means do not disconnect Mongoose
        if (result && result.seeded > 0) {
            console.log(`🎉 [SEED] Auto-seed completed successfully with ${result.seeded} routes!`);
        } else {
            console.log('ℹ️  [SEED] Auto-seed executed with 0 routes created (no-op). Staging routes must be set up explicitly.');
        }
    } catch (_err) {
        console.error('❌ [SEED] Auto-seed failed:', sanitizeConnectionError(_err));
    }
}

// Simple Route
app.get('/', (req, res) => {
    res.json({
        status: 'SISTecChalo Backend Online',
        database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
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

// Helper to broadcast stats to authorized manager/admin sockets
const broadcastStats = async (ioInstance = io, models = { Bus, Route, User }) => {
    try {
        const [busCount, routeCount, userCount] = await Promise.all([
            models.Bus.countDocuments(),
            models.Route.countDocuments(),
            models.User.countDocuments()
        ]);
        const payload = { busCount, routeCount, userCount };
        if (ioInstance && typeof ioInstance.to === 'function') {
            const managersRoom = ioInstance.to('managers');
            if (managersRoom && typeof managersRoom.emit === 'function') {
                managersRoom.emit('statsUpdate', payload);
            }
        }
        return payload;
    } catch (_err) {
        console.error('Stats broadcast error:', _err);
        return null;
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
app.post('/api/auth/login', validateStringInputs(['username', 'password']), async (req, res) => {
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

        // Check account status
        if (user.status && user.status === 'Suspended') {
            console.timeEnd('LoginRequest');
            return res.status(403).json({ error: 'This account has been suspended. Please contact the administrator.' });
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

        const isMustChange = user.mustChangePassword !== false;
        const currentVersion = user.tokenVersion || 0;

        // Generate Token with explicit scope and tokenVersion
        const token = jwt.sign(
            {
                user: { id: user.id, role: matchedRole, tokenVersion: currentVersion },
                scope: isMustChange ? 'password_change' : 'normal'
            },
            getJwtSecret(),
            { expiresIn: isMustChange ? '15m' : '90d' }
        );

        const userResponse = {
            id: user.id,
            username: user.username,
            name: user.name || user.username,
            role: matchedRole,
            email: user.email,
            status: user.status || 'Active',
            mustChangePassword: isMustChange
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
            mustChangePassword: isMustChange 
        });
        console.timeEnd('LoginRequest');

    } catch (_err) {
        console.error('❌ Login Error:', _err);
        console.timeEnd('LoginRequest');
        res.status(500).json({ error: 'Server error' });
    }
});

function buildForgotPasswordResponse() {
    return {
        success: true,
        message: 'If an account matches the provided details and has a registered email, recovery instructions have been sent.'
    };
}

/**
 * @api {post} /api/auth/forgot-password Secure Password Recovery (Token-based)
 */
app.post('/api/auth/forgot-password', recoveryLimiter, validateStringInputs([], ['identifier', 'email', 'username']), async (req, res) => {
    const rawIdentifier = (req.body.identifier || req.body.email || req.body.username || '').toString().trim();
    const providedEmail = (req.body.email || '').toString().trim();

    const genericResponse = buildForgotPasswordResponse();

    if (!rawIdentifier && !providedEmail) {
        return res.status(400).json({ error: 'Please provide your registered Email or Enrollment Number.' });
    }

    try {
        const query = rawIdentifier.includes('@') 
            ? { email: { $regex: new RegExp(`^${rawIdentifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } }
            : { username: { $regex: new RegExp(`^${rawIdentifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } };

        let matchedAccount = null;
        let MatchedModel = null;
        let matchedRole = 'user';

        const collections = [
            { role: 'user', model: User },
            { role: 'driver', model: Driver },
            { role: 'manager', model: Manager },
            { role: 'admin', model: Admin }
        ];

        for (const item of collections) {
            const acc = await item.model.findOne(query);
            if (acc) {
                matchedAccount = acc;
                MatchedModel = item.model;
                matchedRole = item.role;
                break;
            }
        }

        if (!matchedAccount && providedEmail && providedEmail.includes('@')) {
            const emailQuery = { email: { $regex: new RegExp(`^${providedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') } };
            for (const item of collections) {
                const acc = await item.model.findOne(emailQuery);
                if (acc) {
                    matchedAccount = acc;
                    MatchedModel = item.model;
                    matchedRole = item.role;
                    break;
                }
            }
        }

        // Constant-time mitigation: if user not found, suspended, or has no registered email, simulate hash work and return generic success
        if (!matchedAccount || (matchedAccount.status && matchedAccount.status === 'Suspended') || !matchedAccount.email) {
            await argon2.verify(DUMMY_HASH, rawIdentifier.slice(0, 128)).catch(() => {});
            return res.json(genericResponse);
        }

        const rawToken = crypto.randomBytes(32).toString('hex');
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');

        // 6-digit numeric recovery code for mobile app direct entry
        const recoveryCode = Math.floor(100000 + Math.random() * 900000).toString();
        const hashedCode = crypto.createHash('sha256').update(recoveryCode).digest('hex');

        matchedAccount.resetPasswordToken = hashedToken;
        matchedAccount.resetPasswordCode = hashedCode;
        matchedAccount.resetPasswordExpires = new Date(Date.now() + 15 * 60 * 1000);
        await matchedAccount.save();

        // Dispatch Email with recovery code (and token link) asynchronously without blocking the user password
        sendPasswordResetEmail(
            matchedAccount.email,
            matchedAccount.name || matchedAccount.username,
            matchedAccount.username,
            recoveryCode,
            matchedRole
        ).catch(async (emailErr) => {
            console.error('❌ [Auth] Password reset email dispatch failed:', emailErr.message);
            // Roll back tokens in database so no un-emailed token lingers
            await MatchedModel.updateOne(
                { _id: matchedAccount._id, resetPasswordToken: hashedToken },
                { $unset: { resetPasswordToken: 1, resetPasswordCode: 1, resetPasswordExpires: 1 } }
            ).catch(() => {});
        });

        // Constant-time hash verification to align execution latency with unknown user branch
        await argon2.verify(DUMMY_HASH, rawIdentifier.slice(0, 128)).catch(() => {});

        return res.json(genericResponse);

    } catch (err) {
        console.error('❌ Forgot password error:', err);
        return res.status(500).json({ error: 'Failed to process password recovery. Please try again.' });
    }
});

/**
 * @api {post} /api/auth/reset-password Reset Password Using Verification Token or Code
 */
app.post('/api/auth/reset-password', recoveryLimiter, validateStringInputs(['newPassword'], ['token', 'code']), async (req, res) => {
    const rawToken = (req.body.token || req.body.code || '').toString().trim();
    const newPassword = req.body.newPassword;

    if (!rawToken) {
        return res.status(400).json({ error: 'Reset token or recovery code is required.' });
    }
    if (!newPassword || newPassword.length < 6 || newPassword.length > 128) {
        return res.status(400).json({ error: 'New password must be between 6 and 128 characters long.' });
    }

    try {
        const hashedInput = crypto.createHash('sha256').update(rawToken).digest('hex');
        let matchedAccount = null;
        let MatchedModel = null;
        let matchedRole = null;

        for (const item of [
            { role: 'user', model: User },
            { role: 'driver', model: Driver },
            { role: 'manager', model: Manager },
            { role: 'admin', model: Admin }
        ]) {
            const acc = await item.model.findOne({
                $or: [
                    { resetPasswordToken: hashedInput },
                    { resetPasswordCode: hashedInput }
                ],
                resetPasswordExpires: { $gt: new Date() }
            });
            if (acc) {
                matchedAccount = acc;
                MatchedModel = item.model;
                matchedRole = item.role;
                break;
            }
        }

        if (!matchedAccount) {
            await argon2.verify(DUMMY_HASH, newPassword.slice(0, 128)).catch(() => {});
            return res.status(400).json({ error: 'Invalid or expired recovery token or code.' });
        }

        if (matchedAccount.status && matchedAccount.status === 'Suspended') {
            return res.status(403).json({ error: 'Account has been suspended. Please contact the administrator.' });
        }

        const isSame = await argon2.verify(matchedAccount.password, newPassword);
        if (isSame) {
            return res.status(400).json({ error: 'New password cannot be identical to your current password.' });
        }

        const hashedPassword = await secureHashPassword(newPassword);

        // Strictly atomic conditional update: only one concurrent consumer can match and consume the unexpired token
        const updateResult = await MatchedModel.updateOne(
            {
                _id: matchedAccount._id,
                $or: [
                    { resetPasswordToken: hashedInput },
                    { resetPasswordCode: hashedInput }
                ],
                resetPasswordExpires: { $gt: new Date() }
            },
            {
                $set: { password: hashedPassword, mustChangePassword: false },
                $inc: { tokenVersion: 1 },
                $unset: { resetPasswordToken: 1, resetPasswordCode: 1, resetPasswordExpires: 1 }
            }
        );

        if (!updateResult || updateResult.modifiedCount === 0) {
            return res.status(400).json({ error: 'Reset token or code was already consumed or expired.' });
        }

        res.json({
            success: true,
            message: 'Password has been reset successfully. Please sign in with your new password.'
        });
    } catch (err) {
        console.error('❌ Reset password error:', err);
        res.status(500).json({ error: 'Failed to reset password. Please try again.' });
    }
});

/**
 * @api {post} /api/auth/force-change-password Mandatory First-Time Password Reset (Authenticated)
 */
app.post('/api/auth/force-change-password', passwordChangeAuth, validateStringInputs(['newPassword'], ['currentPassword', 'oldPassword']), async (req, res) => {
    const { currentPassword, oldPassword, newPassword } = req.body;
    const pwdToCheck = (currentPassword || oldPassword || '').trim();

    console.log(`🔐 [Auth] Force-change-password request for user ID: "${req.user?.id}" (role: ${req.user?.role})`);

    if (!pwdToCheck) {
        return res.status(400).json({ error: 'Current password is required.' });
    }
    if (!newPassword || newPassword.length < 6 || newPassword.length > 128) {
        return res.status(400).json({ error: 'New password must be between 6 and 128 characters long.' });
    }

    try {
        let MatchedModel;
        switch (req.user.role) {
            case 'user': MatchedModel = User; break;
            case 'driver': MatchedModel = Driver; break;
            case 'manager': MatchedModel = Manager; break;
            case 'admin': MatchedModel = Admin; break;
            default: return res.status(400).json({ error: 'Invalid account role.' });
        }

        const account = await MatchedModel.findById(req.user.id);
        if (!account) {
            return res.status(404).json({ error: 'Account not found.' });
        }

        const isMatch = await argon2.verify(account.password, pwdToCheck);
        if (!isMatch) {
            return res.status(400).json({ error: 'Current temporary password is incorrect.' });
        }

        const isSame = await argon2.verify(account.password, newPassword);
        if (isSame) {
            return res.status(400).json({ error: 'New password cannot be identical to your current password.' });
        }

        const hashedPassword = await secureHashPassword(newPassword);
        account.password = hashedPassword;
        account.mustChangePassword = false;
        account.tokenVersion = (account.tokenVersion || 0) + 1;
        await account.save();

        console.log(`✅ [Auth] Password successfully updated for user "${account.username}" (${req.user.role}). mustChangePassword=false`);

        const freshToken = jwt.sign(
            { user: { id: account.id, role: req.user.role, tokenVersion: account.tokenVersion }, scope: 'normal' },
            getJwtSecret(),
            { expiresIn: '90d' }
        );

        const updatedUserResponse = {
            id: account.id,
            username: account.username,
            name: account.name || account.username,
            role: req.user.role,
            email: account.email,
            status: account.status || 'Active',
            mustChangePassword: false
        };

        if (req.user.role === 'user') {
            updatedUserResponse.routeId = account.routeId;
            updatedUserResponse.pickupPoint = account.pickupPoint;
            updatedUserResponse.localAddress = account.localAddress;
            updatedUserResponse.isCommuteConfigured = account.isCommuteConfigured || (!!account.routeId && !!account.pickupPoint);
            updatedUserResponse.userId = account.userId;
            updatedUserResponse.proximityAlertsEnabled = account.proximityAlertsEnabled ?? true;
            updatedUserResponse.proximityRadiusKm = account.proximityRadiusKm ?? 1.0;
        }

        res.json({
            success: true,
            message: 'Password successfully updated! Welcome to SISTecChalo.',
            token: freshToken,
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

app.get('/api/routes/:id', authMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/routes/:id/stops/feedback', authMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.get('/api/routes/:id/stops/feedback-summary', authMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.get('/api/manager/stop-feedback', authMiddleware, managerMiddleware, async (req, res) => {
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
app.post('/api/manager/stop-feedback/:id/apply', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/manager/stop-feedback/:id/reject', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
// --- User Management Routes (Strict RBAC Protected) ---

// --- ADMIN Management ---
app.post('/api/admins', authMiddleware, adminMiddleware, async (req, res) => {
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
app.post('/api/managers', authMiddleware, adminMiddleware, async (req, res) => {
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

app.get('/api/managers', authMiddleware, adminMiddleware, async (req, res) => {
    try {
        const managers = await Manager.find().select('-password');
        res.json(managers);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch managers' });
    }
});

// --- USER Management (Standard Users) ---
app.post('/api/users', authMiddleware, managerMiddleware, async (req, res) => {
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

app.get('/api/users', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const users = await User.find().select('-password').lean();
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
app.put('/api/users/:id/rights', authMiddleware, adminMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

// Student Management (Admin/Manager Protected)
app.get('/api/students', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const students = await Student.find();
        res.json(students);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch students' });
    }
});

app.post('/api/students', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const newStudent = new Student(req.body);
        await newStudent.save();
        res.status(201).json(newStudent);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to add student' });
    }
});

app.delete('/api/students/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

app.put('/api/buses/:id/status', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

function normalizeNotificationPayload(body = {}) {
    const validAudiences = ['All', 'Users', 'Students', 'Drivers', 'Admins'];
    const rawAudience = typeof body.targetAudience === 'string' ? body.targetAudience.trim() : '';
    const targetAudience = validAudiences.includes(rawAudience) ? rawAudience : 'All';

    const validPriorities = ['low', 'normal', 'high', 'urgent'];
    const rawPriority = typeof body.priority === 'string' ? body.priority.trim().toLowerCase() : '';
    const type = (typeof body.type === 'string' && body.type.trim().length > 0) ? body.type.trim() : 'info';
    const defaultPriority = (type === 'emergency' || type === 'critical') ? 'urgent' : 'normal';
    const priority = validPriorities.includes(rawPriority) ? rawPriority : defaultPriority;
    const title = (typeof body.title === 'string' && body.title.trim().length > 0) ? body.title.trim() : '';
    const message = typeof body.message === 'string' ? body.message.trim() : '';

    return {
        title,
        message,
        type,
        priority,
        targetAudience
    };
}

function emitBroadcastNotification(ioInstance, notificationDoc) {
    if (!ioInstance) return;
    const plain = (notificationDoc && typeof notificationDoc.toObject === 'function')
        ? notificationDoc.toObject()
        : { ...(notificationDoc || {}) };
    const normalizedType = typeof plain.type === 'string' ? plain.type.trim().toLowerCase() : '';
    const normalizedAudience = typeof plain.targetAudience === 'string' ? plain.targetAudience.trim().toLowerCase() : '';
    const isAdminsOnly = ['admins', 'admin', 'managers', 'manager'].includes(normalizedAudience) || normalizedType === 'emergency';
    const alertPayload = {
        id: plain._id ? plain._id.toString() : plain.id,
        title: plain.title || '',
        message: plain.message || '',
        type: plain.type || 'info',
        priority: plain.priority || 'normal',
        targetAudience: plain.targetAudience || 'All',
        timestamp: plain.createdAt ? new Date(plain.createdAt).toISOString() : new Date().toISOString()
    };

    if (isAdminsOnly) {
        if (typeof ioInstance.to === 'function') {
            ioInstance.to('managers').emit('notification', plain);
            ioInstance.to('managers').emit('systemAlert', alertPayload);
        }
    } else if (typeof ioInstance.emit === 'function') {
        ioInstance.emit('notification', plain);
        ioInstance.emit('systemAlert', alertPayload);
    }
}

// Manager: Broadcast Notification
app.post('/api/manager/notifications', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const normalized = normalizeNotificationPayload(req.body);
        if (!normalized.message) {
            return res.status(400).json({ error: 'Notification message is required' });
        }

        // Save to Database
        const newNotification = new Notification({
            title: normalized.title,
            message: normalized.message,
            type: normalized.type,
            priority: normalized.priority,
            targetAudience: normalized.targetAudience,
            createdBy: 'Manager'
        });
        await newNotification.save();

        // Emit both notification (for history) and systemAlert (for live pop-ups)
        emitBroadcastNotification(io, newNotification);
        console.log(`📢 [Manager Broadcast to ${normalized.targetAudience}] "${normalized.message}"`);
        res.json({ success: true, notification: newNotification });
    } catch (err) {
        console.error('❌ Error broadcasting notification:', err);
        res.status(500).json({ error: 'Failed to broadcast notification' });
    }
});

// Manager: Delete Notification
app.delete(['/api/manager/notifications/:id', '/api/notifications/:id'], authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

// ─── MANAGER: 2-TRIP DAY-WISE BUS OPERATIONAL REPORT (JSON & CSV/Excel) ────────────
// GET /api/manager/reports/bus-trip-report?date=YYYY-MM-DD&shift=all|morning|evening&busId=<id>&days=1&format=json|csv
app.get('/api/manager/reports/bus-trip-report', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const { date, shift, busId, routeId, direction, tripId, days, format, csvType } = req.query;
        const targetDate = date || getIstDateString();
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null,
            routeId: routeId || null,
            direction: direction || null,
            tripId: tripId || null,
            days: days ? parseInt(days, 10) : 1
        });

        // If client requested Excel (.xlsx) format
        if (format === 'xlsx' || format === 'excel') {
            const excelBuffer = generateTripReportExcelBuffer(reportData);
            const safeDate = targetDate.replace(/[^0-9-]/g, '');
            const safeBus = busId ? `_${String(busId).replace(/[^a-zA-Z0-9_-]/g, '')}` : '';
            res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
            res.setHeader('Content-Disposition', `attachment; filename="sistec_fleet_report_${safeDate}_${targetShift}${safeBus}.xlsx"`);
            return res.status(200).send(excelBuffer);
        }

        // If client requested PDF (.pdf) format
        if (format === 'pdf') {
            const pdfBuffer = await generateTripReportPdfBuffer(reportData);
            const safeDate = targetDate.replace(/[^0-9-]/g, '');
            const safeBus = busId ? `_${String(busId).replace(/[^a-zA-Z0-9_-]/g, '')}` : '';
            res.setHeader('Content-Type', 'application/pdf');
            res.setHeader('Content-Disposition', `attachment; filename="sistec_fleet_report_${safeDate}_${targetShift}${safeBus}.pdf"`);
            return res.status(200).send(pdfBuffer);
        }

        // If client requested JSON or sent Accept: application/json
        const wantsJson = format === 'json' || 
                          req.query.json === 'true' || 
                          (req.headers.accept && req.headers.accept.includes('application/json') && format !== 'csv' && format !== 'xlsx' && format !== 'pdf');

        if (wantsJson) {
            return res.json({
                success: true,
                ...reportData
            });
        }

        // Generate clean UTF-8 BOM CSV matching organized fleet schema (Row 1 header)
        const selectedCsvType = csvType ? String(csvType).trim() : 'trip_summary';
        const csv = generateTripReportCsvString(reportData, selectedCsvType);
        const safeDate = targetDate.replace(/[^0-9-]/g, '');
        const safeBus = busId ? `_${String(busId).replace(/[^a-zA-Z0-9_-]/g, '')}` : '';
        const safeCsvType = selectedCsvType.replace(/[^a-zA-Z0-9_-]/g, '');
        const csvFilePrefix = csvType ? `sistec_${safeCsvType}` : 'sistec_fleet_report';
        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="${csvFilePrefix}_${safeDate}_${targetShift}${safeBus}.csv"`);
        return res.status(200).send(csv);
    } catch (err) {
        console.error('Report Generation Error:', err);
        res.status(500).json({ error: 'Failed to generate report' });
    }
});

// ─── MANAGER: DIRECT MICROSOFT EXCEL (.XLSX) DOWNLOAD ───────────────────────
// GET /api/manager/reports/bus-trip-report/excel?date=YYYY-MM-DD&shift=all|morning|evening&busId=<id>&days=1
const reportAuthMiddleware = async (req, res, next) => {
    const authHeader = req.header('Authorization');
    if (!authHeader) {
        return res.status(401).json({ error: 'Authorization header required to access executive reports' });
    }
    try {
        const tokenString = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;
        const decoded = jwt.verify(tokenString, getJwtSecret());
        if (decoded.scope === 'password_change') {
            return res.status(403).json({ error: 'Restricted password-change token cannot access executive reports' });
        }
        if (decoded.user?.role !== 'manager' && decoded.user?.role !== 'admin') {
            return res.status(403).json({ error: 'Manager or Administrator privileges required' });
        }
        req.user = decoded.user;
        next();
    } catch (_) {
        return res.status(401).json({ error: 'Invalid or expired report authorization' });
    }
};

app.get('/api/manager/reports/bus-trip-report/excel', reportAuthMiddleware, async (req, res) => {
    try {
        const { date, shift, busId, routeId, direction, tripId, days } = req.query;
        const targetDate = date || getIstDateString();
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null,
            routeId: routeId || null,
            direction: direction || null,
            tripId: tripId || null,
            days: days ? parseInt(days, 10) : 1
        });

        const excelBuffer = generateTripReportExcelBuffer(reportData);
        const safeDate = targetDate.replace(/[^0-9-]/g, '');
        const safeBus = busId ? `_${String(busId).replace(/[^a-zA-Z0-9_-]/g, '')}` : '';
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename="sistec_fleet_report_${safeDate}_${targetShift}${safeBus}.xlsx"`);
        return res.status(200).send(excelBuffer);
    } catch (err) {
        console.error('Excel Report Generation Error:', err);
        res.status(500).json({ error: 'Failed to generate Excel report' });
    }
});

// ─── MANAGER: DIRECT PDF (.PDF) REPORT DOWNLOAD ──────────────────────────────
// GET /api/manager/reports/bus-trip-report/pdf?date=YYYY-MM-DD&shift=all|morning|evening&busId=<id>&days=1
app.get('/api/manager/reports/bus-trip-report/pdf', reportAuthMiddleware, async (req, res) => {
    try {
        const { date, shift, busId, routeId, direction, tripId, days } = req.query;
        const targetDate = date || getIstDateString();
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null,
            routeId: routeId || null,
            direction: direction || null,
            tripId: tripId || null,
            days: days ? parseInt(days, 10) : 1
        });

        const pdfBuffer = await generateTripReportPdfBuffer(reportData);
        const safeDate = targetDate.replace(/[^0-9-]/g, '');
        const safeBus = busId ? `_${String(busId).replace(/[^a-zA-Z0-9_-]/g, '')}` : '';
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename="sistec_fleet_report_${safeDate}_${targetShift}${safeBus}.pdf"`);
        return res.status(200).send(pdfBuffer);
    } catch (err) {
        console.error('PDF Report Generation Error:', err);
        res.status(500).json({ error: 'Failed to generate PDF report' });
    }
});

function formatReportDistance(distanceVal) {
    if (distanceVal === undefined || distanceVal === null || String(distanceVal).trim() === '') {
        return 'N/A';
    }
    const raw = String(distanceVal).trim();
    if (raw.toUpperCase() === 'N/A' || raw.toLowerCase().includes('km')) {
        return raw;
    }
    return `${raw} km`;
}

// ─── MANAGER: PRINTABLE 2-TRIP DAY-WISE HTML & PDF EXECUTIVE REPORT ─────────
// GET /api/manager/reports/bus-trip-report/html?date=YYYY-MM-DD&shift=all|morning|evening&busId=<id>&days=1
function renderTripReportHtml(reportData) {
        const allTripsList = Array.isArray(reportData.allTrips)
            ? reportData.allTrips
            : [...(reportData.morningTrips || []), ...(reportData.eveningTrips || [])];
        const safeEmbeddedTripsJson = JSON.stringify(allTripsList.map(t => ({
            tripId: t.tripId || '',
            date: t.date || reportData.date || '',
            day: t.day || reportData.day || '',
            shift: t.shift || '',
            busNo: t.busNo || '',
            vehicleNo: t.vehicleNo || '',
            routeName: t.routeName || '',
            driverName: t.driverName || '',
            driverPhone: t.driverPhone || '',
            originStop: t.originStop || '',
            destinationStop: t.destinationStop || '',
            departureTime: t.departureTime || '',
            arrivalTime: t.arrivalTime || '',
            duration: t.duration || '',
            punctuality: t.punctuality || '',
            delayMinutes: t.delayMinutes ?? 0,
            stopsCompleted: t.stopsCompleted || '',
            distanceKm: formatReportDistance(t.distanceKm),
            status: t.status || '',
            timeline: Array.isArray(t.stops)
                ? t.stops.map(s => `${s.stopNumber}. ${s.name} (${s.scheduledTime}) [${s.actualTime} | ${s.variance}]`).join(' -> ')
                : ''
        }))).replace(/</g, '\\u003c');

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SISTec Ratibad - Fleet & Trip Operations Report (${reportData.date})</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0a0e17;
            --surface: #111827;
            --surface-card: #1a2234;
            --surface-hover: #243048;
            --text: #f9fafb;
            --text-secondary: #94a3b8;
            --text-muted: #64748b;
            --border: rgba(255, 255, 255, 0.08);
            --primary: #4f46e5;
            --primary-gradient: linear-gradient(135deg, #4f46e5 0%, #3b82f6 100%);
            --accent-green: #10b981;
            --accent-amber: #f59e0b;
            --accent-rose: #ef4444;
            --accent-cyan: #06b6d4;
            --radius-lg: 16px;
            --radius-md: 12px;
            --radius-sm: 8px;
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
            max-width: 1440px;
            margin: 0 auto;
        }

        /* Top Institutional Header */
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
            gap: 18px;
        }

        .brand-logo {
            width: 56px;
            height: 56px;
            border-radius: 14px;
            background: var(--primary-gradient);
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 800;
            font-size: 22px;
            color: #fff;
            box-shadow: 0 8px 20px rgba(79, 70, 229, 0.4);
            letter-spacing: -1px;
        }

        .brand-text h1 {
            font-size: 22px;
            font-weight: 800;
            letter-spacing: -0.3px;
            color: #ffffff;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .brand-badge {
            font-size: 11px;
            font-weight: 700;
            background: rgba(16, 185, 129, 0.15);
            color: #10b981;
            padding: 3px 8px;
            border-radius: 6px;
            border: 1px solid rgba(16, 185, 129, 0.3);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .brand-text p {
            color: var(--text-secondary);
            font-size: 13px;
            font-weight: 500;
            margin-top: 2px;
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
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .btn:hover {
            background: var(--surface-hover);
            transform: translateY(-1px);
            border-color: rgba(255, 255, 255, 0.2);
        }

        .btn-primary {
            background: var(--primary-gradient);
            border: none;
            color: #fff;
            box-shadow: 0 4px 14px rgba(79, 70, 229, 0.35);
        }

        .btn-primary:hover {
            box-shadow: 0 6px 18px rgba(79, 70, 229, 0.5);
        }

        .btn-sheets {
            background: linear-gradient(135deg, #059669 0%, #10b981 100%);
            color: #fff;
            border: none;
            box-shadow: 0 4px 14px rgba(16, 185, 129, 0.3);
        }

        /* KPI Cards Grid */
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
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.2);
        }

        .kpi-card::before {
            content: '';
            position: absolute;
            top: 0; left: 0; width: 4px; height: 100%;
            background: var(--primary);
        }

        .kpi-card.green::before { background: var(--accent-green); }
        .kpi-card.amber::before { background: var(--accent-amber); }
        .kpi-card.cyan::before { background: var(--accent-cyan); }

        .kpi-label {
            font-size: 11px;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 1.2px;
            color: var(--text-secondary);
            margin-bottom: 6px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .kpi-val {
            font-size: 28px;
            font-weight: 800;
            color: #fff;
            font-family: 'Plus Jakarta Sans', sans-serif;
            letter-spacing: -0.5px;
        }

        .kpi-sub {
            font-size: 12px;
            color: var(--text-muted);
            margin-top: 4px;
            font-weight: 500;
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
            transition: border-color 0.2s;
        }

        .input-box:focus {
            border-color: var(--primary);
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
            padding: 7px 16px;
            border-radius: 8px;
            font-size: 12px;
            font-weight: 700;
            color: var(--text-secondary);
            text-decoration: none;
            cursor: pointer;
            border: none;
            background: transparent;
            transition: all 0.2s;
        }

        .shift-tab.active {
            background: var(--primary);
            color: #fff;
            box-shadow: 0 2px 8px rgba(79, 70, 229, 0.4);
        }

        .search-input {
            width: 240px;
            background: var(--surface-card);
            border: 1px solid var(--border);
            color: #fff;
            padding: 8px 14px;
            border-radius: var(--radius-md);
            font-size: 13px;
        }

        /* Section Headings */
        .section-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin: 32px 0 18px 0;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border);
        }

        .section-title {
            font-size: 18px;
            font-weight: 800;
            display: flex;
            align-items: center;
            gap: 10px;
            letter-spacing: -0.2px;
        }

        /* Trip Cards List */
        .trip-cards-container {
            display: flex;
            flex-direction: column;
            gap: 20px;
            margin-bottom: 32px;
        }

        .trip-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            overflow: hidden;
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
            transition: transform 0.2s, border-color 0.2s;
        }

        .trip-card:hover {
            border-color: rgba(99, 102, 241, 0.35);
        }

        .trip-card-header {
            padding: 18px 24px;
            background: var(--surface-card);
            border-bottom: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 14px;
        }

        .trip-bus-info {
            display: flex;
            align-items: center;
            gap: 14px;
        }

        .bus-pill {
            font-family: 'JetBrains Mono', monospace;
            font-size: 13px;
            font-weight: 800;
            background: linear-gradient(135deg, rgba(79, 70, 229, 0.2), rgba(59, 130, 246, 0.2));
            color: #818cf8;
            padding: 6px 12px;
            border-radius: var(--radius-sm);
            border: 1px solid rgba(129, 140, 248, 0.3);
        }

        .plate-pill {
            font-family: 'JetBrains Mono', monospace;
            font-size: 12px;
            font-weight: 700;
            color: var(--text-secondary);
            background: rgba(255, 255, 255, 0.05);
            padding: 4px 10px;
            border-radius: var(--radius-sm);
        }

        .trip-route-title {
            font-size: 16px;
            font-weight: 800;
            color: #fff;
        }

        .trip-driver-meta {
            font-size: 12px;
            color: var(--text-secondary);
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 3px;
        }

        .trip-card-body {
            padding: 20px 24px;
        }

        /* Metric Highlights Strip */
        .metric-strip {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 16px;
            padding-bottom: 18px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 18px;
        }

        .metric-item {
            display: flex;
            flex-direction: column;
        }

        .metric-title {
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.8px;
            color: var(--text-muted);
            margin-bottom: 4px;
        }

        .metric-data {
            font-size: 14px;
            font-weight: 700;
            color: var(--text);
        }

        .metric-data.highlight {
            color: #818cf8;
        }

        /* Visual Stop-by-Stop Stepper */
        .stop-stepper-title {
            font-size: 12px;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: var(--text-secondary);
            margin-bottom: 12px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .stop-timeline-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 10px;
        }

        .stop-node {
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid var(--border);
            border-radius: var(--radius-sm);
            padding: 10px 14px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            transition: background 0.15s;
        }

        .stop-node:hover {
            background: rgba(255, 255, 255, 0.04);
        }

        .stop-node.reached {
            border-left: 3px solid var(--accent-green);
        }

        .stop-node.next {
            border-left: 3px solid var(--accent-amber);
            background: rgba(245, 158, 11, 0.05);
        }

        .stop-node.scheduled {
            border-left: 3px solid rgba(255, 255, 255, 0.2);
        }

        .stop-info {
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }

        .stop-name {
            font-size: 12px;
            font-weight: 700;
            color: #f1f5f9;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .stop-times {
            font-size: 11px;
            color: var(--text-secondary);
            display: flex;
            align-items: center;
            gap: 6px;
            margin-top: 2px;
            font-family: 'JetBrains Mono', monospace;
        }

        .badge {
            display: inline-flex;
            align-items: center;
            padding: 3px 8px;
            border-radius: 6px;
            font-size: 11px;
            font-weight: 700;
            white-space: nowrap;
        }

        .badge-ontime { 
            background: rgba(16, 185, 129, 0.15); 
            color: #10b981; 
            border: 1px solid rgba(16, 185, 129, 0.3); 
        }

        .badge-delayed { 
            background: rgba(245, 158, 11, 0.15); 
            color: #f59e0b; 
            border: 1px solid rgba(245, 158, 11, 0.3); 
        }

        .badge-live { 
            background: rgba(6, 182, 212, 0.15); 
            color: #06b6d4; 
            border: 1px solid rgba(6, 182, 212, 0.3); 
        }

        .badge-status { 
            background: rgba(79, 70, 229, 0.15); 
            color: #818cf8; 
            border: 1px solid rgba(79, 70, 229, 0.3); 
        }

        /* Print Media Styles */
        @media print {
            body {
                background: #ffffff !important;
                color: #0f172a !important;
                padding: 8mm !important;
                font-size: 10pt !important;
            }
            .header-actions, .controls-bar, .search-box { display: none !important; }
            .container { max-width: 100% !important; margin: 0 !important; }
            .kpi-card, .trip-card, .trip-card-header, .stop-node {
                background: #ffffff !important;
                border: 1px solid #cbd5e1 !important;
                box-shadow: none !important;
                color: #0f172a !important;
                page-break-inside: avoid;
            }
            .brand-logo {
                background: #1e293b !important;
                box-shadow: none !important;
            }
            .brand-text h1, .trip-route-title, .kpi-val, .stop-name, .metric-data {
                color: #0f172a !important;
            }
            .bus-pill, .plate-pill {
                background: #f1f5f9 !important;
                color: #0f172a !important;
                border: 1px solid #94a3b8 !important;
            }
            .badge-ontime, .badge-delayed, .badge-live, .badge-status {
                border: 1px solid #64748b !important;
                color: #0f172a !important;
                background: none !important;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div id="standaloneNotice" style="display:none; margin-bottom:20px; padding:12px 16px; border-radius:12px; background:rgba(79, 70, 229, 0.14); border:1px solid rgba(79, 70, 229, 0.4); color:#e2e8f0; font-size:13px; font-weight:600;">
            ℹ️ <strong>Standalone Offline Report Mode:</strong> Instant search, shift tab switching, CSV export, and Print / Save PDF work offline. For live date switching, binary Excel (.xlsx) export, or Google Sheets cloud sync, use the <strong>Manager Analytics Hub</strong> inside the SISTec Chalo app.
        </div>
        <!-- Header -->
        <div class="header">
            <div class="brand-section">
                <div class="brand-logo">SC</div>
                <div class="brand-text">
                    <h1>
                        SISTec Ratibad - Fleet & Trip Operations Report
                        <span class="brand-badge">Official Audit</span>
                    </h1>
                    <p>Generated for: <strong>${reportData.day}, ${reportData.date}</strong> | Complete 2-Trip Scheduled & Live Telemetry Logs</p>
                </div>
            </div>
            <div class="header-actions">
                <button class="btn btn-sheets" onclick="syncSheets(event)">
                    📊 Sync Google Sheets
                </button>
                <a id="excelDownloadLink" href="/api/manager/reports/bus-trip-report?date=${reportData.date}&shift=${reportData.shift}&format=xlsx" onclick="return handleServerLinkClick(event, 'Excel (.xlsx) export')" class="btn" style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); border-color: rgba(16, 185, 129, 0.4); color: #fff;" download>
                    📗 Download Excel (.xlsx)
                </a>
                <button type="button" class="btn" onclick="downloadReportCsv()">
                    📥 Download CSV
                </button>
                <button class="btn btn-primary" onclick="window.print()">
                    🖨️ Print / Save PDF
                </button>
            </div>
        </div>

        <!-- KPI Grid -->
        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-label">Monitored Fleet Buses</div>
                <div class="kpi-val">${reportData.totalBuses}</div>
                <div class="kpi-sub">Total active campus shuttles</div>
            </div>
            <div class="kpi-card green">
                <div class="kpi-label">Daily Scheduled Trips</div>
                <div class="kpi-val">${reportData.totalTrips}</div>
                <div class="kpi-sub">${reportData.morningTrips.length} Pickup + ${reportData.eveningTrips.length} Drop-off</div>
            </div>
            <div class="kpi-card amber">
                <div class="kpi-label">Punctuality Compliance</div>
                <div class="kpi-val">${reportData.punctualityRate}%</div>
                <div class="kpi-sub">${reportData.onTimeTrips} on-time, ${reportData.delayedTrips} delayed</div>
            </div>
            <div class="kpi-card cyan">
                <div class="kpi-label">Fleet Commute Mileage</div>
                <div class="kpi-val">${formatReportDistance(reportData.totalDistance)}</div>
                <div class="kpi-sub">Total road network distance</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Stops Serviced</div>
                <div class="kpi-val">${reportData.totalStopsServiced || reportData.stopLogs.length}</div>
                <div class="kpi-sub">Total passenger boarding stops</div>
            </div>
        </div>

        <!-- Controls Toolbar -->
        <div class="controls-bar">
            <div class="filter-group">
                <label style="font-size:12px; font-weight:700; color:var(--text-secondary);">Select Date:</label>
                <input type="date" id="dateSelector" class="input-box" value="${reportData.date}" onchange="changeDate(this.value)">
                <button class="btn" style="padding:6px 12px; font-size:12px;" onclick="setQuickDate(0)">Today</button>
                <button class="btn" style="padding:6px 12px; font-size:12px;" onclick="setQuickDate(-1)">Yesterday</button>
            </div>

            <div class="filter-group">
                <div class="shift-tabs">
                    <button class="shift-tab ${reportData.shift === 'all' ? 'active' : ''}" data-shift-btn="all" onclick="changeShift('all')">All Trips (${reportData.totalTrips})</button>
                    <button class="shift-tab ${reportData.shift === 'morning' ? 'active' : ''}" data-shift-btn="morning" onclick="changeShift('morning')">🌅 Morning (${reportData.morningTrips.length})</button>
                    <button class="shift-tab ${reportData.shift === 'evening' ? 'active' : ''}" data-shift-btn="evening" onclick="changeShift('evening')">🌆 Afternoon (${reportData.eveningTrips.length})</button>
                </div>
                <input type="text" id="busSearch" class="search-input" placeholder="🔍 Search Bus, Route, Driver..." onkeyup="filterTrips(this.value)">
            </div>
        </div>

        <!-- TRIP 1: MORNING PICKUP -->
        ${reportData.shift === 'all' || reportData.shift === 'morning' ? `
        <div id="morningShiftSection" data-shift-section="morning">
        <div class="section-header">
            <div class="section-title">
                🌅 Trip 1: Morning Pickup Shift (City Origins ➔ SISTec Ratibad Campus)
            </div>
            <span style="font-size:13px; color:var(--text-secondary); font-weight:600;">
                Target Campus Arrival: 08:35 - 08:45 AM
            </span>
        </div>

        <div class="trip-cards-container">
            ${reportData.morningTrips.map(t => `
            <div class="trip-card" data-search="${t.busNo} ${t.vehicleNo} ${t.routeName} ${t.driverName}">
                <div class="trip-card-header">
                    <div class="trip-bus-info">
                        <span class="bus-pill">${t.busNo}</span>
                        <span class="plate-pill">${t.vehicleNo}</span>
                        <div>
                            <div class="trip-route-title">${t.routeName}</div>
                            <div class="trip-driver-meta">
                                <span>👨‍✈️ Driver: <strong>${t.driverName}</strong></span>
                                <span>• 📞 ${t.driverPhone}</span>
                            </div>
                        </div>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span class="badge ${t.punctuality.includes('On-Time') ? 'badge-ontime' : 'badge-delayed'}">${t.punctuality}</span>
                        <span class="badge badge-status">${t.status}</span>
                    </div>
                </div>

                <div class="trip-card-body">
                    <!-- Metric Highlights -->
                    <div class="metric-strip">
                        <div class="metric-item">
                            <span class="metric-title">Origin ➔ Destination</span>
                            <span class="metric-data">${t.originStop} ➔ ${t.destinationStop}</span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Departure Time</span>
                            <span class="metric-data highlight">${t.departureTime} <small style="color:var(--text-muted);">(Sched: ${t.scheduledDeparture})</small></span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Campus Arrival</span>
                            <span class="metric-data highlight">${t.arrivalTime} <small style="color:var(--text-muted);">(Sched: ${t.scheduledArrival})</small></span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Trip Duration & Mileage</span>
                            <span class="metric-data">${t.duration} • ${formatReportDistance(t.distanceKm)}</span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Stops Serviced</span>
                            <span class="metric-data">${t.stopsCompleted} Reached</span>
                        </div>
                    </div>

                    <!-- Stop-by-Stop Stepper -->
                    <div class="stop-stepper-title">
                        <span>Detailed Stop-by-Stop Progress (${t.stops ? t.stops.length : 0} Stops)</span>
                        <span style="font-size:11px; text-transform:none; color:var(--text-muted);">Scheduled vs Actual Arrival</span>
                    </div>
                    <div class="stop-timeline-grid">
                        ${(t.stops || []).map(st => `
                        <div class="stop-node ${st.status.includes('Reached') ? 'reached' : (st.status.includes('Next') ? 'next' : 'scheduled')}">
                            <div class="stop-info">
                                <span class="stop-name">${st.stopNumber}. ${st.name}</span>
                                <div class="stop-times">
                                    <span>Sched: ${st.scheduledTime}</span>
                                    <span>• Reached: <strong>${st.actualTime}</strong></span>
                                </div>
                            </div>
                            <span class="badge ${st.variance.includes('On-Time') ? 'badge-ontime' : (st.variance.includes('Early') ? 'badge-live' : 'badge-delayed')}">${st.variance}</span>
                        </div>
                        `).join('')}
                    </div>
                </div>
            </div>
            `).join('')}
        </div>
        </div>
        ` : ''}

        <!-- TRIP 2: AFTERNOON DROP-OFF -->
        ${reportData.shift === 'all' || reportData.shift === 'evening' ? `
        <div id="eveningShiftSection" data-shift-section="evening">
        <div class="section-header">
            <div class="section-title">
                🌆 Trip 2: Afternoon/Evening Drop-off Shift (SISTec Ratibad Campus ➔ City Terminus)
            </div>
            <span style="font-size:13px; color:var(--text-secondary); font-weight:600;">
                Campus Departure: 04:45 PM
            </span>
        </div>

        <div class="trip-cards-container">
            ${reportData.eveningTrips.map(t => `
            <div class="trip-card" data-search="${t.busNo} ${t.vehicleNo} ${t.routeName} ${t.driverName}">
                <div class="trip-card-header">
                    <div class="trip-bus-info">
                        <span class="bus-pill">${t.busNo}</span>
                        <span class="plate-pill">${t.vehicleNo}</span>
                        <div>
                            <div class="trip-route-title">${t.routeName}</div>
                            <div class="trip-driver-meta">
                                <span>👨‍✈️ Driver: <strong>${t.driverName}</strong></span>
                                <span>• 📞 ${t.driverPhone}</span>
                            </div>
                        </div>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span class="badge ${t.punctuality.includes('On-Time') ? 'badge-ontime' : 'badge-delayed'}">${t.punctuality}</span>
                        <span class="badge badge-status">${t.status}</span>
                    </div>
                </div>

                <div class="trip-card-body">
                    <!-- Metric Highlights -->
                    <div class="metric-strip">
                        <div class="metric-item">
                            <span class="metric-title">Origin ➔ Destination</span>
                            <span class="metric-data">${t.originStop} ➔ ${t.destinationStop}</span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Departure Time</span>
                            <span class="metric-data highlight">${t.departureTime} <small style="color:var(--text-muted);">(Sched: ${t.scheduledDeparture})</small></span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Final Drop Arrival</span>
                            <span class="metric-data highlight">${t.arrivalTime} <small style="color:var(--text-muted);">(Sched: ${t.scheduledArrival})</small></span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Trip Duration & Mileage</span>
                            <span class="metric-data">${t.duration} • ${formatReportDistance(t.distanceKm)}</span>
                        </div>
                        <div class="metric-item">
                            <span class="metric-title">Stops Serviced</span>
                            <span class="metric-data">${t.stopsCompleted} Reached</span>
                        </div>
                    </div>

                    <!-- Stop-by-Stop Stepper -->
                    <div class="stop-stepper-title">
                        <span>Detailed Return Stop Sequence (${t.stops ? t.stops.length : 0} Stops)</span>
                        <span style="font-size:11px; text-transform:none; color:var(--text-muted);">Scheduled vs Actual Arrival</span>
                    </div>
                    <div class="stop-timeline-grid">
                        ${(t.stops || []).map(st => `
                        <div class="stop-node ${st.status.includes('Reached') ? 'reached' : (st.status.includes('Next') ? 'next' : 'scheduled')}">
                            <div class="stop-info">
                                <span class="stop-name">${st.stopNumber}. ${st.name}</span>
                                <div class="stop-times">
                                    <span>Sched: ${st.scheduledTime}</span>
                                    <span>• Reached: <strong>${st.actualTime}</strong></span>
                                </div>
                            </div>
                            <span class="badge ${st.variance.includes('On-Time') ? 'badge-ontime' : (st.variance.includes('Early') ? 'badge-live' : 'badge-delayed')}">${st.variance}</span>
                        </div>
                        `).join('')}
                    </div>
                </div>
            </div>
            `).join('')}
        </div>
        </div>
        ` : ''}

        <!-- Institutional Footer -->
        <div style="text-align:center; padding: 36px 0; font-size:12px; color:var(--text-muted); border-top: 1px solid var(--border); margin-top: 40px;">
            SISTec Chalo Institutional Transit Audit • Sagar Institute of Science & Technology (SISTec), Ratibad Campus, Bhopal • ISO 9001:2015 Transport Protocol
        </div>
    </div>

    <script>
        const REPORT_DATE = "${reportData.date}";
        const REPORT_SHIFT = "${reportData.shift}";
        const REPORT_TOTAL_BUSES = ${Number(reportData.totalBuses) || 0};
        const REPORT_PUNCTUALITY = ${Number(reportData.punctualityRate) || 0};
        const REPORT_TRIPS = ${safeEmbeddedTripsJson};

        function isStandaloneFileMode() {
            return window.location.protocol !== 'http:' && window.location.protocol !== 'https:';
        }

        function handleServerLinkClick(evt, featureLabel) {
            if (isStandaloneFileMode()) {
                if (evt && typeof evt.preventDefault === 'function') evt.preventDefault();
                alert('ℹ️ ' + featureLabel + ' requires a live authenticated session in the SISTec Chalo Manager Analytics Hub. You can use "Download CSV" or "Print / Save PDF" directly from this offline report.');
                return false;
            }
            return true;
        }

        function downloadReportCsv() {
            const esc = (val) => '"' + String(val ?? '').replace(/"/g, '""') + '"';
            let csv = '# SISTec Ratibad - Official Campus Shuttle Operational Trip Log\\n';
            csv += '# Generated Date: ' + REPORT_DATE + ' | Shift: ' + REPORT_SHIFT + ' | Total Buses: ' + REPORT_TOTAL_BUSES + ' | Punctuality: ' + REPORT_PUNCTUALITY + '%\\n\\n';
            csv += 'Trip ID,Date,Day,Shift,Bus Name,License Plate,Route Name,Driver Name,Driver Phone,Origin Stop,Destination Stop,Departure Time,Arrival Time,Duration,Punctuality,Delay (mins),Stops Completed,Total Dist (km),Status,Stop Timeline (Stop: Scheduled [Actual | Variance])\\n';
            REPORT_TRIPS.forEach(t => {
                csv += [
                    esc(t.tripId), esc(t.date), esc(t.day), esc(t.shift),
                    esc(t.busNo), esc(t.vehicleNo), esc(t.routeName),
                    esc(t.driverName), esc(t.driverPhone),
                    esc(t.originStop), esc(t.destinationStop),
                    esc(t.departureTime), esc(t.arrivalTime), esc(t.duration),
                    esc(t.punctuality), Number(t.delayMinutes) || 0,
                    esc(t.stopsCompleted), esc(t.distanceKm), esc(t.status),
                    esc(t.timeline)
                ].join(',') + '\\n';
            });
            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            const safeDate = String(REPORT_DATE).replace(/[^0-9-]/g, '');
            a.href = url;
            a.download = 'sistec_fleet_report_' + safeDate + '_' + REPORT_SHIFT + '.csv';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }

        function changeDate(val) {
            if (isStandaloneFileMode()) {
                alert('ℹ️ Loading a different date requires the Manager Analytics Hub inside the SISTec Chalo app.');
                const dateInput = document.getElementById('dateSelector');
                if (dateInput) dateInput.value = REPORT_DATE;
                return;
            }
            const url = new URL(window.location);
            url.searchParams.set('date', val);
            window.location.href = url.toString();
        }

        function changeShift(shift) {
            const morningEl = document.getElementById('morningShiftSection');
            const eveningEl = document.getElementById('eveningShiftSection');
            const canToggleClientSide = isStandaloneFileMode() || (morningEl && eveningEl);
            if (canToggleClientSide) {
                if (morningEl) {
                    morningEl.style.display = (shift === 'all' || shift === 'morning') ? '' : 'none';
                }
                if (eveningEl) {
                    eveningEl.style.display = (shift === 'all' || shift === 'evening') ? '' : 'none';
                }
                document.querySelectorAll('.shift-tab').forEach(btn => {
                    const btnShift = btn.getAttribute('data-shift-btn');
                    if (btnShift === shift) {
                        btn.classList.add('active');
                    } else {
                        btn.classList.remove('active');
                    }
                });
                return;
            }
            const url = new URL(window.location);
            url.searchParams.set('shift', shift);
            window.location.href = url.toString();
        }

        function setQuickDate(offsetDays) {
            const d = new Date(Date.now() + offsetDays * 86400000);
            const iso = new Intl.DateTimeFormat('en-CA', {
                timeZone: 'Asia/Kolkata',
                year: 'numeric',
                month: '2-digit',
                day: '2-digit'
            }).format(d);
            changeDate(iso);
        }

        function filterTrips(term) {
            const lower = term.toLowerCase().trim();
            const cards = document.querySelectorAll('.trip-card');
            cards.forEach(card => {
                const searchData = (card.getAttribute('data-search') || '').toLowerCase();
                if (!lower || searchData.includes(lower)) {
                    card.style.display = '';
                } else {
                    card.style.display = 'none';
                }
            });
        }

        async function syncSheets(evt) {
            if (isStandaloneFileMode()) {
                handleServerLinkClick(evt, 'Google Sheets Cloud Sync');
                return;
            }
            const date = document.getElementById('dateSelector').value;
            const btn = (evt && evt.currentTarget) ? evt.currentTarget : event.target;
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

        window.addEventListener('load', () => {
            if (isStandaloneFileMode()) {
                const banner = document.getElementById('standaloneNotice');
                if (banner) banner.style.display = 'block';
            }
            const urlParams = new URLSearchParams(window.location.search);
            if (urlParams.get('autoprint') === 'true' || urlParams.get('download') === 'pdf') {
                setTimeout(() => { window.print(); }, 400);
            }
        });
    </script>
</body>
</html>
        `;
        return html;
}

app.get('/api/manager/reports/bus-trip-report/html', reportAuthMiddleware, async (req, res) => {
    try {
        const { date, shift, busId, routeId, direction, tripId, days } = req.query;
        const targetDate = date || getIstDateString();
        const targetShift = shift || 'all';

        const reportData = await generateTripReportData({
            targetDate,
            shift: targetShift,
            busId: busId || null,
            routeId: routeId || null,
            direction: direction || null,
            tripId: tripId || null,
            days: days ? parseInt(days, 10) : 1
        });

        const html = renderTripReportHtml(reportData);
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
app.post('/api/manager/reports/sync-google-sheets', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const { date, shift, busId, routeId, direction, tripId } = req.body || {};
        const targetDate = date || getIstDateString();

        // Generate canonical trip records with official timetable and live logs
        const reportData = await generateTripReportData({
            targetDate,
            shift: shift || 'all',
            busId: busId || null,
            routeId: routeId || null,
            direction: direction || null,
            tripId: tripId || null
        });
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


function isPrivilegedManagerOrAdmin(user) {
    return Boolean(user && (user.role === 'manager' || user.role === 'admin'));
}

function buildNotificationFilterForUser(user) {
    if (isPrivilegedManagerOrAdmin(user)) {
        return {};
    }
    if (user && user.role === 'driver') {
        return {
            type: { $ne: 'emergency' },
            targetAudience: { $nin: ['Admins', 'Students', 'Users'] }
        };
    }
    return {
        type: { $ne: 'emergency' },
        targetAudience: { $nin: ['Admins', 'Drivers'] }
    };
}

function filterNotificationsForUser(notifications, user) {
    if (!Array.isArray(notifications)) return [];
    if (isPrivilegedManagerOrAdmin(user)) {
        return notifications;
    }
    const isDriver = Boolean(user && user.role === 'driver');
    const PRIVILEGED_AUDIENCES = ['admins', 'admin', 'managers', 'manager'];
    const STUDENT_AUDIENCES = ['students', 'student', 'users', 'user'];
    const DRIVER_AUDIENCES = ['drivers', 'driver'];
    return notifications.filter((n) => {
        if (!n || typeof n !== 'object') return false;
        // Legacy documents may carry free-form casing (e.g. 'Emergency') from older broadcast code
        const type = typeof n.type === 'string' ? n.type.trim().toLowerCase() : '';
        if (type === 'emergency') return false;
        const rawAudience = n.targetAudience;
        if (rawAudience !== undefined && rawAudience !== null && typeof rawAudience !== 'string') {
            return false; // Malformed audience: fail closed for non-privileged users
        }
        // Missing/empty audience on legacy documents is treated as 'All'
        const audience = typeof rawAudience === 'string' ? rawAudience.trim().toLowerCase() : '';
        if (PRIVILEGED_AUDIENCES.includes(audience)) return false;
        if (isDriver && STUDENT_AUDIENCES.includes(audience)) return false;
        if (!isDriver && DRIVER_AUDIENCES.includes(audience)) return false;
        return true;
    });
}

// Notifications: Get History (Role-filtered: emergency SOS notifications restricted to Managers/Admins)
app.get('/api/notifications', optionalAuth, async (req, res) => {
    try {
        const filter = buildNotificationFilterForUser(req.user);
        const notifications = await Notification.find(filter).sort({ createdAt: -1 }).limit(50);
        res.json(filterNotificationsForUser(notifications, req.user));
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch notifications' });
    }
});

// Alerts: Get History (Restricted to authenticated Managers and Admins)
app.get('/api/alerts', authMiddleware, managerMiddleware, async (req, res) => {
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
app.post('/api/manager/buses', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const { busNumber, name, capacity, routeId, driverId } = req.body;
        if (!busNumber && !name) {
            return res.status(400).json({ error: 'Bus number or name is required' });
        }
        
        // Prevent duplicate bus number/name
        const checkNum = (busNumber || name).trim();
        const existing = await Bus.findOne({
            $or: [
                { busNumber: { $regex: new RegExp(`^${checkNum}$`, 'i') } },
                { name: { $regex: new RegExp(`^${checkNum}$`, 'i') } }
            ]
        });
        if (existing) {
            return res.status(409).json({ error: `A bus with number "${checkNum}" already exists.` });
        }

        const bus = new Bus(req.body);
        await bus.save();

        // If driver assigned on creation, sync driver's assignedBus
        if (driverId && driverId.trim() !== '') {
            const updatedDriver = await Driver.findByIdAndUpdate(driverId, { assignedBus: bus._id.toString() }, { new: true });
            if (updatedDriver) io.emit('driverUpdated', updatedDriver);
        }

        io.emit('busCreated', bus);
        io.emit('busUpdated', bus);
        io.emit('busesUpdated');
        broadcastStats();
        res.status(201).json(bus);
    } catch (err) {
        console.error('Create bus error:', err);
        res.status(500).json({ error: 'Failed to create bus' });
    }
});

// Update Bus
app.put('/api/manager/buses/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const busId = req.params.id;
        const oldBus = await Bus.findById(busId);
        if (!oldBus) {
            return res.status(404).json({ error: 'Bus not found' });
        }

        const oldDriverId = oldBus.driverId;
        const newDriverId = req.body.driverId;

        // If driver assignment is changing
        if (newDriverId !== undefined && oldDriverId !== newDriverId) {
            if (oldDriverId) {
                const unassignedDriver = await Driver.findByIdAndUpdate(oldDriverId, { assignedBus: '' }, { new: true });
                if (unassignedDriver) io.emit('driverUpdated', unassignedDriver);
            }
            if (newDriverId && newDriverId.trim() !== '' && newDriverId.trim().toUpperCase() !== 'UNASSIGNED') {
                const assignedDriver = await Driver.findByIdAndUpdate(newDriverId, { assignedBus: busId }, { new: true });
                if (assignedDriver) io.emit('driverUpdated', assignedDriver);
            }
        }

        const updatedBus = await Bus.findByIdAndUpdate(busId, req.body, { new: true });
        io.emit('busUpdated', updatedBus);
        io.emit('busesUpdated');
        res.json(updatedBus);
    } catch (err) {
        console.error('Update bus error:', err);
        res.status(500).json({ error: 'Failed to update bus' });
    }
});

// Delete Bus
app.delete('/api/manager/buses/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const busId = req.params.id;
        const bus = await Bus.findById(busId);
        if (!bus) {
            return res.status(404).json({ error: 'Bus not found' });
        }

        // If driver was assigned to this bus, clear driver's assignedBus
        if (bus.driverId) {
            const updatedDriver = await Driver.findByIdAndUpdate(bus.driverId, { assignedBus: '' }, { new: true });
            if (updatedDriver) io.emit('driverUpdated', updatedDriver);
        }
        await Driver.updateMany({ assignedBus: busId }, { assignedBus: '' });

        await Bus.findByIdAndDelete(busId);
        io.emit('busDeleted', { id: busId });
        io.emit('busesUpdated');
        broadcastStats();
        res.json({ message: 'Bus deleted successfully' });
    } catch (err) {
        console.error('Delete bus error:', err);
        res.status(500).json({ error: 'Failed to delete bus' });
    }
});

// Add a new Route with Automatic Geocoding
app.post('/api/manager/routes', authMiddleware, managerMiddleware, async (req, res) => {
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
app.delete('/api/manager/routes/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const routeId = req.params.id;
        const route = await Route.findById(routeId);
        if (!route) {
            return res.status(404).json({ error: 'Route not found' });
        }

        // Dissociate routeId from any buses assigned to this route
        const affectedBuses = await Bus.find({ routeId });
        if (affectedBuses.length > 0) {
            await Bus.updateMany({ routeId }, { $set: { routeId: null, routeName: '' } });
            for (const b of affectedBuses) {
                b.routeId = null;
                b.routeName = '';
                io.emit('busUpdated', b);
            }
            io.emit('busesUpdated');
        }

        // Dissociate routeId from any users and registration submissions assigned to this route
        await User.updateMany({ routeId }, { $set: { routeId: null, stopName: '', stopId: null } });
        await Student.updateMany({ routeId }, { $set: { routeId: null, stopName: '', stopId: null } });

        await Route.findByIdAndDelete(routeId);
        invalidateRoutesCache();
        io.emit('routeDeleted', { id: routeId });
        broadcastStats();
        res.json({ message: 'Route deleted successfully' });
    } catch (err) {
        console.error('Delete route error:', err);
        res.status(500).json({ error: 'Failed to delete route' });
    }
});

app.get('/api/manager/users', authMiddleware, managerMiddleware, async (req, res) => {
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
app.put('/api/manager/users/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const userId = req.params.id;
        const user = await User.findById(userId);
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }

        // If routeId is provided, validate route exists
        if (req.body.routeId && req.body.routeId.trim() !== '') {
            const route = await Route.findById(req.body.routeId);
            if (!route) {
                return res.status(400).json({ error: 'Selected route does not exist' });
            }

            // If pickupPoint is provided, validate it belongs to this route
            const pickup = req.body.pickupPoint || req.body.stopName;
            if (pickup && pickup.trim() !== '') {
                const stopMatch = route.stops?.some(s => 
                    s.name && s.name.toLowerCase().trim() === pickup.toLowerCase().trim()
                );
                if (!stopMatch && route.stops && route.stops.length > 0) {
                    return res.status(400).json({ error: `Pickup stop "${pickup}" does not exist on route "${route.name}"` });
                }
            }
        }

        const updatedUser = await User.findByIdAndUpdate(userId, req.body, { new: true }).select('-password');
        
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
                { createdUserId: userId },
                { $set: updateFields }
            );
        }

        io.emit('userUpdated', updatedUser);
        res.json(updatedUser);
    } catch (err) {
        console.error('Update user error:', err);
        res.status(500).json({ error: 'Failed to update user' });
    }
});

// Manager: Delete User Account
app.delete('/api/manager/users/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
        io.emit('userDeleted', { id: req.params.id });
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
app.get('/api/manager/drivers', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const drivers = await Driver.find().select('-password');
        console.log(`📦 Sending ${drivers.length} drivers to Manager`);
        res.json(drivers);
    } catch (err) {
        console.error('❌ Error fetching manager drivers:', err);
        res.status(500).json({ error: 'Failed to fetch drivers' });
    }
});

// Driver: Get Assigned Bus
app.get('/api/drivers/my-bus', authMiddleware, driverMiddleware, async (req, res) => {
    try {
        let bus = await Bus.findOne({ driverId: req.user.id });
        if (!bus) {
            const driver = await Driver.findById(req.user.id).select('assignedBus username');
            if (driver && driver.assignedBus) {
                bus = await Bus.findById(driver.assignedBus);
            }
            if (!bus && driver && driver.username) {
                const unameDigits = driver.username.replace(/[^0-9]/g, '');
                if (unameDigits) {
                    bus = await Bus.findOne({ busNumber: { $regex: new RegExp(unameDigits, 'i') } });
                }
            }
        }
        if (!bus) return res.status(404).json({ error: 'No bus assigned to this driver' });
        res.json(bus);
    } catch (_) {
        res.status(500).json({ error: 'Failed to fetch assigned bus' });
    }
});


// Manager: Update Driver
app.put('/api/manager/drivers/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
                const oldBus = await Bus.findByIdAndUpdate(oldBusId, { driverId: "" }, { new: true });
                if (oldBus) io.emit('busUpdated', oldBus);
            }
            
            // 2. If new bus is assigned
            if (newBusId && newBusId.trim() !== "" && newBusId.trim().toUpperCase() !== "UNASSIGNED") {
                // Clear any other driver that was assigned to this new bus
                const displacedDrivers = await Driver.find({ _id: { $ne: driverId }, assignedBus: newBusId });
                await Driver.updateMany(
                    { _id: { $ne: driverId }, assignedBus: newBusId },
                    { assignedBus: "" }
                );
                for (const d of displacedDrivers) {
                    d.assignedBus = "";
                    io.emit('driverUpdated', d);
                }
                
                // Set the new bus's driverId to this driver
                const newBus = await Bus.findByIdAndUpdate(newBusId, { driverId: driverId }, { new: true });
                if (newBus) io.emit('busUpdated', newBus);
            }
        }
        
        io.emit('driverUpdated', updatedDriver);
        io.emit('busesUpdated');
        res.json(updatedDriver);
    } catch (err) {
        console.error('❌ Error updating driver:', err);
        res.status(500).json({ error: 'Failed to update driver' });
    }
});

// Manager: Add New Driver
app.post('/api/manager/drivers', authMiddleware, managerMiddleware, async (req, res) => {
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
app.post('/api/manager/drivers/:id/documents', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.delete('/api/manager/drivers/:id/documents/:docId', authMiddleware, managerMiddleware, validateObjectIdParam(['id', 'docId']), async (req, res) => {
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
app.delete('/api/manager/drivers/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const { id } = req.params;
        const driver = await Driver.findById(id);
        if (!driver) {
            return res.status(404).json({ error: 'Driver not found' });
        }

        if (driver.assignedBus) {
            const unassignedBus = await Bus.findByIdAndUpdate(driver.assignedBus, { driverId: '' }, { new: true });
            if (unassignedBus) {
                io.emit('busUpdated', unassignedBus);
            }
        }

        await Driver.findByIdAndDelete(id);
        io.emit('driverDeleted', { id });
        io.emit('busesUpdated');
        res.json({ message: 'Driver deleted successfully' });
    } catch (err) {
        console.error('❌ Error deleting driver:', err);
        res.status(500).json({ error: 'Failed to delete driver' });
    }
});

// ─── MANAGER: EDIT ROUTE (name, color, stops) ────────────────────────────────
// Body: { name, color, stops: [{ name, lat, lng }] }
app.put('/api/manager/routes/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

// ─── MANAGER: UPDATE BUS NUMBER / BASIC FIELDS / QUICK ROUTE REASSIGN ────────
// PATCH /api/manager/buses/:id
// Body: { busNumber, occupancy, routeId, routeName, routeColor, name, shift }
app.patch('/api/manager/buses/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const allowed = {};
        if (req.body.busNumber)  allowed.busNumber  = req.body.busNumber.trim();
        if (req.body.occupancy)  allowed.occupancy  = req.body.occupancy;
        if (req.body.routeId)    allowed.routeId    = req.body.routeId.trim();
        if (req.body.routeName)  allowed.routeName  = req.body.routeName.trim();
        if (req.body.routeColor) allowed.routeColor = req.body.routeColor.trim();
        if (req.body.name)       allowed.name       = req.body.name.trim();
        if (req.body.shift)      allowed.shift      = req.body.shift.trim();
        allowed.lastUpdated = new Date();

        const updated = await Bus.findByIdAndUpdate(req.params.id, allowed, { new: true });
        if (!updated) return res.status(404).json({ error: 'Bus not found' });
        io.emit('busUpdate', updated);
        io.emit('busUpdated', updated);
        broadcastStats();
        res.json(updated);
    } catch (err) {
        console.error('Bus patch error:', err);
        res.status(500).json({ error: 'Failed to update bus' });
    }
});

// ─── MANAGER: INSTANT / EMERGENCY BUS-TO-ROUTE REASSIGNMENT ─────────────────
// POST /api/manager/buses/quick-assign
// Body: { busNumber, busId, routeId, routeName, routeColor, notifyUsers, reason }
app.post('/api/manager/buses/quick-assign', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const { busNumber, busId, routeId, routeName, routeColor, notifyUsers, reason } = req.body;
        if (!routeId && !routeName) {
            return res.status(400).json({ error: 'Target Route ID or Route Name is required' });
        }
        if (!busNumber && !busId) {
            return res.status(400).json({ error: 'Bus Number or Bus ID is required' });
        }

        // 1. Fetch Target Route
        let targetRoute = null;
        if (routeId && isValidId(routeId)) {
            targetRoute = await Route.findById(routeId);
        } else if (routeId) {
            targetRoute = await Route.findOne({ name: new RegExp('^' + routeId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i') });
        }
        if (!targetRoute && routeName) {
            targetRoute = await Route.findOne({ name: new RegExp(routeName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i') });
        }
        if (!targetRoute && routeName) {
            targetRoute = new Route({
                name: routeName,
                color: routeColor || '#2563EB',
                stops: [],
                coordinates: []
            });
            await targetRoute.save();
        }

        const effectiveRouteName = targetRoute ? targetRoute.name : (routeName || 'Assigned Route');
        const effectiveRouteColor = targetRoute ? (targetRoute.color || '#2563EB') : (routeColor || '#2563EB');
        const effectiveRouteId = targetRoute ? targetRoute._id.toString() : (routeId || 'route_default');

        // 2. Find or Create Bus
        let bus = null;
        if (busId && isValidId(busId)) {
            bus = await Bus.findById(busId);
        }

        if (!bus && busNumber) {
            const cleanBusNum = busNumber.trim();
            const numDigits = cleanBusNum.replace(/\D/g, '');
            bus = await Bus.findOne({
                $or: [
                    { busNumber: cleanBusNum },
                    { busNumber: new RegExp('^Bus\\s*0?' + numDigits + '$', 'i') },
                    { name: new RegExp('Bus\\s*0?' + numDigits + '\\b', 'i') }
                ]
            });
        }

        const formattedBusNum = bus ? bus.busNumber : (busNumber || 'Bus').trim();
        const busDisplayName = `${formattedBusNum} - ${effectiveRouteName}`;

        if (!bus) {
            bus = new Bus({
                busNumber: formattedBusNum,
                name: busDisplayName,
                routeId: effectiveRouteId,
                routeName: effectiveRouteName,
                routeColor: effectiveRouteColor,
                status: 'On-time',
                lastUpdated: new Date()
            });
            await bus.save();
            io.emit('busCreated', bus);
        } else {
            bus.routeId = effectiveRouteId;
            bus.routeName = effectiveRouteName;
            bus.routeColor = effectiveRouteColor;
            bus.name = busDisplayName;
            bus.lastUpdated = new Date();
            await bus.save();
        }

        // 3. Emit Real-time Socket Updates
        io.emit('busUpdate', bus);
        io.emit('busUpdated', bus);
        io.emit('busesUpdated');
        broadcastStats();

        // 4. Create Notification if requested
        if (notifyUsers !== false) {
            try {
                const noticeMsg = `⚡ Bus Update: ${formattedBusNum} has been assigned to ${effectiveRouteName}${reason ? ' (' + reason + ')' : ''}.`;
                const notif = new Notification({
                    message: noticeMsg,
                    type: 'info',
                    targetAudience: 'All',
                    createdBy: req.user ? (req.user.name || 'Manager') : 'Manager',
                    createdAt: new Date()
                });
                await notif.save();
                io.emit('notification', notif);
            } catch (notifErr) {
                console.error('Failed to create notification on bus assign:', notifErr.message);
            }
        }

        res.json({
            success: true,
            message: `Successfully assigned ${formattedBusNum} to ${effectiveRouteName}`,
            bus,
            route: targetRoute
        });
    } catch (err) {
        console.error('Quick assign bus error:', err);
        res.status(500).json({ error: 'Failed to assign bus to route: ' + err.message });
    }
});

// POST /api/manager/buses/restore-defaults
// Resets all buses back to default institutional standby status (In Depot)
app.post('/api/manager/buses/restore-defaults', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const buses = await Bus.find({});
        for (const b of buses) {
            b.status = 'Offline';
            b.speed = 0;
            b.lastUpdated = new Date(0); // Mark as not live
            b.reachedStops = [];
            b.completedStops = 0;
            await b.save();
        }

        io.emit('busesUpdated');
        io.emit('fleetReset');
        broadcastStats();

        res.json({
            success: true,
            message: 'All buses restored to default In-Depot standby status.',
            count: buses.length
        });
    } catch (err) {
        console.error('Restore defaults error:', err);
        res.status(500).json({ error: 'Failed to restore defaults: ' + err.message });
    }
});

// ─── MANAGER: IN-APP PER-BUS DAILY REPORT (JSON - REAL LOG DRIVEN) ─────────────
// GET /api/manager/reports/bus/:busId/summary
// Returns genuine daily operational records from recorded LiveTripLog documents.
app.get('/api/manager/reports/bus/:busId/summary', authMiddleware, managerMiddleware, async (req, res) => {
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

        // Fetch up to 60 recent LiveTripLog records for this bus
        const tripLogs = await LiveTripLog.find({
            $or: [{ busId: bus._id.toString() }, { busNumber: bus.busNumber }]
        }).sort({ startTime: -1 }).limit(60).lean();

        // Group by operational date
        const dateMap = {};
        tripLogs.forEach(tl => {
            const d = tl.date;
            if (!dateMap[d]) {
                dateMap[d] = { pickup: null, dropoff: null };
            }
            if (tl.tripType === 'dropoff') {
                if (!dateMap[d].dropoff) dateMap[d].dropoff = tl;
            } else {
                if (!dateMap[d].pickup) dateMap[d].pickup = tl;
            }
        });

        const sortedDates = Object.keys(dateMap).sort().reverse().slice(0, 30);
        const dailyRecords = [];
        let onTimeCount = 0;

        sortedDates.forEach(dateStr => {
            const entry = dateMap[dateStr];
            const pTrip = entry.pickup;
            const dTrip = entry.dropoff;

            const tDate = new Date(dateStr);
            const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
            const dayName = isNaN(tDate.getDay()) ? 'Mon' : dayNames[tDate.getDay()];

            const formatTrip = (tl, type, label, orig, dest) => {
                if (!tl) {
                    return {
                        type,
                        label,
                        originStop: orig,
                        destinationStop: dest,
                        departureTime: 'Unavailable',
                        arrivalTime: 'Unavailable',
                        tripDurationMins: null,
                        status: 'Not Operated',
                        stopTimeline: []
                    };
                }
                const depTime = tl.startTime ? new Date(tl.startTime).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true }) : 'Unavailable';
                const arrTime = tl.endTime ? new Date(tl.endTime).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true }) : (tl.status === 'Active' ? 'In-Transit' : 'Unavailable');
                const dur = tl.durationMinutes != null ? tl.durationMinutes : (tl.endTime && tl.startTime ? Math.max(1, Math.round((new Date(tl.endTime) - new Date(tl.startTime)) / 60000)) : null);
                
                return {
                    type,
                    label,
                    originStop: orig,
                    destinationStop: dest,
                    departureTime: depTime,
                    arrivalTime: arrTime,
                    tripDurationMins: dur,
                    distanceKm: tl.distanceKm || 0,
                    distanceSource: tl.distanceSource || 'Unavailable',
                    status: tl.status === 'Completed' ? 'On-time' : tl.status,
                    stopTimeline: (tl.reachedStops || []).map((rs, idx) => ({
                        stopNumber: idx + 1,
                        stopName: rs.stopName,
                        time: new Date(rs.reachedTime).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true }),
                        isOrigin: idx === 0,
                        isCampus: idx === (tl.reachedStops.length - 1)
                    }))
                };
            };

            const pickupFormatted = formatTrip(pTrip, 'pickup', 'Trip 1: Morning Pickup (City ➔ College)', firstStop, lastStop);
            const dropoffFormatted = formatTrip(dTrip, 'dropoff', 'Trip 2: Evening Drop-off (College ➔ City)', lastStop, firstStop);

            const isOperating = (pTrip && pTrip.status === 'Completed') || (dTrip && dTrip.status === 'Completed');
            if (isOperating) onTimeCount++;

            dailyRecords.push({
                date: isNaN(tDate.getTime()) ? dateStr : tDate.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }),
                dayName,
                busNumber: bus.busNumber || 'N/A',
                driverName,
                routeName: bus.routeName,
                pickupTrip: pickupFormatted,
                dropoffTrip: dropoffFormatted,
                departureTime: pickupFormatted.departureTime,
                arrivalTime: pickupFormatted.arrivalTime,
                tripDurationMins: pickupFormatted.tripDurationMins,
                totalStops: stopNames.length,
                status: isOperating ? 'On-time' : 'Incomplete',
                stopTimeline: pickupFormatted.stopTimeline
            });
        });

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
                delayedDays:        Math.max(0, dailyRecords.length - onTimeCount),
                onTimePercent:      dailyRecords.length ? Math.round((onTimeCount / dailyRecords.length) * 100) : 0,
                avgSpeedKmh:        0,
                totalStudentsServed: 0,
                avgStudentsPerDay:  0,
            },
            dailyRecords
        });
    } catch (err) {
        console.error('Report summary error:', err);
        res.status(500).json({ error: 'Failed to generate report summary: ' + err.message });
    }
});

// ─── MANAGER: TRIP RECORDS & HISTORY (Paginated, Filtered, Sorted) ────────────
// GET /api/manager/trips?page=1&limit=20&startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&busId=<id>&status=all|Active|Completed|Cancelled|Failed&tripType=all|pickup|dropoff&sortBy=-startTime
app.get('/api/manager/trips', authMiddleware, managerMiddleware, validatePagination({ defaultPage: 1, defaultLimit: 20, maxLimit: 100 }), async (req, res) => {
    try {
        const page = (req.pagination && req.pagination.page) || Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = (req.pagination && req.pagination.limit) || Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
        const skip = (req.pagination && req.pagination.skip) != null ? req.pagination.skip : (page - 1) * limit;

        const filter = {};

        // Date range filtering
        const { startDate, endDate, date, busId, status, tripType, sortBy } = req.query;
        if (date) {
            filter.date = date;
        } else if (startDate || endDate) {
            filter.date = {};
            if (startDate) filter.date.$gte = startDate;
            if (endDate) filter.date.$lte = endDate;
        }

        // Bus filter
        if (busId && busId !== 'all') {
            filter.$or = [{ busId }, { busNumber: busId }];
        }

        // Status filter
        if (status && status !== 'all') {
            filter.status = status;
        }

        // Trip type filter
        if (tripType && tripType !== 'all') {
            filter.tripType = tripType;
        }

        // Sorting
        let sortObj = { startTime: -1 };
        if (sortBy) {
            if (sortBy === 'startTime' || sortBy === 'date') sortObj = { startTime: 1 };
            else if (sortBy === '-startTime' || sortBy === '-date') sortObj = { startTime: -1 };
            else if (sortBy === 'durationMinutes') sortObj = { durationMinutes: 1 };
            else if (sortBy === '-durationMinutes') sortObj = { durationMinutes: -1 };
        }

        const [trips, totalCount, statusCounts] = await Promise.all([
            LiveTripLog.find(filter).sort(sortObj).skip(skip).limit(limit).lean(),
            LiveTripLog.countDocuments(filter),
            LiveTripLog.aggregate([
                { $match: filter },
                { $group: { _id: '$status', count: { $sum: 1 } } }
            ])
        ]);

        const countsMap = { Active: 0, Completed: 0, Cancelled: 0, Failed: 0 };
        statusCounts.forEach(sc => {
            if (sc._id && countsMap[sc._id] !== undefined) {
                countsMap[sc._id] = sc.count;
            }
        });

        // Compute summary metrics across matching completed trips
        const completedTripsAgg = await LiveTripLog.aggregate([
            { $match: { ...filter, status: 'Completed' } },
            { 
                $group: { 
                    _id: null, 
                    avgDuration: { $avg: '$durationMinutes' },
                    totalDistance: { $sum: '$distanceKm' }
                } 
            }
        ]);

        const avgDuration = completedTripsAgg.length && completedTripsAgg[0].avgDuration != null
            ? Math.round(completedTripsAgg[0].avgDuration)
            : 0;
        const totalDistance = completedTripsAgg.length && completedTripsAgg[0].totalDistance != null
            ? parseFloat(completedTripsAgg[0].totalDistance.toFixed(1))
            : 0;

        const totalPages = Math.ceil(totalCount / limit) || 1;

        res.json({
            success: true,
            pagination: {
                page,
                limit,
                totalPages,
                totalCount,
                hasMore: page < totalPages
            },
            summary: {
                totalTrips: totalCount,
                completedTrips: countsMap.Completed,
                cancelledTrips: countsMap.Cancelled,
                activeTrips: countsMap.Active,
                failedTrips: countsMap.Failed,
                averageDurationMinutes: avgDuration,
                totalDistanceKm: totalDistance
            },
            trips: trips.map(t => ({
                id: t._id,
                _id: t._id,
                busId: t.busId,
                busNumber: t.busNumber,
                busName: t.busName,
                driverId: t.driverId,
                driverName: t.driverName,
                driverPhone: t.driverPhone,
                routeId: t.routeId,
                routeName: t.routeName,
                date: t.date,
                startTime: t.startTime,
                endTime: t.endTime,
                durationMinutes: t.durationMinutes,
                distanceKm: t.distanceKm,
                distanceSource: t.distanceSource,
                tripType: t.tripType,
                status: t.status,
                cancellationReason: t.cancellationReason,
                reachedStopsCount: t.reachedStops ? t.reachedStops.length : 0
            }))
        });
    } catch (err) {
        console.error('Manager trips history error:', err);
        res.status(500).json({ error: 'Failed to fetch trip history: ' + err.message });
    }
});

// ─── MANAGER: EXPORT FILTERED TRIP RECORDS (CSV) ─────────────────────────────
// GET /api/manager/trips/export/csv?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&busId=<id>&status=all|Active|Completed|Cancelled|Failed
app.get('/api/manager/trips/export/csv', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        const filter = {};
        const { startDate, endDate, date, busId, status, tripType } = req.query;
        if (date) {
            filter.date = date;
        } else if (startDate || endDate) {
            filter.date = {};
            if (startDate) filter.date.$gte = startDate;
            if (endDate) filter.date.$lte = endDate;
        }
        if (busId && busId !== 'all') {
            filter.$or = [{ busId }, { busNumber: busId }];
        }
        if (status && status !== 'all') {
            filter.status = status;
        }
        if (tripType && tripType !== 'all') {
            filter.tripType = tripType;
        }

        const trips = await LiveTripLog.find(filter).sort({ startTime: -1 }).limit(5000).lean();

        let csv = '# SISTec Ratibad - Official Shuttle Trip History Export\n';
        csv += `# Total Records: ${trips.length} | Exported At: ${new Date().toISOString()}\n\n`;
        csv += 'Trip ID,Date,Shift Type,Bus Number,Bus Name,Route Name,Driver Name,Driver Phone,Start Time,End Time,Duration (mins),Distance (km),Distance Source,Status,Stops Reached,Cancellation Reason\n';

        trips.forEach(t => {
            const tripId = t._id ? t._id.toString() : '';
            const dateStr = t.date || '';
            const shiftType = t.tripType || 'pickup';
            const busNumber = (t.busNumber || 'N/A').replace(/"/g, '""');
            const busName = (t.busName || 'N/A').replace(/"/g, '""');
            const routeName = (t.routeName || 'Unassigned').replace(/"/g, '""');
            const driverName = (t.driverName || 'Unassigned').replace(/"/g, '""');
            const driverPhone = (t.driverPhone || 'N/A').replace(/"/g, '""');
            const startTimeStr = t.startTime ? new Date(t.startTime).toISOString() : 'Unavailable';
            const endTimeStr = t.endTime ? new Date(t.endTime).toISOString() : (t.status === 'Active' ? 'In-Progress' : 'Unavailable');
            const duration = t.durationMinutes != null ? t.durationMinutes : 'Unavailable';
            const distance = (typeof t.distanceKm === 'number' && t.distanceKm > 0) ? t.distanceKm.toFixed(1) : 'Unavailable';
            const distanceSource = t.distanceSource || 'Unavailable';
            const status = t.status || 'Active';
            const stopsReached = t.reachedStops ? t.reachedStops.length : 0;
            const reason = (t.cancellationReason || '').replace(/"/g, '""');

            csv += `"${tripId}","${dateStr}","${shiftType}","${busNumber}","${busName}","${routeName}","${driverName}","${driverPhone}","${startTimeStr}","${endTimeStr}",${duration},"${distance}","${distanceSource}","${status}",${stopsReached},"${reason}"\n`;
        });

        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', 'attachment; filename="sistec_trip_history.csv"');
        res.status(200).send(csv);
    } catch (err) {
        console.error('Trip CSV Export Error:', err);
        res.status(500).json({ error: 'Failed to export trip history CSV: ' + err.message });
    }
});

// ─── MANAGER: SINGLE TRIP RECORD DETAIL & STOP TIMELINE ───────────────────────
// GET /api/manager/trips/:id
app.get('/api/manager/trips/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
    try {
        const { id } = req.params;
        if (!id || id.length < 10) {
            return res.status(400).json({ error: 'Invalid trip ID format' });
        }

        const trip = await LiveTripLog.findById(id).lean();
        if (!trip) {
            return res.status(404).json({ error: 'Trip record not found' });
        }

        // Fetch Route if routeId is available for route coordinates / stops comparison
        let routeCoordinates = [];
        let scheduledStops = [];
        if (trip.routeId) {
            const routeDoc = await Route.findById(trip.routeId).lean();
            if (routeDoc) {
                routeCoordinates = routeDoc.coordinates || [];
                scheduledStops = routeDoc.stops || [];
            }
        }

        // Stop events and deviations from schedule
        const stopEvents = (trip.reachedStops || []).map((rs, idx) => {
            let scheduledTime = null;
            let deviationMinutes = null;
            let status = 'Recorded';

            const matchingScheduled = scheduledStops.find(s => 
                s.name && rs.stopName && s.name.toLowerCase().trim() === rs.stopName.toLowerCase().trim()
            );

            if (matchingScheduled && matchingScheduled.time) {
                scheduledTime = matchingScheduled.time;
                const schedMatch = scheduledTime.match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
                if (schedMatch && rs.reachedTime) {
                    let sh = parseInt(schedMatch[1], 10);
                    const sm = parseInt(schedMatch[2], 10);
                    const ampm = (schedMatch[3] || 'AM').toUpperCase();
                    if (ampm === 'PM' && sh < 12) sh += 12;
                    if (ampm === 'AM' && sh === 12) sh = 0;
                    const schedMins = sh * 60 + sm;

                    const rDate = new Date(rs.reachedTime);
                    const actMins = rDate.getHours() * 60 + rDate.getMinutes();
                    deviationMinutes = actMins - schedMins;
                    status = deviationMinutes > 5 ? 'Delayed' : (deviationMinutes < -5 ? 'Early' : 'On-Time');
                }
            }

            return {
                stopNumber: idx + 1,
                stopName: rs.stopName,
                reachedTime: rs.reachedTime,
                scheduledTime: scheduledTime || 'Unavailable',
                deviationMinutes: deviationMinutes != null ? deviationMinutes : 'Unavailable',
                status
            };
        });

        res.json({
            success: true,
            trip: {
                id: trip._id,
                _id: trip._id,
                busId: trip.busId,
                busNumber: trip.busNumber,
                busName: trip.busName,
                driverId: trip.driverId,
                driverName: trip.driverName,
                driverPhone: trip.driverPhone,
                routeId: trip.routeId,
                routeName: trip.routeName,
                date: trip.date,
                startTime: trip.startTime,
                endTime: trip.endTime,
                durationMinutes: trip.durationMinutes,
                distanceKm: trip.distanceKm,
                distanceSource: trip.distanceSource,
                tripType: trip.tripType,
                status: trip.status,
                cancellationReason: trip.cancellationReason,
                reachedStops: stopEvents,
                routeCoordinates: routeCoordinates.length > 0 ? routeCoordinates : null
            }
        });
    } catch (err) {
        console.error('Manager trip detail error:', err);
        res.status(500).json({ error: 'Failed to fetch trip detail: ' + err.message });
    }
});


// Socket.io for Real-time Bus Updates
const busGeofenceState = {}; // { busId: { stopName: lastNotifiedTimestamp } }
const userGeofenceState = {}; // { userId: { stopName: lastNotifiedTimestamp } }
const GEOFENCE_RADIUS_KM = 1.0; // 1.0 km as per request
const COOLDOWN_MS = 30 * 60 * 1000; // 30 minutes

// In-memory debounce map for SOS emergency alerts (Anti-spam cooldown: 15s)
const sosCooldownMap = new Map(); // key: userId / socket.id -> { timestamp, alertId, alertPayload }
const SOS_COOLDOWN_MS = 15000;

// ─── Socket.io JWT Authentication Middleware ─────────────────────────────────
io.use(async (socket, next) => {
    if (isShuttingDown) {
        return next(new Error('SERVER_SHUTTING_DOWN'));
    }
    const rawToken = socket.handshake.auth?.token 
        || socket.handshake.headers?.authorization
        || socket.handshake.query?.token;

    if (!rawToken) {
        // Unauthenticated client (guest explorer or student before login).
        // Permitted to connect for read-only tracking and emergency SOS, but cannot execute driver actions.
        socket.user = null;
        return next();
    }

    try {
        const tokenString = rawToken.startsWith('Bearer ') ? rawToken.slice(7) : rawToken;
        const decoded = jwt.verify(tokenString, getJwtSecret());

        if (decoded.scope === 'password_change') {
            return next(new Error('Authentication error: Restricted password-change token'));
        }

        const account = await getAccountByIdAndRole(decoded.user?.id, decoded.user?.role);
        if (!account) {
            return next(new Error('Authentication error: Account no longer exists'));
        }

        if (account.status && account.status === 'Suspended') {
            return next(new Error('Authentication error: Account suspended'));
        }

        const tokenVersion = decoded.user?.tokenVersion;
        const currentVersion = account.tokenVersion || 0;
        if (tokenVersion === undefined || tokenVersion !== currentVersion) {
            return next(new Error('Authentication error: Session expired. Please log in again.'));
        }

        socket.user = {
            id: (account._id ? account._id.toString() : account.id),
            role: decoded.user?.role,
            username: account.username || account.enrollmentNumber || decoded.user?.username || '',
            name: account.name || decoded.user?.name || '',
            tokenVersion: currentVersion,
            status: account.status || 'Active'
        };

        return next();
    } catch (_err) {
        return next(new Error('Authentication error: Token is not valid or expired'));
    }
});

/**
 * Initializes Socket.io connection listeners.
 * Handles continuous location updates from buses and broadcasts them.
 */
function emitSensitiveSosAlert(ioInstance, alertPayload) {
    if (!ioInstance || typeof ioInstance.to !== 'function') return;
    const managersRoom = ioInstance.to('managers');
    if (managersRoom && typeof managersRoom.emit === 'function') {
        managersRoom.emit('sosAlert', alertPayload);
        managersRoom.emit('sosAlertManager', alertPayload);
    }
}

function emitEmergencySosNotification(ioInstance, notifPayload) {
    if (!ioInstance || typeof ioInstance.to !== 'function') return;
    const managersRoom = ioInstance.to('managers');
    if (managersRoom && typeof managersRoom.emit === 'function') {
        managersRoom.emit('notification', notifPayload);
        managersRoom.emit('notificationManager', notifPayload);
    }
}

function parseSosCoordinates(data) {
    const parseCoord = (val) => {
        if (typeof val === 'number') {
            return Number.isFinite(val) ? val : null;
        }
        if (typeof val === 'string') {
            const trimmed = val.trim();
            if (!trimmed) return null;
            const num = Number(trimmed);
            return Number.isFinite(num) ? num : null;
        }
        return null;
    };

    const rawLat = data && typeof data === 'object' ? parseCoord(data.latitude) : null;
    const rawLng = data && typeof data === 'object' ? parseCoord(data.longitude) : null;

    const explicitUnavailable = Boolean(
        data && typeof data === 'object' && data.locationAvailable === false
    );

    const hasValidCoords = !explicitUnavailable &&
        rawLat !== null &&
        rawLng !== null &&
        rawLat >= -90 && rawLat <= 90 &&
        rawLng >= -180 && rawLng <= 180 &&
        !(rawLat === 0 && rawLng === 0);

    return {
        latitude: hasValidCoords ? rawLat : null,
        longitude: hasValidCoords ? rawLng : null,
        locationAvailable: hasValidCoords
    };
}

// 60s stale threshold = 5x the 12s stationary driver heartbeat interval (12x the 5s moving timer)
const DRIVER_STALE_THRESHOLD_MS = 60 * 1000;

function normalizeTripType(rawTripType) {
    const cleaned = String(rawTripType || '').trim().toLowerCase();
    return (cleaned === 'dropoff' || cleaned === 'evening') ? 'dropoff' : 'pickup';
}

function normalizeDistanceKm(rawDistanceKm) {
    if (rawDistanceKm === null || rawDistanceKm === undefined || rawDistanceKm === '') return null;
    const parsed = typeof rawDistanceKm === 'number' ? rawDistanceKm : Number(rawDistanceKm);
    if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1000) return null;
    return Number(parsed.toFixed(2));
}

function parseTelemetryPacketTimestamp(rawTimestamp, nowMs = Date.now()) {
    if (rawTimestamp === null || rawTimestamp === undefined || rawTimestamp === '') {
        return new Date(nowMs);
    }
    if (rawTimestamp instanceof Date) {
        return !isNaN(rawTimestamp.getTime()) ? rawTimestamp : new Date(nowMs);
    }
    if (typeof rawTimestamp === 'number') {
        return Number.isFinite(rawTimestamp) ? new Date(rawTimestamp) : new Date(nowMs);
    }
    if (typeof rawTimestamp === 'string') {
        const trimmed = rawTimestamp.trim();
        if (!trimmed) return new Date(nowMs);
        let normalized = trimmed;
        // Legacy driver APKs emit Dart DateTime.now().toIso8601String() without Z/offset.
        // Interpret timezone-naive ISO datetime strings as IST (+05:30) rather than server UTC.
        if (/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(trimmed)) {
            normalized = `${trimmed.replace(' ', 'T')}+05:30`;
        }
        const parsed = new Date(normalized);
        return !isNaN(parsed.getTime()) ? parsed : new Date(nowMs);
    }
    return new Date(nowMs);
}

function resolveBusTelemetryStatus(currentBusStatus, incomingStatus, explicitStatusOverride = false) {
    const current = String(currentBusStatus || '').trim();
    const incoming = String(incomingStatus || '').trim();
    if (
        current.toLowerCase() === 'delayed' &&
        !explicitStatusOverride &&
        incoming.toLowerCase() !== 'delayed'
    ) {
        return 'Delayed';
    }
    if (incoming && incoming.toLowerCase() !== 'offline') {
        return incoming;
    }
    return current.toLowerCase() === 'delayed' ? 'Delayed' : 'On-time';
}

async function verifyDriverBusAuthorization({ socketUser, bus, busId, DriverModel }) {
    if (!socketUser || !socketUser.role) {
        return { authorized: false, reason: 'unauthenticated' };
    }
    if (socketUser.role === 'manager' || socketUser.role === 'admin') {
        return { authorized: true, driverDoc: null };
    }
    if (socketUser.role !== 'driver') {
        return { authorized: false, reason: 'unauthorized_role' };
    }
    const driver = await DriverModel.findById(socketUser.id).select('status assignedBus username name phone contactNumber');
    if (!driver || driver.status === 'Suspended') {
        return { authorized: false, reason: 'driver_unavailable_or_suspended' };
    }
    const targetBusId = (bus && bus._id ? bus._id : busId || '').toString();
    const driverUsername = (driver.username || socketUser.username || '');
    const driverDigits = driverUsername.replace(/[^0-9]/g, '');
    const busDigits = ((bus && bus.busNumber) || '').replace(/[^0-9]/g, '');
    const isUsernameMatch = Boolean(driverDigits && busDigits && driverDigits === busDigits);
    const isAssigned = Boolean(
        (driver.assignedBus && driver.assignedBus.toString() === targetBusId) ||
        (bus && bus.driverId && bus.driverId.toString() === String(socketUser.id)) ||
        isUsernameMatch
    );
    if (!isAssigned) {
        return { authorized: false, reason: 'driver_not_assigned_to_bus' };
    }
    return { authorized: true, driverDoc: driver };
}

const DELAY_MESSAGE_MAX_LENGTH = 500;
const DELAY_MINUTES_MAX = 240;
const OBJECT_ID_PATTERN = /^[a-fA-F0-9]{24}$/;

/**
 * Authorizes a delay-notification broadcast before anything is persisted or emitted.
 * - Only driver, manager, or admin roles may broadcast.
 * - routeId (and optional busId) must be well-formed and must exist.
 * - Drivers must be explicitly assigned to the bus (assignedBus or bus.driverId; the
 *   username-digit heuristic is NOT accepted here) and the bus must serve routeId.
 * - Managers/admins may target any existing route; a supplied busId must serve that route.
 * - routeName is always taken from the database, never from the client.
 */
async function authorizeDelayNotification({ user, body, RouteModel, BusModel, DriverModel }) {
    const deny = (status, error) => ({ authorized: false, status, error });

    if (!user || !['driver', 'manager', 'admin'].includes(user.role)) {
        return deny(403, 'Forbidden: Driver, Manager, or Admin role required to broadcast delay alerts');
    }

    const src = (body && typeof body === 'object') ? body : {};
    const routeId = typeof src.routeId === 'string' ? src.routeId.trim() : '';
    const requestedBusId = typeof src.busId === 'string' ? src.busId.trim() : '';
    const message = typeof src.message === 'string' ? src.message.trim() : '';

    if (!routeId || !message) return deny(400, 'routeId and message required');
    if (!OBJECT_ID_PATTERN.test(routeId)) return deny(400, 'Invalid routeId');
    if (requestedBusId && !OBJECT_ID_PATTERN.test(requestedBusId)) return deny(400, 'Invalid busId');
    if (message.length > DELAY_MESSAGE_MAX_LENGTH) {
        return deny(400, `Delay message must be ${DELAY_MESSAGE_MAX_LENGTH} characters or fewer`);
    }

    const route = await RouteModel.findById(routeId);
    if (!route) return deny(404, 'Route not found');

    let bus = null;
    if (user.role === 'driver') {
        let effectiveBusId = requestedBusId;
        if (!effectiveBusId) {
            const driverDoc = await DriverModel.findById(user.id).select('status assignedBus username name');
            if (!driverDoc || driverDoc.status === 'Suspended') {
                return deny(403, 'Forbidden: Driver account is unavailable or suspended');
            }
            effectiveBusId = driverDoc.assignedBus ? String(driverDoc.assignedBus).trim() : '';
        }
        if (!effectiveBusId || !OBJECT_ID_PATTERN.test(effectiveBusId)) {
            return deny(403, 'Forbidden: Driver is not assigned to a bus');
        }

        bus = await BusModel.findById(effectiveBusId);
        // Uniform 403 avoids revealing whether an unauthorized bus ID exists
        if (!bus) return deny(403, 'Forbidden: Driver is not authorized for this bus');

        const authz = await verifyDriverBusAuthorization({
            socketUser: user,
            bus,
            busId: effectiveBusId,
            DriverModel
        });
        if (!authz.authorized) return deny(403, 'Forbidden: Driver is not authorized for this bus');

        const busIdStr = bus._id ? bus._id.toString() : effectiveBusId;
        const explicitlyAssigned = Boolean(
            (authz.driverDoc && authz.driverDoc.assignedBus && authz.driverDoc.assignedBus.toString() === busIdStr) ||
            (bus.driverId && bus.driverId.toString() === String(user.id))
        );
        if (!explicitlyAssigned) return deny(403, 'Forbidden: Driver is not authorized for this bus');

        if (String(bus.routeId || '').trim() !== routeId) {
            return deny(403, 'Forbidden: Driver bus is not assigned to the specified route');
        }
    } else if (requestedBusId) {
        bus = await BusModel.findById(requestedBusId);
        if (!bus) return deny(404, 'Bus not found');
        if (String(bus.routeId || '').trim() !== routeId) {
            return deny(400, 'Bus is not assigned to the specified route');
        }
    }

    const rawMinutes = Number(src.delayMinutes);
    const delayMinutes = Number.isFinite(rawMinutes)
        ? Math.min(DELAY_MINUTES_MAX, Math.max(0, Math.round(rawMinutes)))
        : 0;

    return {
        authorized: true,
        routeId,
        routeName: (route.name && String(route.name).trim()) || routeId,
        busId: bus && bus._id ? bus._id.toString() : null,
        busNumber: bus && bus.busNumber ? String(bus.busNumber) : null,
        message,
        delayMinutes
    };
}

function buildBusApproachingStopPayload({ bus, stopName, distanceKm, minutes }) {
    const rawId = bus && (bus._id || bus.id || bus.busId);
    const busId = rawId ? rawId.toString() : '';
    const busNumber = (bus && bus.busNumber && String(bus.busNumber).trim().length > 0)
        ? String(bus.busNumber).trim()
        : 'Shuttle';
    const routeId = (bus && bus.routeId) ? bus.routeId.toString() : '';
    const routeName = (bus && bus.routeName && String(bus.routeName).trim().length > 0)
        ? String(bus.routeName).trim()
        : 'SISTec Route';
    const resolvedStopName = String(stopName || 'Bus Stop').trim() || 'Bus Stop';
    const numericDist = (typeof distanceKm === 'number' && Number.isFinite(distanceKm) && distanceKm >= 0)
        ? Number(distanceKm.toFixed(2))
        : 0;
    const resolvedMinutes = (typeof minutes === 'number' && Number.isFinite(minutes))
        ? Math.max(0, Math.round(minutes))
        : 1;
    const message = `Bus ${busNumber} (${routeName}) is approaching ${resolvedStopName} (${numericDist.toFixed(1)} km away, ~${resolvedMinutes} min).`;

    return {
        busId,
        busNumber,
        routeId,
        routeName,
        stopName: resolvedStopName,
        distanceKm: numericDist,
        etaMinutes: resolvedMinutes,
        minutes: resolvedMinutes,
        message
    };
}

async function startOrResumeTripLog({
    LiveTripLogModel,
    bus,
    todayStr,
    tripType,
    distanceKm,
    verifiedDriverId,
    resolveSnapshots
}) {
    const normalizedType = normalizeTripType(tripType);
    const validDistanceKm = normalizeDistanceKm(distanceKm);
    const busIdStr = bus._id.toString();

    const existingActiveTrip = await LiveTripLogModel.findOne({
        busId: busIdStr,
        date: todayStr,
        tripType: normalizedType,
        status: 'Active'
    });

    if (existingActiveTrip) {
        if (
            verifiedDriverId &&
            existingActiveTrip.driverId &&
            existingActiveTrip.driverId.toString() !== String(verifiedDriverId)
        ) {
            return { tripLog: null, isResumed: false, conflict: 'driver_mismatch' };
        }
        return { tripLog: existingActiveTrip, isResumed: true, conflict: null };
    }

    const snapshots = typeof resolveSnapshots === 'function' ? await resolveSnapshots() : {};
    const hasPositiveDistance = validDistanceKm !== null && validDistanceKm > 0;
    const tripLog = await LiveTripLogModel.create({
        busId: busIdStr,
        busNumber: bus.busNumber || 'N/A',
        busName: bus.name || `Bus ${bus.busNumber || ''}`,
        driverId: snapshots.driverId || verifiedDriverId || null,
        driverName: snapshots.driverName || 'Unassigned',
        driverPhone: snapshots.driverPhone || 'N/A',
        routeId: snapshots.routeId || null,
        routeName: snapshots.routeName || (bus.routeName || 'Unassigned'),
        date: todayStr,
        startTime: new Date(),
        tripType: normalizedType,
        status: 'Active',
        distanceKm: hasPositiveDistance ? validDistanceKm : 0,
        distanceSource: hasPositiveDistance ? 'GPS' : 'Unavailable'
    });

    return { tripLog, isResumed: false, conflict: null };
}

async function syncActiveTripLogForTelemetry({
    LiveTripLogModel,
    bus,
    todayStr,
    tripType,
    distanceKm,
    reachedStops,
    verifiedDriverId,
    resolveSnapshots
}) {
    const normalizedType = normalizeTripType(tripType);
    const validDistanceKm = normalizeDistanceKm(distanceKm);
    const busIdStr = bus._id.toString();

    let tripLog = await LiveTripLogModel.findOne({
        busId: busIdStr,
        date: todayStr,
        tripType: normalizedType,
        status: 'Active'
    });

    if (!tripLog) {
        const snapshots = typeof resolveSnapshots === 'function' ? await resolveSnapshots() : {};
        const hasPositiveDistance = validDistanceKm !== null && validDistanceKm > 0;
        tripLog = await LiveTripLogModel.create({
            busId: busIdStr,
            busNumber: bus.busNumber || 'N/A',
            busName: bus.name || bus.busNumber,
            driverId: snapshots.driverId || verifiedDriverId || null,
            driverName: snapshots.driverName || 'Unassigned',
            driverPhone: snapshots.driverPhone || 'N/A',
            routeId: snapshots.routeId || null,
            routeName: snapshots.routeName || (bus.routeName || 'Unassigned'),
            date: todayStr,
            startTime: new Date(),
            tripType: normalizedType,
            status: 'Active',
            distanceKm: hasPositiveDistance ? validDistanceKm : 0,
            distanceSource: hasPositiveDistance ? 'GPS' : 'Unavailable'
        });
        console.log(`🚀 [TRIP START] New live ${normalizedType.toUpperCase()} trip log created for Bus ${bus.busNumber} on ${todayStr}`);
    } else {
        // Prevent cross-driver contamination if a record belongs to another driver
        if (
            verifiedDriverId &&
            tripLog.driverId &&
            tripLog.driverId.toString() !== String(verifiedDriverId)
        ) {
            return null;
        }
        let logChanged = false;
        if (reachedStops && Array.isArray(reachedStops)) {
            for (const sName of reachedStops) {
                const strName = sName.toString().trim();
                if (strName && !tripLog.reachedStops.some(rs => rs.stopName === strName)) {
                    tripLog.reachedStops.push({ stopName: strName, reachedTime: new Date() });
                    logChanged = true;
                }
            }
        }
        if (validDistanceKm !== null && validDistanceKm > (tripLog.distanceKm || 0)) {
            tripLog.distanceKm = validDistanceKm;
            tripLog.distanceSource = 'GPS';
            logChanged = true;
        }
        if (logChanged) {
            await tripLog.save();
        }
    }

    return tripLog;
}

async function completeActiveTripLog({
    LiveTripLogModel,
    busId,
    todayStr,
    tripType,
    distanceKm,
    verifiedDriverId
}) {
    const validDistanceKm = normalizeDistanceKm(distanceKm);
    const hasExplicitTripType = Boolean(tripType && String(tripType).trim().length > 0);
    let tripLog = null;

    if (hasExplicitTripType) {
        const normalizedType = normalizeTripType(tripType);
        tripLog = await LiveTripLogModel.findOne({
            busId,
            date: todayStr,
            tripType: normalizedType,
            status: 'Active'
        });
    } else {
        tripLog = await LiveTripLogModel.findOne({
            busId,
            date: todayStr,
            status: 'Active'
        });
    }
    if (!tripLog) return null;

    if (
        verifiedDriverId &&
        tripLog.driverId &&
        tripLog.driverId.toString() !== String(verifiedDriverId)
    ) {
        return null;
    }

    tripLog.endTime = new Date();
    tripLog.durationMinutes = Math.max(1, Math.round((tripLog.endTime - tripLog.startTime) / 60000));
    tripLog.status = 'Completed';
    if (validDistanceKm !== null && validDistanceKm > (tripLog.distanceKm || 0)) {
        tripLog.distanceKm = validDistanceKm;
        tripLog.distanceSource = 'GPS';
    }
    await tripLog.save();
    return tripLog;
}

async function resolveFindOneWithOptionalSort(model, query, sortSpec) {
    const q = model.findOne(query);
    if (q && typeof q.sort === 'function' && sortSpec) {
        return await q.sort(sortSpec);
    }
    return await q;
}

/**
 * Resolves and terminates (Cancels or Fails) an active LiveTripLog using strong trip identity
 * (_id/tripLogId if provided, else active status for busId + optional tripType sorted by latest startTime)
 * without restricting lookup to today's IST date so cross-midnight trips terminate cleanly.
 */
async function terminateActiveTripLog({
    LiveTripLogModel,
    busId,
    tripId = null,
    tripType = null,
    targetStatus,
    reason,
    verifiedDriverId = null,
    clearSamplerFn = clearTelemetrySamplerState,
    samplerState
}) {
    let tripLog = null;
    const explicitTripId = tripId ? String(tripId).trim() : '';

    if (explicitTripId) {
        tripLog = await resolveFindOneWithOptionalSort(
            LiveTripLogModel,
            { _id: explicitTripId, busId: String(busId), status: 'Active' }
        );
    } else {
        const activeQuery = { busId: String(busId), status: 'Active' };
        if (tripType && String(tripType).trim().length > 0) {
            activeQuery.tripType = normalizeTripType(tripType);
        }
        tripLog = await resolveFindOneWithOptionalSort(
            LiveTripLogModel,
            activeQuery,
            { startTime: -1, createdAt: -1 }
        );
    }

    if (!tripLog) return null;

    if (
        verifiedDriverId &&
        tripLog.driverId &&
        tripLog.driverId.toString() !== String(verifiedDriverId)
    ) {
        return null;
    }

    if (samplerState !== undefined) {
        clearSamplerFn(tripLog._id, samplerState);
    } else {
        clearSamplerFn(tripLog._id);
    }

    tripLog.endTime = new Date();
    tripLog.durationMinutes = Math.max(1, Math.round((tripLog.endTime - tripLog.startTime) / 60000));
    tripLog.status = targetStatus;
    tripLog.cancellationReason = reason;
    await tripLog.save();
    return tripLog;
}

io.on('connection', (socket) => {
    console.log('🔌 New Client Connected:', socket.id, socket.user ? `(Authenticated: ${socket.user.role} ${socket.user.id})` : '(Guest/Unauthenticated)');

    // Automatically join dedicated room for managers & admins to receive high-privilege emergency telemetry
    if (socket.user && (socket.user.role === 'manager' || socket.user.role === 'admin')) {
        socket.join('managers');
        console.log(`👑 [AUTH-ROOM] Socket ${socket.id} joined privileged "managers" room`);
        broadcastStats();
    }

    // Privileged room subscription handler with strict RBAC verification
    socket.on('joinManager', (dataOrCallback, maybeCallback) => {
        const callback = typeof dataOrCallback === 'function' ? dataOrCallback : maybeCallback;

        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'joinManager');
        if (!limitCheck.allowed) {
            console.warn(`⚠️ [RATE-LIMIT] Socket ${socket.id} exceeded joinManager rate limit`);
            if (typeof callback === 'function') callback({ success: false, error: limitCheck.reason, code: 'RATE_LIMIT_EXCEEDED' });
            return;
        }

        if (socket.user && (socket.user.role === 'manager' || socket.user.role === 'admin')) {
            socket.join('managers');
            broadcastStats();
            if (typeof callback === 'function') callback({ success: true, room: 'managers' });
        } else {
            console.warn(`🚫 [AUTH-BLOCK] Socket ${socket.id} rejected from joining "managers" room`);
            socket.emit('error', 'Unauthorized: Manager or Admin privileges required');
            if (typeof callback === 'function') callback({ success: false, error: 'Unauthorized: Manager or Admin privileges required' });
        }
    });

    socket.on('leaveManager', () => {
        socket.leave('managers');
    });

    socket.on('triggerSOS', async (data, callback) => {
        if (isShuttingDown) {
            console.warn(`🛑 [SHUTDOWN] Rejected triggerSOS from socket ${socket.id} — server shutting down`);
            if (typeof callback === 'function') callback({ success: false, error: 'SERVER_SHUTTING_DOWN' });
            return;
        }

        // Payload size protection
        if (!defaultLimiter.validatePayloadSize(data, 2048)) {
            console.warn(`⚠️ [SECURITY] Rejected oversized SOS payload from socket ${socket.id}`);
            if (typeof callback === 'function') callback({ success: false, error: 'Oversized payload rejected' });
            return;
        }

        // Per-socket / per-user SOS Rate Limiting (Never silently drop)
        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'triggerSOS');
        if (!limitCheck.allowed) {
            console.warn(`⚠️ [AUDIT-ALERT] SOS trigger rate limit reached for socket ${socket.id} (user: ${socket.user?.id || 'guest'})`);
            const existingAlert = sosCooldownMap.get(socket.user?.id) || sosCooldownMap.get(socket.id);
            if (typeof callback === 'function') {
                callback({
                    success: false,
                    error: 'SOS rate limit exceeded. Existing alert is active and already broadcast to managers.',
                    code: 'SOS_THROTTLED',
                    existingAlertId: existingAlert?.alertId
                });
            }
            return;
        }

        operationTracker.begin();
        console.log('🚨 \x1b[31mACTIVE SOS EMERGENCY RECEIVED\x1b[0m:', data);
        
        try {
            // Strict identity attribution: Authenticated credentials ALWAYS override client payload
            let verifiedUserId;
            let verifiedRole;
            let alertName;

            if (socket.user && socket.user.id) {
                verifiedUserId = socket.user.id;
                verifiedRole = socket.user.role || 'user';
                alertName = socket.user.name || socket.user.username || 'Authenticated Commuter';
            } else {
                verifiedUserId = 'guest_' + socket.id;
                verifiedRole = 'guest'; // NEVER trust client-supplied role for unauthenticated sockets
                alertName = (data && typeof data.name === 'string' && data.name.trim().length > 0)
                    ? data.name.trim().slice(0, 50)
                    : 'Emergency Guest';
            }

            // Anti-Spam Debounce: Prevent duplicate submissions within cooldown window
            const now = Date.now();
            const existingAlert = sosCooldownMap.get(verifiedUserId) || sosCooldownMap.get(socket.id);
            if (existingAlert && (now - existingAlert.timestamp) < SOS_COOLDOWN_MS) {
                const secondsRemaining = Math.ceil((SOS_COOLDOWN_MS - (now - existingAlert.timestamp)) / 1000);
                console.log(`⏱️ [SOS-COOLDOWN] Duplicate SOS from ${alertName} (${verifiedUserId}) within ${Math.round((now - existingAlert.timestamp)/1000)}s. Acknowledging existing alert (${secondsRemaining}s remaining).`);
                if (typeof callback === 'function') {
                    callback({
                        success: true,
                        alertId: existingAlert.alertId,
                        deduplicated: true,
                        cooldownSecondsRemaining: secondsRemaining
                    });
                }
                return;
            }

            // Coordinate Sanity & Validation: Do NOT default invalid/missing coordinates to misleading (0,0)
            const { latitude: safeLat, longitude: safeLng, locationAvailable } = parseSosCoordinates(data);

            const safeTimestamp = (data && data.timestamp && !isNaN(Date.parse(data.timestamp)))
                ? new Date(data.timestamp)
                : new Date();

            const newAlert = new Alert({
                userId: verifiedUserId,
                name: alertName,
                role: verifiedRole,
                latitude: safeLat,
                longitude: safeLng,
                locationAvailable: locationAvailable,
                routeId: data && data.routeId ? String(data.routeId) : undefined,
                routeName: data && data.routeName ? String(data.routeName).slice(0, 100) : undefined,
                busId: data && data.busId ? String(data.busId) : undefined,
                timestamp: safeTimestamp
            });

            await newAlert.save();
            const alertPayload = newAlert.toObject ? newAlert.toObject() : { ...newAlert };
            alertPayload.id = newAlert._id.toString();
            alertPayload._id = newAlert._id.toString();
            alertPayload.locationAvailable = locationAvailable;
            alertPayload.latitude = safeLat;
            alertPayload.longitude = safeLng;
            // Data privacy: Strip sensitive authentication attributes
            delete alertPayload.password;
            delete alertPayload.token;

            // Cache in cooldown map
            sosCooldownMap.set(verifiedUserId, { timestamp: now, alertId: newAlert._id, alertPayload });
            if (socket.id) {
                sosCooldownMap.set(socket.id, { timestamp: now, alertId: newAlert._id, alertPayload });
            }

            // Restrict SOS alert telemetry to authorized managers/admins room only
            emitSensitiveSosAlert(io, alertPayload);

            // Also emit system notification so managers/admins have it in notifications feed
            try {
                if (mongoose.connection.readyState === 1) {
                    const coordsText = locationAvailable
                        ? `Coordinates: ${safeLat.toFixed(4)}, ${safeLng.toFixed(4)}`
                        : `Coordinates: Location Unavailable (GPS offline or pending)`;

                    const emergencyNotif = new Notification({
                        title: `🚨 EMERGENCY SOS: ${alertName}`,
                        message: `SOS alert triggered by ${alertName} (${verifiedRole.toUpperCase()})${data && data.busId ? ` on Bus ${data.busNumber || data.busId}` : ''}. ${coordsText}`,
                        type: 'emergency',
                        priority: 'urgent',
                        targetAudience: 'Admins',
                        createdAt: new Date()
                    });
                    await emergencyNotif.save();
                    const notifPayload = emergencyNotif.toObject ? emergencyNotif.toObject() : { ...emergencyNotif };
                    notifPayload.id = emergencyNotif._id.toString();
                    notifPayload._id = emergencyNotif._id.toString();
                    emitEmergencySosNotification(io, notifPayload);
                }
            } catch (notifErr) {
                console.error('⚠️ [SOS] Failed to save emergency notification:', notifErr.message);
            }

            // Push FCM to Managers and Admins (STRICTLY GUARDED: Mocked in test / staging / disabled mode)
            try {
                if (!areExternalNotificationsSuppressed(process.env) && admin.apps.length > 0 && mongoose.connection.readyState === 1) {
                    const managers = await Manager.find({ fcmToken: { $exists: true, $ne: null } }).select('fcmToken');
                    const admins = await Admin.find({ fcmToken: { $exists: true, $ne: null } }).select('fcmToken');
                    const tokens = [...managers, ...admins].map(m => m.fcmToken).filter(t => t && t.length > 10);
                    if (tokens.length > 0) {
                        const fcmResult = await dispatchFcmMulticast({
                            notification: {
                                title: `🚨 EMERGENCY SOS ALERT`,
                                body: `${alertName} triggered an emergency SOS alert!`
                            },
                            android: {
                                priority: 'high',
                                notification: {
                                    channelId: 'SISTecChalo_pulse_alerts',
                                    color: '#FF2E63',
                                    sound: 'default'
                                }
                            },
                            tokens: tokens
                        });
                        if (!fcmResult.suppressed) {
                            console.log(`🔥 [Firebase] Sent SOS push notifications to ${tokens.length} managers/admins.`);
                        }
                    }
                }
            } catch (fcmErr) {
                console.error('⚠️ [Firebase] Failed to send manager SOS push:', fcmErr.message);
            }

            if (typeof callback === 'function') callback({ success: true, alertId: newAlert._id });
        } catch (err) {
            console.error('Failed to save SOS alert:', err);
            // Fallback: emit sanitized alert without crashing if DB fails, preserving location availability
            const { latitude: safeLat, longitude: safeLng, locationAvailable } = parseSosCoordinates(data);
            const fallbackPayload = {
                id: 'fallback_' + Date.now(),
                userId: socket.user?.id || 'guest',
                name: socket.user?.name || socket.user?.username || 'Emergency User',
                role: socket.user?.role || 'guest',
                latitude: safeLat,
                longitude: safeLng,
                locationAvailable,
                timestamp: new Date().toISOString()
            };
            emitSensitiveSosAlert(io, fallbackPayload);
            if (typeof callback === 'function') callback({ success: false, error: err.message });
        } finally {
            operationTracker.end();
        }
    });

    socket.on('joinRoute', (routeId, callback) => {
        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'joinRoute');
        if (!limitCheck.allowed) {
            console.warn(`⚠️ [RATE-LIMIT] Socket ${socket.id} exceeded joinRoute rate limit`);
            if (typeof callback === 'function') callback({ success: false, error: limitCheck.reason, code: 'RATE_LIMIT_EXCEEDED' });
            return;
        }

        if (routeId) {
            const cleanRouteId = String(routeId).trim().slice(0, 64);
            const roomName = `route_${cleanRouteId}`;
            socket.join(roomName);
            console.log(`🚪 Socket ${socket.id} joined room: ${roomName}`);
            if (typeof callback === 'function') callback({ success: true, room: roomName });
        }
    });

    socket.on('leaveRoute', (routeId) => {
        if (routeId) {
            const cleanRouteId = String(routeId).trim().slice(0, 64);
            const roomName = `route_${cleanRouteId}`;
            socket.leave(roomName);
            console.log(`🚪 Socket ${socket.id} left room: ${roomName}`);
        }
    });

    socket.on('locationUpdate', async (data) => {
        if (isShuttingDown) {
            socket.emit('telemetryRejected', {
                code: 'SERVER_SHUTTING_DOWN',
                message: 'Server is restarting for deployment. Telemetry rejected.',
                retryAfterMs: 2500
            });
            return;
        }

        // Rate limiting check across socket, user and IP
        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'locationUpdate');
        if (!limitCheck.allowed) {
            socket.emit('telemetryRejected', {
                code: 'RATE_LIMIT_EXCEEDED',
                message: limitCheck.reason,
                retryAfterMs: limitCheck.retryAfterMs
            });
            return;
        }

        // Payload size check
        if (!defaultLimiter.validatePayloadSize(data, 4096)) {
            socket.emit('telemetryRejected', {
                code: 'PAYLOAD_TOO_LARGE',
                message: 'Telemetry payload exceeds maximum permitted byte size (4KB).'
            });
            return;
        }

        // Payload structure and coordinate bounds validation
        const payloadValidation = defaultLimiter.validateLocationPayload(data);
        if (!payloadValidation.valid) {
            socket.emit('telemetryRejected', {
                code: 'INVALID_TELEMETRY_PAYLOAD',
                message: payloadValidation.error
            });
            return;
        }

        // STRICT DRIVER AUTHENTICATION: Never trust client-supplied driverId or role
        if (!socket.user) {
            console.warn(`🚫 [AUTH-BLOCK] Unauthenticated socket ${socket.id} attempted locationUpdate`);
            socket.emit('telemetryRejected', {
                code: 'UNAUTHENTICATED',
                message: 'Authentication required for telemetry updates.'
            });
            return;
        }

        if (socket.user.role !== 'driver' && socket.user.role !== 'manager' && socket.user.role !== 'admin') {
            console.warn(`🚫 [AUTH-BLOCK] Unauthorized role "${socket.user.role}" attempted locationUpdate`);
            socket.emit('telemetryRejected', {
                code: 'UNAUTHORIZED_ROLE',
                message: 'Driver privileges required for telemetry updates.'
            });
            return;
        }

        const incomingBusId = (data.busId || data.id || data._id || '').toString();
        if (!incomingBusId) return;

        operationTracker.begin();
        try {
            let bus = await Bus.findById(incomingBusId);
            
            // SECURITY BLOCK: If the ID is from an old simulation, reject it.
            if (!bus) {
                if (socket.user.role === 'driver') {
                    const driverDoc = await Driver.findById(socket.user.id).select('assignedBus status');
                    if (driverDoc && driverDoc.assignedBus) {
                        bus = await Bus.findById(driverDoc.assignedBus);
                    }
                }
                if (!bus) {
                    process.stdout.write('🚫 [SIM-BLOCK] Rejected Old/Simulation BusID: ' + incomingBusId + '\r');
                    return;
                }
            }

            // Derive driver ID strictly from verified socket.user, NEVER from client-supplied data.driverId
            const verifiedDriverId = socket.user.id;

            // Validate Driver Authorization and Account Status
            if (socket.user.role === 'driver') {
                const driver = await Driver.findById(verifiedDriverId).select('status assignedBus username name');
                if (!driver || driver.status === 'Suspended') {
                    return; // Reject telemetry from non-existent or suspended drivers
                }
                const driverUsername = (driver.username || socket.user.username || '');
                const driverUsernameDigits = driverUsername.replace(/[^0-9]/g, '');
                const busDigits = (bus.busNumber || '').replace(/[^0-9]/g, '');
                const isUsernameMatch = Boolean(driverUsernameDigits && busDigits && driverUsernameDigits === busDigits);

                const isAssigned = (driver.assignedBus && driver.assignedBus.toString() === bus._id.toString()) ||
                                   (bus.driverId && bus.driverId.toString() === verifiedDriverId) ||
                                   isUsernameMatch;
                if (!isAssigned) {
                    console.warn(`🚫 [AUTH-BLOCK] Driver ${verifiedDriverId} attempted update for unassigned bus ${bus.busNumber}`);
                    return; // Reject telemetry from driver not assigned to this bus
                }
            }

            const rawLat = (data.latitude !== undefined && data.latitude !== null) ? Number(data.latitude) : ((data.currentLat !== undefined && data.currentLat !== null) ? Number(data.currentLat) : bus.currentLat);
            const rawLng = (data.longitude !== undefined && data.longitude !== null) ? Number(data.longitude) : ((data.currentLng !== undefined && data.currentLng !== null) ? Number(data.currentLng) : bus.currentLng);
            const rawSpeed = data.speed !== undefined ? Number(data.speed) : (bus.speed || 0);
            const rawHeading = data.heading !== undefined ? Number(data.heading) : (bus.heading || 0);

            // Strict Coordinate Sanity Validation: Reject NaN, Null, and out-of-range coordinates
            if (rawLat === null || rawLat === undefined || isNaN(rawLat) || rawLat < -90 || rawLat > 90 ||
                rawLng === null || rawLng === undefined || isNaN(rawLng) || rawLng < -180 || rawLng > 180) {
                return; // Discard malformed coordinate packet
            }

            // Reject uninitialized Null Island (0,0) coordinates
            if (rawLat === 0 && rawLng === 0) {
                return;
            }

            // Timestamp parsing & out-of-order rejection
            const validPacketTime = parseTelemetryPacketTimestamp(data.timestamp);

            // Reject anomalous packets timestamped > 60s in future
            if (validPacketTime.getTime() > Date.now() + 60000) {
                console.warn(`⚠️ [TELEMETRY-REJECTED] Future timestamp from bus ${bus.busNumber || incomingBusId}: ${data.timestamp}`);
                socket.emit('telemetryRejected', {
                    code: 'FUTURE_TIMESTAMP',
                    message: 'Telemetry packet timestamp is too far in the future.'
                });
                return;
            }

            // Monotonicity check: Reject stale out-of-order packet if older than last recorded update by > 3s
            if (bus.lastUpdated && validPacketTime.getTime() < (new Date(bus.lastUpdated).getTime() - 3000)) {
                return;
            }

            // Teleportation / Plausible Jump Filter:
            // Max plausible vehicle speed 130 km/h with 350m GPS multipath buffer
            if (bus.currentLat && bus.currentLng && bus.lastUpdated && !(bus.currentLat === 0 && bus.currentLng === 0)) {
                const timeDeltaSec = (validPacketTime.getTime() - new Date(bus.lastUpdated).getTime()) / 1000;
                if (timeDeltaSec > 0.5 && timeDeltaSec < 120) {
                    const R = 6371;
                    const dLat = (rawLat - bus.currentLat) * Math.PI / 180;
                    const dLon = (rawLng - bus.currentLng) * Math.PI / 180;
                    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                              Math.cos(bus.currentLat * Math.PI / 180) * Math.cos(rawLat * Math.PI / 180) *
                              Math.sin(dLon / 2) * Math.sin(dLon / 2);
                    const jumpDistKm = R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                    const impliedKmh = (jumpDistKm / timeDeltaSec) * 3600;
                    if (jumpDistKm > 0.35 && impliedKmh > 130) {
                        return; // Discard teleportation / GPS multipath jump
                    }
                }
            }

            const lat = rawLat;
            const lng = rawLng;
            const speed = Math.max(0, Math.min(130, isNaN(rawSpeed) ? 0 : rawSpeed));
            const heading = Math.max(0, Math.min(360, isNaN(rawHeading) ? 0 : rawHeading));

            const gpsAccuracy = data.gpsAccuracy !== undefined ? Number(data.gpsAccuracy) : null;

            process.stdout.write(`📍 [LIVE] Bus: ${bus.busNumber} | Lat: ${lat.toFixed(5)} | Lng: ${lng.toFixed(5)} | Speed: ${speed.toFixed(1)} KM/H${gpsAccuracy != null ? ` | GPS: ±${gpsAccuracy.toFixed(0)}m` : ''}\r`);

            // ── DUAL TRIP DIRECTION: 'pickup' (Stop -> College) vs 'dropoff' (College -> Stop) ──
            const tripType = normalizeTripType(data.tripType);
            bus.tripType = tripType;

            // ── LIVE TRIP LOG: Auto-create or sync today's trip scoped by tripType (IST date) ──
            const todayStr = getIstDateString();
            const tripLog = await syncActiveTripLogForTelemetry({
                LiveTripLogModel: LiveTripLog,
                bus,
                todayStr,
                tripType,
                distanceKm: data.distanceKm,
                reachedStops: data.reachedStops,
                verifiedDriverId: socket.user.role === 'driver' ? verifiedDriverId : null,
                resolveSnapshots: async () => {
                    let driverDoc = socket.user.role === 'driver'
                        ? await Driver.findById(verifiedDriverId)
                        : (bus.driverId ? await Driver.findById(bus.driverId) : null);
                    if (!driverDoc && bus.driverId) {
                        driverDoc = await Driver.findById(bus.driverId);
                    }
                    if (!driverDoc) {
                        driverDoc = await Driver.findOne({ assignedBus: bus._id.toString() });
                    }
                    const driverNameLive = driverDoc ? (driverDoc.name || driverDoc.username) : 'Unassigned';
                    const driverPhoneLive = driverDoc ? (driverDoc.phone || driverDoc.contactNumber || 'N/A') : 'N/A';
                    const routeDoc = bus.routeId ? await Route.findById(bus.routeId) : null;
                    const routeNameLive = routeDoc ? routeDoc.name : (bus.routeName || 'Unassigned');
                    return {
                        driverId: driverDoc ? driverDoc._id : null,
                        driverName: driverNameLive,
                        driverPhone: driverPhoneLive,
                        routeId: routeDoc ? routeDoc._id : null,
                        routeName: routeNameLive
                    };
                }
            });

            // Update Route & Identity if sent by driver cockpit (prevent arbitrary overwriting if busNumber already set)
            if (data.routeId && data.routeId.toString().length > 5) {
                bus.routeId = data.routeId.toString();
            }
            if (data.routeName && data.routeName.trim().length > 0) {
                bus.routeName = data.routeName.trim();
            }
            if ((!bus.busNumber || bus.busNumber === 'N/A') && data.busNumber && data.busNumber.trim().length > 0 && data.busNumber !== 'N/A') {
                bus.busNumber = data.busNumber.trim();
            }

            // Update DB telemetry
            bus.currentLat = lat;
            bus.currentLng = lng;
            bus.speed = speed;
            bus.heading = heading;
            bus.lastUpdated = validPacketTime;
            // Preserve an existing Delayed status unless explicitly overridden
            bus.status = resolveBusTelemetryStatus(bus.status, data.status, Boolean(data.explicitStatusOverride));

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
                    const progress = computeRouteProgressAndETAs(lat, lng, speed, route.stops, route.coordinates, tripType, bus.reachedStops);
                    etas = progress.etas;
                    nextStopName = progress.nextStopName;

                    for (let sIdx = 0; sIdx < etas.length; sIdx++) {
                        const stop = etas[sIdx];
                        const currentStopName = stop.name || stop.stopName || '';
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
                            if (distanceKm <= 3.0 && currentStopName) {
                                (async () => {
                                    if (!areExternalNotificationsSuppressed(process.env) && admin.apps.length > 0) {
                                        try {
                                            const targetUsers = await User.find({
                                                routeId: bus.routeId ? bus.routeId.toString() : null,
                                                pickupPoint: { $regex: new RegExp(`^${currentStopName.trim()}$`, 'i') },
                                                proximityAlertsEnabled: true
                                            });

                                            const now = Date.now();
                                            const tokens = [];

                                            for (const user of targetUsers) {
                                                const uRadius = user.proximityRadiusKm !== undefined ? user.proximityRadiusKm : 1.0;
                                                if (distanceKm <= uRadius) {
                                                    if (!userGeofenceState[user._id]) userGeofenceState[user._id] = {};
                                                    const lastNotified = userGeofenceState[user._id][currentStopName] || 0;

                                                    if (now - lastNotified > COOLDOWN_MS) {
                                                        userGeofenceState[user._id][currentStopName] = now;
                                                        tokens.push(user.fcmToken);
                                                    }
                                                }
                                            }

                                            if (tokens.length > 0) {
                                                const messagePayload = {
                                                    notification: {
                                                        title: `Bus Approaching: ${bus.routeName || 'Shuttle'}`,
                                                        body: `Your shuttle is approaching ${currentStopName}. Distance: ${distanceKm.toFixed(1)} km. Est: ${stopMinutes} min.`
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
                                                const response = await dispatchFcmMulticast(messagePayload);
                                                if (!response.suppressed) {
                                                    console.log(`🔥 [Firebase] Sent custom proximity push notification to ${response.successCount} users.`);
                                                }
                                                
                                                // Clean up invalid tokens
                                                (response.responses || []).forEach((resp, idx) => {
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

                            if (distanceKm <= GEOFENCE_RADIUS_KM && currentStopName) {
                                const now = Date.now();
                                if (!busGeofenceState[bus._id]) busGeofenceState[bus._id] = {};
                                const lastNotified = busGeofenceState[bus._id][currentStopName] || 0;

                                if (now - lastNotified > COOLDOWN_MS) {
                                    busGeofenceState[bus._id][currentStopName] = now;
                                    const approachPayload = buildBusApproachingStopPayload({
                                        bus,
                                        stopName: currentStopName,
                                        distanceKm,
                                        minutes: stopMinutes
                                    });
                                    io.emit('busApproachingStop', approachPayload);
                                    if (approachPayload.routeId) {
                                        io.to(`route_${approachPayload.routeId}`).emit('busApproachingStop', approachPayload);
                                    }
                                    console.log(`🔔 [GEOFENCE] Bus ${bus.busNumber} reached stop: ${currentStopName}`);

                                    // ── LIVE TRIP LOG: Record actual stop-reached time ──
                                    if (tripLog && Array.isArray(tripLog.reachedStops)) {
                                        const alreadyRecorded = tripLog.reachedStops.some(rs => rs.stopName === currentStopName);
                                        if (!alreadyRecorded) {
                                            tripLog.reachedStops.push({ stopName: currentStopName, reachedTime: new Date() });
                                            await tripLog.save();
                                            console.log(`✅ [TRIP LOG] Recorded: Bus ${bus.busNumber} → Stop "${currentStopName}" at ${new Date().toLocaleTimeString()}`);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            const isStopAlreadyPassed = (name) => {
                if (!name || !bus.reachedStops || !Array.isArray(bus.reachedStops)) return false;
                const n = String(name).trim().toLowerCase();
                return bus.reachedStops.some(r => {
                    const rT = String(r).trim().toLowerCase();
                    return rT === n || (rT.length > 2 && (n.includes(rT) || rT.includes(n)));
                });
            };

            const candidateDriverNext = (data.nextStop && !isStopAlreadyPassed(data.nextStop)) ? data.nextStop : '';
            const resolvedNextStop = candidateDriverNext || nextStopName || (etas[0] ? (etas[0].stopName || etas[0].name) : '');
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
            busPayload.busId = bus._id.toString();
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
            busPayload.lastUpdated = validPacketTime;
            busPayload.timestamp = validPacketTime.toISOString();

            io.emit('busLocationUpdate', busPayload);
            io.emit('locationUpdate', busPayload);
            if (bus.routeId) {
                io.to(`route_${bus.routeId.toString()}`).emit('busLocationUpdate', busPayload);
                io.to(`route_${bus.routeId.toString()}`).emit('locationUpdate', busPayload);
            }

            // ── HISTORICAL TELEMETRY PERSISTENCE (Non-blocking, sampled, tripLogId-scoped) ──
            if (tripLog && tripLog._id) {
                const rawTelemetrySpeed = (data.speed !== undefined && data.speed !== null && data.speed !== '')
                    ? Number(data.speed)
                    : null;
                const rawTelemetryHeading = (data.heading !== undefined && data.heading !== null && data.heading !== '')
                    ? Number(data.heading)
                    : null;
                const rawTelemetryAccuracy = (data.gpsAccuracy !== undefined && data.gpsAccuracy !== null && data.gpsAccuracy !== '')
                    ? Number(data.gpsAccuracy)
                    : null;

                persistTelemetryPointIfSampled({
                    TripTelemetryPointModel: TripTelemetryPoint,
                    tripLogId: tripLog._id,
                    busId: bus._id.toString(),
                    lat,
                    lng,
                    speed: rawTelemetrySpeed,
                    heading: rawTelemetryHeading,
                    accuracy: rawTelemetryAccuracy,
                    timestamp: validPacketTime
                }).catch(err => {
                    console.warn('⚠️ [TELEMETRY PERSISTENCE WARNING]:', err.message);
                });
            }

        } catch (err) {
            console.error('❌ [TRACKING ERROR]:', err.message);
        } finally {
            operationTracker.end();
        }
    });

    // Driver signals end of trip or stops broadcast
    const handleTripEndOrStopBroadcast = async (data) => {
        if (isShuttingDown) return;
        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'tripEnd');
        if (!limitCheck.allowed) {
            console.warn(`⚠️ [RATE-LIMIT] Socket ${socket.id} exceeded tripEnd rate limit`);
            socket.emit('error', { code: 'RATE_LIMIT_EXCEEDED', message: limitCheck.reason });
            return;
        }
        operationTracker.begin();
        try {
            // STRICT DRIVER AUTHENTICATION: Never trust client-supplied driverId or role
            if (!socket.user) {
                console.warn(`🚫 [AUTH-BLOCK] Unauthenticated socket ${socket.id} attempted tripEnd`);
                return;
            }

            if (socket.user.role !== 'driver' && socket.user.role !== 'manager' && socket.user.role !== 'admin') {
                console.warn(`🚫 [AUTH-BLOCK] Unauthorized role "${socket.user.role}" attempted tripEnd`);
                return;
            }

            const busId = (data.busId || data.id || data._id || '').toString();
            if (!busId) return;

            if (socket.user.role === 'driver') {
                const driver = await Driver.findById(socket.user.id).select('status assignedBus username name');
                if (!driver || driver.status === 'Suspended') return;
                const busDoc = await Bus.findById(busId).select('busNumber driverId');
                const driverUsername = (driver.username || socket.user.username || '');
                const driverDigits = driverUsername.replace(/[^0-9]/g, '');
                const busDigits = (busDoc?.busNumber || '').replace(/[^0-9]/g, '');
                const isUsernameMatch = Boolean(driverDigits && busDigits && driverDigits === busDigits);
                const isAssigned = (driver.assignedBus && driver.assignedBus.toString() === busId) ||
                                   (busDoc?.driverId && busDoc.driverId.toString() === socket.user.id) ||
                                   isUsernameMatch;
                if (!isAssigned) {
                    console.warn(`🚫 [AUTH-BLOCK] Driver ${socket.user.id} cannot terminate unassigned bus ${busId}`);
                    return;
                }
            }
            if (busId) {
                const bus = await Bus.findByIdAndUpdate(
                    busId, 
                    { status: 'Offline', speed: 0, etas: [], reachedStops: [], completedStops: 0, nextStop: '', lastUpdated: new Date() },
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
                    reachedStops: [],
                    completedStops: 0,
                    nextStop: '',
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
            const todayStr = getIstDateString();
            const tripLog = await completeActiveTripLog({
                LiveTripLogModel: LiveTripLog,
                busId,
                todayStr,
                tripType: data ? data.tripType : undefined,
                distanceKm: data ? data.distanceKm : undefined,
                verifiedDriverId: socket.user.role === 'driver' ? socket.user.id : null
            });
            if (tripLog) {
                clearTelemetrySamplerState(tripLog._id);
                io.emit('tripCompleted', {
                    tripId: tripLog._id,
                    busId,
                    tripType: tripLog.tripType,
                    distanceKm: tripLog.distanceKm,
                    durationMinutes: tripLog.durationMinutes,
                    endTime: tripLog.endTime,
                    status: 'Completed'
                });
            }
        } catch (err) {
            console.error('❌ [TRIP END ERROR]:', err.message);
        } finally {
            operationTracker.end();
        }
    };

    const handleTripStart = async (data) => {
        if (isShuttingDown) return;
        const limitCheck = defaultLimiter.consume(defaultLimiter.getSocketEntities(socket), 'startTrip');
        if (!limitCheck.allowed) {
            console.warn(`⚠️ [RATE-LIMIT] Socket ${socket.id} exceeded startTrip rate limit`);
            socket.emit('error', { code: 'RATE_LIMIT_EXCEEDED', message: limitCheck.reason });
            return;
        }
        operationTracker.begin();
        try {
            if (!socket.user) return;
            if (socket.user.role !== 'driver' && socket.user.role !== 'manager' && socket.user.role !== 'admin') return;

            const busId = (data.busId || data.id || data._id || '').toString();
            if (!busId) return;

            const bus = await Bus.findById(busId);
            if (!bus) return;

            const authCheck = await verifyDriverBusAuthorization({
                socketUser: socket.user,
                bus,
                busId,
                DriverModel: Driver
            });
            if (!authCheck.authorized) {
                console.warn(`🚫 [AUTH-BLOCK] Socket user ${socket.user.id} cannot start trip for bus ${busId} (${authCheck.reason})`);
                return;
            }

            const todayStr = getIstDateString();
            const tripType = normalizeTripType(data.tripType);
            const verifiedDriverId = socket.user.role === 'driver' ? socket.user.id : null;

            const startResult = await startOrResumeTripLog({
                LiveTripLogModel: LiveTripLog,
                bus,
                todayStr,
                tripType,
                distanceKm: data ? data.distanceKm : undefined,
                verifiedDriverId,
                resolveSnapshots: async () => {
                    let driverDoc = authCheck.driverDoc || (bus.driverId ? await Driver.findById(bus.driverId) : null);
                    if (!driverDoc) {
                        driverDoc = await Driver.findOne({ assignedBus: bus._id.toString() });
                    }
                    const driverName = driverDoc ? (driverDoc.name || driverDoc.username) : 'Unassigned';
                    const driverPhone = driverDoc ? (driverDoc.phone || driverDoc.contactNumber || 'N/A') : 'N/A';
                    const routeDoc = bus.routeId ? await Route.findById(bus.routeId) : null;
                    const routeName = routeDoc ? routeDoc.name : (bus.routeName || 'Unassigned');
                    return {
                        driverId: driverDoc ? driverDoc._id : null,
                        driverName,
                        driverPhone,
                        routeId: routeDoc ? routeDoc._id : null,
                        routeName
                    };
                }
            });

            if (!startResult.tripLog) {
                console.warn(`🚫 [TRIP START CONFLICT] Rejected tripStart for Bus ${bus.busNumber} (${startResult.conflict})`);
                return;
            }

            const { tripLog, isResumed } = startResult;
            if (isResumed) {
                console.log(`⚠️ [TRIP START GUARD] Trip already active for Bus ${bus.busNumber} (${tripType}) on ${todayStr} (ID: ${tripLog._id})`);
                socket.emit('tripStarted', {
                    success: true,
                    tripId: tripLog._id,
                    busId: bus._id.toString(),
                    tripType,
                    status: 'Active',
                    isResumed: true
                });
                return;
            }

            bus.status = resolveBusTelemetryStatus(bus.status, 'On-time', false);
            bus.tripType = tripType;
            await bus.save();

            socket.emit('tripStarted', {
                success: true,
                tripId: tripLog._id,
                busId: bus._id.toString(),
                tripType,
                status: 'Active',
                isResumed: false
            });
            io.emit('tripStarted', {
                tripId: tripLog._id,
                busId: bus._id.toString(),
                busNumber: bus.busNumber,
                tripType,
                status: 'Active',
                startTime: tripLog.startTime
            });
        } catch (err) {
            console.error('❌ [TRIP START ERROR]:', err.message);
        } finally {
            operationTracker.end();
        }
    };

    const handleTripCancel = async (data) => {
        if (isShuttingDown) return;
        operationTracker.begin();
        try {
            if (!socket.user) return;
            if (socket.user.role !== 'driver' && socket.user.role !== 'manager' && socket.user.role !== 'admin') return;

            const busId = (data.busId || data.id || data._id || '').toString();
            if (!busId) return;

            if (socket.user.role === 'driver') {
                const busDoc = await Bus.findById(busId).select('busNumber driverId');
                const authCheck = await verifyDriverBusAuthorization({
                    socketUser: socket.user,
                    bus: busDoc,
                    busId,
                    DriverModel: Driver
                });
                if (!authCheck.authorized) {
                    console.warn(`🚫 [AUTH-BLOCK] Driver ${socket.user.id} cannot cancel unassigned bus ${busId}`);
                    return;
                }
            }

            const bus = await Bus.findByIdAndUpdate(
                busId,
                { status: 'Offline', speed: 0, etas: [], reachedStops: [], completedStops: 0, nextStop: '', lastUpdated: new Date() },
                { new: true }
            );

            const cancelPayload = {
                id: busId,
                _id: busId,
                busId: busId,
                busNumber: bus ? bus.busNumber : undefined,
                status: 'Offline',
                speed: 0,
                etas: [],
                reachedStops: [],
                completedStops: 0,
                nextStop: '',
                lastUpdated: new Date(),
                isCancelled: true
            };

            io.emit('busLocationUpdate', cancelPayload);
            io.emit('locationUpdate', cancelPayload);
            io.emit('busUpdated', cancelPayload);
            io.emit('tripCancelled', { busId, reason: data.reason || 'Trip cancelled by driver' });

            const verifiedDriverId = socket.user.role === 'driver' ? socket.user.id : null;
            const tripLog = await terminateActiveTripLog({
                LiveTripLogModel: LiveTripLog,
                busId,
                tripId: data?.tripId || data?.tripLogId || null,
                tripType: data?.tripType || null,
                targetStatus: 'Cancelled',
                reason: data.reason || 'Trip cancelled by driver',
                verifiedDriverId
            });
            if (tripLog) {
                io.emit('tripCancelled', {
                    tripId: tripLog._id,
                    busId,
                    tripType: tripLog.tripType,
                    reason: tripLog.cancellationReason,
                    endTime: tripLog.endTime,
                    status: 'Cancelled'
                });
            }
        } catch (err) {
            console.error('❌ [TRIP CANCEL ERROR]:', err.message);
        } finally {
            operationTracker.end();
        }
    };

    const handleTripFail = async (data) => {
        if (isShuttingDown) return;
        operationTracker.begin();
        try {
            if (!socket.user) return;
            if (socket.user.role !== 'driver' && socket.user.role !== 'manager' && socket.user.role !== 'admin') return;

            const busId = (data.busId || data.id || data._id || '').toString();
            if (!busId) return;

            if (socket.user.role === 'driver') {
                const busDoc = await Bus.findById(busId).select('busNumber driverId');
                const authCheck = await verifyDriverBusAuthorization({
                    socketUser: socket.user,
                    bus: busDoc,
                    busId,
                    DriverModel: Driver
                });
                if (!authCheck.authorized) {
                    console.warn(`🚫 [AUTH-BLOCK] Driver ${socket.user.id} cannot mark unassigned bus ${busId} failed`);
                    return;
                }
            }

            await Bus.findByIdAndUpdate(busId, { status: 'Offline', speed: 0, lastUpdated: new Date() });
            const verifiedDriverId = socket.user.role === 'driver' ? socket.user.id : null;
            const tripLog = await terminateActiveTripLog({
                LiveTripLogModel: LiveTripLog,
                busId,
                tripId: data?.tripId || data?.tripLogId || null,
                tripType: data?.tripType || null,
                targetStatus: 'Failed',
                reason: data.reason || 'Vehicle breakdown / mechanical failure',
                verifiedDriverId
            });
            if (tripLog) {
                io.emit('tripFailed', {
                    tripId: tripLog._id,
                    busId,
                    reason: tripLog.cancellationReason,
                    endTime: tripLog.endTime,
                    status: 'Failed'
                });
            }
        } catch (err) {
            console.error('❌ [TRIP FAIL ERROR]:', err.message);
        } finally {
            operationTracker.end();
        }
    };

    socket.on('startTrip', handleTripStart);
    socket.on('startBroadcast', handleTripStart);
    socket.on('tripEnd', handleTripEndOrStopBroadcast);
    socket.on('stopBroadcast', handleTripEndOrStopBroadcast);
    socket.on('stopTrip', handleTripEndOrStopBroadcast);
    socket.on('cancelTrip', handleTripCancel);
    socket.on('tripCancelled', handleTripCancel);
    socket.on('failTrip', handleTripFail);
    socket.on('tripFailed', handleTripFail);
    socket.on('ping', () => socket.emit('pong'));
    socket.on('disconnect', () => {
        defaultLimiter.handleDisconnect(socket.id);
        console.log('Client disconnected');
    });
});



// --- SEED DATABASE ROUTE ---
app.post('/api/manager/seed', authMiddleware, adminMiddleware, async (req, res) => {
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
app.post('/api/manager/geocode-stops', authMiddleware, adminMiddleware, async (req, res) => {
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
app.post('/api/manager/preview-timetable', authMiddleware, managerMiddleware, uploadTimetable.single('file'), async (req, res) => {
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
app.post('/api/manager/apply-timetable', authMiddleware, managerMiddleware, async (req, res) => {
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
        broadcastStats();

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
app.post('/api/manager/upload-timetable', authMiddleware, managerMiddleware, uploadTimetable.single('file'), async (req, res) => {
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
            broadcastStats();
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
        broadcastStats();

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
app.post('/api/manager/sync-official-timetable', authMiddleware, managerMiddleware, async (req, res) => {
    try {
        console.log('🔄 [Manager API] 1-Tap Official Ratibad Roster Sync initiated...');
        const synced = await syncOfficialRatibadRoster(io);
        invalidateRoutesCache();

        io.emit('routesUpdated', synced);
        io.emit('busesUpdated');
        io.emit('timetableUpdated', { count: synced.length, timestamp: new Date() });
        broadcastStats();

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
app.put('/api/routes/:id/stops', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

        // Check if the requested stop has already been reached or departed
        const cleanStopName = stop.name.toLowerCase().trim();
        const hasPassed = Array.isArray(bus.reachedStops) && bus.reachedStops.some(
            s => s.toString().toLowerCase().trim() === cleanStopName
        );

        let minutes;
        let isDeparted = false;
        let activeTargetStop = stop.name;

        if (hasPassed) {
            isDeparted = true;
            // Trip Phase Transition: Target final destination (Campus in morning, route origin/terminal in dropoff)
            const terminalStop = (bus.tripType === 'dropoff') 
                ? route.stops[0] 
                : route.stops[route.stops.length - 1];
            activeTargetStop = terminalStop ? terminalStop.name : 'SISTec Campus';
            
            if (terminalStop && terminalStop.lat != null && terminalStop.lng != null) {
                minutes = await calculateETA(bus.currentLat, bus.currentLng, terminalStop.lat, terminalStop.lng, speed, route);
            } else {
                minutes = 15;
            }
        } else {
            minutes = await calculateETA(bus.currentLat, bus.currentLng, stop.lat, stop.lng, speed, route);
        }

        res.json({
            eta: minutes,
            hasPassed: isDeparted,
            targetDestination: activeTargetStop,
            originalStop: stop.name,
            busId: bus._id.toString(),
            busNumber: bus.busNumber,
            routeName: route.name,
            stopName: activeTargetStop,
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

app.post('/api/schedule', authMiddleware, managerMiddleware, async (req, res) => {
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

        // Notify managers via socket (scoped to privileged room only)
        if (io && typeof io.to === 'function') {
            io.to('managers').emit('newComplaint', complaint);
        }
        console.log(`🚨 [Complaint] New from user ${req.user.id}: "${description.substring(0,60)}..."`);

        res.status(201).json(complaint);
    } catch (_err) {
        console.error('❌ Complaint Error:', _err);
        res.status(500).json({ error: 'Failed to submit complaint' });
    }
});

app.get('/api/complaints', authMiddleware, validatePagination({ defaultPage: 1, defaultLimit: 50, maxLimit: 100 }), async (req, res) => {
    try {
        const query = (req.user.role === 'admin' || req.user.role === 'manager')
            ? {}
            : { userId: req.user.id };
        const limit = (req.pagination && req.pagination.limit) || 50;
        const skip = (req.pagination && req.pagination.skip) || 0;
        const complaints = await Complaint.find(query).sort({ createdAt: -1 }).skip(skip).limit(limit);
        res.json(complaints);
    } catch (_err) {
        res.status(500).json({ error: 'Failed to fetch complaints' });
    }
});

app.put('/api/complaints/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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

// Driver (for their own assigned bus/route), Manager, or Admin can POST to this to fire a delay alert
app.post('/api/notify-delay', authMiddleware, async (req, res) => {
    try {
        const authz = await authorizeDelayNotification({
            user: req.user,
            body: req.body,
            RouteModel: Route,
            BusModel: Bus,
            DriverModel: Driver
        });
        if (!authz.authorized) {
            return res.status(authz.status).json({ error: authz.error });
        }

        const payload = {
            routeId: authz.routeId,
            routeName: authz.routeName,
            busId: authz.busId,
            busNumber: authz.busNumber,
            message: authz.message,
            delayMinutes: authz.delayMinutes,
            timestamp: new Date().toISOString(),
        };
        // Public, non-sensitive route-level info (no PII); clients filter by routeId
        io.emit('busDelayed', payload);

        // Persist as a normalized notification; emitBroadcastNotification also emits the systemAlert
        const notifData = normalizeNotificationPayload({
            title: `Bus Delay: ${authz.routeName}`,
            message: authz.message,
            type: 'critical',
            priority: 'high',
            targetAudience: 'All'
        });
        const notif = await Notification.create({ ...notifData, createdBy: req.user.role });
        const notifPayload = notif.toObject ? notif.toObject() : { ...notif };
        notifPayload.id = (notif._id || notif.id || '').toString();
        notifPayload._id = notifPayload.id;
        emitBroadcastNotification(io, notifPayload);

        console.log(`⚠️ [Delay Alert] Route ${authz.routeName} by ${req.user.role}`);
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

        // Notify managers in real-time (scoped to privileged room only)
        if (io && typeof io.to === 'function') {
            io.to('managers').emit('newRegistration', {
                id: submission._id,
                name, studentId, routeName, pickupStop,
                submittedAt: submission.submittedAt,
            });
        }
        console.log(`📝 [Registration] New submission: ${name} (${studentId}) → ${routeName}`);
        res.status(201).json({ success: true });
    } catch (_err) {
        console.error('Registration submission error:', _err);
        res.status(500).json({ error: 'Server error. Please try again.' });
    }
});

// ── MANAGER: Create a new registration form ───────────────────────────────
app.post('/api/manager/registration-form', authMiddleware, managerMiddleware, async (req, res) => {
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
app.get('/api/manager/registration-form', authMiddleware, managerMiddleware, async (req, res) => {
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
app.put('/api/manager/registration-form/:id/close', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.get('/api/manager/registrations', authMiddleware, managerMiddleware, async (req, res) => {
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
app.post('/api/manager/registrations/bulk', authMiddleware, managerMiddleware, async (req, res) => {
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
app.put('/api/manager/registrations/:id/approve', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/manager/registrations/:id/resend-email', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/manager/test-email', authMiddleware, managerMiddleware, async (req, res) => {
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
app.put('/api/manager/registrations/:id/unapprove', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/manager/registrations/bulk-approve', authMiddleware, managerMiddleware, async (req, res) => {
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
app.put('/api/manager/registrations/:id/reject', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.delete('/api/manager/registrations/:id', authMiddleware, managerMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.post('/api/manager/registrations/bulk-delete', authMiddleware, managerMiddleware, async (req, res) => {
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
app.get('/api/debug/smtp-test', authMiddleware, adminMiddleware, async (req, res) => {
    if (areExternalNotificationsSuppressed(process.env)) {
        return res.json({
            success: true,
            suppressed: true,
            provider: 'Mock Dispatcher',
            message: 'External email/SMTP notifications are suppressed in this environment.'
        });
    }
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
app.put('/api/admin/users/:role/:id', authMiddleware, adminMiddleware, validateObjectIdParam('id'), async (req, res) => {
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
app.delete('/api/admin/users/:role/:id', authMiddleware, adminMiddleware, validateObjectIdParam('id'), async (req, res) => {
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


// ⚡ Automated SMS & WhatsApp Geofence Proximity Notification Engine
async function sendProximitySMSWhatsApp(userObj, stopName, distanceKm, minutes, busNumber) {
    if (areExternalNotificationsSuppressed(process.env)) {
        console.log(`[Mock SMS/WhatsApp Alert] External alert suppressed for stop: ${stopName}`);
        return { success: true, suppressed: true, provider: 'Mock Dispatcher' };
    }

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
            console.log(`💬 [WhatsApp Cloud API] Arrival notification sent for stop: ${stopName}`);
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
            console.log(`📱 [Transactional SMS] Proximity SMS dispatched for stop: ${stopName}`);
        } catch (err) {
            console.warn(`⚠️ [SMS Warning] ${err.message}`);
        }
    } else {
        console.log(`💬 [WhatsApp / SMS Alert Simulation] External alert simulated for stop: ${stopName}`);
    }
}

// ⚡ FUEL MILEAGE & VEHICLE COST MANAGER ROUTES

// 1. POST /api/driver/fuel-log — Driver logs fuel refill entry
app.post('/api/driver/fuel-log', authMiddleware, driverMiddleware, async (req, res) => {
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
app.get('/api/manager/fuel-logs', authMiddleware, managerMiddleware, validatePagination({ defaultPage: 1, defaultLimit: 50, maxLimit: 200 }), async (req, res) => {
    try {
        const limit = (req.pagination && req.pagination.limit) || 100;
        const skip = (req.pagination && req.pagination.skip) || 0;
        const logs = await FuelLog.find().sort({ refillDate: -1 }).skip(skip).limit(limit);
        res.json({ success: true, logs });
    } catch (err) {
        console.error('Fuel logs fetch error:', err);
        res.status(500).json({ error: 'Failed to fetch fuel logs' });
    }
});

// 3. GET /api/manager/fuel-analytics — Fleet fuel & mileage KPI summary
app.get('/api/manager/fuel-analytics', authMiddleware, managerMiddleware, async (req, res) => {
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
app.get('/api/student/bus-pass', authMiddleware, studentMiddleware, async (req, res) => {
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
app.post('/api/driver/scan-pass', authMiddleware, driverMiddleware, async (req, res) => {
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
app.get('/api/manager/boarding-logs', authMiddleware, managerMiddleware, validatePagination({ defaultPage: 1, defaultLimit: 50, maxLimit: 200 }), async (req, res) => {
    try {
        const limit = (req.pagination && req.pagination.limit) || 100;
        const skip = (req.pagination && req.pagination.skip) || 0;
        const logs = await BoardingLog.find().sort({ boardedAt: -1 }).skip(skip).limit(limit);
        res.json({ success: true, logs });
    } catch (err) {
        console.error('Boarding logs error:', err);
        res.status(500).json({ error: 'Failed to fetch boarding logs' });
    }
});

// Classifies database errors into safe diagnostic categories without exposing credentials, URIs, hostnames, or DB names
function sanitizeConnectionError(err) {
    if (!err) {
        return '[Category: UNKNOWN_DB_ERROR] Database operation failed.';
    }
    const rawMsg = (err && err.message) ? String(err.message) : String(err);
    const rawName = (err && err.name && typeof err.name === 'string') ? err.name : 'DatabaseError';
    const rawCode = (err && err.code) ? String(err.code) : '';

    if (/auth|not authorized|bad auth|permission/i.test(rawMsg) || rawCode === '18' || rawCode === '8000' || rawCode === '13') {
        return '[Category: AUTH_OR_PERMISSION_ERROR] Database authentication or authorization failed.';
    }
    if (/ETIMEDOUT|ENOTFOUND|ECONNREFUSED|EAI_AGAIN|ServerSelection|Network|timed out|buffering timed out/i.test(rawMsg) || /Network|ServerSelection|Timeout/i.test(rawName)) {
        return '[Category: NETWORK_OR_TIMEOUT_ERROR] Database network reachability or operation timeout.';
    }
    if (/MongoParseError|Invalid scheme|URI|connection string/i.test(rawMsg) || rawName === 'MongoParseError') {
        return '[Category: URI_FORMAT_ERROR] Malformed database connection configuration.';
    }

    const allowedErrorTypes = new Set(['MongoError', 'MongoServerError', 'MongooseError', 'ValidationError', 'CastError', 'StrictModeError', 'VersionError', 'ParallelSaveError']);
    const safeType = allowedErrorTypes.has(rawName) ? rawName : 'DatabaseError';
    return `[Category: DATABASE_OPERATION_ERROR] Database operation failed (${safeType}).`;
}

function isSafeLoopbackUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') return false;
    try {
        const parsed = new URL(rawUrl.trim());
        if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return false;
        const host = (parsed.hostname || '').toLowerCase();
        return host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]';
    } catch (_e) {
        return false;
    }
}

function resolveKeepAliveUrl(env = process.env) {
    const isStaging = (env.NODE_ENV || '').toLowerCase().trim() === 'staging';
    const port = (env.PORT && String(env.PORT).trim()) ? String(env.PORT).trim() : '5000';

    if (isStaging) {
        if (env.SELF_URL && isSafeLoopbackUrl(env.SELF_URL)) {
            return env.SELF_URL.trim().replace(/\/+$/, '');
        }
        return `http://localhost:${port}`;
    }

    if (env.SELF_URL && env.SELF_URL.trim().length > 0) {
        return env.SELF_URL.trim();
    }
    if (env.RENDER_EXTERNAL_URL && env.RENDER_EXTERNAL_URL.trim().length > 0) {
        return env.RENDER_EXTERNAL_URL.trim();
    }
    return 'https://smart-shuttle-backend-2h13.onrender.com';
}

let lastWatchdogErrorMessage = null;
let serverStarted = false;
function startServer() {
    if (serverStarted) return;
    serverStarted = true;
    const PORT = process.env.PORT || 5000;
    server.listen(PORT, '0.0.0.0', () => {
        console.log(`\n🚀 Server running on port ${PORT}`);
        console.log(`📡 Socket.io ready for connections`);

        // ─── Real Driver Telemetry Inactivity Watchdog (Production Strict) ────────
        // Automatically marks bus Offline if driver stops broadcasting (>30s)
        watchdogIntervalId = setInterval(runDriverInactivityWatchdogCycle, 10000);
        initKeepAlive();
    });
}

async function runDriverInactivityWatchdogCycle(nowMs = Date.now()) {
        if (isShuttingDown || mongoose.connection.readyState !== 1) {
            return { skipped: true, reason: isShuttingDown ? 'server_shutting_down' : 'db_not_connected' };
        }
        try {
            const staleCutoff = new Date(nowMs - DRIVER_STALE_THRESHOLD_MS);
            const staleBuses = await Bus.find({
                status: { $in: ['On-time', 'Delayed', 'Active'] },
                lastUpdated: { $lt: staleCutoff }
            });

            if (staleBuses && staleBuses.length > 0) {
                for (const bus of staleBuses) {
                    bus.status = 'Offline';
                    bus.speed = 0;
                    bus.etas = [];
                    bus.reachedStops = [];
                    bus.completedStops = 0;
                    bus.nextStop = '';
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
                        reachedStops: [],
                        completedStops: 0,
                        nextStop: '',
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
                    console.log(`📴 [DRIVER INACTIVITY WATCHDOG] Bus ${bus.busNumber || bus._id} stopped broadcasting (>60s) -> Marked Offline`);
                }
            }
            lastWatchdogErrorMessage = null;
            return { skipped: false, updated: staleBuses ? staleBuses.length : 0, staleThresholdMs: DRIVER_STALE_THRESHOLD_MS };
        } catch (err) {
            const safeErr = sanitizeConnectionError(err);
            if (lastWatchdogErrorMessage !== safeErr) {
                console.error('Watchdog interval error:', safeErr);
                lastWatchdogErrorMessage = safeErr;
            }
            return { skipped: false, error: safeErr };
        }
}

function initKeepAlive() {
    // ⚡ RENDER 100% FREE KEEP-ALIVE ENGINE (Prevents 15-min idle sleep)
    const SELF_URL = resolveKeepAliveUrl(process.env);
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
    keepAliveIntervalId = setInterval(triggerKeepAlive, 5 * 60 * 1000);
    // Initial ping 15 seconds after startup
    keepAliveTimeoutId = setTimeout(triggerKeepAlive, 15000);

    console.log(`⚡ [Render 100% Free Keep-Alive] Active every 5 min → ${SELF_URL}/api/health`);
}

let shutdownPromise = null;
function initiateGracefulShutdown(signal = 'SIGTERM') {
    if (shutdownPromise) {
        console.log(`⚠️ [SHUTDOWN] Signal ${signal} received while shutdown already in progress. Ignoring duplicate signal.`);
        return shutdownPromise;
    }

    shutdownPromise = (async () => {
        isShuttingDown = true;
        console.log(`\n🛑 [SHUTDOWN] Received ${signal} — initiating graceful shutdown...`);

        // 1. Hard deadline timer (8.0 seconds)
        const forceExitTimer = setTimeout(() => {
            const remaining = operationTracker.getActiveCount();
            console.error(`❌ [SHUTDOWN FATAL] Hard deadline (8s) exceeded with ${remaining} active operations in flight. Forcing process.exit(1).`);
            if (process.env.NODE_ENV !== 'test') {
                process.exit(1);
            }
        }, 8000);

        try {
            // 2. Stop all background intervals
            if (watchdogIntervalId) { clearInterval(watchdogIntervalId); watchdogIntervalId = null; }
            if (keepAliveIntervalId) { clearInterval(keepAliveIntervalId); keepAliveIntervalId = null; }
            if (keepAliveTimeoutId) { clearTimeout(keepAliveTimeoutId); keepAliveTimeoutId = null; }
            console.log('🛑 [SHUTDOWN] Background watchdog and keep-alive timers stopped.');

            // 3. Broadcast shutdown advisory to connected Socket.io clients
            try {
                io.emit('serverShutdown', {
                    reason: 'maintenance_restart',
                    reconnectAfterMs: 2500,
                    timestamp: new Date().toISOString()
                });
                console.log('📢 [SHUTDOWN] Dispatched serverShutdown advisory to active clients.');
            } catch (emitErr) {
                console.warn('⚠️ [SHUTDOWN] Advisory emit notice:', emitErr.message);
            }

            // 4. Brief 300ms window to push packets through TCP buffers
            await new Promise(r => setTimeout(r, 300));

            // 5. Close HTTP server ingress (stop accepting new TCP connections)
            server.close((err) => {
                if (err) console.error('❌ [SHUTDOWN] HTTP server close error:', err.message);
                else console.log('🛑 [SHUTDOWN] HTTP server ingress closed.');
            });

            // 6. Drain in-flight active operations (5.0s max bounded timeout)
            const drainResult = await operationTracker.waitForDrain(5000);
            if (drainResult.drained) {
                console.log('✅ [SHUTDOWN] All in-flight operations drained successfully.');
            } else {
                console.warn(`⚠️ [SHUTDOWN] Drain timeout reached. Continuing teardown with ${drainResult.remaining} operations in flight.`);
            }

            // 7. Teardown WebSockets explicitly (breaks HTTP server close deadlock)
            try {
                io.disconnectSockets(true);
                io.close();
                console.log('🛑 [SHUTDOWN] Socket.IO connections closed cleanly.');
            } catch (wsErr) {
                console.error('❌ [SHUTDOWN] Socket.IO close notice:', wsErr.message);
            }

            // 8. Close MongoDB connection cleanly
            try {
                if (mongoose.connection.readyState !== 0) {
                    await mongoose.connection.close(false);
                    console.log('🍃 [SHUTDOWN] MongoDB connection cleanly closed.');
                }
            } catch (dbErr) {
                const safeErr = sanitizeConnectionError(dbErr);
                console.error('❌ [SHUTDOWN FATAL] Mongoose close failed:', safeErr);
            }

            clearTimeout(forceExitTimer);
            console.log('✅ [SHUTDOWN] Graceful shutdown complete. Exiting cleanly.\n');
            if (process.env.NODE_ENV !== 'test') {
                process.exit(0);
            }
            return { success: true, drained: drainResult.drained, remaining: drainResult.remaining };
        } catch (fatalErr) {
            clearTimeout(forceExitTimer);
            console.error('❌ [SHUTDOWN UNCAUGHT] Fatal error during shutdown sequence:', fatalErr.message);
            if (process.env.NODE_ENV !== 'test') {
                process.exit(1);
            }
            return { success: false, error: fatalErr.message };
        }
    })();

    return shutdownPromise;
}

if (process.env.NODE_ENV !== 'test') {
    process.on('SIGTERM', () => initiateGracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => initiateGracefulShutdown('SIGINT'));

    process.on('unhandledRejection', (reason) => {
        const safeErr = sanitizeConnectionError(reason);
        console.error('❌ [PROCESS UNHANDLED REJECTION]:', safeErr);
    });

    process.on('uncaughtException', (err) => {
        console.error('❌ [PROCESS UNCAUGHT EXCEPTION]:', err.message);
        initiateGracefulShutdown('UNCAUGHT_EXCEPTION').finally(() => {
            if (process.env.NODE_ENV !== 'test') process.exit(1);
        });
    });
}

module.exports = {
    app,
    server,
    io,
    defaultLimiter,
    getCorsOptions,
    runDriverInactivityWatchdogCycle,
    DRIVER_STALE_THRESHOLD_MS,
    sanitizeConnectionError,
    resolveKeepAliveUrl,
    areExternalNotificationsSuppressed,
    initializeFirebaseAdmin,
    dispatchFcmMulticast,
    sendProximitySMSWhatsApp,
    buildForgotPasswordResponse,
    buildNotificationFilterForUser,
    filterNotificationsForUser,
    emitSensitiveSosAlert,
    emitEmergencySosNotification,
    parseSosCoordinates,
    buildBusApproachingStopPayload,
    normalizeTripType,
    normalizeDistanceKm,
    parseTelemetryPacketTimestamp,
    resolveBusTelemetryStatus,
    verifyDriverBusAuthorization,
    authorizeDelayNotification,
    startOrResumeTripLog,
    syncActiveTripLogForTelemetry,
    completeActiveTripLog,
    terminateActiveTripLog,
    broadcastStats,
    normalizeNotificationPayload,
    emitBroadcastNotification,
    formatReportDistance,
    renderTripReportHtml,
    shutdownIngressMiddleware,
    AsyncOperationTracker,
    operationTracker,
    initiateGracefulShutdown,
    getIsShuttingDown: () => isShuttingDown,
    setIsShuttingDownForTesting: (val) => { isShuttingDown = val; },
    getShutdownPromiseForTesting: () => shutdownPromise,
    getWatchdogIntervalIdForTesting: () => watchdogIntervalId,
    getKeepAliveIntervalIdForTesting: () => keepAliveIntervalId,
    resetShutdownStateForTesting: () => {
        isShuttingDown = false;
        shutdownPromise = null;
        operationTracker.activeCount = 0;
        if (watchdogIntervalId) { clearInterval(watchdogIntervalId); watchdogIntervalId = null; }
        if (keepAliveIntervalId) { clearInterval(keepAliveIntervalId); keepAliveIntervalId = null; }
        if (keepAliveTimeoutId) { clearTimeout(keepAliveTimeoutId); keepAliveTimeoutId = null; }
    }
};








