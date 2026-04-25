const mongoose = require('mongoose');

const registrationFormSchema = new mongoose.Schema({
  title:       { type: String, default: 'ChaloCampus Registration' },
  description: { type: String, default: 'Register for the college bus service' },
  routeOptions:  [{ routeId: String, routeName: String }],
  stopOptions:   [{ routeId: String, stops: [String] }],
  isActive:    { type: Boolean, default: true },
  createdBy:   { type: String },  // manager username
  createdAt:   { type: Date, default: Date.now },
  closedAt:    { type: Date },
  submissionCount: { type: Number, default: 0 },
});

module.exports = mongoose.model('RegistrationForm', registrationFormSchema);
