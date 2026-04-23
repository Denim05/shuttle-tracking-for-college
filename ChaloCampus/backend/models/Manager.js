const mongoose = require('mongoose');

const managerSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true }, // In production, hash this!
  email: String,
  employeeId: { type: String, required: true, unique: true },
  department: String,
  // Managers can grant specific rights or manage specific areas
  canManage: { type: [String], default: ['students', 'drivers', 'buses'] }, 
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Manager', managerSchema);
