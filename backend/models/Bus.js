const mongoose = require('mongoose');

const busSchema = new mongoose.Schema({
  routeId: { type: String, required: true },
  routeName: String,
  routeColor: String,
  currentLat: Number,
  currentLng: Number,
  heading: Number,
  speed: Number,
  status: { type: String, enum: ['On-time', 'Delayed', 'Offline'], default: 'Offline' },
  driverId: String, // Link to User
  lastUpdated: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Bus', busSchema);
