const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
﻿const mongoose = require('mongoose');
const argon2 = require('argon2');
const URI = process.env.MONGODB_URI;
if (!URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

async function testPassword() {
    await mongoose.connect(URI, { dbName: 'sistecChalo' });
    const User = mongoose.model('User', new mongoose.Schema({ username: String, password: String }, { strict: false }));
    
    const user = await User.findOne({ username: 'Akanksha' });
    if (!user) {
        console.log('Akanksha not found');
        process.exit(1);
    }
    
    const isValid = await argon2.verify(user.password, '123456');
    console.log('Password "123456" is valid for Akanksha:', isValid);
    process.exit(0);
}

testPassword();

