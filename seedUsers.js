
const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const mongoose = require('mongoose');
const argon2 = require('argon2');

// Import Models
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const User = require('./models/User');

const MONGODB_URI = process.env.MONGODB_URI;
if (!MONGODB_URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

async function seedUsers() {
    try {
        // 🛡️ Safety Check: Prevent running in Production
        if (process.env.NODE_ENV === 'production') {
            console.error('❌ STOP! You are attempting to seed data in production. This will wipe the database.');
            process.exit(1);
        }

        await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
        console.log('✅ Connected to MongoDB');

        // Default Password Hash
        const defaultPassword = process.env.DEFAULT_SEED_PASSWORD || '123456';
        const passwordHash = await argon2.hash(defaultPassword);

        // 1. Create Admin
        const adminRequest = (async () => {
            const admin = new Admin({
                username: 'admin',
                password: passwordHash,
                email: 'admin@SISTecChalo.edu'
            });
            await Admin.deleteMany({});
            await admin.save();
            console.log(`👤 Admin created: admin / ${defaultPassword}`);
        })();

        // 2. Create Manager
        const managerRequest = (async () => {
            const manager = new Manager({
                username: 'manager',
                password: passwordHash,
                name: 'Core Architect',
                contactNumber: '9876543210',
                employeeId: 'MGR-777',
                department: 'Pulse Operations'
            });
            await Manager.deleteMany({});
            await manager.save();
            console.log(`👤 Manager created: manager / ${defaultPassword}`);
        })();


        // 4. Create Users (Standard Users)
        const usersRequest = (async () => {
            await User.deleteMany({});

            const allUsersData = [
                { username: 'student', email: 'student@SISTecChalo.edu', userId: 'STU-PULSE-001', pickupPoint: 'SISTecChalo Hub' },
                { username: 'Denim', email: 'denim@SISTecChalo.edu', userId: 'STU-PULSE-002', pickupPoint: 'Bhopal Station' },
                { username: 'Dhruv', email: 'druv@SISTecChalo.edu', userId: 'STU-PULSE-003', pickupPoint: 'Indrapuri' },
                { username: 'Pankaj', email: 'pankaj@SISTecChalo.edu', userId: 'STU-PULSE-004', pickupPoint: 'Ayodhya Bypass' },
                { username: 'Prashant', email: 'prashant@SISTecChalo.edu', userId: 'STU-PULSE-005', pickupPoint: 'New Market' },
                { username: 'Palak', email: 'palak@SISTecChalo.edu', userId: 'STU-PULSE-006', pickupPoint: 'Minal Residency' },
                { username: 'Satyam', email: 'satyam@SISTecChalo.edu', userId: 'STU-PULSE-007', pickupPoint: 'Lalghati' },
                { username: 'Akanksha', email: 'akanksha@SISTecChalo.edu', userId: 'STU-PULSE-008', pickupPoint: 'Indrapuri' }
            ];

            // Create all user promises
            const userPromises = allUsersData.map(u =>
                new User({
                    username: u.username,
                    password: passwordHash,
                    email: u.email,
                    userId: u.userId,
                    pickupPoint: u.pickupPoint,
                    status: 'Active',
                    accessRights: ['view_routes', 'track_bus']
                }).save()
            );

            await Promise.all(userPromises);

            console.log(`👤 Created ${allUsersData.length} Users with proper Pulse UIDs.`);
        })();

        // Await all parallel operations
        await Promise.all([adminRequest, managerRequest, usersRequest]);

        console.log('✨ Seeding Complete!');
        process.exit(0);

    } catch (err) {
        console.error('❌ Seeding Failed:', err);
        process.exit(1);
    }
}

seedUsers();

