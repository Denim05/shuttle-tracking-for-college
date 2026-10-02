/**
 * sync_ratibad_9am_timetable.js
 * Synchronize all 37 official college buses and routes from:
 * "SISTec Ratibad time 9_00 am.xlsx - sistec123 900.pdf"
 * 
 * Rules:
 * - Prefix each route with Bus No (e.g. Bus 01 - Gandhi Nagar & Lalghati Route)
 * - Preserve all existing stop coordinates 100%
 * - Assign road polyline geometry
 * - Update Bus models with official registration plates and route IDs
 * - Update driver logins
 */

const path = require('path');
const fs = require('fs');

let envPath = path.resolve(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, '..', '..', 'backend', '.env');
}
require('dotenv').config({ path: envPath });

const mongoose = require('mongoose');
const { syncOfficialRatibadRoster } = require('../timetable_importer');

async function run() {
    console.log('🚀 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB. Starting 37-bus official roster synchronization...');

    const startTime = Date.now();
    const results = await syncOfficialRatibadRoster();
    const duration = ((Date.now() - startTime) / 1000).toFixed(1);

    console.log(`\n🎉 Successfully synchronized ${results.length} official buses & routes in ${duration}s!`);
    results.forEach((r, i) => {
        console.log(`[${i + 1}/${results.length}] ${r.busNumber} (${r.vehicleNo}) -> ${r.routeName} [${r.stopsCount} stops] Driver: ${r.driverName} (${r.driverPhone})`);
    });

    console.log('\n✅ All routes and buses in MongoDB now match the official PDF roster!');
    process.exit(0);
}

run().catch(err => {
    console.error('❌ Sync failed:', err);
    process.exit(1);
});
