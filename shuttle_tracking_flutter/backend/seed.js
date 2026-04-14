require('dotenv').config();
const mongoose = require('mongoose');
const Route = require('./models/Route');
const Bus = require('./models/Bus');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/';

const MOCK_ROUTES = [
  {
    name: 'Blue Route',
    color: '#007AFF',
    coordinates: [
      { latitude: 23.2599, longitude: 77.4126 },
      { latitude: 23.2650, longitude: 77.4200 },
      { latitude: 23.2700, longitude: 77.4250 },
      { latitude: 23.2750, longitude: 77.4300 },
    ],
    stops: [
      { name: 'SISTec Gate', lat: 23.2599, lng: 77.4126 },
      { name: 'MP Nagar', lat: 23.2324, lng: 77.4315 }
    ]
  },
  {
    name: 'Gandinagar Route',
    color: '#9C27B0',
    coordinates: [
      { latitude: 23.2863, longitude: 77.3421 },
      { latitude: 23.2750, longitude: 77.3550 },
      { latitude: 23.2706, longitude: 77.3718 },
      { latitude: 23.2500, longitude: 77.3950 },
      { latitude: 23.2435, longitude: 77.4044 },
    ],
    stops: [
      { name: 'Gandhi Nagar', lat: 23.2863, lng: 77.3421 },
      { name: 'Lalghati', lat: 23.2706, lng: 77.3718 },
      { name: 'Kamla Park', lat: 23.2500, lng: 77.3950 },
      { name: 'Poly Technic', lat: 23.2435, lng: 77.4044 },
      { name: 'Ratibad Campus', lat: 23.1610, lng: 77.3512 },
    ]
  },
];

mongoose.connect(MONGODB_URI)
  .then(async () => {
    console.log('✅ Connected to MongoDB for Seeding...');

    // Clear existing data
    await Route.deleteMany({});
    await Bus.deleteMany({});
    console.log('🗑️  Cleared old data');

    // Insert Routes
    const seededRoutes = await Route.insertMany(MOCK_ROUTES);
    console.log(`🌱 Seeded ${seededRoutes.length} Routes successfully!`);

    // Insert Mock Buses for the first few routes
    const mockBuses = seededRoutes.map(route => ({
      routeId: route._id,
      routeName: route.name,
      routeColor: route.color,
      currentLat: route.coordinates[0].latitude,
      currentLng: route.coordinates[0].longitude,
      heading: 45,
      speed: 30,
      status: 'On-time',
      occupancy: 'Low'
    }));

    await Bus.insertMany(mockBuses);
    console.log(`🚌 Seeded ${mockBuses.length} Buses successfully!`);

    mongoose.connection.close();
  })
  .catch(err => {
    console.error('❌ Error seeding database:', err);
    mongoose.connection.close();
  });
