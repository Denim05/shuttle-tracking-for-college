require('dotenv').config();
const mongoose = require('mongoose');
const Route = require('./models/Route');
const Bus = require('./models/Bus');

const rawUri = process.env.MONGODB_URI;
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/sistecChalo$1').replace(/^(mongodb(?:\+srv)?:\/\/[^/]+)$/, '$1/sistecChalo');

async function testETA() {
    await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
    
    const routes = await Route.find({});
    console.log(`✅ Total Routes in DB: ${routes.length}`);

    let totalStopsCount = 0;
    let stopsWithCoords = 0;

    routes.forEach(r => {
        totalStopsCount += r.stops.length;
        r.stops.forEach(s => {
            if (s.lat != null && s.lng != null) {
                stopsWithCoords++;
            }
        });
    });

    console.log(`📍 Total Stops across Fleet: ${totalStopsCount}`);
    console.log(`🎯 Stops with Valid Geocoded Lat/Lng: ${stopsWithCoords} (${((stopsWithCoords / totalStopsCount) * 100).toFixed(1)}%)`);

    if (routes.length > 0) {
        const sampleRoute = routes[0];
        const stop = sampleRoute.stops[0];
        console.log(`\n🔍 Sample Verification for Route: "${sampleRoute.name}"`);
        console.log(`   Stop: "${stop.name}" -> Lat: ${stop.lat}, Lng: ${stop.lng}`);
        
        // Simulating bus at Ratibad Campus (23.1270, 77.3494)
        const busLat = 23.1270, busLng = 77.3494;
        const R = 6371;
        const dLat = (stop.lat - busLat) * Math.PI / 180;
        const dLon = (stop.lng - busLng) * Math.PI / 180;
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(busLat * Math.PI / 180) * Math.cos(stop.lat * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        const dist = R * c;
        const speed = 30; // km/h
        const etaMin = Math.round((dist / speed) * 60);

        console.log(`   Distance from Ratibad Campus: ${dist.toFixed(2)} km`);
        console.log(`   Calculated Real-Time ETA: ${etaMin} minutes`);
    }

    await mongoose.disconnect();
}

testETA().catch(console.error);
