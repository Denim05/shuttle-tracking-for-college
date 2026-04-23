require('dotenv').config();
const mongoose = require('mongoose');
const Driver = require('./models/Driver');
const Bus = require('./models/Bus');
const Route = require('./models/Route');
const argon2 = require('argon2');
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus';

async function seedData() {
    try {
        await mongoose.connect(MONGODB_URI);
        console.log('✅ Connected to MongoDB');

        // 1. Clear existing data
        await Route.deleteMany({});
        await Bus.deleteMany({});
        await Driver.deleteMany({});
        console.log('🗑️  Cleared old data');

        // 2. Create Routes
        const route1 = new Route({
            name: "Main Campus Route",
            color: "#6C63FF",
            stops: [
                { name: "Gate 1", lat: 23.2333, lng: 77.4333 },
                { name: "Admin Block", lat: 23.2350, lng: 77.4380 },
                { name: "Hostel Block", lat: 23.2310, lng: 77.4280 }
            ]
        });
        await route1.save();
        console.log('🛣️  Route created');

        // 3. Create Driver
        const hashedPassword = await argon2.hash('driver123');
        const driver = new Driver({
            username: 'driver1',
            password: hashedPassword,
            name: 'John Doe',
            contactNumber: '9876543210',
            status: 'Active'
        });
        await driver.save();
        console.log('👨‍✈️ Driver created: driver1 / driver123');

        // 4. Create Bus and link to driver
        const bus = new Bus({
            busNumber: "MP-04-AB-1234",
            name: "Campus Shuttle 01",
            routeId: route1._id,
            routeName: route1.name,
            routeColor: route1.color,
            currentLat: 23.2333,
            currentLng: 77.4333,
            status: "On-time",
            occupancy: "Low",
            driverId: driver._id, // LINKED
            lastUpdated: new Date()
        });
        await bus.save();
        
        // Update driver with assigned bus
        driver.assignedBus = bus._id.toString();
        await driver.save();
        
        console.log('🚌 Bus created and linked to driver');
        console.log('✅ Seeding complete!');
        process.exit(0);
    } catch (err) {
        console.error('❌ Error during seeding:', err);
        process.exit(1);
    }
}

seedData();
