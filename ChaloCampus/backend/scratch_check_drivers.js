const mongoose = require('mongoose');
const Driver = require('./models/Driver');
const MONGODB_URI = 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus';

async function checkDrivers() {
    try {
        await mongoose.connect(MONGODB_URI);
        const drivers = await Driver.find({});
        console.log('DRIVERS FOUND:', JSON.stringify(drivers, null, 2));
        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

checkDrivers();
