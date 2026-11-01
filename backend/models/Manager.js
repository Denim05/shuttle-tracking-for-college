const mongoose = require('mongoose');

const managerSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true }, // In production, hash this!
  email: String,
  employeeId: { type: String, required: true, unique: true },
  department: String,
  // Managers can grant specific rights or manage specific areas
  canManage: { type: [String], default: ['students', 'drivers', 'buses'] }, 
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  mustChangePassword: { type: Boolean, default: true },
  resetPasswordToken: { type: String, default: null },
  resetPasswordCode: { type: String, default: null },
  resetPasswordExpires: { type: Date, default: null },
  tokenVersion: { type: Number, default: 0 },
  loginAttempts: { type: Number, default: 0 },
  lockUntil: { type: Date, default: null },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Manager', managerSchema);
