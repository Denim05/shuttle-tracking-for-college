const mongoose = require('mongoose');

const driverSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  name: String,
  assignedBus: String,
  contactNumber: String,
  licenseNumber: String,
  emergencyContact: String,
  address: String,
  experienceYears: String,
  notes: String,
  status: { type: String, enum: ['Active', 'Suspended'], default: 'Active' },
  documents: [{
    name: String,
    url: String,
    fileType: String,
    uploadedAt: { type: Date, default: Date.now }
  }],
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Driver', driverSchema);