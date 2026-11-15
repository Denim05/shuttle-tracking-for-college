/**
 * SISTec Chalo — Automated Encrypted Production Backup & Isolated Restore Verification
 *
 * Pipeline:
 *   mongodump (read-only) -> non-empty check -> AES-256-GCM V2 encryption ->
 *   SHA-256 integrity file -> private Backblaze B2 upload -> retention pruning ->
 *   download verification -> SHA-256 check -> decrypt verification ->
 *   isolated local mongorestore (sistecChalo_restore_verify) ->
 *   collection sanity checks -> guaranteed cleanup
 *
 * Security & Isolation Guarantees:
 * - Zero secrets are logged, written to disk, or embedded in filenames.
 * - Restore verification ONLY targets local 127.0.0.1:27017 / sistecChalo_restore_verify.
 * - Explicitly refuses 'sistecChalo' or any remote/Atlas host as a restore target.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFile } = require('child_process');
const mongoose = require('mongoose');
const {
    encryptArchive,
    decryptArchive,
    secureWipeFile
} = require('./authenticated_backup');

const PRODUCTION_DB_NAME = 'sistecChalo';
const RESTORE_VERIFY_DB_NAME = 'sistecChalo_restore_verify';
const ALLOWED_RESTORE_HOSTS = new Set(['127.0.0.1', 'localhost']);
const DEFAULT_RESTORE_URI = 'mongodb://127.0.0.1:27017';
const DEFAULT_RETENTION_DAYS = 30;
const REQUIRED_COLLECTIONS = ['routes', 'buses', 'drivers', 'managers', 'users', 'livetriplogs'];

const REQUIRED_ENV_VARS = [
    'MONGODB_BACKUP_URI',
    'BACKUP_PASSPHRASE',
    'B2_KEY_ID',
    'B2_APPLICATION_KEY',
    'B2_ENDPOINT',
    'B2_BUCKET'
];

/**
 * Validates that all required secrets and endpoints are present without exposing values.
 * @param {NodeJS.ProcessEnv|Object} env
 */
function validateRequiredEnv(env = process.env) {
    const missing = REQUIRED_ENV_VARS.filter((key) => {
        const val = env[key];
        return typeof val !== 'string' || val.trim().length === 0;
    });
    if (missing.length > 0) {
        throw new Error(`FATAL: Missing required environment variable(s): ${missing.join(', ')}`);
    }

    if (env.BACKUP_PASSPHRASE.trim().length < 16) {
        throw new Error('FATAL: BACKUP_PASSPHRASE must be at least 16 characters.');
    }

    let endpointUrl;
    try {
        endpointUrl = new URL(env.B2_ENDPOINT.trim());
    } catch (_) {
        throw new Error('FATAL: B2_ENDPOINT must be a valid URL.');
    }
    if (endpointUrl.protocol !== 'https:') {
        throw new Error('FATAL: B2_ENDPOINT must use HTTPS.');
    }

    const bucket = env.B2_BUCKET.trim();
    if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(bucket)) {
        throw new Error('FATAL: B2_BUCKET contains invalid bucket name characters.');
    }
}

/**
 * Generates a sanitized UTC backup filename containing zero secrets or path characters.
 * @param {Date} [date]
 * @returns {string}
 */
function buildBackupFilename(date = new Date()) {
    const iso = date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    const filename = `sistecChalo_${iso}.archive.enc`;
    if (!/^[a-zA-Z0-9_.-]+$/.test(filename) || filename.includes('..')) {
        throw new Error('FATAL: Generated backup filename failed sanitization.');
    }
    return filename;
}

/**
 * Ensures a file exists and has a strictly positive byte size.
 * @param {string} filePath
 * @param {string} [label]
 * @returns {number} File size in bytes
 */
function validateNonEmptyFile(filePath, label = 'file') {
    if (!filePath || !fs.existsSync(filePath)) {
        throw new Error(`FATAL: Expected ${label} is missing.`);
    }
    const stat = fs.statSync(filePath);
    if (!stat.isFile() || stat.size <= 0) {
        throw new Error(`FATAL: Expected ${label} is empty (0 bytes).`);
    }
    return stat.size;
}

/**
 * Computes SHA-256 hex digest for a file.
 * @param {string} filePath
 * @returns {string}
 */
function computeSha256(filePath) {
    validateNonEmptyFile(filePath, 'checksum target');
    const buf = fs.readFileSync(filePath);
    return crypto.createHash('sha256').update(buf).digest('hex');
}

