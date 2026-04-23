const mongoose = require('mongoose');
const URI = 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus?retryWrites=true&w=majority';

async function test() {
    await mongoose.connect(URI);
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
