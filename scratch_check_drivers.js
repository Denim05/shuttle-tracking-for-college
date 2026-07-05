const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
﻿const mongoose = require('mongoose');
const Driver = require('./models/Driver');
const MONGODB_URI = process.env.MONGODB_URI;
if (!MONGODB_URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

async function checkDrivers() {
    try {
        await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
        const drivers = await Driver.find({});
        console.log('DRIVERS FOUND:', JSON.stringify(drivers, null, 2));
        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

checkDrivers();

