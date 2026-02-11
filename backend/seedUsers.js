
require('dotenv').config();
const mongoose = require('mongoose');
const argon2 = require('argon2');

// Import Models
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const Driver = require('./models/Driver');
const User = require('./models/User');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/sistec_chalo';

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

    // 3. Create Driver
    const driverRequest = (async () => {
        const driver = new Driver({
            username: 'driver',
            password: passwordHash,
            name: 'Ramu Kaka',
            driverId: 'DL-MP04-2024',
            contactNumber: '9988776655',
            status: 'Active'
        });
        await Driver.deleteMany({});
        await driver.save();
        console.log(`🚌 Driver created: driver / ${defaultPassword}`);
    })();

    // 4. Create Users (Students)
    const usersRequest = (async () => {
        await User.deleteMany({});
        
        const singleUsers = [
            { username: 'student', email: 'student@sistec.ac.in' },
            { username: 'Denim', email: 'denim@sistec.ac.in' }
        ];

        const bulkUsers = [
             { username: 'Dhruv', email: 'druv@sistec.ac.in' },
            { username: 'Pankaj', email: 'pankaj@sistec.ac.in' },
            { username: 'Prashant', email: 'prashant@sistec.ac.in' },
            { username: 'Palak', email: 'palak@sistec.ac.in' },
            { username: 'Satyam', email: 'satyam@sistec.ac.in' }
        ];

        const allUsersData = [...singleUsers, ...bulkUsers];

        // Create all user promises
        const userPromises = allUsersData.map(u => 
            new User({
                username: u.username,
                password: passwordHash,
                email: u.email,
                status: 'Active'
            }).save()
        );

        await Promise.all(userPromises);
        
        console.log(`👤 Created ${allUsersData.length} Students (User) with password: ${defaultPassword}`);
    })();

    // Await all parallel operations
    await Promise.all([adminRequest, managerRequest, driverRequest, usersRequest]);

    console.log('✨ Seeding Complete!');
    process.exit(0);

  } catch (err) {
    console.error('❌ Seeding Failed:', err);
    process.exit(1);
  }
}

seedUsers();