/**
 * Writes a standard `<sha256>  <basename>` integrity file.
 * @param {string} filePath
 * @param {string} shaFilePath
 * @returns {string} Expected SHA-256 hex digest
 */
function writeSha256File(filePath, shaFilePath) {
    const digest = computeSha256(filePath);
    const basename = path.basename(filePath);
    fs.writeFileSync(shaFilePath, `${digest}  ${basename}\n`, 'utf8');
    validateNonEmptyFile(shaFilePath, 'SHA-256 integrity file');
    return digest;
}

/**
 * Verifies a file against its `.sha256` integrity file.
 * @param {string} filePath
 * @param {string} shaFilePath
 * @returns {string} Verified SHA-256 hex digest
 */
function verifySha256File(filePath, shaFilePath) {
    validateNonEmptyFile(shaFilePath, 'SHA-256 integrity file');
    const content = fs.readFileSync(shaFilePath, 'utf8').trim();
    const match = content.match(/^([a-f0-9]{64})\s+\S+$/i);
    if (!match) {
        throw new Error('FATAL: Malformed SHA-256 integrity file.');
    }
    const expected = match[1].toLowerCase();
    const actual = computeSha256(filePath).toLowerCase();
    if (actual !== expected) {
        throw new Error('FATAL: SHA-256 integrity verification failed (checksum mismatch).');
    }
    return actual;
}

/**
 * Hard guard ensuring restore verification NEVER targets production 'sistecChalo' or any remote host.
 * @param {Object} params
 * @param {string} params.restoreUri
 * @param {string} params.restoreDb
 * @param {string} [params.backupUri]
 */
function assertIsolatedRestoreTarget({ restoreUri, restoreDb, backupUri = '' }) {
    if (!restoreDb || typeof restoreDb !== 'string') {
        throw new Error('FATAL: Restore database name is required.');
    }
    const cleanDb = restoreDb.trim();
    if (cleanDb === PRODUCTION_DB_NAME) {
        throw new Error(`FATAL: Refusing restore into production database '${PRODUCTION_DB_NAME}'.`);
    }
    if (cleanDb !== RESTORE_VERIFY_DB_NAME) {
        throw new Error(`FATAL: Restore database must be '${RESTORE_VERIFY_DB_NAME}', got '${cleanDb}'.`);
    }

    if (!restoreUri || typeof restoreUri !== 'string') {
        throw new Error('FATAL: Restore URI is required.');
    }
    const cleanUri = restoreUri.trim();
    if (backupUri && cleanUri === backupUri.trim()) {
        throw new Error('FATAL: Restore URI must never match MONGODB_BACKUP_URI.');
    }
    if (/^mongodb\+srv:\/\//i.test(cleanUri) || cleanUri.includes('mongodb.net')) {
        throw new Error('FATAL: Refusing non-local/Atlas URI for restore verification.');
    }

    let parsed;
    try {
        parsed = new URL(cleanUri);
    } catch (_) {
        throw new Error('FATAL: Invalid restore MongoDB URI.');
    }
    if (parsed.protocol !== 'mongodb:') {
        throw new Error('FATAL: Restore URI must use mongodb:// protocol.');
    }
    if (!ALLOWED_RESTORE_HOSTS.has(parsed.hostname)) {
        throw new Error(`FATAL: Refusing non-local restore host '${parsed.hostname}'.`);
    }
}

/**
 * Promisified execFile wrapper that rejects on non-zero exit without leaking env secrets.
 */
function defaultExecFile(cmd, args, options = {}) {
    return new Promise((resolve, reject) => {
        execFile(cmd, args, { maxBuffer: 10 * 1024 * 1024, ...options }, (err, stdout, stderr) => {
            if (err) {
                const msg = (stderr || err.message || 'Command failed').toString().trim();
                reject(new Error(`${cmd} failed: ${msg}`));
                return;
            }
            resolve({ stdout: String(stdout || ''), stderr: String(stderr || '') });
        });
    });
}

/**
 * Default collection sanity verifier against the isolated local restore database.
 */
async function defaultVerifyRestoredCollections({ restoreUri, restoreDb, requiredCollections = REQUIRED_COLLECTIONS }) {
    assertIsolatedRestoreTarget({ restoreUri, restoreDb });
    const conn = await mongoose.createConnection(restoreUri, {
        dbName: restoreDb,
        serverSelectionTimeoutMS: 8000
    }).asPromise();

    try {
        const existingCols = (await conn.db.listCollections().toArray()).map((c) => c.name);
        const counts = {};
        for (const colName of requiredCollections) {
            if (!existingCols.includes(colName)) {
                throw new Error(`FATAL: Restored database missing required collection '${colName}'.`);
            }
            const count = await conn.db.collection(colName).countDocuments();
            if (count <= 0) {
                throw new Error(`FATAL: Restored collection '${colName}' is empty (0 documents).`);
            }
            counts[colName] = count;
        }
        await conn.db.dropDatabase();
        return counts;
    } finally {
        await conn.close().catch(() => {});
    }
}

