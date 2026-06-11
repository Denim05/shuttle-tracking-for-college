const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  email: String,
  role: { type: String, default: 'user' },
  userId: String, // UID for user
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  routeId: { type: String, default: null },
  pickupPoint: { type: String, default: null },
  // Specific rights given to this user by Admin/Manager
  accessRights: { type: [String], default: ['view_routes', 'track_bus'] }, 
  proximityAlertsEnabled: { type: Boolean, default: true },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('User', userSchema);
