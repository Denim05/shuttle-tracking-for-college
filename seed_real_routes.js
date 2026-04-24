/**
 * seed_real_routes.js
 * Seeds the ChaloCampus DB with ALL real routes from:
 * "TIME - New Update Bus Route 19-08-2025"
 * Sagar Group of Institutions, Ratibad, Bhopal
 *
 * Run: node seed_real_routes.js
 */

const mongoose = require('mongoose');
const Route    = require('./models/Route');
const Bus      = require('./models/Bus');

const rawUri = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus';
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/chalocampus$1').replace(/^(mongodb(?:\+srv)?:\/\/[^/]+)$/, '$1/chalocampus');

// ─── Route definitions from PDF ──────────────────────────────────────────────
const ROUTES = [
  {
    busNo: '01',
    vehicle: 'MP04 PA 3497',
    name: 'Gandinagar Route',
    color: '#6C63FF',
    driver: 'Ghanshyam Nagar',
    driverMob: '9770534112',
    stops: [
      { name: 'Gandinagar',            time: '6:45' },
      { name: 'Pul Bogda',             time: '6:50' },
      { name: 'Roshanpura',            time: '6:55' },
      { name: 'Manavseva Square',      time: '7:00' },
      { name: 'Bharat Mata Square',    time: '7:05' },
      { name: 'Ashoka Garden Chouraha',time: '7:10' },
      { name: 'Nehru Nagar',           time: '7:30' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '02',
    vehicle: 'MP04 PA 3498',
    name: 'Ashoka Garden Route (Bus 02)',
    color: '#FF6B6B',
    driver: 'Rahul Verma',
    driverMob: '9981838418',
    stops: [
      { name: 'Bhopal Railway Station Platform-1', time: '8:05' },
      { name: 'Pushpa Nagar',          time: '8:07' },
      { name: 'Sangam Tent House',     time: '8:08' },
      { name: '80-feet Road',          time: '8:10' },
      { name: 'Ashoka Garden Pani ki Tanki', time: '8:15' },
      { name: 'Prabhat Square',        time: '8:17' },
      { name: 'Bogda Pull',            time: '8:20' },
      { name: 'Jinsi Square',          time: '8:25' },
      { name: 'Roshanpura',            time: '8:30' },
      { name: 'Dipo',                  time: '8:35' },
      { name: 'Ratibad Campus',        time: '9:15' },
    ],
  },
  {
    busNo: '03',
    vehicle: 'MP04 PA 3501',
    name: 'Karond Route',
    color: '#00F0FF',
    driver: 'Praveen Pal',
    driverMob: '7692879431',
    stops: [
      { name: 'DwarkaDham SPS Campus', time: '6:30' },
      { name: 'Lambakheda',            time: '6:45' },
      { name: 'Karond',                time: '6:50' },
      { name: 'Bhanpur',               time: '6:55' },
      { name: 'Chhola Mandir',         time: '7:00' },
      { name: 'Best Prize',            time: '7:06' },
      { name: 'Kalyan Nagar',          time: '7:07' },
      { name: 'Shiv Mandir',           time: '7:08' },
      { name: 'Karond Sabzi Mandi',    time: '7:10' },
      { name: 'DIG Bungla',            time: '7:12' },
      { name: 'Nadra Bus Stand',       time: '7:17' },
      { name: 'Bharat Talkies',        time: '7:22' },
      { name: 'Jahangirabad',          time: '7:27' },
      { name: 'PHQ',                   time: '7:29' },
      { name: 'Roshanpura',            time: '7:43' },
      { name: 'Bharat Mata Square',    time: '7:47' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '04',
    vehicle: 'MP04 PA 3504',
    name: 'Kolar Road Route',
    color: '#FFB347',
    driver: 'Mukesh Shisodiya',
    driverMob: '8251047765',
    stops: [
      { name: 'DPS School',            time: '6:35' },
      { name: 'Bairagarh',             time: '6:37' },
      { name: '610 Kolar',             time: '6:43' },
      { name: 'Babadiya Kala',         time: '6:53' },
      { name: 'Aura Mall',             time: '7:00' },
      { name: 'Shivay Complex',        time: '7:03' },
      { name: '10 No Shop',            time: '7:10' },
      { name: 'Arera Petrol Pump',     time: '7:15' },
      { name: 'Patrakar Colony',       time: '7:17' },
      { name: 'Pancheel Nagar',        time: '7:25' },
      { name: 'Vaishali Nagar',        time: '7:30' },
      { name: 'Nehru Nagar',           time: '7:35' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '05',
    vehicle: 'MP04 PA 3510',
    name: 'Ashoka Garden Route (Bus 05)',
    color: '#FF2E63',
    driver: 'Babloo Meena',
    driverMob: '8959307531',
    stops: [
      { name: 'Bhopal Railway Station Platform-1', time: '8:05' },
      { name: 'Pushpa Nagar',          time: '8:07' },
      { name: 'Sangam Tent House',     time: '8:08' },
      { name: '80-feet Road',          time: '8:10' },
      { name: 'Ashoka Garden Pani ki Tanki', time: '8:15' },
      { name: 'Prabhat Square',        time: '8:17' },
      { name: 'Ratibad Campus',        time: '9:15' },
    ],
  },
  {
    busNo: '06',
    vehicle: 'MP04 PA 3511',
    name: 'Ashta Route',
    color: '#A8FF78',
    driver: 'Raj Kumar',
    driverMob: '8989878725',
    stops: [
      { name: 'Alipur',                time: '6:05' },
      { name: 'Old Bus Stand',         time: '6:06' },
      { name: 'Bhopal Naka',           time: '6:07' },
      { name: 'Bajaranga Colony',      time: '6:08' },
      { name: 'Colony Square',         time: '6:09' },
      { name: 'Banjari Mata',          time: '6:10' },
      { name: 'Kachanariya Jod',       time: '6:35' },
      { name: 'Kotri',                 time: '6:38' },
      { name: 'Jat Khedi Jod',         time: '6:40' },
      { name: 'Amlaha',                time: '6:50' },
      { name: 'Bhadakhedi Jod',        time: '7:00' },
      { name: 'Goodwela',              time: '7:15' },
      { name: 'Jhagriya By-pass Sehore', time: '7:25' },
      { name: 'Jhagriya',              time: '7:50' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '07',
    vehicle: 'MP04 PA 3512',
    name: 'Kolar Route (Bus 07)',
    color: '#F7971E',
    driver: 'Virendra',
    driverMob: '7770873503',
    stops: [
      { name: 'Gehnu Kheda',           time: '6:40' },
      { name: 'D-Mart',                time: '6:43' },
      { name: 'Lalita Nagar',          time: '6:44' },
      { name: 'Naya Pura',             time: '6:51' },
      { name: 'Mandakini',             time: '6:56' },
      { name: 'J.K. Hospital',         time: '7:03' },
      { name: 'Bansal Hospital',       time: '7:12' },
      { name: '10 Number',             time: '7:25' },
      { name: 'Arera Petrol Pump',     time: '7:27' },
      { name: 'Kolar Tiraha',          time: '7:30' },
      { name: 'Panchsil Nagar',        time: '7:33' },
      { name: 'Vaishali Nagar',        time: '7:36' },
      { name: 'Nehru Nagar Chauraha',  time: '7:40' },
      { name: 'Nehru Nagar Naya Basera', time: '7:45' },
      { name: 'Dipo 100 Daily Office', time: '7:50' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '09',
    vehicle: 'MP04 PA 3513',
    name: 'Mandideep Route',
    color: '#2D5BFF',
    driver: 'Satish Tomar',
    driverMob: '9111645969',
    stops: [
      { name: 'Satlapur',              time: '6:15' },
      { name: 'Vardhman',              time: '6:25' },
      { name: 'Sarakiya',              time: '6:35' },
      { name: 'HEG/Mandideep',         time: '6:50' },
      { name: 'Samardha',              time: '6:55' },
      { name: 'Radhapuram',            time: '6:56' },
      { name: 'Pal Dhaba',             time: '6:58' },
      { name: 'Indus Town',            time: '7:00' },
      { name: '11 Meal',               time: '7:02' },
      { name: 'Misrod',                time: '7:05' },
      { name: 'Ashima Mall',           time: '7:10' },
      { name: 'Danish Nagar',          time: '7:12' },
      { name: 'Bagsawaniya Thana',     time: '7:15' },
      { name: 'SP Office',             time: '7:17' },
      { name: 'Narayan Nagar',         time: '7:20' },
      { name: 'Ganesh Mandir',         time: '7:21' },
      { name: 'BJP Office',            time: '7:22' },
      { name: 'Nutan College',         time: '7:25' },
      { name: 'Durga Petrol Pump',     time: '7:27' },
      { name: 'Narmada Bhawan',        time: '7:30' },
      { name: 'Panchsil Nagar',        time: '7:32' },
      { name: 'Mata Mandir',           time: '7:33' },
      { name: 'PNT',                   time: '7:35' },
      { name: 'Nehru Nagar New Basti', time: '7:36' },
      { name: 'Nehru Nagar Square',    time: '7:40' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '10',
    vehicle: 'MP04 PA 3523',
    name: 'Ashoka Garden Route (Bus 10)',
    color: '#B721FF',
    driver: 'Devendra Parmar',
    driverMob: '9111997080',
    stops: [
      { name: 'Bhopal Railway Station Platform-1', time: '8:05' },
      { name: 'Pushpa Nagar',          time: '8:07' },
      { name: 'Sangam Tent House',     time: '8:08' },
      { name: '80-feet Road',          time: '8:10' },
      { name: 'Ashoka Garden Pani ki Tanki', time: '8:15' },
      { name: 'Prabhat Square',        time: '8:17' },
      { name: 'Bogda Pull',            time: '8:20' },
      { name: 'Jinsi Square',          time: '8:25' },
      { name: 'Roshanpura',            time: '8:30' },
      { name: 'Dipo',                  time: '8:35' },
      { name: 'Ratibad Campus',        time: '9:15' },
    ],
  },
  {
    busNo: '11',
    vehicle: 'MP04 PA 3522',
    name: 'SLV Route',
    color: '#21D4FD',
    driver: 'Tulsi Das',
    driverMob: '8964003485',
    stops: [
      { name: 'SOS',                   time: '6:45' },
      { name: 'Transport Nagar',       time: '6:50' },
      { name: 'Patel Nagar',           time: '6:55' },
      { name: 'Anand Nagar Police Choki', time: '6:57' },
      { name: 'Ratna Giri Chourha',    time: '6:59' },
      { name: 'Viranda Van Nagar',     time: '7:00' },
      { name: 'Tanatan Daba',          time: '7:01' },
      { name: 'Narela Chouraha',       time: '7:02' },
      { name: 'Ayodhya Nagar Square',  time: '7:03' },
      { name: 'Piplani Chouraha',      time: '7:10' },
      { name: 'Indrapuri',             time: '7:11' },
      { name: 'ITI',                   time: '7:13' },
      { name: 'Bijli Gate',            time: '7:14' },
      { name: 'Subhash Nagar',         time: '7:15' },
      { name: 'Vallabh Bhavan',        time: '7:20' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '12',
    vehicle: 'MP04 PA 3521',
    name: 'Neelbad Route',
    color: '#43E97B',
    driver: 'Arjun Maran',
    driverMob: '7724080617',
    stops: [
      { name: 'Neelbad',               time: '8:00' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '13',
    vehicle: 'MP04 PA 2288',
    name: 'Sehore Route',
    color: '#FA709A',
    driver: 'Mukesh Verma',
    driverMob: '9303557964',
    stops: [
      { name: 'Bishan Khedi',          time: '5:45' },
      { name: 'Bhav Khedi',            time: '5:55' },
      { name: 'Khakar Kheda',          time: '6:05' },
      { name: 'Daite Colony',          time: '6:15' },
      { name: 'Kodiya',                time: '6:30' },
      { name: 'Ganesh Mandir Sehore',  time: '6:35' },
      { name: 'Moti Baba Mandir',      time: '6:40' },
      { name: 'Reliance Petrol Pump',  time: '6:45' },
      { name: 'Kohli Pura',            time: '6:50' },
      { name: 'Ganga Ashram',          time: '6:52' },
      { name: 'Bhopal Naka',           time: '6:55' },
      { name: 'Chanakya Puri',         time: '7:00' },
      { name: 'Chanakya Puri Vishal Mega Mart', time: '7:05' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
  {
    busNo: '14',
    vehicle: 'MP04 PA 2290',
    name: 'Fanda Route',
    color: '#FEE140',
    driver: 'Sunil Kumar Prajapati',
    driverMob: '9977246988',
    stops: [
      { name: 'Fanda',                 time: '6:25' },
      { name: 'Pipaliya',              time: '6:30' },
      { name: 'Padli Jod',             time: '6:40' },
      { name: 'Kolas',                 time: '6:55' },
      { name: 'Naya Gano',             time: '7:05' },
      { name: 'Sastakhedi',            time: '7:15' },
      { name: 'Tilakhedi',             time: '7:20' },
      { name: 'Deheriya',              time: '7:25' },
      { name: 'Mundla',                time: '7:27' },
      { name: 'Narela',                time: '7:30' },
      { name: 'Khokariya',             time: '7:35' },
      { name: 'Kodiya',                time: '7:40' },
      { name: 'Kajlash',               time: '7:50' },
      { name: 'Nanni',                 time: '8:05' },
      { name: 'Ratibad Campus',        time: '8:15' },
    ],
  },
];

// All routes terminate at Ratibad Campus
const RATIBAD = { lat: 23.1270, lng: 77.3494 };

async function seed() {
  console.log('🔌 Connecting to MongoDB (chalocampus)...');
  await mongoose.connect(MONGODB_URI, { dbName: 'chalocampus' });
  console.log(`✅ Connected to: ${mongoose.connection.name}`);

  // Clear existing routes and buses
  await Route.deleteMany({});
  await Bus.deleteMany({});
  console.log('🧹 Cleared existing routes and buses');

  for (let ri = 0; ri < ROUTES.length; ri++) {
    const r = ROUTES[ri];
    
    // Build stops with names only — NO fake coordinates
    // (Real GPS coordinates should be added via the manager dashboard or a proper geocoding step)
    const stopsWithNames = r.stops.map(stop => ({ name: stop.name }));

    const route = await Route.create({
      name: r.name,
      color: r.color,
      stops: stopsWithNames,
      coordinates: [], // Empty — no fake polyline
    });

    // Create one bus per route (match Bus schema exactly)
    await Bus.create({
      busNumber: r.vehicle,           // vehicle number as busNumber
      name: `Bus ${r.busNo} - ${r.name}`,
      routeId: route._id.toString(),
      routeName: r.name,
      routeColor: r.color,
      currentLat: RATIBAD.lat,
      currentLng: RATIBAD.lng,
      heading: 0,
      speed: 0,
      status: 'On-time',
      occupancy: 'Low',
      etas: [],
      lastUpdated: new Date(),
    });

    console.log(`✅ Bus ${r.busNo}: ${r.name} (${r.stops.length} stops)`);
  }

  console.log(`\n🎉 Seeded ${ROUTES.length} routes and ${ROUTES.length} buses successfully!`);
  console.log('📍 All routes terminate at: Ratibad Campus (Sagar Group of Institutions)');
  await mongoose.disconnect();
}

seed().catch(err => {
  console.error('❌ Seed failed:', err);
  mongoose.disconnect();
  process.exit(1);
});
