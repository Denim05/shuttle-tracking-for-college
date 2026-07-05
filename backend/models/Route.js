const mongoose = require('mongoose');

const routeSchema = new mongoose.Schema({
  name: { type: String, required: true },
  color: String,
  coordinates: [{
    latitude: Number,
    longitude: Number
  }],
  stops: [{
    name: String,
    lat: Number,
    lng: Number
  }]
});

module.exports = mongoose.model('Route', routeSchema);
