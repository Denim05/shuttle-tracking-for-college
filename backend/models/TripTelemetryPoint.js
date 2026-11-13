const mongoose = require('mongoose');

const TELEMETRY_RETENTION_SECONDS = 90 * 24 * 60 * 60; // 90 days

const tripTelemetryPointSchema = new mongoose.Schema({
  tripLogId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'LiveTripLog',
    required: true,
    index: true
  },
  busId: {
    type: String,
    required: true,
    index: true
  },
  lat: {
    type: Number,
    required: true
  },
  lng: {
    type: Number,
    required: true
  },
  speed: {
    type: Number,
    default: null
  },
  heading: {
    type: Number,
    default: null
  },
  accuracy: {
    type: Number,
    default: null
  },
  timestamp: {
    type: Date,
    required: true,
    default: Date.now
  }
}, {
  versionKey: false
});

tripTelemetryPointSchema.index({ tripLogId: 1, timestamp: 1 });
tripTelemetryPointSchema.index({ busId: 1, timestamp: 1 });
tripTelemetryPointSchema.index(
  { timestamp: 1 },
  { expireAfterSeconds: TELEMETRY_RETENTION_SECONDS }
);

module.exports = mongoose.model('TripTelemetryPoint', tripTelemetryPointSchema);
module.exports.TELEMETRY_RETENTION_SECONDS = TELEMETRY_RETENTION_SECONDS;
