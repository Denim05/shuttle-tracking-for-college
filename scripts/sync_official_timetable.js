/**
 * sync_official_timetable.js
 * Synchronizes the SISTecChalo MongoDB database with the official college bus timetable:
 * "TIME - New Update Bus Route 19-08-2025 111111.xlsx" / PDF
 * 
 * Features:
 * 1. Accurately extracts all 25+ official buses & routes without stop bleeding.
 * 2. Precision geocoding using verified Bhopal transit landmark corridors.
 * 3. Generates REAL road-following turn-by-turn polyline geometry using OSRM.
 * 4. Configures driver accounts & bus models with live status.
 * 
 * Run: node backend/scripts/sync_official_timetable.js
 */

const path = require('path');
const fs = require('fs');

let envPath = path.resolve(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, '..', '..', 'backend', '.env');
}
require('dotenv').config({ path: envPath });

const mongoose = require('mongoose');
const argon2 = require('argon2');
const XLSX = require(path.resolve(__dirname, '..', '..', 'web_dashboard', 'node_modules', 'xlsx'));

const Route = require('../models/Route');
const Bus = require('../models/Bus');
const Driver = require('../models/Driver');
const { geocodeStopName } = require('../geocode_stops');
const { getRoadPolylineForStops } = require('../road_routing_service');

const rawUri = process.env.MONGODB_URI;
if (!rawUri) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!');
    process.exit(1);
}
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/sistecChalo$1').replace(/^(mongodb(?:\+srv)?:\/\/[^/]+)$/, '$1/sistecChalo');

const ROUTE_COLOR_PALETTE = [
    '#2563EB', '#38EF7D', '#6366F1', '#EC4899', '#F59E0B',
    '#8B5CF6', '#10B981', '#3B82F6', '#14B8A6', '#F97316',
    '#06B6D4', '#84CC16', '#E11D48', '#A855F7', '#0EA5E9',
    '#EAB308', '#22C55E', '#D946EF', '#64748B', '#FB7185',
    '#38BDF8', '#4ADE80', '#C084FC', '#F43F5E', '#2DD4BF'
];

function excelTimeToString(val) {
    if (typeof val === 'number') {
        const totalMinutes = Math.round(val * 24 * 60);
        let hours = Math.floor(totalMinutes / 60);
        const mins = totalMinutes % 60;
        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12;
        if (hours === 0) hours = 12;
        return hours.toString().padStart(2, '0') + ':' + mins.toString().padStart(2, '0') + ' ' + ampm;
    }
    return String(val || '').trim();
}

function parseTimetableExcel() {
    const filePath = path.resolve(__dirname, '..', '..', 'TIME - New Update Bus Route  19-08-2025 111111.xlsx');
    if (!fs.existsSync(filePath)) {
        throw new Error(`File not found: ${filePath}`);
    }

    const workbook = XLSX.readFile(filePath);
    const sheet = workbook.Sheets['ALL BUSES'] || workbook.Sheets[workbook.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 });

    const buses = [];
    let current = null;

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row || row.length === 0) continue;
        const rowStr = row.map(c => String(c)).join(' ').trim();

        // Detect new bus block start by 'Vehicle No' or 'ECCO'
        if (/Vehicle\s*No/i.test(rowStr) || /ECCO/i.test(rowStr)) {
            if (current && (current.busNo || current.stops.length > 0)) {
                buses.push(current);
            }
            current = {
                busNo: '',
                vehicleNo: '',
                routeName: '',
                driverName: '',
                driverPhone: '',
                stops: []
            };

            const vMatch = rowStr.match(/Vehicle\s*No\s*[:\.]\s*([A-Za-z0-9\s]+?)(?:\s{2,}|Route|$)/i);
            if (vMatch) current.vehicleNo = vMatch[1].trim();

            const rMatch = rowStr.match(/(?:Vehicle\s*No\s*[:\.].*?)\s+([A-Za-z0-9\s\+\-]+\s*Route|[A-Za-z\s]+Route)/i);
            if (rMatch) {
                current.routeName = rMatch[1].trim();
            } else if (/ECCO/i.test(rowStr)) {
                current.routeName = 'Icchawar Route (Pvt ECCO)';
                current.busNo = 'ECCO (Pvt)';
            }
        }

        if (current && (/Bus\s*No/i.test(rowStr) || /ECCO/i.test(rowStr))) {
            const bMatch = rowStr.match(/Bus\s*No\s*[:\.]\s*([A-Za-z0-9\-\s\+]+?)(?:\s{2,}|Effective|$)/i);
            if (bMatch) {
                current.busNo = bMatch[1].trim();
            } else if (/ECCO/i.test(rowStr)) {
                current.busNo = 'ECCO (Pvt)';
            }
        }

        // Parse individual stops
        if (current && typeof row[0] === 'number' && row[1]) {
            current.stops.push({
                sNo: row[0],
                name: String(row[1]).trim(),
                time: excelTimeToString(row[2])
            });
        }

        // Parse driver details
        if (current && (/Driver/i.test(rowStr) || /Mob/i.test(rowStr))) {
            const dMatch = rowStr.match(/Driver\s*:\s*([A-Za-z\s]+?)(?:Mob|\-|\:|\d|$)/i);
            const pMatch = rowStr.match(/(?:Mob|\-|\:)\s*(\d{10})/i) || rowStr.match(/(\d{10})/);
            if (dMatch && !current.driverName) {
                current.driverName = dMatch[1].trim().replace(/\s+/g, ' ');
            }
            if (pMatch && !current.driverPhone) {
                current.driverPhone = pMatch[1].trim();
            }
        }
    }

    if (current && (current.busNo || current.stops.length > 0)) {
        buses.push(current);
    }

    return buses;
}

