const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
﻿const mongoose = require('mongoose');
const URI = process.env.MONGODB_URI;
if (!URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

async function test() {
    await mongoose.connect(URI, { dbName: 'sistecChalo' });
    const User = mongoose.model('User', new mongoose.Schema({ username: String }, { strict: false }));
    
    const username = 'Akanksha';
    const query = { username: { $regex: new RegExp(`^${username}$`, 'i') } };
    
    const user = await User.findOne(query);
    console.log('Query:', JSON.stringify(query));
    console.log('Result:', user ? user.username : 'NULL');
    
    const allUsers = await User.find({}, { username: 1 });
    console.log('All Users in DB:', allUsers.map(u => u.username));
    
    process.exit(0);
}

test();

