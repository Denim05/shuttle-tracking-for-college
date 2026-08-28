const mongoose = require('mongoose');

const boardingLogSchema = new mongoose.Schema({
    studentId: { type: String, required: true },
    studentName: { type: String, required: true },
    rollNumber: { type: String, required: true },
    busId: { type: String, required: true },
    busNumber: { type: String, default: 'N/A' },
    routeName: { type: String, default: 'Unassigned' },
    pickupPoint: { type: String, default: 'N/A' },
    driverId: { type: String },
    driverName: { type: String },
    boardedAt: { type: Date, default: Date.now },
    status: { type: String, enum: ['Valid', 'Expired', 'Manual'], default: 'Valid' }
}, { timestamps: true });

module.exports = mongoose.model('BoardingLog', boardingLogSchema);