/**
 * Prunes encrypted backup objects in Backblaze B2 older than retentionDays.
 */
async function pruneExpiredB2Objects({ execFileFn, b2Env, bucket, endpoint, retentionDays }) {
    const { stdout } = await execFileFn('aws', [
        's3api', 'list-objects-v2',
        '--bucket', bucket,
        '--prefix', 'backups/',
        '--endpoint-url', endpoint,
        '--output', 'json'
    ], { env: b2Env });

    if (!stdout || !stdout.trim()) return 0;
    const parsed = JSON.parse(stdout);
    const contents = Array.isArray(parsed.Contents) ? parsed.Contents : [];
    const cutoffMs = Date.now() - (retentionDays * 24 * 60 * 60 * 1000);

    let deleted = 0;
    for (const obj of contents) {
        if (!obj || !obj.Key || !obj.LastModified) continue;
        const modifiedMs = Date.parse(obj.LastModified);
        if (!Number.isFinite(modifiedMs) || modifiedMs >= cutoffMs) continue;

        await execFileFn('aws', [
            's3', 'rm', `s3://${bucket}/${obj.Key}`,
            '--endpoint-url', endpoint
        ], { env: b2Env });
        deleted++;
    }
    return deleted;
}

/**
 * Runs the full encrypted backup, offsite upload, retention, and isolated restore verification pipeline.
 */
