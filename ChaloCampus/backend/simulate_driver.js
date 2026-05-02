require('dotenv').config();
const { io } = require('socket.io-client');
const mongoose = require('mongoose');
const Bus = require('./models/Bus');
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus';

async function runSimulation() {
    await mongoose.connect(MONGODB_URI, { dbName: 'chalocampus' });
    const bus = await Bus.findOne();
    if (!bus) {
        console.error('Bus not found! Seed first.');
        process.exit(1);
    }
    const busId = bus._id.toString();
    console.log(`🔍 Found Bus ID: ${busId}`);
    await mongoose.disconnect();

    const socket = io('http://localhost:5000');

    socket.on('connect', () => {
        console.log('✅ Connected to server as simulation');
        
        let lat = 23.2333;
        let speed = 25;
        
        const interval = setInterval(() => {
            lat += 0.0005;
            speed += (Math.random() - 0.5) * 4;
            if (speed < 0) speed = 0;
            
            console.log(`📤 Sending update for Bus ${busId}: Lat=${lat.toFixed(4)}, Speed=${speed.toFixed(1)}`);
            socket.emit('locationUpdate', {
                busId: busId,
                driverId: bus.driverId,
                latitude: lat,
                longitude: 77.4333,
                speed: speed,
                status: 'On-time'
            });
        }, 2000);

        setTimeout(() => {
            clearInterval(interval);
            console.log('🛑 Simulation finished');
            socket.disconnect();
            process.exit(0);
        }, 12000);
    });

    socket.on('connect_error', (err) => {
        console.error('❌ Connection error:', err.message);
        process.exit(1);
    });
}

runSimulation();
