const mongoose = require('mongoose');
require('dotenv').config();

async function checkUsers() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/sistecChalo', { dbName: 'sistecChalo' });
        console.log('Connected to DB');
        
        const User = mongoose.model('User', new mongoose.Schema({
            username: String,
            role: String
        }));

        const users = await User.find({});
        console.log('Total Users:', users.length);
        users.forEach(u => console.log(`- ${u.username} (${u.role})`));

        process.exit(0);
    } catch (err) {
        console.error(err);
        process.exit(1);
    }
}

checkUsers();


