const mongoose = require('mongoose');

const driverSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true }, // For login
  password: { type: String, required: true }, // For login
  name: { type: String, required: true },
  driverId: { type: String, required: true, unique: true }, // License or Emp ID
  contactNumber: String,
  assignedBusId: String,
  status: { type: String, enum: ['Active', 'Inactive'], default: 'Active' },
  permissions: { type: [String], default: ['drive'] },
  createdAt: { type: Date, default: Date.now }
});

driverSchema.index({ status: 1 });

module.exports = mongoose.model('Driver', driverSchema);
