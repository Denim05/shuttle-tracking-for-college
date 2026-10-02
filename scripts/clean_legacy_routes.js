const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });
const Route = require('../models/Route');
const Bus = require('../models/Bus');

async function cleanLegacy() {
    await mongoose.connect(process.env.MONGODB_URI);
    
    // Get all valid route IDs
    const routes = await Route.find().lean();
    const validRouteIds = new Set(routes.map(r => r._id.toString()));
    
    const allBuses = await Bus.find().lean();
    let removed = 0;
    for (const b of allBuses) {
        if (!validRouteIds.has(b.routeId) || !b.name.startsWith('Bus ')) {
            await Bus.deleteOne({ _id: b._id });
            removed++;
        }
    }
    console.log(`Cleaned up ${removed} orphaned/legacy buses.`);
    
    const activeBuses = await Bus.find().lean();
    console.log(`Active official buses now in DB: ${activeBuses.length}`);
    activeBuses.forEach((b, i) => {
        console.log(`[${i + 1}/${activeBuses.length}] ${b.busNumber} -> ${b.name}`);
    });
    
    process.exit(0);
}

cleanLegacy().catch(e => {
    console.error(e);
    process.exit(1);
});
