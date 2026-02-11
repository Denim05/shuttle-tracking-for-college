require('dotenv').config();
const mongoose = require('mongoose');
const argon2 = require('argon2');

// Import Models
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const Driver = require('./models/Driver');
const User = require('./models/User');
const Route = require('./models/Route');
const Bus = require('./models/Bus');
const Student = require('./models/Student');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/sistec_chalo';

const MOCK_ROUTES = [
  {
    name: 'Blue Route',
    color: '#007AFF',
    coordinates: [
      { latitude: 37.7749, longitude: -122.4194 },
      { latitude: 37.7755, longitude: -122.4180 },
      { latitude: 37.7760, longitude: -122.4165 },
      { latitude: 37.7765, longitude: -122.4150 },
    ],
    stops: [
      { name: 'Main Gate', lat: 37.7749, lng: -122.4194 },
      { name: 'Library', lat: 37.7765, lng: -122.4150 }
    ]
  },
  {
    name: 'Gold Route',
    color: '#FFD700',
    coordinates: [
      { latitude: 37.7749, longitude: -122.4194 },
      { latitude: 37.7740, longitude: -122.4200 },
      { latitude: 37.7730, longitude: -122.4210 },
      { latitude: 37.7725, longitude: -122.4225 },
    ],
    stops: [
      { name: 'Main Gate', lat: 37.7749, lng: -122.4194 },
      { name: 'Dorms', lat: 37.7725, lng: -122.4225 }
    ]
  },
  {
    name: 'Gandinagar Route',
    color: '#9C27B0',
    coordinates: [
      { latitude: 23.2863, longitude: 77.3421 }, // Gandhi Nagar
      { latitude: 23.2750, longitude: 77.3550 }, // Halalpur
      { latitude: 23.2706, longitude: 77.3718 }, // Lalghati
      { latitude: 23.2650, longitude: 77.3750 }, // Koh-E-Fiza
      { latitude: 23.2500, longitude: 77.3950 }, // Kamla Park
      { latitude: 23.2435, longitude: 77.4044 }, // Poly Technic
      { latitude: 23.2355, longitude: 77.3970 }, // Jawahar Chowk
      { latitude: 23.2250, longitude: 77.3900 },
      { latitude: 23.2100, longitude: 77.3800 },
      { latitude: 23.1610, longitude: 77.3512 },
    ],
    stops: [
      { name: 'Gandhi Nagar', lat: 23.2863, lng: 77.3421 },
      { name: 'Halalpur (Bus Stand)', lat: 23.2750, lng: 77.3550 },
      { name: 'Lalghati', lat: 23.2706, lng: 77.3718 },
      { name: 'Koh-E-Fiza', lat: 23.2650, lng: 77.3750 },
      { name: 'Kamla Park', lat: 23.2500, lng: 77.3950 },
      { name: 'Ratibad Campus', lat: 23.1610, lng: 77.3512 },
    ]
  },
];

const MOCK_BUSES = [
  {
    routeName: 'Blue Route', // Will map to routeId dynamically
    routeColor: '#007AFF',
    currentLat: 37.7752,
    currentLng: -122.4185,
    status: 'On-time',
    heading: 65,
    driverUsername: 'driver' // Will map to driverId dynamically
  },
  {
    routeName: 'Gold Route',
    routeColor: '#FFD700',
    currentLat: 37.7735,
    currentLng: -122.4205,
    status: 'Delayed',
    heading: 200,
  },
  {
    routeName: 'Gandinagar Route',
    routeColor: '#9C27B0',
    currentLat: 23.2750,
    currentLng: 77.3550,
    status: 'On-time',
    heading: 160,
  }
];

const MOCK_STUDENTS = [
    { name: 'Student 1', studentId: 'SIS-001', pickupPoint: 'Gandhi Nagar', contactNumber: '9000000001' },
    { name: 'Student 2', studentId: 'SIS-002', pickupPoint: 'Lalghati', contactNumber: '9000000002' },
];

async function seedAll() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('Connected to MongoDB');

    // 1. CLEAR DATABASE
    console.log('🧹 Clearing existing data...');
    await Promise.all([
        Admin.deleteMany({}),
        Manager.deleteMany({}),
        Driver.deleteMany({}),
        User.deleteMany({}),
        Route.deleteMany({}),
        Bus.deleteMany({}),
        Student.deleteMany({})
    ]);

    // 2. CREATE USERS
    console.log('👤 Creating Users...');
    const passwordHash = await argon2.hash('123456');

    await Admin.create({ username: 'admin', password: passwordHash, email: 'admin@sistec.ac.in' });
    
    await Manager.create({ 
        username: 'manager', 
        password: passwordHash, 
        name: 'System Manager', 
        employeeId: 'MGR-001', 
        department: 'Transport' 
    });

    const driverDoc = await Driver.create({ 
        username: 'driver', 
        password: passwordHash, 
        name: 'Ramu Kaka', 
        driverId: 'DL-MP04-2024', 
        contactNumber: '9988776655', 
        status: 'Active' 
    });

    const usersToCreate = [
        { username: 'student', email: 'student@sistec.ac.in' },
        { username: 'Denim', email: 'denim@sistec.ac.in' },
        { username: 'Dhruv', email: 'druv@sistec.ac.in' },
        { username: 'Pankaj', email: 'pankaj@sistec.ac.in' },
        { username: 'Prashant', email: 'prashant@sistec.ac.in' },
        { username: 'Palak', email: 'palak@sistec.ac.in' },
        { username: 'Satyam', email: 'satyam@sistec.ac.in' }
    ];

    for (const u of usersToCreate) {
        await User.create({
            username: u.username,
            password: passwordHash,
            email: u.email,
            status: 'Active'
        });
    }

    // 3. CREATE ROUTES
    console.log('🛣️ Creating Routes...');
    const routeDocs = await Route.insertMany(MOCK_ROUTES);
    
    // Helper to find route ID by name
    const getRouteId = (name) => routeDocs.find(r => r.name === name)?._id;

    // 4. CREATE BUSES
    console.log('🚌 Creating Buses...');
    const busesWithIds = MOCK_BUSES.map(bus => ({
        ...bus,
        routeId: getRouteId(bus.routeName),
        driverId: bus.driverUsername === 'driver' ? driverDoc.username : null // Linking mock driver
    }));
    await Bus.insertMany(busesWithIds);

    // 5. CREATE STUDENTS
    console.log('🎓 Creating Students...');
    // Assign random route to students
    const studentsWithRoutes = MOCK_STUDENTS.map(s => ({
        ...s,
        routeId: routeDocs[Math.floor(Math.random() * routeDocs.length)]._id
    }));
    await Student.insertMany(studentsWithRoutes);

    console.log('✨ Seed All Complete!');
    console.log('   - Admin: admin / 123456');
    console.log('   - Manager: manager / 123456');
    console.log('   - Driver: driver / 123456');
    console.log('   - Users: student / 123456 (and others)');
    
    process.exit(0);
  } catch (err) {
    console.error('❌ Seeding Failed:', err);
    process.exit(1);
  }
}

seedAll();
