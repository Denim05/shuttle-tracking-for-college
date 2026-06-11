const mongoose = require('mongoose');
const Route = require('./models/Route');
const Bus = require('./models/Bus');
const Driver = require('./models/Driver');

const MONGODB_URI = 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/sistecChalo?retryWrites=true&w=majority';

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


