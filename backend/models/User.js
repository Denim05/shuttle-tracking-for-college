const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  email: String,
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  // Specific rights given to this user by Admin/Manager
  accessRights: { type: [String], default: ['view_routes', 'track_bus'] }, 
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('User', userSchema);
