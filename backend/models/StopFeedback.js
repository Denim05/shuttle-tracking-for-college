const mongoose = require('mongoose');

const stopFeedbackSchema = new mongoose.Schema({
  routeId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Route',
    required: true,
  },
  routeName: {
    type: String,
    default: '',
  },
  stopName: {
    type: String,
    required: true,
    trim: true,
  },
  userId: {
    type: String,
    required: true,
  },
  userName: {
    type: String,
    default: 'Anonymous Passenger',
  },
  userRole: {
    type: String,
    enum: ['student', 'driver', 'manager', 'admin', 'user'],
    default: 'student',
  },
  feedbackType: {
    type: String,
    enum: ['confirm_correct', 'suggest_location', 'stop_moved'],
    required: true,
  },
  suggestedLat: {
    type: Number,
  },
  suggestedLng: {
    type: Number,
  },
  accuracy: {
    type: Number, // GPS horizontal accuracy in meters (e.g. 5m)
    default: 10,
  },
  comment: {
    type: String,
    trim: true,
  },
  status: {
    type: String,
    enum: ['pending', 'consensus_reached', 'applied', 'rejected'],
    default: 'pending',
  },
  consensusClusterId: {
    type: String,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// Index for fast lookups by route and stop
stopFeedbackSchema.index({ routeId: 1, stopName: 1, status: 1 });

module.exports = mongoose.model('StopFeedback', stopFeedbackSchema);
