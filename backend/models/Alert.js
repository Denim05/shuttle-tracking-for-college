const mongoose = require('mongoose');

const AlertSchema = new mongoose.Schema({
    userId: { type: String, required: true },
    name: { type: String, required: true },
    role: { type: String, required: true },
    latitude: { type: Number, default: null },
    longitude: { type: Number, default: null },
    locationAvailable: { type: Boolean, default: true },
    routeId: { type: String, default: null },
    routeName: { type: String, default: null },
    busId: { type: String, default: null },
    timestamp: { type: Date, default: Date.now },
    status: { type: String, enum: ['active', 'resolved', 'dismissed'], default: 'active' }
});

module.exports = mongoose.model('Alert', AlertSchema);
