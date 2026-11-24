const mongoose = require('mongoose');

const auditTrailEntrySchema = new mongoose.Schema({
  _id: false,
  who: { type: String, required: true },
  role: { type: String, required: true },
  oldLatitude: { type: Number, default: null },
  oldLongitude: { type: Number, default: null },
  newLatitude: { type: Number, default: null },
  newLongitude: { type: Number, default: null },
  action: { type: String, required: true },
  reason: { type: String, default: '' },
  source: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});

const stopVerificationStateSchema = new mongoose.Schema({
  stopId: {
    type: String,
    required: true,
    unique: true,
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
  routeName: {
    type: String,
    default: '',
  },
  stopIndex: {
    type: Number,
    required: true,
  },
  stopName: {
    type: String,
    required: true,
    trim: true,
  },

  // Canonical production coordinate (mirrored from Route.stops; NEVER auto-mutated by user submissions)
  canonicalLatitude: { type: Number, required: true },
  canonicalLongitude: { type: Number, required: true },

  // Automated candidate coordinate (separate from canonical & recommended)
  candidateLatitude: { type: Number, default: null },
  candidateLongitude: { type: Number, default: null },
  candidateSource: { type: String, default: null },
  candidateConfidence: { type: Number, default: null },
  generatedAt: { type: Date, default: null },

  // Consensus engine recommended coordinate (pending manager review unless already verified)
  recommendedLatitude: { type: Number, default: null },
  recommendedLongitude: { type: Number, default: null },

  verificationStatus: {
    type: String,
    enum: ['UNVERIFIED', 'CANDIDATE', 'NEEDS_REVIEW', 'VERIFIED', 'FIELD_VERIFY'],
    default: 'UNVERIFIED',
  },
  confidenceScore: {
    type: Number,
    min: 0,
    max: 100,
    default: 0,
  },
  confidenceReasons: [{ type: String }],

  stats: {
    confirmations: { type: Number, default: 0 },
    corrections: { type: Number, default: 0 },
    studentConfirmations: { type: Number, default: 0 },
    studentCorrections: { type: Number, default: 0 },
    driverConfirmations: { type: Number, default: 0 },
    driverCorrections: { type: Number, default: 0 },
    conflictingClusters: { type: Number, default: 0 },
    outlierCount: { type: Number, default: 0 },
    clusterSpreadMeters: { type: Number, default: 0 },
  },

  auditTrail: [auditTrailEntrySchema],
  updatedAt: { type: Date, default: Date.now },
});

stopVerificationStateSchema.index({ routeId: 1, verificationStatus: 1 });
stopVerificationStateSchema.index({ verificationStatus: 1, confidenceScore: -1 });

module.exports = mongoose.model('StopVerificationState', stopVerificationStateSchema);
