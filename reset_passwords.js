const mongoose = require('mongoose');
const argon2 = require('argon2');
const Admin = require('./models/Admin');
const Manager = require('./models/Manager');

const MONGODB_URI = process.env.MONGODB_URI || "mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/sistecChalo?retryWrites=true&w=majority";

async function resetPasswords() {
    try {
        await mongoose.connect(MONGODB_URI);
        console.log('Connected to MongoDB Atlas.');

        const adminHash = await argon2.hash('Sistec@admin');
        const managerHash = await argon2.hash('Sistec@bus');

        // Update all Admins
        const admins = await Admin.find({});
        console.log(`Found ${admins.length} Admins to update.`);
        for (const admin of admins) {
            admin.password = adminHash;
            await admin.save();
            console.log(`🔑 Reset password for Admin: ${admin.username}`);
        }

        // Update all Managers
        const managers = await Manager.find({});
        console.log(`Found ${managers.length} Managers to update.`);
        for (const manager of managers) {
            manager.password = managerHash;
            await manager.save();
            console.log(`🔑 Reset password for Manager: ${manager.username}`);
        }

        console.log('Database passwords reset successfully!');
    } catch (err) {
        console.error('Password reset failed:', err);
    } finally {
        await mongoose.disconnect();
    }
}

resetPasswords();
