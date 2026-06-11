require('dotenv').config();
const mongoose = require('mongoose');
const argon2 = require('argon2');

// Import Models
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');
const User = require('./models/User');
const Route = require('./models/Route');
const Bus = require('./models/Bus');
const Student = require('./models/Student');
const Driver = require('./models/Driver');

const MONGODB_URI = process.argv[2] || process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/sistecChalo';

const MOCK_ROUTES = [
  {
    name: 'Route 1 - MP Nagar',
    color: '#6C63FF',
    coordinates: [
      { latitude: 23.3210, longitude: 77.3520 }, // SISTec Gandhi Nagar
      { latitude: 23.3100, longitude: 77.3600 },
      { latitude: 23.2950, longitude: 77.3750 },
      { latitude: 23.2800, longitude: 77.3900 }, // Lalghati
      { latitude: 23.2600, longitude: 77.4000 },
      { latitude: 23.2450, longitude: 77.4150 }, // Poly Technic
      { latitude: 23.2333, longitude: 77.4333 }, // MP Nagar
    ],
    stops: [
      { name: 'SISTec Main Gate', lat: 23.3210, lng: 77.3520 },
      { name: 'Lalghati Junction', lat: 23.2800, lng: 77.3900 },
      { name: 'MP Nagar Zone 1', lat: 23.2333, lng: 77.4333 }
    ]
  },
  {
    name: 'Route 2 - Bairagarh',
    color: '#00F0FF',
    coordinates: [
      { latitude: 23.3210, longitude: 77.3520 },
      { latitude: 23.2850, longitude: 77.3300 }, // Bairagarh
    ],
    stops: [
      { name: 'SISTec Main Gate', lat: 23.3210, lng: 77.3520 },
      { name: 'Bairagarh Stand', lat: 23.2850, lng: 77.3300 }
    ]
  },
  {
    name: 'Gandinagar Route',
    color: '#FF2E63',
    coordinates: [
      { latitude: 23.2863, longitude: 77.3421 }, // Gandhi Nagar
      { latitude: 23.2750, longitude: 77.3550 }, // Halalpur
      { latitude: 23.2706, longitude: 77.3718 }, // Lalghati
      { latitude: 23.2650, longitude: 77.3750 }, // Koh-E-Fiza
      { latitude: 23.2500, longitude: 77.3950 }, // Kamla Park
      { latitude: 23.2435, longitude: 77.4044 }, // Poly Technic
      { latitude: 23.1610, longitude: 77.3512 }, // SISTecChalo Hub
    ],
    stops: [
      { name: 'Gandhi Nagar', lat: 23.2863, lng: 77.3421 },
      { name: 'Halalpur (Bus Stand)', lat: 23.2750, lng: 77.3550 },
      { name: 'Lalghati', lat: 23.2706, lng: 77.3718 },
      { name: 'Kamla Park', lat: 23.2500, lng: 77.3950 },
      { name: 'SISTecChalo Hub', lat: 23.1610, lng: 77.3512 },
    ]
  },
  {
    name: 'BHEL Route',
    color: '#FFD700',
    coordinates: [
      { latitude: 23.2500, longitude: 77.4500 }, // BHEL
      { latitude: 23.2600, longitude: 77.4600 }, // Piplani
    ],
    stops: [
      { name: 'BHEL Jubilee Gate', lat: 23.2500, lng: 77.4500 },
      { name: 'Piplani', lat: 23.2600, lng: 77.4600 }
    ]
  },
];

const MOCK_BUSES = [
  {
    busNumber: 'MP-04-P-0001',
    routeName: 'Route 1 - MP Nagar',
    routeColor: '#6C63FF',
    currentLat: 23.3210,
    currentLng: 77.3520,
    status: 'On-time',
    heading: 65,
    occupancy: 'Low'
  },
  {
    busNumber: 'MP-04-P-0002',
    routeName: 'Route 2 - Bairagarh',
    routeColor: '#00F0FF',
    currentLat: 23.2850,
    currentLng: 77.3300,
    status: 'Delayed',
    heading: 200,
    occupancy: 'Medium'
  },
  {
    busNumber: 'MP-04-P-0003',
    routeName: 'Gandinagar Route',
    routeColor: '#FF2E63',
    currentLat: 23.2750,
    currentLng: 77.3550,
    status: 'On-time',
    heading: 160,
    occupancy: 'High'
  },
  {
    busNumber: 'MP-04-P-0004',
    routeName: 'BHEL Route',
    routeColor: '#FFD700',
    currentLat: 23.2500,
    currentLng: 77.4500,
    status: 'On-time',
    heading: 45,
    occupancy: 'Low'
  },
  {
    busNumber: 'MP-04-P-0005',
    routeName: 'Route 1 - MP Nagar',
    routeColor: '#6C63FF',
    currentLat: 23.2333,
    currentLng: 77.4333,
    status: 'Offline',
    heading: 0,
    occupancy: 'Low'
  }
];

