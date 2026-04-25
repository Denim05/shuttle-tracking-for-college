const mongoose = require('mongoose');

const scheduleSchema = new mongoose.Schema({
  routeId:   { type: String, required: true },
  routeName: { type: String },
  stopName:  { type: String, required: true },
  // Departure times as "HH:MM" strings, e.g. ["07:00","08:30","13:00","17:30"]
  times:     [{ type: String }],
  daysActive:{ type: [String], default: ['Mon','Tue','Wed','Thu','Fri','Sat'] },
});

module.exports = mongoose.model('Schedule', scheduleSchema);
