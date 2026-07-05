const mongoose = require('mongoose');

const NotificationSchema = new mongoose.Schema({
    message: { type: String, required: true },
    type: { type: String, default: 'info' },
    createdBy: { type: String, default: 'System' },
    createdAt: { type: Date, default: Date.now, expires: 86400 } // Expires in 24 hours (1 day)
});

module.exports = mongoose.model('Notification', NotificationSchema);
