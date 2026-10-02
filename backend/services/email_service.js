/**
 * email_service.js
 * High-Reliability Automated Email Dispatch Service for SISTec Chalo.
 * Handles Student Approval, Login Credentials, and Transit Notifications.
 */

const nodemailer = require('nodemailer');

/**
 * Builds the clean, vibrant, professional light-theme HTML template for student credentials
 */
function buildCredentialsEmailHtml({ name, username, password, role = 'student' }) {
    const isStudent = role === 'student' || role === 'user';
    const roleBadge = isStudent ? 'STUDENT TRANSPORT PASS' : `${role.toUpperCase()} PROFILE`;
    const year = new Date().getFullYear();

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SISTec Chalo - Account Provisioned</title>
</head>
<body style="margin: 0; padding: 0; background-color: #EDF2F7; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; color: #1E293B; -webkit-font-smoothing: antialiased; line-height: 1.6;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #EDF2F7; padding: 36px 12px;">
        <tr>
            <td align="center">
                <!-- Main Card Container -->
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width: 580px; width: 100%; background-color: #FFFFFF; border: 1px solid #E2E8F0; border-radius: 14px; overflow: hidden; box-shadow: 0 4px 18px rgba(15, 23, 42, 0.06);">
                    
                    <!-- Header Section with Deep Royal Blue Banner -->
                    <tr>
                        <td style="background-color: #0C2340; padding: 32px 30px 26px 30px; text-align: left; border-bottom: 4px solid #2563EB;">
                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                                <tr>
                                    <td>
                                        <div style="font-size: 10px; font-weight: 800; letter-spacing: 1.5px; text-transform: uppercase; color: #93C5FD; margin-bottom: 4px;">
                                            Sagar Group of Institutions • Bhopal
                                        </div>
                                        <div style="font-size: 24px; font-weight: 900; color: #FFFFFF; letter-spacing: -0.5px;">
                                            SISTec<span style="color: #38BDF8;"> Chalo</span>
                                        </div>
                                    </td>
                                    <td align="right" valign="middle">
                                        <div style="display: inline-block; background-color: rgba(255, 255, 255, 0.12); border: 1px solid rgba(255, 255, 255, 0.25); border-radius: 9999px; padding: 5px 14px; font-size: 10px; font-weight: 800; color: #38BDF8; letter-spacing: 1px;">
                                            ${roleBadge}
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <!-- Body Content -->
                    <tr>
                        <td style="padding: 32px 32px 28px 32px;">
                            
                            <!-- Salutation -->
                            <div style="font-size: 19px; font-weight: 800; color: #0F172A; margin-bottom: 12px; letter-spacing: -0.3px;">
                                Welcome, ${name}
                            </div>
                            
                            <p style="margin: 0 0 24px 0; font-size: 14px; color: #475569; line-height: 1.65;">
                                Your campus transit registration has been reviewed and approved. Your official <strong>SISTec Chalo</strong> bus tracking account has been provisioned and is now active.
                            </p>

                            <!-- Credentials Vault Box (Soft Blue Tint) -->
                            <div style="background-color: #F0F7FF; border: 1.5px solid #BFDBFE; border-radius: 12px; padding: 22px 22px; margin-bottom: 26px;">
                                <div style="font-size: 11px; font-weight: 800; color: #1E40AF; text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 16px; border-bottom: 1px solid #DBEAFE; padding-bottom: 8px;">
                                    Official Account Credentials
                                </div>
                                
                                <!-- Username Row -->
                                <div style="margin-bottom: 16px;">
                                    <div style="font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px;">
                                        Enrollment ID / Username
                                    </div>
                                    <div style="font-family: 'Consolas', 'Courier New', monospace; font-size: 16px; font-weight: 800; color: #0F172A; background-color: #FFFFFF; border: 1.5px solid #CBD5E1; border-radius: 8px; padding: 10px 14px; display: inline-block; min-width: 220px;">
                                        ${username}
                                    </div>
                                </div>

                                <!-- Password Row -->
                                <div>
                                    <div style="font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px;">
                                        Temporary Password
                                    </div>
                                    <div style="font-family: 'Consolas', 'Courier New', monospace; font-size: 16px; font-weight: 800; color: #2563EB; background-color: #FFFFFF; border: 1.5px solid #93C5FD; border-radius: 8px; padding: 10px 14px; display: inline-block; min-width: 220px; letter-spacing: 0.5px;">
                                        ${password}
                                    </div>
                                </div>
                            </div>

                            <!-- Getting Started Steps -->
                            <div style="margin-bottom: 26px;">
                                <div style="font-size: 12px; font-weight: 800; color: #0F172A; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.8px;">
                                    Getting Started:
                                </div>
                                
                                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                                    <tr>
                                        <td valign="top" style="width: 32px; padding-bottom: 12px;">
                                            <div style="width: 22px; height: 22px; border-radius: 9999px; background-color: #2563EB; color: #FFFFFF; font-size: 11px; font-weight: 800; text-align: center; line-height: 22px;">1</div>
                                        </td>
                                        <td style="padding-bottom: 12px; font-size: 13px; color: #334155; line-height: 1.5;">
                                            Open the <strong>SISTec Chalo</strong> mobile application on your smartphone.
                                        </td>
                                    </tr>
                                    <tr>
                                        <td valign="top" style="width: 32px; padding-bottom: 12px;">
                                            <div style="width: 22px; height: 22px; border-radius: 9999px; background-color: #2563EB; color: #FFFFFF; font-size: 11px; font-weight: 800; text-align: center; line-height: 22px;">2</div>
                                        </td>
                                        <td style="padding-bottom: 12px; font-size: 13px; color: #334155; line-height: 1.5;">
                                            Sign in using your <strong>Enrollment ID</strong> and <strong>Temporary Password</strong>.
                                        </td>
                                    </tr>
                                    <tr>
                                        <td valign="top" style="width: 32px;">
                                            <div style="width: 22px; height: 22px; border-radius: 9999px; background-color: #2563EB; color: #FFFFFF; font-size: 11px; font-weight: 800; text-align: center; line-height: 22px;">3</div>
                                        </td>
                                        <td style="font-size: 13px; color: #334155; line-height: 1.5;">
                                            Set a new personal password when prompted upon initial sign-in.
                                        </td>
                                    </tr>
                                </table>
                            </div>

                            <!-- Security Advisory Callout (Soft Amber) -->
                            <div style="background-color: #FFFBEB; border: 1px solid #FDE68A; border-left: 4px solid #F59E0B; border-radius: 8px; padding: 14px 16px; margin-bottom: 24px;">
                                <div style="font-size: 12px; font-weight: 800; color: #92400E; margin-bottom: 3px;">
                                    Security Advisory
                                </div>
                                <div style="font-size: 12px; line-height: 1.5; color: #78350F;">
                                    Do not share your credentials with others. For route queries or account support, visit the Central Transport Office on campus or submit a request directly inside the SISTec Chalo app.
                                </div>
                            </div>

                            <!-- Formal Sign-Off -->
                            <div style="font-size: 13px; color: #64748B; line-height: 1.5;">
                                Sincerely,<br>
                                <strong style="color: #0F172A;">SISTec Chalo Team</strong><br>
                                Sagar Group of Institutions (SISTec), Bhopal
                            </div>

                        </td>
                    </tr>

                    <!-- Footer -->
                    <tr>
                        <td style="padding: 22px 28px; text-align: center; background-color: #F8FAFC; border-top: 1px solid #E2E8F0;">
                            <div style="font-size: 11px; font-weight: 700; color: #64748B; margin-bottom: 4px;">
                                Sagar Group of Institutions (SISTec) • Bhopal, Madhya Pradesh
                            </div>
                            <div style="font-size: 10px; color: #94A3B8; line-height: 1.4;">
                                This is an automated administrative notification from SISTec Chalo.<br>
                                © ${year} SISTec Chalo. All rights reserved.
                            </div>
                        </td>
                    </tr>

                </table>
            </td>
        </tr>
    </table>
</body>
</html>
    `;
}

/**
 * Sends credentials email via Resend API, Brevo API, or Nodemailer SMTP.
 * Strictly verifies real delivery to the recipient's live inbox.
 */
async function sendCredentialsEmail(email, name, username, password, role = 'student', extraInfo = {}) {
    if (!email || !email.includes('@')) {
        console.warn(`⚠️ [Email Service] Skipping email dispatch — invalid email: "${email}" for ${name} (${username})`);
        return { success: false, error: 'Invalid recipient email address' };
    }

    const htmlContent = buildCredentialsEmailHtml({ name, username, password, role });
    const subject = `SISTec Chalo: Account Login Credentials (${username})`;
    const deliveryErrors = [];

    // ── 1. Brevo HTTP API (Primary: Zero Google Profile Pic & Clean Header) ─
    const brevoApiKey = process.env.BREVO_API_KEY || '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';
    if (brevoApiKey) {
        try {
            console.log(`✉️ [Brevo API] Attempting clean email dispatch to ${email}...`);
            const response = await fetch('https://api.brevo.com/v3/smtp/email', {
                method: 'POST',
                headers: {
                    'accept': 'application/json',
                    'api-key': brevoApiKey.trim(),
                    'content-type': 'application/json'
                },
                body: JSON.stringify({
                    sender: { name: 'SISTec Chalo Transport', email: 'denimhajare@gmail.com' },
                    to: [{ email: email.trim(), name: name || 'Student' }],
                    subject: subject,
                    htmlContent: htmlContent,
                    textContent: `Dear ${name},\n\nYour registration request for the college shuttle service has been approved.\n\nAccount Credentials:\nEnrollment ID / Username: ${username}\nTemporary Password: ${password}\n\nPlease sign in to the SISTec Chalo mobile app and update your password upon initial login.\n\nSISTec Chalo Team\nSagar Group of Institutions (SISTec), Bhopal`
                })
            });

            if (response.ok) {
                const resData = await response.json();
                console.log(`✅ [Brevo API Sent] Email delivered to ${email}. MessageId: ${resData.messageId}`);
                return { success: true, provider: 'Brevo API', messageId: resData.messageId };
            } else {
                const errJson = await response.json().catch(() => ({ message: response.statusText }));
                console.warn(`⚠️ [Brevo API Warning] ${response.status}:`, errJson);
                deliveryErrors.push(`Brevo: ${errJson.message || response.statusText}`);
            }
        } catch (err) {
            console.warn(`⚠️ [Brevo Exception] ${err.message}`);
            deliveryErrors.push(`Brevo: ${err.message}`);
        }
    }

    // ── 2. Resend API (Backup #1) ───────────────────────────────────────────
    const resendApiKey = process.env.RESEND_API_KEY;
    if (resendApiKey) {
        try {
            console.log(`✉️ [Resend API] Attempting live email delivery to ${email}...`);
            const res = await fetch('https://api.resend.com/emails', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${resendApiKey.trim()}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    from: 'SISTec Chalo <onboarding@resend.dev>',
                    to: [email.trim()],
                    subject: subject,
                    html: htmlContent
                })
            });

            if (res.ok) {
                const resData = await res.json();
                console.log(`✅ [Resend API Delivered] Email dispatched to ${email}. ID: ${resData.id}`);
                return { success: true, provider: 'Resend API', messageId: resData.id };
            } else {
                const errText = await res.text();
                console.warn(`⚠️ [Resend API Warning] ${res.status}: ${errText}`);
                deliveryErrors.push(`Resend: ${errText}`);
            }
        } catch (rErr) {
            console.warn(`⚠️ [Resend Exception] ${rErr.message}`);
            deliveryErrors.push(`Resend: ${rErr.message}`);
        }
    }

    // ── 3. Nodemailer SMTP (Fallback #2) ────────────────────────────────────
    const user = (process.env.SMTP_USER && process.env.SMTP_USER.trim().length > 0) ? process.env.SMTP_USER.trim() : 'denimhajare@gmail.com';
    const rawPass = (process.env.SMTP_PASS && process.env.SMTP_PASS.trim().length > 0) ? process.env.SMTP_PASS.trim() : 'ydxpebcwzefkalmy';
    const cleanPass = rawPass.replace(/\s+/g, '');

    if (user && cleanPass) {
        try {
            const host = process.env.SMTP_HOST || 'smtp.gmail.com';
            const port = parseInt(process.env.SMTP_PORT) || 587;
            const isGmail = host.includes('gmail.com') || user.includes('@gmail.com');

            console.log(`✉️ [SMTP Transport] Attempting dispatch via ${isGmail ? 'Gmail Service' : host + ':' + port} (${user}) to ${email}...`);
            
            const transporterConfig = isGmail
                ? {
                    service: 'gmail',
                    auth: { user: user.trim(), pass: cleanPass }
                }
                : {
                    host: host.trim(),
                    port: port,
                    secure: port === 465,
                    auth: { user: user.trim(), pass: cleanPass },
                    tls: { rejectUnauthorized: false }
                };

            const transporter = nodemailer.createTransport(transporterConfig);

            const info = await transporter.sendMail({
                from: `"SISTec Chalo" <${user.trim()}>`,
                to: email.trim(),
                subject: subject,
                html: htmlContent,
                text: `Dear ${name},\n\nYour registration request for the college shuttle service has been approved.\n\nAccount Credentials:\nEnrollment ID / Username: ${username}\nTemporary Password: ${password}\n\nPlease sign in to the SISTec Chalo mobile app and update your password upon initial login.\n\nSISTec Chalo Team\nSagar Group of Institutions (SISTec), Bhopal`
            });

            console.log(`✅ [SMTP Sent] Email delivered to ${email}. MessageId: ${info.messageId}`);
            return { success: true, provider: isGmail ? 'Gmail SMTP' : 'Custom SMTP', messageId: info.messageId };
        } catch (smtpErr) {
            console.warn(`⚠️ [SMTP Warning] Failed to send via configured SMTP: ${smtpErr.message}`);
            deliveryErrors.push(`SMTP: ${smtpErr.message}`);
        }
    }

    console.error(`❌ [Live Email Delivery Failed] Could not deliver live email to ${email}. Errors:`, deliveryErrors);

    // Generate debug sandbox so developers can view what would have been sent
    try {
        const testAccount = await nodemailer.createTestAccount();
        const testTransporter = nodemailer.createTransport({
            host: 'smtp.ethereal.email',
            port: 587,
            secure: false,
            auth: { user: testAccount.user, pass: testAccount.pass }
        });

        const testInfo = await testTransporter.sendMail({
            from: `"SISTec Chalo" <no-reply@sistecchalo.edu>`,
            to: email.trim(),
            subject: subject,
            html: htmlContent
        });

        const previewUrl = nodemailer.getTestMessageUrl(testInfo);
        console.log(`📫 [Sandbox Preview URL (Not delivered to real inbox)]: ${previewUrl}`);
        
        return { 
            success: false, 
            error: deliveryErrors.join(' | '),
            previewUrl,
            sandboxProvider: 'Ethereal Sandbox (Real inbox delivery failed)'
        };
    } catch (_fallbackErr) {
        console.error('Failed to create Ethereal fallback account:', _fallbackErr.message);
    }

    return { success: false, error: deliveryErrors.join(' | ') };
}

/**
 * Builds the HTML template for Password Reset with Temporary Password
 */
function buildPasswordResetEmailHtml({ name, username, temporaryPassword, role = 'user' }) {
    const isStudent = role === 'student' || role === 'user';
    const roleBadge = isStudent ? 'STUDENT / USER' : `${role.toUpperCase()}`;
    const year = new Date().getFullYear();

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SISTec Chalo - Password Reset</title>
</head>
<body style="margin: 0; padding: 0; background-color: #EDF2F7; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; color: #1E293B; line-height: 1.6;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #EDF2F7; padding: 36px 12px;">
        <tr>
            <td align="center">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width: 580px; width: 100%; background-color: #FFFFFF; border: 1px solid #E2E8F0; border-radius: 14px; overflow: hidden; box-shadow: 0 4px 18px rgba(15, 23, 42, 0.06);">
                    <tr>
                        <td style="background-color: #0C2340; padding: 32px 30px 26px 30px; text-align: left; border-bottom: 4px solid #2563EB;">
                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                                <tr>
                                    <td>
                                        <div style="font-size: 10px; font-weight: 800; letter-spacing: 1.5px; text-transform: uppercase; color: #93C5FD; margin-bottom: 4px;">
                                            Sagar Group of Institutions • Bhopal
                                        </div>
                                        <div style="font-size: 24px; font-weight: 900; color: #FFFFFF; letter-spacing: -0.5px;">
                                            SISTec<span style="color: #38BDF8;"> Chalo</span>
                                        </div>
                                    </td>
                                    <td align="right" valign="middle">
                                        <div style="display: inline-block; background-color: rgba(255, 255, 255, 0.12); border: 1px solid rgba(255, 255, 255, 0.25); border-radius: 9999px; padding: 5px 14px; font-size: 10px; font-weight: 800; color: #38BDF8; letter-spacing: 1px;">
                                            ${roleBadge}
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding: 32px 32px 28px 32px;">
                            <div style="font-size: 19px; font-weight: 800; color: #0F172A; margin-bottom: 12px;">
                                Hello, ${name || username}
                            </div>
                            <p style="margin: 0 0 20px 0; font-size: 14px; color: #475569; line-height: 1.65;">
                                A password reset request was initiated for your <strong>SISTec Chalo</strong> account. You have been issued a temporary password to regain access.
                            </p>
                            <div style="background-color: #F8FAFC; border: 1.5px solid #CBD5E1; border-radius: 12px; padding: 22px; margin-bottom: 24px;">
                                <div style="font-size: 11px; font-weight: 800; color: #1E40AF; text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 14px;">
                                    Temporary Credentials
                                </div>
                                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                                    <tr>
                                        <td style="padding: 6px 0; font-size: 13px; color: #64748B; width: 140px;">Account ID:</td>
                                        <td style="padding: 6px 0; font-size: 14px; font-weight: 700; color: #0F172A; font-family: monospace;">${username}</td>
                                    </tr>
                                    <tr>
                                        <td style="padding: 6px 0; font-size: 13px; color: #64748B;">Temporary Password:</td>
                                        <td style="padding: 6px 0; font-size: 16px; font-weight: 800; color: #2563EB; font-family: monospace; letter-spacing: 1.5px;">${temporaryPassword}</td>
                                    </tr>
                                </table>
                            </div>
                            <div style="background-color: #FEF3C7; border-left: 4px solid #F59E0B; padding: 12px 16px; border-radius: 6px; margin-bottom: 24px;">
                                <div style="font-size: 12.5px; color: #92400E; font-weight: 600;">
                                    Important: When prompted in the app, please set your new personal password immediately.
                                </div>
                            </div>
                            <p style="font-size: 12px; color: #94A3B8; margin: 0;">
                                If you did not request this password reset, please report it to the SISTec Transport Desk.
                            </p>
                        </td>
                    </tr>
                    <tr>
                        <td style="background-color: #F1F5F9; padding: 18px 30px; text-align: center; border-top: 1px solid #E2E8F0; font-size: 11px; color: #64748B;">
                            © ${year} Sagar Group of Institutions (SISTec), Bhopal • SISTec Chalo Smart Transit
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
    `;
}

