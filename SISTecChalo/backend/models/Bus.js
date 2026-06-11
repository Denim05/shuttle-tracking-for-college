const mongoose = require('mongoose');

const busSchema = new mongoose.Schema({
  busNumber: { type: String, default: 'N/A' }, // e.g. MP-04-AB-1234
  name: String,
  routeId: { type: String, required: true },
  routeName: String,
  routeColor: String,
  currentLat: { type: Number, default: 23.2599 },
  currentLng: { type: Number, default: 77.4126 },
  heading: { type: Number, default: 0 },
  speed: { type: Number, default: 0 },
  status: { type: String, enum: ['On-time', 'Delayed', 'Offline'], default: 'Offline' },
  driverId: String, // Link to User
  occupancy: { type: String, enum: ['Low', 'Medium', 'High'], default: 'Low' },
  etas: [{
    stopName: String,
    minutes: Number
  }],
  lastUpdated: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Bus', busSchema);