async function runBackupAndVerifyPipeline({
    env = process.env,
    execFileFn = defaultExecFile,
    verifyCollectionsFn = defaultVerifyRestoredCollections,
    workDir = null,
    now = new Date(),
    retentionDays = DEFAULT_RETENTION_DAYS
} = {}) {
    validateRequiredEnv(env);

    const restoreUri = (env.RESTORE_VERIFY_URI || DEFAULT_RESTORE_URI).trim();
    const restoreDb = (env.RESTORE_VERIFY_DB || RESTORE_VERIFY_DB_NAME).trim();
    assertIsolatedRestoreTarget({
        restoreUri,
        restoreDb,
        backupUri: env.MONGODB_BACKUP_URI
    });

    const ownedWorkDir = workDir || fs.mkdtempSync(path.join(os.tmpdir(), 'sistec_prod_backup_'));
    const verifyDir = path.join(ownedWorkDir, 'verify');
    fs.mkdirSync(verifyDir, { recursive: true });

    const encFilename = buildBackupFilename(now);
    const plainFilename = encFilename.replace(/\.enc$/, '');
    const shaFilename = `${encFilename}.sha256`;

    const plainPath = path.join(ownedWorkDir, plainFilename);
    const encPath = path.join(ownedWorkDir, encFilename);
    const shaPath = path.join(ownedWorkDir, shaFilename);

    const dlEncPath = path.join(verifyDir, encFilename);
    const dlShaPath = path.join(verifyDir, shaFilename);
    const decryptedPath = path.join(verifyDir, plainFilename);

    const bucket = env.B2_BUCKET.trim();
    const endpoint = env.B2_ENDPOINT.trim();
    const b2ObjectKey = `backups/${encFilename}`;
    const b2ShaKey = `backups/${shaFilename}`;

    const b2Env = {
        ...process.env,
        AWS_ACCESS_KEY_ID: env.B2_KEY_ID.trim(),
        AWS_SECRET_ACCESS_KEY: env.B2_APPLICATION_KEY.trim(),
        AWS_DEFAULT_REGION: env.B2_REGION ? env.B2_REGION.trim() : 'us-west-004'
    };

    try {
        console.log(`📦 [1/11] Running read-only mongodump for '${PRODUCTION_DB_NAME}'...`);
        await execFileFn('mongodump', [
            `--uri=${env.MONGODB_BACKUP_URI.trim()}`,
            `--db=${PRODUCTION_DB_NAME}`,
            `--archive=${plainPath}`,
            '--gzip'
        ]);

        console.log('🔍 [2/11] Validating non-empty dump archive...');
        const dumpBytes = validateNonEmptyFile(plainPath, 'mongodump archive');

        console.log('🔐 [3/11] Encrypting archive with AES-256-GCM V2 (600,000 PBKDF2 rounds)...');
        const encMeta = await encryptArchive({
            inputPath: plainPath,
            outputPath: encPath,
            passphrase: env.BACKUP_PASSPHRASE,
            wipeSource: true
        });
        validateNonEmptyFile(encPath, 'encrypted archive');

        console.log('🧾 [4/11] Generating SHA-256 integrity file...');
        const expectedSha256 = writeSha256File(encPath, shaPath);

        console.log('☁️ [5/11] Uploading encrypted archive and SHA-256 to private Backblaze B2 bucket...');
        await execFileFn('aws', [
            's3', 'cp', encPath, `s3://${bucket}/${b2ObjectKey}`,
            '--endpoint-url', endpoint
        ], { env: b2Env });
        await execFileFn('aws', [
            's3', 'cp', shaPath, `s3://${bucket}/${b2ShaKey}`,
            '--endpoint-url', endpoint
        ], { env: b2Env });

        console.log(`🧹 [6/11] Applying ${retentionDays}-day B2 retention pruning...`);
        const prunedCount = await pruneExpiredB2Objects({
            execFileFn,
            b2Env,
            bucket,
            endpoint,
            retentionDays
        });

        console.log('⬇️ [7/11] Downloading uploaded objects from B2 for verification...');
        await execFileFn('aws', [
            's3', 'cp', `s3://${bucket}/${b2ObjectKey}`, dlEncPath,
            '--endpoint-url', endpoint
        ], { env: b2Env });
        await execFileFn('aws', [
            's3', 'cp', `s3://${bucket}/${b2ShaKey}`, dlShaPath,
            '--endpoint-url', endpoint
        ], { env: b2Env });
        validateNonEmptyFile(dlEncPath, 'downloaded encrypted archive');

        console.log('✅ [8/11] Verifying SHA-256 checksum...');
        verifySha256File(dlEncPath, dlShaPath);

        console.log('🔓 [9/11] Decrypting downloaded archive & validating GCM auth tag...');
        await decryptArchive({
            inputPath: dlEncPath,
            outputPath: decryptedPath,
            passphrase: env.BACKUP_PASSPHRASE
        });
        validateNonEmptyFile(decryptedPath, 'decrypted archive');

        console.log(`🧪 [10/11] Restoring into isolated local DB '${RESTORE_VERIFY_DB_NAME}'...`);
        assertIsolatedRestoreTarget({
            restoreUri,
            restoreDb,
            backupUri: env.MONGODB_BACKUP_URI
        });
        await execFileFn('mongorestore', [
            `--uri=${restoreUri}`,
            '--gzip',
            `--archive=${decryptedPath}`,
            `--nsFrom=${PRODUCTION_DB_NAME}.*`,
            `--nsTo=${RESTORE_VERIFY_DB_NAME}.*`,
            '--drop'
        ]);

        console.log('🔎 [11/11] Running collection sanity checks on isolated restored DB...');
        const collectionCounts = await verifyCollectionsFn({
            restoreUri,
            restoreDb,
            requiredCollections: REQUIRED_COLLECTIONS
        });

        return {
            status: 'PASS',
            filename: encFilename,
            dumpBytes,
            encryptedBytes: encMeta.bytesWritten,
            sha256: expectedSha256,
            prunedCount,
            collectionCounts
        };
    } finally {
        for (const sensitivePath of [plainPath, decryptedPath]) {
            if (fs.existsSync(sensitivePath)) {
                secureWipeFile(sensitivePath);
            }
        }
        try {
            fs.rmSync(ownedWorkDir, { recursive: true, force: true });
        } catch (_) {}
    }
}

if (require.main === module) {
    runBackupAndVerifyPipeline()
        .then((summary) => {
            console.log(`✅ Backup & Isolated Restore Verification COMPLETE: ${summary.filename} (${summary.encryptedBytes} bytes, sha256=${summary.sha256})`);
            process.exit(0);
        })
        .catch((err) => {
            console.error(`❌ Backup Pipeline FAILED: ${err.message}`);
            process.exit(1);
        });
}

module.exports = {
    PRODUCTION_DB_NAME,
    RESTORE_VERIFY_DB_NAME,
    DEFAULT_RESTORE_URI,
    DEFAULT_RETENTION_DAYS,
    REQUIRED_COLLECTIONS,
    REQUIRED_ENV_VARS,
    validateRequiredEnv,
    buildBackupFilename,
    validateNonEmptyFile,
    computeSha256,
    writeSha256File,
    verifySha256File,
    assertIsolatedRestoreTarget,
    pruneExpiredB2Objects,
    runBackupAndVerifyPipeline
};