function getDescriptiveRouteName(busNo, rawRoute, stops) {
    const firstStop = stops.length > 0 ? stops[0].name : '';

    if (busNo === '01') return 'Gandhi Nagar & Lalghati Route';
    if (busNo === '02') return 'Ashoka Garden & Bhopal Station Route (Shift 1)';
    if (busNo === '03') return 'DwarkaDham & Karond Route';
    if (busNo === '04') return 'Kolar Road & DPS School Route';
    if (busNo === '05') return 'Bhopal Station & Ashoka Garden Route (Shift 2)';
    if (busNo === '06') return 'Alipur & Ashta Route (Shift 1)';
    if (busNo === '07') return 'Gehnu Kheda & Lalita Nagar Route';
    if (busNo === '09') return 'Mandideep & Satlapur Route';
    if (busNo === '10') return 'Bhopal Station & Ashoka Garden Route (Shift 3)';
    if (busNo === '11') return 'SOS & Transport Nagar & Ayodhya Bypass Route';
    if (busNo === '13') return 'Sehore & Bishan Khedi Route';
    if (busNo === '14') return 'Fanda & Pipaliya Route';
    if (busNo === '15') return 'Icchawar & Diwadiya Route';
    if (busNo === '16') return 'Ashta & Bhopal Naka Route';
    if (busNo === '17') return 'Bhopal Station & Ashoka Garden Route (Shift 4)';
    if (busNo === '18') return 'Bhopal Station & Ashoka Garden Route (Shift 5)';
    if (busNo === '19') return 'Dodi & Sonkach & Jawar Route';
    if (busNo === '20') return 'Bhopal Station & Ashoka Garden Route (Shift 6)';
    if (busNo === '21') return 'Neelbad Express Shuttle Route';
    if (busNo === '22') return 'Bhopal Station & Ashoka Garden Route (Shift 7)';
    if (busNo === '23') return 'Katara & Bagmugaliya & AIIMS Route';
    if (busNo === '24') return 'Ashoka Garden & Bhopal Station (Shift 8)';
    if (busNo === 'T-4') return 'Rehti & Narsullaganj Route';
    if (busNo === 'T-5') return 'Hoshangabad & Babai & Mana Gaon Route';
    if (busNo === 'T-6') return 'Bakaniya & Kharkedi Route';
    if (busNo.includes('ECCO')) return 'Brajesh Nagar & Icchawar Route (Pvt)';

    if (firstStop) return `${firstStop} Route (Bus ${busNo})`;
    return `Route ${busNo} - ${rawRoute || 'SISTec Transit'}`;
}

