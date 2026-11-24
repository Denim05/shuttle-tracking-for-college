const mongoose = require('mongoose');

const stopVerificationSchema = new mongoose.Schema({
  stopId: {
    type: String,
    required: true,
    trim: true,
  },
  routeId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Route',
    required: true,
  },
  busId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Bus',
    default: null,
  },
  stopName: {
    type: String,
    required: true,
    trim: true,
  },
  userId: {
    type: String,
    required: true,
    trim: true,
  },
  role: {
    type: String,
    enum: ['student', 'user', 'driver', 'manager', 'admin'],
    required: true,
  },
  action: {
    type: String,
    enum: [
      'CONFIRMED',
      'ADJUSTED',
      'MANAGER_APPROVED',
      'MANAGER_ADJUSTED',
      'MANAGER_REJECTED',
      'MARKED_FIELD_VERIFY',
    ],
    required: true,
  },
  source: {
    type: String,
    enum: ['USER', 'DRIVER', 'MANAGER', 'AUTOMATED_CANDIDATE'],
    required: true,
  },
  suggestedLatitude: {
    type: Number,
    required: true,
  },
  suggestedLongitude: {
    type: Number,
    required: true,
  },
  selectedLatitude: {
    type: Number,
    required: true,
  },
  selectedLongitude: {
    type: Number,
    required: true,
  },
  distanceFromSuggested: {
    type: Number,
    default: 0,
  },
  confidenceContribution: {
    type: Number,
    default: 1,
  },
  status: {
    type: String,
    enum: ['ACTIVE', 'SUPERSEDED', 'REJECTED', 'APPLIED'],
    default: 'ACTIVE',
  },
  routeValidation: {
    isSuspicious: { type: Boolean, default: false },
    maxNeighborDistKm: { type: Number, default: 0 },
    flags: [{ type: String }],
  },
  timestamp: {
    type: Date,
    default: Date.now,
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {},
  },
});

stopVerificationSchema.index({ stopId: 1, timestamp: -1 });
stopVerificationSchema.index({ stopId: 1, status: 1 });
stopVerificationSchema.index({ routeId: 1, stopId: 1 });
stopVerificationSchema.index({ userId: 1, timestamp: -1 });

module.exports = mongoose.model('StopVerification', stopVerificationSchema);
