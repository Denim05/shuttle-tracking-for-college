const mongoose = require('mongoose');

const liveTripLogSchema = new mongoose.Schema({
  busId: { type: String, required: true, index: true },
  busNumber: { type: String, default: 'N/A' },
  busName: { type: String, default: 'N/A' },
  driverId: { type: mongoose.Schema.Types.ObjectId, ref: 'Driver', default: null },
  driverName: { type: String, default: 'Unassigned' },
  driverPhone: { type: String, default: 'N/A' },
  routeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Route', default: null },
  routeName: { type: String, default: 'Unassigned' },
  date: { type: String, required: true, index: true }, // Format: YYYY-MM-DD
  startTime: { type: Date, default: Date.now },
  endTime: { type: Date, default: null },
  durationMinutes: { type: Number, default: null },
  distanceKm: { type: Number, default: 0 },
  distanceSource: { 
    type: String, 
    enum: ['GPS', 'Polyline', 'Unavailable'], 
    default: 'Unavailable' 
  },
  cancellationReason: { type: String, default: null },
  reachedStops: [{
    stopName: { type: String, required: true },
    reachedTime: { type: Date, default: Date.now },
    scheduledTime: { type: String, default: null }
  }],
  tripType: { type: String, enum: ['pickup', 'dropoff'], default: 'pickup' },
  status: { 
    type: String, 
    enum: ['Active', 'Completed', 'Cancelled', 'Failed'], 
    default: 'Active',
    index: true 
  }
}, {
  timestamps: true
});

liveTripLogSchema.index({ busId: 1, date: 1, status: 1 });
liveTripLogSchema.index({ date: -1, status: 1 });

module.exports = mongoose.model('LiveTripLog', liveTripLogSchema);
