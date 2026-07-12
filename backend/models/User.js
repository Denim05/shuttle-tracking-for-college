const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  name: String,
  email: String,
  role: { type: String, default: 'user' },
  userId: String, // UID for user
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  routeId: { type: String, default: null },
  pickupPoint: { type: String, default: null },
  gender: String,
  fatherName: String,
  courseName: String,
  fatherPhone: String,
  // Specific rights given to this user by Admin/Manager
  accessRights: { type: [String], default: ['view_routes', 'track_bus'] }, 
  proximityAlertsEnabled: { type: Boolean, default: true },
  proximityRadiusKm: { type: Number, default: 1.0 },
  fcmToken: { type: String, default: null },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('User', userSchema);
