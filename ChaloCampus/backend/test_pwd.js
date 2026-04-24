const mongoose = require('mongoose');
const argon2 = require('argon2');
const URI = 'mongodb+srv://denimhajare_db_user:Denim123@cluster0.xn7pkoa.mongodb.net/chalocampus?retryWrites=true&w=majority';

async function testPassword() {
    await mongoose.connect(URI, { dbName: 'chalocampus' });
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
