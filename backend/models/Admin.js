const mongoose = require('mongoose');

const adminSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true }, // In production, hash this!
  email: { type: String, unique: true },
  permissions: { type: [String], default: ['all'] }, // Admins have all rights by default
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  mustChangePassword: { type: Boolean, default: false },
  resetPasswordToken: { type: String, default: null },
  resetPasswordCode: { type: String, default: null },
  resetPasswordExpires: { type: Date, default: null },
  tokenVersion: { type: Number, default: 0 },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Admin', adminSchema);
