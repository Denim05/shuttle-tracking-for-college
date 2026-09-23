const nodemailer = require('nodemailer');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

async function testBrevoSmtp() {
  console.log('Testing Brevo SMTP Relay (smtp-relay.brevo.com)...');
  const transporter = nodemailer.createTransport({
    host: 'smtp-relay.brevo.com',
    port: 587,
    secure: false,
    auth: {
      user: 'denimhajare@gmail.com',
      pass: process.env.BREVO_API_KEY || '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',
    },
    tls: {
      rejectUnauthorized: false
    }
  });

  try {
    const info = await transporter.sendMail({
      from: `"SISTec Chalo" <denimhajare@gmail.com>`,
      to: 'denimhajare@gmail.com',
      subject: 'Test Brevo SMTP Relay',
      text: 'Hello from SISTec Chalo via Brevo SMTP Relay!'
    });
    console.log('✅ Brevo SMTP SUCCESS! MessageId:', info.messageId);
  } catch (err) {
    console.error('❌ Brevo SMTP Failed:', err.message);
  }
}

testBrevoSmtp();
