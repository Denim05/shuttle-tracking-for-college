const mongoose = require('mongoose');

const routeSchema = new mongoose.Schema({
  name: { type: String, required: true },
  color: String,
  coordinates: [{
    _id: false,
    latitude: Number,
    longitude: Number
  }],
  stops: [{
    name: String,
    lat: Number,
    lng: Number,
    time: String
  }]
});

module.exports = mongoose.model('Route', routeSchema);