const MOCK_STUDENTS = [
  { name: 'student', studentId: 'STU-PULSE-001', pickupPoint: 'SISTecChalo Hub', contactNumber: '9000000001' },
  { name: 'Denim', studentId: 'STU-PULSE-002', pickupPoint: 'Bhopal Station', contactNumber: '9000000002' },
  { name: 'Dhruv', studentId: 'STU-PULSE-003', pickupPoint: 'Indrapuri', contactNumber: '9000000003' },
  { name: 'Pankaj', studentId: 'STU-PULSE-004', pickupPoint: 'Ayodhya Bypass', contactNumber: '9000000004' },
  { name: 'Prashant', studentId: 'STU-PULSE-005', pickupPoint: 'New Market', contactNumber: '9000000005' },
  { name: 'Palak', studentId: 'STU-PULSE-006', pickupPoint: 'Minal Residency', contactNumber: '9000000006' },
  { name: 'Satyam', studentId: 'STU-PULSE-007', pickupPoint: 'Lalghati', contactNumber: '9000000007' },
  { name: 'Akanksha', studentId: 'STU-PULSE-008', pickupPoint: 'Indrapuri', contactNumber: '9000000008' },
];

async function seedAll() {
  try {
    await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
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

    // 2. CREATE ADMINS/MANAGERS/DRIVERS
    console.log('👤 Creating Administrative Users...');
    const passwordHash = await argon2.hash('123456');

    await Admin.create({ username: 'admin', password: passwordHash, email: 'admin@SISTecChalo.edu' });

    await Manager.create({
      username: 'manager',
      password: passwordHash,
      name: 'Pulse Manager',
      employeeId: 'MGR-001',
      department: 'Fleet Ops'
    });

    await Driver.create([
      { username: 'driver', password: passwordHash, name: 'Unit Captain 01', status: 'Active' },
      { username: 'driver2', password: passwordHash, name: 'Unit Captain 02', status: 'Active' },
      { username: 'driver3', password: passwordHash, name: 'Unit Captain 03', status: 'Active' },
      { username: 'driver4', password: passwordHash, name: 'Unit Captain 04', status: 'Active' },
      { username: 'driver5', password: passwordHash, name: 'Unit Captain 05', status: 'Active' },
    ]);

    // 3. CREATE ROUTES
    console.log('🛣️ Creating Routes...');
    const routeDocs = await Route.insertMany(MOCK_ROUTES);
    
    // 4. CREATE USERS
    console.log('👤 Creating Users...');
    // Assign specific route to 'student' for testing notifications
    const firstRoute = routeDocs[0];
    await User.create({
      username: 'student',
      password: passwordHash,
      email: 'student@SISTecChalo.edu',
      status: 'Active',
      role: 'user',
      routeId: firstRoute._id.toString(),
      pickupPoint: firstRoute.stops[0].name // e.g., 'SISTecChalo Hub'
    });

    const otherUsers = [
      { username: 'Denim', email: 'denim@SISTecChalo.edu' },
      { username: 'Dhruv', email: 'druv@SISTecChalo.edu' },
      { username: 'Pankaj', email: 'pankaj@SISTecChalo.edu' },
      { username: 'Prashant', email: 'prashant@SISTecChalo.edu' },
      { username: 'Palak', email: 'palak@SISTecChalo.edu' },
      { username: 'Satyam', email: 'satyam@SISTecChalo.edu' },
      { username: 'Akanksha', email: 'akanksha@SISTecChalo.edu' }
    ];

    for (const u of otherUsers) {
      await User.create({
        username: u.username,
        password: passwordHash,
        email: u.email,
        status: 'Active',
        role: 'user'
      });
    }


    // Helper to find route ID by name
    const getRouteId = (name) => routeDocs.find(r => r.name === name)?._id;

    // 4. CREATE BUSES
    console.log('🚌 Creating Buses...');
    const drivers = await Driver.find({});
    const busesWithIds = MOCK_BUSES.map((bus, index) => ({
      ...bus,
      routeId: getRouteId(bus.routeName),
      driverId: drivers[index]?._id // Assign unique driver to each bus
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


