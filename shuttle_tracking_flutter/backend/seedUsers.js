
require('dotenv').config();
const mongoose = require('mongoose');
const argon2 = require('argon2');

// Import Models
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const User = require('./models/User');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/';

async function seedUsers() {
    try {
        // 🛡️ Safety Check: Prevent running in Production
        if (process.env.NODE_ENV === 'production') {
            console.error('❌ STOP! You are attempting to seed data in production. This will wipe the database.');
            process.exit(1);
        }

        await mongoose.connect(MONGODB_URI);
        console.log('✅ Connected to MongoDB');

        // Default Password Hash
        const defaultPassword = process.env.DEFAULT_SEED_PASSWORD || '123456';
        const passwordHash = await argon2.hash(defaultPassword);

        // 1. Create Admin
        const adminRequest = (async () => {
            const admin = new Admin({
                username: 'admin',
                password: passwordHash,
                email: 'admin@sistec.ac.in'
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
                name: 'System Manager',
                contactNumber: '9876543210',
                employeeId: 'MGR-001',
                department: 'Transport'
            });
            await Manager.deleteMany({});
            await manager.save();
            console.log(`👤 Manager created: manager / ${defaultPassword}`);
        })();


        // 4. Create Users (Standard Users)
        const usersRequest = (async () => {
            await User.deleteMany({});

            const allUsersData = [
                { username: 'student', email: 'student@sistec.ac.in', userId: 'STU-2024-001', pickupPoint: 'Main Gate' },
                { username: 'Denim', email: 'denim@sistec.ac.in', userId: 'STU-2024-002', pickupPoint: 'Bhopal Station' },
                { username: 'Dhruv', email: 'druv@sistec.ac.in', userId: 'STU-2024-003', pickupPoint: 'Indrapuri' },
                { username: 'Pankaj', email: 'pankaj@sistec.ac.in', userId: 'STU-2024-004', pickupPoint: 'Ayodhya Bypass' },
                { username: 'Prashant', email: 'prashant@sistec.ac.in', userId: 'STU-2024-005', pickupPoint: 'New Market' },
                { username: 'Palak', email: 'palak@sistec.ac.in', userId: 'STU-2024-006', pickupPoint: 'Minal Residency' },
                { username: 'Satyam', email: 'satyam@sistec.ac.in', userId: 'STU-2024-007', pickupPoint: 'Lalghati' }
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

            console.log(`👤 Created ${allUsersData.length} Users with proper UIDs and Pickup Points.`);
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
