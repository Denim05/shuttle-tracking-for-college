/**
 * SISTec Chalo — Production Backup & Isolated Restore Verification Unit Tests
 *
 * Strictly unit/local-only tests:
 * - Never connects to production MongoDB Atlas or Backblaze B2.
 * - Uses temporary local directories and mocked CLI runners.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');

const {
    PRODUCTION_DB_NAME,
    RESTORE_VERIFY_DB_NAME,
    DEFAULT_RESTORE_URI,
    validateRequiredEnv,
    buildBackupFilename,
    validateNonEmptyFile,
    writeSha256File,
    verifySha256File,
    assertIsolatedRestoreTarget,
    runBackupAndVerifyPipeline
} = require('../scripts/backup_and_verify');

function makeValidEnv(overrides = {}) {
    return {
        MONGODB_BACKUP_URI: 'mongodb+srv://backup_user:placeholder@cluster0.example.mongodb.net/sistecChalo',
        BACKUP_PASSPHRASE: 'StrongTestBackupPassphrase_2026_!@#',
        B2_KEY_ID: '004testkeyid',
        B2_APPLICATION_KEY: 'K004testappkey',
        B2_ENDPOINT: 'https://s3.us-west-004.backblazeb2.com',
        B2_BUCKET: 'sistec-chalo-backups-private',
        RESTORE_VERIFY_URI: DEFAULT_RESTORE_URI,
        RESTORE_VERIFY_DB: RESTORE_VERIFY_DB_NAME,
        ...overrides
    };
}

test('SISTec Chalo — Backup & Isolated Restore Pipeline Tests', async (t) => {
    await t.test('1. Required environment validation rejects missing secrets without leaking values', () => {
        const base = makeValidEnv();
        assert.doesNotThrow(() => validateRequiredEnv(base));

        for (const key of ['MONGODB_BACKUP_URI', 'BACKUP_PASSPHRASE', 'B2_KEY_ID', 'B2_APPLICATION_KEY', 'B2_ENDPOINT', 'B2_BUCKET']) {
            const broken = { ...base, [key]: '' };
            assert.throws(
                () => validateRequiredEnv(broken),
                (err) => err.message.includes(key) && !err.message.includes(base.BACKUP_PASSPHRASE)
            );
        }

        assert.throws(() => validateRequiredEnv(makeValidEnv({ BACKUP_PASSPHRASE: 'short' })), /at least 16/);
        assert.throws(() => validateRequiredEnv(makeValidEnv({ B2_ENDPOINT: 'http://insecure.example.com' })), /HTTPS/);
    });

    await t.test('2. Backup filename sanitization produces safe UTC name with zero secrets', () => {
        const fixedDate = new Date('2026-11-15T20:05:30.123Z');
        const filename = buildBackupFilename(fixedDate);
        assert.equal(filename, 'sistecChalo_20261115T200530Z.archive.enc');
        assert.ok(/^[a-zA-Z0-9_.-]+$/.test(filename));
        assert.ok(!filename.includes('..'));
    });

    await t.test('3. Non-empty archive validation rejects missing and 0-byte files', () => {
        const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sistec_nonempty_'));
        t.after(() => fs.rmSync(tempDir, { recursive: true, force: true }));

        const missing = path.join(tempDir, 'missing.archive');
        assert.throws(() => validateNonEmptyFile(missing, 'archive'), /missing/);

        const empty = path.join(tempDir, 'empty.archive');
        fs.writeFileSync(empty, '');
        assert.throws(() => validateNonEmptyFile(empty, 'archive'), /empty/);

        const valid = path.join(tempDir, 'valid.archive');
        fs.writeFileSync(valid, 'non-empty-bson-payload');
        assert.equal(validateNonEmptyFile(valid, 'archive'), 22);
    });

    await t.test('4. SHA-256 checksum generation and tamper detection', () => {
        const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sistec_sha_'));
        t.after(() => fs.rmSync(tempDir, { recursive: true, force: true }));

        const dataFile = path.join(tempDir, 'test.archive.enc');
        const shaFile = path.join(tempDir, 'test.archive.enc.sha256');
        fs.writeFileSync(dataFile, 'encrypted-payload-bytes');

        const digest = writeSha256File(dataFile, shaFile);
        assert.equal(digest.length, 64);
        assert.equal(verifySha256File(dataFile, shaFile), digest);

        // Tamper 1 byte in encrypted file -> must fail
        fs.writeFileSync(dataFile, 'encrypted-payload-byteZ');
        assert.throws(() => verifySha256File(dataFile, shaFile), /checksum mismatch/);
    });

    await t.test('5. Restore target guard accepts isolated local target and rejects production or remote hosts', () => {
        assert.doesNotThrow(() =>
            assertIsolatedRestoreTarget({
                restoreUri: 'mongodb://127.0.0.1:27017',
                restoreDb: RESTORE_VERIFY_DB_NAME,
                backupUri: 'mongodb+srv://user:pass@cluster0.mongodb.net/sistecChalo'
            })
        );

        // Reject production database name
        assert.throws(
            () => assertIsolatedRestoreTarget({ restoreUri: 'mongodb://127.0.0.1:27017', restoreDb: PRODUCTION_DB_NAME }),
            /Refusing restore into production database/
        );

        // Reject arbitrary non-verify database name
        assert.throws(
            () => assertIsolatedRestoreTarget({ restoreUri: 'mongodb://127.0.0.1:27017', restoreDb: 'other_db' }),
            /must be 'sistecChalo_restore_verify'/
        );

        // Reject non-local / Atlas restore host
        assert.throws(
            () => assertIsolatedRestoreTarget({ restoreUri: 'mongodb+srv://cluster0.mongodb.net', restoreDb: RESTORE_VERIFY_DB_NAME }),
            /Refusing non-local\/Atlas URI/
        );
        assert.throws(
            () => assertIsolatedRestoreTarget({ restoreUri: 'mongodb://10.0.0.5:27017', restoreDb: RESTORE_VERIFY_DB_NAME }),
            /Refusing non-local restore host/
        );

        // Reject matching backup URI
        assert.throws(
            () => assertIsolatedRestoreTarget({
                restoreUri: 'mongodb://127.0.0.1:27017',
                restoreDb: RESTORE_VERIFY_DB_NAME,
                backupUri: 'mongodb://127.0.0.1:27017'
            }),
            /must never match MONGODB_BACKUP_URI/
        );
    });

    await t.test('6. Full pipeline succeeds with mocked CLI tools and cleans up temp workspace', async () => {
        const workDir = path.join(os.tmpdir(), `sistec_pipe_ok_${Date.now()}`);
        const b2MockStore = new Map();

        const mockExecFile = async (cmd, args) => {
            if (cmd === 'mongodump') {
                const archiveArg = args.find((a) => a.startsWith('--archive='));
                const outPath = archiveArg.slice('--archive='.length);
                fs.writeFileSync(outPath, Buffer.from('MOCK_GZIP_MONGODUMP_ARCHIVE_PAYLOAD'));
                return { stdout: '', stderr: '' };
            }
            if (cmd === 'aws' && args[0] === 's3' && args[1] === 'cp') {
                const src = args[2];
                const dst = args[3];
                if (dst.startsWith('s3://')) {
                    b2MockStore.set(dst, fs.readFileSync(src));
                } else if (src.startsWith('s3://')) {
                    const buf = b2MockStore.get(src);
                    if (!buf) throw new Error('NoSuchKey');
                    fs.writeFileSync(dst, buf);
                }
                return { stdout: '', stderr: '' };
            }
            if (cmd === 'aws' && args[0] === 's3api' && args[1] === 'list-objects-v2') {
                return { stdout: JSON.stringify({ Contents: [] }), stderr: '' };
            }
            if (cmd === 'mongorestore') {
                assert.ok(args.includes('--nsFrom=sistecChalo.*'));
                assert.ok(args.includes('--nsTo=sistecChalo_restore_verify.*'));
                return { stdout: '', stderr: '' };
            }
            throw new Error(`Unexpected command: ${cmd}`);
        };

        const result = await runBackupAndVerifyPipeline({
            env: makeValidEnv(),
            execFileFn: mockExecFile,
            verifyCollectionsFn: async () => ({ routes: 37, buses: 37, drivers: 57, managers: 4, users: 42, livetriplogs: 79 }),
            workDir,
            now: new Date('2026-11-15T20:05:30.000Z')
        });

        assert.equal(result.status, 'PASS');
        assert.equal(result.filename, 'sistecChalo_20261115T200530Z.archive.enc');
        assert.equal(b2MockStore.size, 2);
        assert.equal(fs.existsSync(workDir), false, 'Temp working directory must be cleaned up');
    });

    await t.test('7. Failure propagation and guaranteed cleanup on gate failures', async () => {
        const scenarios = [
            { name: 'mongodump non-zero', failOn: 'mongodump', match: /mongodump failed/ },
            { name: 'empty archive', failOn: 'empty_dump', match: /empty/ },
            { name: 'B2 upload failure', failOn: 'upload', match: /upload error/ },
            { name: 'checksum mismatch', failOn: 'corrupt_download', match: /checksum mismatch/ },
            { name: 'mongorestore failure', failOn: 'mongorestore', match: /restore error/ },
            { name: 'collection sanity failure', failOn: 'sanity', match: /missing required collection/ }
        ];

        for (const sc of scenarios) {
            const workDir = path.join(os.tmpdir(), `sistec_pipe_fail_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`);
            const b2MockStore = new Map();

            const mockExecFile = async (cmd, args) => {
                if (cmd === 'mongodump') {
                    if (sc.failOn === 'mongodump') throw new Error('mongodump failed');
                    const outPath = args.find((a) => a.startsWith('--archive=')).slice('--archive='.length);
                    fs.writeFileSync(outPath, sc.failOn === 'empty_dump' ? Buffer.alloc(0) : Buffer.from('VALID_ARCHIVE'));
                    return { stdout: '', stderr: '' };
                }
                if (cmd === 'aws' && args[0] === 's3' && args[1] === 'cp') {
                    const src = args[2];
                    const dst = args[3];
                    if (dst.startsWith('s3://')) {
                        if (sc.failOn === 'upload') throw new Error('upload error');
                        b2MockStore.set(dst, fs.readFileSync(src));
                    } else {
                        const buf = Buffer.from(b2MockStore.get(src));
                        if (sc.failOn === 'corrupt_download' && dst.endsWith('.enc')) {
                            buf[buf.length - 1] ^= 0xff;
                        }
                        fs.writeFileSync(dst, buf);
                    }
                    return { stdout: '', stderr: '' };
                }
                if (cmd === 'aws' && args[0] === 's3api') {
                    return { stdout: JSON.stringify({ Contents: [] }), stderr: '' };
                }
                if (cmd === 'mongorestore') {
                    if (sc.failOn === 'mongorestore') throw new Error('restore error');
                    return { stdout: '', stderr: '' };
                }
                return { stdout: '', stderr: '' };
            };

            await assert.rejects(
                () => runBackupAndVerifyPipeline({
                    env: makeValidEnv(),
                    execFileFn: mockExecFile,
                    verifyCollectionsFn: async () => {
                        if (sc.failOn === 'sanity') throw new Error('FATAL: Restored database missing required collection.');
                        return { routes: 1 };
                    },
                    workDir
                }),
                sc.match
            );

            assert.equal(fs.existsSync(workDir), false, `Workdir must be cleaned up after ${sc.name}`);
        }
    });
});