/**
 * Sends Password Reset Email with Temporary Password
 */
async function sendPasswordResetEmail(email, name, username, temporaryPassword, role = 'user') {
    if (!email || !email.includes('@')) {
        return { success: false, error: 'Invalid recipient email address' };
    }

    const htmlContent = buildPasswordResetEmailHtml({ name, username, temporaryPassword, role });
    const subject = `SISTec Chalo: Temporary Password for Account Recovery (${username})`;
    const deliveryErrors = [];

    // 1. Try Brevo
    const brevoApiKey = process.env.BREVO_API_KEY || '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';
    if (brevoApiKey) {
        try {
            const response = await fetch('https://api.brevo.com/v3/smtp/email', {
                method: 'POST',
                headers: {
                    'accept': 'application/json',
                    'api-key': brevoApiKey.trim(),
                    'content-type': 'application/json'
                },
                body: JSON.stringify({
                    sender: { name: 'SISTec Chalo Transport', email: 'denimhajare@gmail.com' },
                    to: [{ email: email.trim(), name: name || username }],
                    subject: subject,
                    htmlContent: htmlContent,
                    textContent: `Dear ${name || username},\n\nYour temporary password for SISTec Chalo is: ${temporaryPassword}\n\nPlease enter this temporary password in the app and set your new password.\n\nSISTec Chalo Team`
                })
            });

            if (response.ok) {
                const resData = await response.json();
                console.log(`✅ [Brevo API Sent Reset] Email delivered to ${email}. MessageId: ${resData.messageId}`);
                return { success: true, provider: 'Brevo API', messageId: resData.messageId };
            } else {
                const errJson = await response.json().catch(() => ({ message: response.statusText }));
                deliveryErrors.push(`Brevo: ${errJson.message || response.statusText}`);
            }
        } catch (err) {
            deliveryErrors.push(`Brevo: ${err.message}`);
        }
    }

    // 2. Try SMTP
    const user = (process.env.SMTP_USER && process.env.SMTP_USER.trim().length > 0) ? process.env.SMTP_USER.trim() : 'denimhajare@gmail.com';
    const rawPass = (process.env.SMTP_PASS && process.env.SMTP_PASS.trim().length > 0) ? process.env.SMTP_PASS.trim() : 'ydxpebcwzefkalmy';
    const cleanPass = rawPass.replace(/\s+/g, '');

    if (user && cleanPass) {
        try {
            const host = process.env.SMTP_HOST || 'smtp.gmail.com';
            const port = parseInt(process.env.SMTP_PORT) || 587;
            const isGmail = host.includes('gmail.com') || user.includes('@gmail.com');

            const transporter = nodemailer.createTransport(isGmail
                ? { service: 'gmail', auth: { user: user.trim(), pass: cleanPass } }
                : { host: host.trim(), port: port, secure: port === 465, auth: { user: user.trim(), pass: cleanPass }, tls: { rejectUnauthorized: false } }
            );

            const info = await transporter.sendMail({
                from: `"SISTec Chalo" <${user.trim()}>`,
                to: email.trim(),
                subject: subject,
                html: htmlContent,
                text: `Dear ${name || username},\n\nYour temporary password for SISTec Chalo is: ${temporaryPassword}\n\nPlease enter this temporary password in the app and set your new password.\n\nSISTec Chalo Team`
            });

            console.log(`✅ [SMTP Sent Reset] Email delivered to ${email}. MessageId: ${info.messageId}`);
            return { success: true, provider: isGmail ? 'Gmail SMTP' : 'Custom SMTP', messageId: info.messageId };
        } catch (smtpErr) {
            deliveryErrors.push(`SMTP: ${smtpErr.message}`);
        }
    }

    console.warn(`⚠️ [Password Reset Email Fallback] Errors: ${deliveryErrors.join(' | ')}`);
    return { success: false, error: deliveryErrors.join(' | ') };
}

module.exports = {
    sendCredentialsEmail,
    buildCredentialsEmailHtml,
    sendPasswordResetEmail,
    buildPasswordResetEmailHtml
};

