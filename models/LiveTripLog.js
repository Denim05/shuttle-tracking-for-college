const mongoose = require('mongoose');

const liveTripLogSchema = new mongoose.Schema({
  busId: { type: String, required: true },
  busNumber: { type: String, default: 'N/A' },
  busName: { type: String, default: 'N/A' },
  driverName: { type: String, default: 'Unassigned' },
  routeName: { type: String, default: 'Unassigned' },
  date: { type: String, required: true }, // Format: YYYY-MM-DD
  startTime: { type: Date, default: Date.now },
  endTime: { type: Date },
  reachedStops: [{
    stopName: { type: String, required: true },
    reachedTime: { type: Date, default: Date.now }
  }],
  status: { type: String, enum: ['Active', 'Completed'], default: 'Active' }
});

module.exports = mongoose.model('LiveTripLog', liveTripLogSchema);
