const mongoose = require('mongoose');

const driverSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  name: String,
  assignedBus: String,
  contactNumber: String,
  phone: String,
  licenseNumber: String,
  emergencyContact: String,
  address: String,
  experienceYears: String,
  notes: String,
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  mustChangePassword: { type: Boolean, default: true },
  email: { type: String, default: null },
  resetPasswordToken: { type: String, default: null },
  resetPasswordCode: { type: String, default: null },
  resetPasswordExpires: { type: Date, default: null },
  tokenVersion: { type: Number, default: 0 },
  loginAttempts: { type: Number, default: 0 },
  lockUntil: { type: Date, default: null },
  documents: [{
    name: String,
    url: String,
    fileType: String,
    uploadedAt: { type: Date, default: Date.now }
  }],
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Driver', driverSchema);