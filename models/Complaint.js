const mongoose = require('mongoose');

const complaintSchema = new mongoose.Schema({
  userId:      { type: String, required: true },
  userName:    { type: String, default: 'Unknown' },
  routeId:     { type: String },
  routeName:   { type: String },
  driverName:  { type: String },
  busNumber:   { type: String },
  category:    {
    type: String,
    enum: ['rash_driving','late_arrival','misconduct','overloaded','other'],
    default: 'other',
  },
  description: { type: String, required: true },
  status:      { type: String, enum: ['pending','reviewed','resolved'], default: 'pending' },
  createdAt:   { type: Date, default: Date.now },
});

module.exports = mongoose.model('Complaint', complaintSchema);
