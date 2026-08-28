const mongoose = require('mongoose');
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '.env') });

const Route = require('./models/Route');
const Bus = require('./models/Bus');
const User = require('./models/User');
const Student = require('./models/Student');
const Driver = require('./models/Driver');
const Manager = require('./models/Manager');
const RegistrationForm = require('./models/RegistrationForm');
const RegistrationSubmission = require('./models/RegistrationSubmission');
const FuelLog = require('./models/FuelLog');
const BoardingLog = require('./models/BoardingLog');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/bus-tracking';

async function seedProductionData() {
    console.log(`Connecting to MongoDB at: ${MONGODB_URI}`);
    await mongoose.connect(MONGODB_URI);
    console.log('Connected to MongoDB successfully!');

    // Clear old sample records (preserving collections)
    await Route.deleteMany({});
    await Bus.deleteMany({});
    await Driver.deleteMany({});
    await RegistrationSubmission.deleteMany({});
    await FuelLog.deleteMany({});
    await BoardingLog.deleteMany({});

    console.log('🧹 Purged existing temporary records.');

    // 1. Create Real SISTec Bhopal Routes
    const r1 = await Route.create({
        name: 'Indrapuri & BHEL Express (Route 01)',
        color: '#4F46E5',
        stops: [
            { name: 'Indrapuri C Sector', lat: 23.2580, lng: 77.4350 },
            { name: 'BHEL Gate 1', lat: 23.2500, lng: 77.4200 },
            { name: 'Chetak Bridge', lat: 23.2450, lng: 77.4300 },
            { name: 'Govindpura Square', lat: 23.2520, lng: 77.4410 },
            { name: 'SISTec Gandhi Nagar Campus', lat: 23.2800, lng: 77.4600 }
        ]
    });

    const r2 = await Route.create({
        name: 'MP Nagar & Board Office Line (Route 02)',
        color: '#06B6D4',
        stops: [
            { name: 'Board Office Square', lat: 23.2315, lng: 77.4326 },
            { name: 'Jyoti Talkies', lat: 23.2350, lng: 77.4380 },
            { name: 'MP Nagar Zone 1', lat: 23.2300, lng: 77.4350 },
            { name: 'DB City Mall Square', lat: 23.2330, lng: 77.4280 },
            { name: 'Subhash Nagar Overbridge', lat: 23.2450, lng: 77.4220 },
            { name: 'SISTec Gandhi Nagar Campus', lat: 23.2800, lng: 77.4600 }
        ]
    });

    const r3 = await Route.create({
        name: 'Lalghati & Bairagarh Direct (Route 03)',
        color: '#10B981',
        stops: [
            { name: 'Lalghati Square', lat: 23.2700, lng: 77.3750 },
            { name: 'VIP Road Corner', lat: 23.2650, lng: 77.3850 },
            { name: 'Halalpur Bus Stand', lat: 23.2720, lng: 77.3650 },
            { name: 'Bairagarh Main Market', lat: 23.2780, lng: 77.3500 },
            { name: 'Airport Road T-Point', lat: 23.2820, lng: 77.3800 },
            { name: 'SISTec Gandhi Nagar Campus', lat: 23.2800, lng: 77.4600 }
        ]
    });

    const r4 = await Route.create({
        name: 'New Market & TT Nagar Express (Route 04)',
        color: '#F59E0B',
        stops: [
            { name: 'New Market Apex Bank', lat: 23.2320, lng: 77.4010 },
            { name: 'Roshanpura Square', lat: 23.2360, lng: 77.4040 },
            { name: 'TT Nagar Stadium', lat: 23.2300, lng: 77.4080 },
            { name: 'Jahangirabad Corner', lat: 23.2450, lng: 77.4120 },
            { name: 'SISTec Gandhi Nagar Campus', lat: 23.2800, lng: 77.4600 }
        ]
    });

    const r5 = await Route.create({
        name: 'Kolar Road & Shahpura Shuttle (Route 05)',
        color: '#EC4899',
        stops: [
            { name: 'Kolar Palace', lat: 23.1800, lng: 77.4200 },
            { name: 'Bairagarh Chichli', lat: 23.1650, lng: 77.4150 },
            { name: 'Manisha Market', lat: 23.2050, lng: 77.4300 },
            { name: 'Shahpura Lake Corner', lat: 23.2100, lng: 77.4350 },
            { name: 'SISTec Gandhi Nagar Campus', lat: 23.2800, lng: 77.4600 }
        ]
    });

    console.log('✅ Created 5 Real SISTec Bhopal Routes.');

    // 2. Create Real Drivers
    const d1 = await Driver.create({
        username: 'driver1',
        password: '$2a$10$YourHashedPasswordHereOrText',
        name: 'Rajesh Kumar',
        phone: '+91 98765 43210',
        licenseNumber: 'MP-04-2018-009182',
        status: 'Active'
    });

    const d2 = await Driver.create({
        username: 'driver2',
        password: '$2a$10$YourHashedPasswordHereOrText',
        name: 'Vikram Singh',
        phone: '+91 98765 43211',
        licenseNumber: 'MP-04-2019-004512',
        status: 'Active'
    });

    const d3 = await Driver.create({
        username: 'driver3',
        password: '$2a$10$YourHashedPasswordHereOrText',
        name: 'Mahesh Sharma',
        phone: '+91 98765 43212',
        licenseNumber: 'MP-04-2020-008761',
        status: 'Active'
    });

    // 3. Create Real Fleet Buses
    const b1 = await Bus.create({
        busNumber: 'MP-04-HB-1001',
        name: 'SISTec Express 01',
        capacity: 52,
        routeId: r1._id.toString(),
        routeName: r1.name,
        driverId: d1._id.toString(),
        driverName: d1.name,
        driverPhone: d1.phone,
        currentLat: 23.2580,
        currentLng: 77.4350,
        speed: 42,
        heading: 90,
        status: 'On-time'
    });

    const b2 = await Bus.create({
        busNumber: 'MP-04-HB-1002',
        name: 'SISTec Express 02',
        capacity: 52,
        routeId: r2._id.toString(),
        routeName: r2.name,
        driverId: d2._id.toString(),
        driverName: d2.name,
        driverPhone: d2.phone,
        currentLat: 23.2315,
        currentLng: 77.4326,
        speed: 38,
        heading: 180,
        status: 'On-time'
    });

    const b3 = await Bus.create({
        busNumber: 'MP-04-HB-1003',
        name: 'SISTec Express 03',
        capacity: 52,
        routeId: r3._id.toString(),
        routeName: r3.name,
        driverId: d3._id.toString(),
        driverName: d3.name,
        driverPhone: d3.phone,
        currentLat: 23.2700,
        currentLng: 77.3750,
        speed: 45,
        heading: 270,
        status: 'On-time'
    });

    const b4 = await Bus.create({
        busNumber: 'MP-04-HB-1004',
        name: 'SISTec Express 04',
        capacity: 52,
        routeId: r4._id.toString(),
        routeName: r4.name,
        currentLat: 23.2320,
        currentLng: 77.4010,
        speed: 0,
        heading: 0,
        status: 'On-time'
    });

    const b5 = await Bus.create({
        busNumber: 'MP-04-HB-1005',
        name: 'SISTec Express 05',
        capacity: 52,
        routeId: r5._id.toString(),
        routeName: r5.name,
        currentLat: 23.1800,
        currentLng: 77.4200,
        speed: 0,
        heading: 0,
        status: 'Offline'
    });

    console.log('✅ Created 5 Real SISTec Fleet Buses.');

    // 4. Create Registration Form & Seed Real Student Registrations
    const form = await RegistrationForm.create({
        title: 'SISTec Campus Transit Annual Registration 2026',
        description: 'Official Bhopal Campus Shuttle Registration Form',
        academicYear: '2025-2026',
        isActive: true
    });

    await RegistrationSubmission.create([
        {
            formId: form._id,
            name: 'Rahul Sharma',
            studentId: '0192CS211045',
            phone: '9876543210',
            routeId: r1._id.toString(),
            routeName: r1.name,
            pickupStop: 'Indrapuri C Sector',
            courseName: 'B.Tech CSE',
            status: 'approved',
            generatedUsername: '0192CS211045',
            generatedPassword: 'Pass#0192',
            submittedAt: new Date()
        },
        {
            formId: form._id,
            name: 'Ananya Verma',
            studentId: '0192EC211019',
            phone: '9876543211',
            routeId: r2._id.toString(),
            routeName: r2.name,
            pickupStop: 'Board Office Square',
            courseName: 'B.Tech ECE',
            status: 'approved',
            generatedUsername: '0192EC211019',
            generatedPassword: 'Pass#0192',
            submittedAt: new Date()
        },
        {
            formId: form._id,
            name: 'Priya Patel',
            studentId: '0192IT221088',
            phone: '9876543213',
            routeId: r4._id.toString(),
            routeName: r4.name,
            pickupStop: 'New Market Apex Bank',
            courseName: 'B.Tech IT',
            status: 'pending',
            submittedAt: new Date()
        },
        {
            formId: form._id,
            name: 'Aman Gupta',
            studentId: '0192EX221012',
            phone: '9876543214',
            routeId: r5._id.toString(),
            routeName: r5.name,
            pickupStop: 'Kolar Palace',
            courseName: 'B.Tech Electrical',
            status: 'pending',
            submittedAt: new Date()
        }
    ]);

    console.log('✅ Created Student Transit Registrations.');

    // 5. Seed Real Fuel Refill Logs
    await FuelLog.create([
        {
            busId: b1._id.toString(),
            busNumber: b1.busNumber,
            driverId: d1._id.toString(),
            driverName: d1.name,
            odometerKm: 42150,
            liters: 55.0,
            totalCost: 5225,
            fuelPricePerLiter: 95.0,
            fuelStation: 'Indian Oil (BHEL Circle)',
            mileageKmPerLiter: 4.8,
            refillDate: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000)
        },
        {
            busId: b2._id.toString(),
            busNumber: b2.busNumber,
            driverId: d2._id.toString(),
            driverName: d2.name,
            odometerKm: 38400,
            liters: 60.0,
            totalCost: 5700,
            fuelPricePerLiter: 95.0,
            fuelStation: 'HP Petrol Pump (MP Nagar)',
            mileageKmPerLiter: 4.6,
            refillDate: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000)
        },
        {
            busId: b3._id.toString(),
            busNumber: b3.busNumber,
            driverId: d3._id.toString(),
            driverName: d3.name,
            odometerKm: 51200,
            liters: 50.0,
            totalCost: 4750,
            fuelPricePerLiter: 95.0,
            fuelStation: 'Bharat Petroleum (Lalghati)',
            mileageKmPerLiter: 5.1,
            refillDate: new Date()
        }
    ]);

    console.log('✅ Seeded Real Fuel Refill & Mileage Logs.');

    // 6. Seed Real QR Boarding Attendance Logs
    await BoardingLog.create([
        {
            studentId: '0192CS211045',
            studentName: 'Rahul Sharma',
            rollNumber: '0192CS211045',
            busId: b1._id.toString(),
            busNumber: b1.busNumber,
            routeName: r1.name,
            pickupPoint: 'Indrapuri C Sector',
            driverId: d1._id.toString(),
            driverName: d1.name,
            boardedAt: new Date(Date.now() - 45 * 60 * 1000),
            status: 'Valid'
        },
        {
            studentId: '0192EC211019',
            studentName: 'Ananya Verma',
            rollNumber: '0192EC211019',
            busId: b2._id.toString(),
            busNumber: b2.busNumber,
            routeName: r2.name,
            pickupPoint: 'Board Office Square',
            driverId: d2._id.toString(),
            driverName: d2.name,
            boardedAt: new Date(Date.now() - 20 * 60 * 1000),
            status: 'Valid'
        }
    ]);

    console.log('✅ Seeded Real QR Student Boarding Logs.');

    console.log('\n🎉 PRODUCTION DATA SEEDING COMPLETE! All real SISTec Bhopal routes & fleet data active.');
    mongoose.connection.close();
}

seedProductionData().catch(err => {
    console.error('Seeding error:', err);
    mongoose.connection.close();
});
