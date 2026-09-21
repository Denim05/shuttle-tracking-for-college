const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, '..', 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const mongoose = require('mongoose');

const User = require('../models/User');
const Student = require('../models/Student');
const RegistrationSubmission = require('../models/RegistrationSubmission');

async function clearRegisteredUsers() {
    const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
    if (!mongoUri) {
        console.error('❌ Missing MONGO_URI');
        process.exit(1);
    }

    console.log('📡 Connecting to MongoDB...');
    await mongoose.connect(mongoUri);
    console.log('✅ Connected to MongoDB database:', mongoose.connection.name);

    // Count existing records before deletion
    const userCount = await User.countDocuments();
    let studentCount = 0;
    try {
        studentCount = await Student.countDocuments();
    } catch (_) {}
    let submissionCount = 0;
    try {
        submissionCount = await RegistrationSubmission.countDocuments();
    } catch (_) {}

    console.log(`📊 Found before deletion:`);
    console.log(`   - Users: ${userCount}`);
    console.log(`   - Students: ${studentCount}`);
    console.log(`   - Registration Submissions: ${submissionCount}`);

    // Delete only registered commuter users (role: 'user'), preserving admin/manager/driver accounts
    const deleteUsersResult = await User.deleteMany({ role: 'user' });
    console.log(`🗑️ Deleted ${deleteUsersResult.deletedCount} commuter user(s) (role: 'user') from 'users' collection.`);

    try {
        const deleteStudentsResult = await Student.deleteMany({});
        console.log(`🗑️ Deleted ${deleteStudentsResult.deletedCount} student(s) from 'students' collection.`);
    } catch (_) {}

    try {
        const deleteSubmissionsResult = await RegistrationSubmission.deleteMany({});
        console.log(`🗑️ Deleted ${deleteSubmissionsResult.deletedCount} submission(s) from 'registrationsubmissions' collection.`);
    } catch (_) {}

    console.log('✨ All registered user data has been completely cleared!');
    await mongoose.disconnect();
    process.exit(0);
}

clearRegisteredUsers().catch(err => {
    console.error('❌ Error clearing users:', err);
    process.exit(1);
});
