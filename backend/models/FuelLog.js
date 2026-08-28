const mongoose = require('mongoose');

const fuelLogSchema = new mongoose.Schema({
    busId: { type: String, required: true },
    busNumber: { type: String, required: true },
    driverId: { type: String, required: true },
    driverName: { type: String, required: true },
    odometerKm: { type: Number, required: true },
    liters: { type: Number, required: true },
    totalCost: { type: Number, required: true },
    fuelPricePerLiter: { type: Number, default: 95.0 },
    fuelStation: { type: String, default: 'Indian Oil' },
    receiptImage: { type: String, default: null },
    mileageKmPerLiter: { type: Number, default: 0.0 },
    refillDate: { type: Date, default: Date.now }
}, { timestamps: true });

module.exports = mongoose.model('FuelLog', fuelLogSchema);
