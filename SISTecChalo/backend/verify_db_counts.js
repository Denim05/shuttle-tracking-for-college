const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const mongoose = require('mongoose');
const Route = require('./models/Route');
const Bus = require('./models/Bus');
const Driver = require('./models/Driver');

const MONGODB_URI = process.env.MONGODB_URI;
if (!MONGODB_URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

async function verify() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
    console.log('✅ Connected.');

    const routeCount = await Route.countDocuments({});
    const busCount = await Bus.countDocuments({});
    const driverCount = await Driver.countDocuments({});

    console.log('\n======================================');
    console.log('📊 DATABASE SEED VERIFICATION REPORT');
    console.log('======================================');
    console.log(`Routes:  ${routeCount} / 30 ${routeCount === 30 ? '✅ MATCH' : '❌ MISMATCH'}`);
    console.log(`Buses:   ${busCount} / 30 ${busCount === 30 ? '✅ MATCH' : '❌ MISMATCH'}`);
    console.log(`Drivers: ${driverCount} / 30 ${driverCount === 30 ? '✅ MATCH' : '❌ MISMATCH'}`);
    console.log('======================================\n');

    console.log('🔍 Checking bidirectional linking & data integrity:');
    const buses = await Bus.find({});
    let linkedCorrectlyCount = 0;
    
    for (const bus of buses) {
      const driver = await Driver.findById(bus.driverId);
      const route = await Route.findById(bus.routeId);
      
      const driverOk = driver && driver.assignedBus === bus.id;
      const routeOk = !!route;
      
      if (driverOk && routeOk) {
        linkedCorrectlyCount++;
      } else {
        console.log(`⚠️  Link Issue for ${bus.name}: Driver Found: ${!!driver}, Driver linked back: ${driver ? driver.assignedBus === bus.id : 'N/A'}, Route Found: ${!!route}`);
      }
    }
    
    console.log(`🔗 Linked Correctly: ${linkedCorrectlyCount} / ${buses.length} buses`);
    
    console.log('\n👥 Listing all seeded Driver usernames:');
    const drivers = await Driver.find({}).sort({ username: 1 });
    drivers.forEach(d => {
      console.log(`- Username: ${d.username.padEnd(25)} | Name: ${d.name}`);
    });

    process.exit(0);
  } catch (err) {
    console.error('❌ Verification failed:', err);
    process.exit(1);
  }
}

verify();

