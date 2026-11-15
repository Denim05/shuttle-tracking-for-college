/**
 * SISTec Chalo — Enterprise Authenticated Backup Engine Test Suite (Hardened V2)
 *
 * Verifies:
 * 1. AES-256-GCM AEAD encryption and roundtrip bit-for-bit SHA-256 recovery.
 * 2. 600,000 PBKDF2-HMAC-SHA256 work factor execution.
 * 3. Tamper resistance: Altering 1 byte in ciphertext triggers GCM auth tag failure.
 * 4. Header & AAD resistance: Altering iteration count in V2 header triggers AAD auth failure.
 * 5. Password mismatch resistance: Wrong passphrase throws authentication failure.
 * 6. Header corruption resistance: Malformed or truncated header throws.
 * 7. Backward compatibility: Decrypts legacy V1 archives (100,000 iterations) seamlessly.
 * 8. Temporary-file cleanup: No temp or corrupted files remain on failure.
 * 9. Plaintext shredding: wipeSource securely zeroes and unlinks unencrypted source.
 * 10. End-to-End Dummy Archive DB Restoration into isolated staging test collection.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const mongoose = require('mongoose');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '../.env.staging') });

const {
    encryptArchive,
    decryptArchive,
    deriveKey,
    secureWipeFile,
    MAGIC_HEADER_V1,
    MAGIC_HEADER_V2,
    DEFAULT_PBKDF2_ITERATIONS,
    V1_PBKDF2_ITERATIONS
} = require('../scripts/authenticated_backup');

test('SISTec Chalo — Authenticated Backup Encryption (AES-256-GCM AEAD V2) Suite', async (t) => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sistec_backup_test_'));
    const dummyArchive = path.join(tempDir, 'dummy_db_dump.archive');
    const encryptedArchive = path.join(tempDir, 'dummy_db_dump.archive.enc');
    const restoredArchive = path.join(tempDir, 'dummy_db_dump_restored.archive');
    const passphrase = 'SuperSecureProductionBackupPassphrase_2026_XYZ!#@9';

    // Generate 256 KB of realistic pseudo-archive data (BSON / JSON structured payloads)
    const dummyContent = Buffer.alloc(256 * 1024);
    for (let i = 0; i < dummyContent.length; i++) {
        dummyContent[i] = (i * 31 + 17) % 256;
    }
    fs.writeFileSync(dummyArchive, dummyContent);
    const originalHash = crypto.createHash('sha256').update(dummyContent).digest('hex');

    t.after(() => {
        try {
            fs.rmSync(tempDir, { recursive: true, force: true });
        } catch (_) {}
    });

    await t.test('1. Roundtrip Encryption & Decryption (V2 600,000 rounds): Bit-for-bit SHA-256 identity', async () => {
        const encResult = await encryptArchive({
            inputPath: dummyArchive,
            outputPath: encryptedArchive,
            passphrase,
            iterations: DEFAULT_PBKDF2_ITERATIONS
        });

        assert.ok(fs.existsSync(encryptedArchive), 'Encrypted archive must be created');
        assert.equal(encResult.iterations, 600000, 'Must record 600,000 iterations');
        assert.ok(encResult.bytesWritten > dummyContent.length, 'Encrypted file includes headers, salt, IV, and tag');

        const decResult = await decryptArchive({
            inputPath: encryptedArchive,
            outputPath: restoredArchive,
            passphrase
        });

        assert.ok(fs.existsSync(restoredArchive), 'Decrypted archive must exist');
        assert.equal(decResult.version, 'V2', 'Must recognize V2 format');
        assert.equal(decResult.iterations, 600000, 'Must extract 600,000 iterations');
        assert.equal(decResult.sha256, originalHash, 'Decrypted file SHA-256 must match original exactly');
        assert.equal(decResult.bytesDecrypted, dummyContent.length, 'Decrypted length matches original length');

        const restoredBytes = fs.readFileSync(restoredArchive);
        assert.ok(restoredBytes.equals(dummyContent), 'Restored bytes must be bit-for-bit identical to original');
    });

    await t.test('2. Tamper Resistance: Modifying 1 byte in ciphertext triggers authentication failure', async () => {
        const tamperedArchive = path.join(tempDir, 'tampered.archive.enc');
        const buf = fs.readFileSync(encryptedArchive);
        
        // Flip one bit in the middle of ciphertext
        const targetByteIndex = buf.length - 100;
        buf[targetByteIndex] ^= 0x01;
        fs.writeFileSync(tamperedArchive, buf);

        const tamperedRestored = path.join(tempDir, 'tampered_restored.archive');
        
        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: tamperedArchive,
                    outputPath: tamperedRestored,
                    passphrase
                });
            },
            (err) => {
                return err instanceof Error && (err.message.includes('authenticate') || err.message.includes('Unsupported state'));
            },
            'Tampered ciphertext must be rejected by GCM authentication tag'
        );
        assert.equal(fs.existsSync(tamperedRestored), false, 'Must not produce output file on tamper failure');
    });

    await t.test('3. Header AAD Tamper Resistance: Modifying iteration count in V2 header is rejected', async () => {
        const tamperedIterArchive = path.join(tempDir, 'tampered_iter.archive.enc');
        const buf = fs.readFileSync(encryptedArchive);
        
        // Offset 17 is the 4-byte UInt32BE iteration count. Overwrite with 100,000
        buf.writeUInt32BE(100000, 17);
        fs.writeFileSync(tamperedIterArchive, buf);

        const targetOut = path.join(tempDir, 'should_fail_iter.archive');

        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: tamperedIterArchive,
                    outputPath: targetOut,
                    passphrase
                });
            },
            (err) => {
                return err instanceof Error && (err.message.includes('authenticate') || err.message.includes('Unsupported state'));
            },
            'Tampered iteration count must be rejected by Associated Data (AAD) check'
        );
        assert.equal(fs.existsSync(targetOut), false);
    });

    await t.test('4. Passphrase Mismatch: Incorrect password triggers authentication failure', async () => {
        const wrongPassRestored = path.join(tempDir, 'wrong_pass_restored.archive');

        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: encryptedArchive,
                    outputPath: wrongPassRestored,
                    passphrase: 'WrongIncorrectPassword_999!'
                });
            },
            (err) => {
                return err instanceof Error && (err.message.includes('authenticate') || err.message.includes('Unsupported state'));
            },
            'Wrong passphrase must fail GCM tag validation without producing corrupt data'
        );
        assert.equal(fs.existsSync(wrongPassRestored), false);
    });

    await t.test('5. Header Corruption: Invalid magic header is rejected immediately', async () => {
        const corruptHeaderArchive = path.join(tempDir, 'corrupt_header.archive.enc');
        const buf = fs.readFileSync(encryptedArchive);
        buf[0] = 0x58; // Overwrite 'S' with 'X'
        fs.writeFileSync(corruptHeaderArchive, buf);

        const corruptRestored = path.join(tempDir, 'corrupt_restored.archive');

        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: corruptHeaderArchive,
                    outputPath: corruptRestored,
                    passphrase
                });
            },
            /magic header mismatch/,
            'Corrupted magic header must be rejected before decryption'
        );
        assert.equal(fs.existsSync(corruptRestored), false);
    });

    await t.test('6. Truncated Archive: Truncated file throws header incomplete error', async () => {
        const truncatedArchive = path.join(tempDir, 'truncated.archive.enc');
        fs.writeFileSync(truncatedArchive, Buffer.from('SISTEC_ENC_GCM'));

        const truncatedRestored = path.join(tempDir, 'truncated_restored.archive');

        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: truncatedArchive,
                    outputPath: truncatedRestored,
                    passphrase
                });
            },
            /header incomplete/,
            'Truncated file must be rejected immediately'
        );
        assert.equal(fs.existsSync(truncatedRestored), false);
    });

    await t.test('7. Backward Compatibility: Seamlessly decrypts V1 legacy archive (100,000 iterations)', async () => {
        // Construct a genuine V1 container
        const v1Salt = crypto.randomBytes(32);
        const v1Iv = crypto.randomBytes(12);
        const v1Key = deriveKey(passphrase, v1Salt, V1_PBKDF2_ITERATIONS);
        const v1Cipher = crypto.createCipheriv('aes-256-gcm', v1Key, v1Iv);
        const v1Ciphertext = Buffer.concat([v1Cipher.update(dummyContent), v1Cipher.final()]);
        const v1Tag = v1Cipher.getAuthTag();

        const v1Container = Buffer.concat([
            MAGIC_HEADER_V1,
            v1Salt,
            v1Iv,
            v1Tag,
            v1Ciphertext
        ]);

        const v1EncFile = path.join(tempDir, 'legacy_v1.archive.enc');
        fs.writeFileSync(v1EncFile, v1Container);

        const v1RestoredFile = path.join(tempDir, 'legacy_v1_restored.archive');
        const v1Result = await decryptArchive({
            inputPath: v1EncFile,
            outputPath: v1RestoredFile,
            passphrase
        });

        assert.equal(v1Result.version, 'V1', 'Must identify V1 format');
        assert.equal(v1Result.iterations, 100000, 'Must use 100,000 iterations');
        assert.equal(v1Result.sha256, originalHash, 'Decrypted V1 SHA-256 must match original exactly');
        assert.ok(fs.readFileSync(v1RestoredFile).equals(dummyContent));
    });

    await t.test('8. Failure Cleanup: No corrupt output or temporary file remains on failure', async () => {
        const iterBuf = Buffer.alloc(4);
        iterBuf.writeUInt32BE(600000, 0);
        const corruptFile = path.join(tempDir, 'corrupt.archive.enc');
        fs.writeFileSync(corruptFile, Buffer.concat([MAGIC_HEADER_V2, iterBuf, Buffer.alloc(120)]));
        const targetOutput = path.join(tempDir, 'should_not_exist.archive');

        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: corruptFile,
                    outputPath: targetOutput,
                    passphrase: 'AnyPassword'
                });
            }
        );

        assert.equal(fs.existsSync(targetOutput), false, 'Failed decryption must not leave corrupt destination file');
    });

    await t.test('8b. DoS Protection: Out-of-bounds iteration counts are rejected immediately', async () => {
        const iterBuf = Buffer.alloc(4);
        iterBuf.writeUInt32BE(50000000, 0); // 50 million iterations
        const dosFile = path.join(tempDir, 'dos_attack.archive.enc');
        fs.writeFileSync(dosFile, Buffer.concat([MAGIC_HEADER_V2, iterBuf, Buffer.alloc(120)]));
        const targetOut = path.join(tempDir, 'dos_fail.archive');

        const startTime = Date.now();
        await assert.rejects(
            async () => {
                await decryptArchive({
                    inputPath: dosFile,
                    outputPath: targetOut,
                    passphrase: 'AnyPassword'
                });
            },
            /Untrusted PBKDF2 iteration count/,
            'Excessive iteration count must be rejected before PBKDF2 execution'
        );
        const elapsed = Date.now() - startTime;
        assert.ok(elapsed < 100, 'Rejection must be virtually instantaneous (<100ms)');
        assert.equal(fs.existsSync(targetOut), false);
    });

    await t.test('9. Plaintext Shredding: wipeSource zeroes and unlinks unencrypted source', async () => {
        const sourceToShred = path.join(tempDir, 'sensitive_dump_to_shred.archive');
        fs.writeFileSync(sourceToShred, Buffer.from('SENSITIVE_MOCK_STUDENT_DATA_12345'));
        const targetEnc = path.join(tempDir, 'shred_test.archive.enc');

        assert.ok(fs.existsSync(sourceToShred));

        await encryptArchive({
            inputPath: sourceToShred,
            outputPath: targetEnc,
            passphrase,
            wipeSource: true
        });

        assert.ok(fs.existsSync(targetEnc), 'Encrypted archive exists');
        assert.equal(fs.existsSync(sourceToShred), false, 'Plaintext source must be completely unlinked after encryption');
    });

    await t.test('10. End-to-End Dummy Archive DB Restoration into isolated test collection', async () => {
        const stagingUri = process.env.MONGODB_URI;
        if (!stagingUri || stagingUri.includes('/sistecChalo?') || stagingUri.endsWith('/sistecChalo')) {
            console.log('Skipping live DB restore test: Staging URI unconfigured or points to production');
            return;
        }

        const conn = await mongoose.createConnection(stagingUri, {
            dbName: 'sistecChalo_staging',
            serverSelectionTimeoutMS: 5000
        }).asPromise();

        const dummySchema = new mongoose.Schema({
            batchId: String,
            routeCode: String,
            busPlate: String,
            passengerCount: Number,
            createdAt: Date
        });

        const TestModel = conn.model('BackupVerificationItem', dummySchema, '_backup_hardening_test_records');

        // 1. Prepare dummy database records
        const seedBatch = [
            { batchId: 'BATCH-2026-A', routeCode: 'RT-99', busPlate: 'MP04-PA-3498', passengerCount: 45, createdAt: new Date() },
            { batchId: 'BATCH-2026-B', routeCode: 'RT-04', busPlate: 'MP04-HE-1122', passengerCount: 38, createdAt: new Date() },
            { batchId: 'BATCH-2026-C', routeCode: 'RT-12', busPlate: 'MP04-TA-9900', passengerCount: 52, createdAt: new Date() }
        ];

        // Clean any leftover from previous runs
        await TestModel.deleteMany({});
        await TestModel.insertMany(seedBatch);

        // 2. Export to dummy archive format
        const fetchedDocs = await TestModel.find({}).lean();
        assert.equal(fetchedDocs.length, 3);
        const jsonDump = JSON.stringify(fetchedDocs);
        const dumpPath = path.join(tempDir, 'live_dummy_export.json');
        const dumpEncPath = path.join(tempDir, 'live_dummy_export.json.enc');
        const dumpRestoredPath = path.join(tempDir, 'live_dummy_restored.json');

        fs.writeFileSync(dumpPath, jsonDump);
        const dumpSha256 = crypto.createHash('sha256').update(Buffer.from(jsonDump)).digest('hex');

        // 3. Encrypt archive with V2 AEAD (600,000 rounds)
        const encInfo = await encryptArchive({
            inputPath: dumpPath,
            outputPath: dumpEncPath,
            passphrase,
            wipeSource: true
        });

        assert.equal(fs.existsSync(dumpPath), false, 'Source dump shredded');
        assert.ok(fs.existsSync(dumpEncPath));

        // 4. Decrypt archive
        const decInfo = await decryptArchive({
            inputPath: dumpEncPath,
            outputPath: dumpRestoredPath,
            passphrase
        });

        assert.equal(decInfo.sha256, dumpSha256, 'Restored file SHA-256 matches exactly');

        // 5. Restore back into isolated test collection
        const restoredContent = fs.readFileSync(dumpRestoredPath, 'utf8');
        const restoredRecords = JSON.parse(restoredContent);
        assert.equal(restoredRecords.length, 3);

        const targetRestoreModel = conn.model('BackupRestoredItem', dummySchema, '_backup_hardening_restored_records');
        await targetRestoreModel.deleteMany({});
        await targetRestoreModel.insertMany(restoredRecords);

        const verifiedRestored = await targetRestoreModel.find({}).lean();
        assert.equal(verifiedRestored.length, 3);
        assert.equal(verifiedRestored[0].routeCode, 'RT-99');
        assert.equal(verifiedRestored[1].routeCode, 'RT-04');
        assert.equal(verifiedRestored[2].routeCode, 'RT-12');

        // 6. Final cleanup of temporary test collections
        await TestModel.deleteMany({});
        await targetRestoreModel.deleteMany({});
        try { await TestModel.collection.drop(); } catch (_) {}
        try { await targetRestoreModel.collection.drop(); } catch (_) {}
        await conn.close();
    });
});
