const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });
const { sendCredentialsEmail } = require('./services/email_service');

async function testEmail() {
  console.log('🔍 Testing email dispatch with current .env settings...');
  console.log('SMTP_USER:', process.env.SMTP_USER);
  console.log('BREVO_API_KEY:', process.env.BREVO_API_KEY ? 'Present' : 'Missing');

  const testRecipient = process.env.SMTP_USER || 'denimhajare@gmail.com';
  const result = await sendCredentialsEmail(
    testRecipient,
    'Test Student',
    'TEST1234',
    'Pass@123',
    'student'
  );

  console.log('\n📬 Result:', JSON.stringify(result, null, 2));
}

testEmail().catch(console.error);
