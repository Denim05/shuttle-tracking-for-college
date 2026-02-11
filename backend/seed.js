require('dotenv').config();
const mongoose = require('mongoose');
const Route = require('./models/Route');

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
    ],
    stops: [
      { name: 'Gandhi Nagar', lat: 23.2863, lng: 77.3421 },
      { name: 'Asharam Bapu Square', lat: 23.2840, lng: 77.3450 },
      { name: 'Bhaskar Colony', lat: 23.2820, lng: 77.3480 },
      { name: 'Data Colony', lat: 23.2800, lng: 77.3500 },
      { name: 'Panchwati', lat: 23.2780, lng: 77.3520 },
      { name: 'Halalpur (Bus Stand)', lat: 23.2750, lng: 77.3550 },
      { name: 'Bairahgarh Police Station', lat: 23.2721, lng: 77.3585 },
      { name: 'Chirayu Hospital', lat: 23.2700, lng: 77.3650 },
      { name: 'Lalghati', lat: 23.2706, lng: 77.3718 },
      { name: 'Koh-E-Fiza', lat: 23.2650, lng: 77.3750 },
      { name: 'Satae Bank Square', lat: 23.2620, lng: 77.3780 },
      { name: 'Royal Market', lat: 23.2598, lng: 77.3805 },
      { name: 'Imami gate', lat: 23.2570, lng: 77.3820 },
      { name: 'Peer Gate', lat: 23.2550, lng: 77.3840 },
      { name: 'Moti Masjid', lat: 23.2536, lng: 77.3887 },
      { name: 'Kamla Park', lat: 23.2500, lng: 77.3950 },
      { name: 'Poly Technic', lat: 23.2435, lng: 77.4044 },
      { name: 'Roshanpura', lat: 23.2380, lng: 77.4000 },
      { name: 'Jawahar Chowk', lat: 23.2355, lng: 77.3970 },
      { name: 'Bharat Mata Square', lat: 23.2250, lng: 77.3900 },
      { name: '23 Bataliyan', lat: 23.2100, lng: 77.3800 },
      { name: 'Ratibad Campus', lat: 23.1610, lng: 77.3512 },
    ]
  },
];

mongoose.connect(MONGODB_URI)
  .then(async () => {
    console.log('✅ Connected to MongoDB for Seeding...');
    
    // Clear existing data
    await Route.deleteMany({});
    console.log('🗑️  Cleared old routes');

    // Insert new data
    await Route.insertMany(MOCK_ROUTES);
    console.log('🌱 Seeded Routes successfully!');

    mongoose.connection.close();
  })
  .catch(err => {
    console.error('❌ Error seeding database:', err);
    mongoose.connection.close();
  });
