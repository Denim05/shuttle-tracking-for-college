const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const mongoose = require('mongoose');

const URI = process.env.MONGODB_URI;
if (!URI) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!\n');
    process.exit(1);
}

const rawUri = process.env.MONGODB_URI;
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/sistecChalo$1');

async function clean() {
    try {
        console.log('🔌 Connecting to MongoDB...');
        await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
        console.log('✅ Connected.');

        const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }));
        const RegistrationSubmission = mongoose.model('RegistrationSubmission', new mongoose.Schema({}, { strict: false }));

        // Count items before delete
        const studentCount = await User.countDocuments({ role: 'user' });
        const submissionCount = await RegistrationSubmission.countDocuments({});

        console.log(`📊 Current Counts:`);
        console.log(`   - Student Users (role: 'user'): ${studentCount}`);
        console.log(`   - Registration Submissions: ${submissionCount}`);

        if (studentCount === 0 && submissionCount === 0) {
            console.log('✨ No test data to clean.');
            process.exit(0);
        }

        console.log('🧹 Cleaning Student Users (role: "user")...');
        const userResult = await User.deleteMany({ role: 'user' });
        console.log(`🗑️ Deleted ${userResult.deletedCount} Student Users.`);

        console.log('🧹 Cleaning all Registration Submissions...');
        const subResult = await RegistrationSubmission.deleteMany({});
        console.log(`🗑️ Deleted ${subResult.deletedCount} submissions.`);

        console.log('🎉 Database cleaned successfully! You can now perform clean import and approval testing.');
        process.exit(0);
    } catch (err) {
        console.error('❌ Clean script error:', err);
        process.exit(1);
    }
}

clean();
