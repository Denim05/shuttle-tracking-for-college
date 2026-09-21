/**
 * send_test_notification.js
 * Utility to dispatch a live background push notification via Firebase Cloud Messaging.
 */
require('dotenv').config();
const mongoose = require('mongoose');
const admin = require('firebase-admin');
const path = require('path');

async function sendBackgroundNotification() {
    try {
        const serviceAccountPath = path.resolve(__dirname, '../firebase-service-account.json');
        if (!admin.apps.length) {
            admin.initializeApp({
                credential: admin.credential.cert(require(serviceAccountPath))
            });
        }

        await mongoose.connect(process.env.MONGODB_URI);
        const db = mongoose.connection.db;

        const users = await db.collection('users').find({ fcmToken: { $exists: true, $ne: null } }).toArray();
        console.log(`Found ${users.length} user(s) with active FCM token(s).`);

        if (users.length === 0) {
            console.log('❌ No users with FCM tokens found.');
            process.exit(0);
        }

        const uniqueTokens = [...new Set(users.map(u => u.fcmToken).filter(Boolean))];
        console.log(`Targeting ${uniqueTokens.length} unique device token(s)...`);

        users.forEach(user => {
            console.log(`📱 Target: ${user.username} (${user.name || 'User'}) | Token: ${user.fcmToken.substring(0, 25)}...`);
        });

        const payload = {
            notification: {
                title: '🚌 SISTec Chalo: Bus Approaching',
                body: 'Your campus shuttle is 1.2 km away and approaching your stop (~3 min).'
            },
            data: {
                type: 'proximity_alert',
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                title: '🚌 SISTec Chalo: Bus Approaching',
                body: 'Your campus shuttle is 1.2 km away and approaching your stop (~3 min).',
                routeId: 'ROUTE-04',
                timestamp: new Date().toISOString()
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'SISTecChalo_pulse_alerts',
                    color: '#2563EB',
                    sound: 'default',
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    visibility: 'public',
                    priority: 'high'
                }
            },
            tokens: uniqueTokens
        };

        console.log('🚀 Dispatching live background notification via Firebase Admin SDK...');
        const response = await admin.messaging().sendEachForMulticast(payload);

        console.log(`✅ [FCM Multicast Complete] Success Count: ${response.successCount}, Failure Count: ${response.failureCount}`);
        response.responses.forEach((r, idx) => {
            if (r.success) {
                console.log(`   [Device ${idx + 1}] Message ID: ${r.messageId}`);
            } else {
                console.log(`   [Device ${idx + 1}] Error: ${r.error?.message}`);
            }
        });

        process.exit(0);
    } catch (err) {
        console.error('❌ Error sending notification:', err);
        process.exit(1);
    }
}

sendBackgroundNotification();
