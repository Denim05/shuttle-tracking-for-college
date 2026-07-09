const mongoose = require('mongoose');
const User = require('./models/User');
const RegistrationSubmission = require('./models/RegistrationSubmission');

const MONGODB_URI = process.env.MONGODB_URI || "mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/sistecChalo?retryWrites=true&w=majority";

async function migrate() {
    try {
        await mongoose.connect(MONGODB_URI);
        console.log('Connected to MongoDB Atlas.');

        const users = await User.find({ 
            $or: [
                { name: { $exists: false } },
                { name: null },
                { name: "" }
            ]
        });
        console.log(`Found ${users.length} users with missing name field.`);

        for (const user of users) {
            // Find registration submission with this username as studentId or match createdUserId
            const submission = await RegistrationSubmission.findOne({
                $or: [
                    { studentId: user.username.trim() },
                    { createdUserId: user._id.toString() }
                ]
            });

            if (submission && submission.name) {
                user.name = submission.name;
                await user.save();
                console.log(`Updated user ${user.username} with name: "${submission.name}"`);
            } else {
                user.name = user.username;
                await user.save();
                console.log(`Updated user ${user.username} with fallback name: "${user.username}"`);
            }
        }

        console.log('Migration complete!');
    } catch (err) {
        console.error('Migration failed:', err);
    } finally {
        await mongoose.disconnect();
    }
}

migrate();
