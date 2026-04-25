const mongoose = require('mongoose');

const registrationSubmissionSchema = new mongoose.Schema({
  formId:      { type: mongoose.Schema.Types.ObjectId, ref: 'RegistrationForm', required: true },
  name:        { type: String, required: true },
  studentId:   { type: String, required: true },
  phone:       { type: String, required: true },
  email:       { type: String },
  routeId:     { type: String, required: true },
  routeName:   { type: String },
  pickupStop:  { type: String, required: true },
  // Approval
  status:      { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  rejectionNote: { type: String },
  // Auto-generated credentials on approval
  generatedUsername: { type: String },
  generatedPassword: { type: String }, // plain text, shown once to manager
  createdUserId: { type: String }, // the _id of the User document created on approval
  submittedAt: { type: Date, default: Date.now },
  reviewedAt:  { type: Date },
});

module.exports = mongoose.model('RegistrationSubmission', registrationSubmissionSchema);
