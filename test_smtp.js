const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const nodemailer = require('nodemailer');

const host = process.env.SMTP_HOST;
const port = parseInt(process.env.SMTP_PORT);
const user = process.env.SMTP_USER;
const pass = process.env.SMTP_PASS;

console.log('📋 Loaded Configuration:');
console.log(`   - Host: ${host}`);
console.log(`   - Port: ${port}`);
console.log(`   - User: ${user}`);
console.log(`   - Pass: ${pass ? '****' : 'MISSING'}`);

if (!host || !user || !pass) {
    console.error('\n❌ ERROR: SMTP credentials are not configured in your local backend/.env file!\n');
    console.log('Please open your local backend/.env file and add:');
    console.log('SMTP_HOST=smtp.gmail.com');
    console.log('SMTP_PORT=587');
    console.log('SMTP_USER=your_email@gmail.com');
    console.log('SMTP_PASS=your_16_digit_app_password\n');
    process.exit(1);
}

async function testConnection() {
    console.log('\n🔌 Testing connection to SMTP server...');
    const transporter = nodemailer.createTransport({
        host,
        port,
        secure: port === 465,
        auth: { user, pass }
    });

    try {
        await transporter.verify();
        console.log('✅ Success! Transporter is ready to send emails.');

        console.log('✉️ Sending a test email...');
        const info = await transporter.sendMail({
            from: `"SISTecChalo Test" <${user}>`,
            to: user, // send to yourself
            subject: 'SISTecChalo SMTP Test Email',
            text: 'If you are reading this, SMTP configuration is working perfectly!',
            html: '<p>If you are reading this, <strong>SMTP configuration is working perfectly!</strong></p>'
        });
        console.log(`🎉 Test email sent successfully! Message ID: ${info.messageId}`);
        process.exit(0);
    } catch (err) {
        console.error('\n❌ SMTP Verification Failed:');
        console.error(err);
        process.exit(1);
    }
}

testConnection();