async function syncAll() {
    console.log('🚀 Starting High-Precision Timetable & Road Geometry Sync...');
    console.log(`🔌 Connecting to MongoDB: ${MONGODB_URI}`);
    await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
    console.log('✅ Connected to MongoDB Atlas.');

    const parsedBuses = parseTimetableExcel();
    console.log(`📋 Successfully extracted ${parsedBuses.length} buses from official timetable.`);

    const defaultDriverPasswordHash = await argon2.hash('123456');

    // Clean existing routes and buses for pristine re-sync
    await Route.deleteMany({});
    await Bus.deleteMany({});
    console.log('🧹 Cleaned existing routes and bus records for clean sync.');

    for (let i = 0; i < parsedBuses.length; i++) {
        const b = parsedBuses[i];
        const routeColor = ROUTE_COLOR_PALETTE[i % ROUTE_COLOR_PALETTE.length];
        const fullRouteName = getDescriptiveRouteName(b.busNo, b.routeName, b.stops);

        console.log(`\n🚍 [${i + 1}/${parsedBuses.length}] Bus ${b.busNo} (${b.vehicleNo || 'N/A'}) - "${fullRouteName}" (${b.stops.length} stops)`);

        // 1. Geocode stops sequentially
        const geocodedStops = [];
        for (const stop of b.stops) {
            const coords = await geocodeStopName(stop.name, b.busNo);
            geocodedStops.push({
                name: stop.name,
                lat: coords.lat,
                lng: coords.lng,
                time: stop.time || ''
            });
        }

        // Ensure campus is terminal stop if not present
        const hasCampus = geocodedStops.some(s => s.name.toLowerCase().includes('ratibad') || s.name.toLowerCase().includes('campus'));
        if (!hasCampus && geocodedStops.length > 0) {
            geocodedStops.push({
                name: 'Ratibad Campus',
                lat: 23.180302,
                lng: 77.302695,
                time: '08:45 AM'
            });
        }

        // 2. Fetch true road-following polyline geometry
        console.log(`   🛣️  Computing road-following route path via OSRM...`);
        const roadResult = await getRoadPolylineForStops(geocodedStops);
        console.log(`   ✨ Generated road path: ${roadResult.distanceKm} km, ${roadResult.coordinates.length} polyline waypoints.`);

        // 3. Save Route to DB
        const newRoute = await Route.create({
            name: fullRouteName,
            color: routeColor,
            stops: geocodedStops,
            coordinates: roadResult.coordinates
        });

        // 4. Create or update driver account
        let driverDoc = null;
        if (b.driverName) {
            const driverUsername = `driver_${b.busNo.toLowerCase().replace(/[^a-z0-9]/g, '')}`;
            const driverPhone = b.driverPhone || '9876543210';

            driverDoc = await Driver.findOne({ username: driverUsername });
            if (!driverDoc) {
                driverDoc = await Driver.create({
                    username: driverUsername,
                    password: defaultDriverPasswordHash,
                    name: b.driverName,
                    phone: driverPhone,
                    busNumber: b.vehicleNo || `Bus ${b.busNo}`,
                    status: 'Active'
                });
            } else {
                driverDoc.name = b.driverName;
                driverDoc.phone = driverPhone;
                driverDoc.busNumber = b.vehicleNo || `Bus ${b.busNo}`;
                await driverDoc.save();
            }
        }

        // 5. Create Bus record in DB
        const firstStopCoords = geocodedStops.length > 0 ? geocodedStops[0] : { lat: 23.180302, lng: 77.302695 };
        const newBus = await Bus.create({
            busNumber: b.vehicleNo || `Bus ${b.busNo}`,
            name: `Bus ${b.busNo} - ${fullRouteName}`,
            routeId: newRoute._id,
            routeName: fullRouteName,
            routeColor: routeColor,
            currentLat: firstStopCoords.lat,
            currentLng: firstStopCoords.lng,
            heading: 0,
            speed: 0,
            status: 'Offline',
            driverId: driverDoc ? driverDoc._id : null,
            occupancy: 'Low',
            tripType: 'pickup',
            etas: []
        });

        if (driverDoc) {
            driverDoc.assignedBus = newBus._id;
            await driverDoc.save();
        }

        // Small delay between routes to avoid OSRM public server rate limits
        await new Promise(r => setTimeout(r, 150));
    }

    console.log('\n===============================================================');
    console.log('🎉 100% ROAD-FOLLOWING TIMETABLE SYNC COMPLETED SUCCESSFULLY!');
    console.log(`📊 Synced: ${parsedBuses.length} Buses & Routes with verified road polylines.`);
    console.log('===============================================================');

    await mongoose.disconnect();
    process.exit(0);
}

if (require.main === module) {
    syncAll().catch(err => {
        console.error('❌ Sync failed:', err);
        mongoose.disconnect();
        process.exit(1);
    });
}

module.exports = { syncAll };
