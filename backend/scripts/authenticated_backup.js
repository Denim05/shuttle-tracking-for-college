/**
 * SISTec Chalo — Enterprise Authenticated Backup Encryption Engine
 *
 * Cryptographic Architecture:
 * - Cipher: AES-256-GCM (Authenticated Encryption with Associated Data - AEAD)
 * - Key Derivation: PBKDF2 with HMAC-SHA256, 600,000 iterations (OWASP Standard)
 * - Nonce/IV: 12-byte cryptographically secure random bytes per archive
 * - Salt: 32-byte cryptographically secure random bytes per archive
 * - Authentication Tag: 16-byte GCM authentication tag verifying integrity & authenticity
 * - Associated Data (AAD): In V2, the header [MAGIC + ITERATIONS + SALT + IV] is authenticated as AAD
 * - Backward Compatibility: Automatically detects and decrypts V1 archives (100,000 iterations)
 * - Tampering Guard: Any alteration to header, salt, IV, or payload throws an authentication failure
 */

const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const { pipeline } = require('stream/promises');

const MAGIC_HEADER_V1 = Buffer.from('SISTEC_ENC_GCM_V1'); // 17 bytes (legacy)
const MAGIC_HEADER_V2 = Buffer.from('SISTEC_ENC_GCM_V2'); // 17 bytes (hardened with AAD & dynamic iterations)
const SALT_LEN = 32;
const IV_LEN = 12;
const TAG_LEN = 16;
const DEFAULT_PBKDF2_ITERATIONS = 600000; // OWASP recommendation for PBKDF2-HMAC-SHA256
const MIN_PBKDF2_ITERATIONS = 10000;
const MAX_PBKDF2_ITERATIONS = 2000000; // Protect against CPU-exhaustion DoS
const V1_PBKDF2_ITERATIONS = 100000;
const KEY_LEN = 32; // 256 bits

/**
 * Derives a 256-bit encryption key from a passphrase, salt, and iteration count.
 * @param {string|Buffer} passphrase
 * @param {Buffer} salt
 * @param {number} iterations
 * @returns {Buffer}
 */
function deriveKey(passphrase, salt, iterations = DEFAULT_PBKDF2_ITERATIONS) {
    if (!passphrase || (typeof passphrase === 'string' && passphrase.trim().length === 0)) {
        throw new Error('FATAL: Backup passphrase must not be empty.');
    }
    const rounds = Number(iterations) || DEFAULT_PBKDF2_ITERATIONS;
    if (rounds < MIN_PBKDF2_ITERATIONS || rounds > MAX_PBKDF2_ITERATIONS) {
        throw new Error(`FATAL: Untrusted PBKDF2 iteration count (${rounds}). Allowed range: ${MIN_PBKDF2_ITERATIONS} - ${MAX_PBKDF2_ITERATIONS}.`);
    }
    return crypto.pbkdf2Sync(passphrase, salt, rounds, KEY_LEN, 'sha256');
}

/**
 * Securely overwrites a file with random data or zeroes before unlinking.
 * @param {string} filePath
 */
function secureWipeFile(filePath) {
    if (!fs.existsSync(filePath)) return;
    try {
        const stat = fs.statSync(filePath);
        if (stat.size > 0) {
            // Overwrite with zeroes
            const zeroes = Buffer.alloc(Math.min(stat.size, 1024 * 1024));
            const fd = fs.openSync(filePath, 'r+');
            let written = 0;
            while (written < stat.size) {
                const toWrite = Math.min(zeroes.length, stat.size - written);
                fs.writeSync(fd, zeroes, 0, toWrite, written);
                written += toWrite;
            }
            fs.fsyncSync(fd);
            fs.closeSync(fd);
        }
    } catch (_) {
        // Fall through to unlink
    }
    try {
        fs.unlinkSync(filePath);
    } catch (_) {}
}

/**
 * Encrypts an unencrypted archive file using AES-256-GCM authenticated encryption (V2 with AAD).
 * Format: [MAGIC_HEADER_V2 (17B)][ITERATIONS (4B UInt32BE)][SALT (32B)][IV (12B)][TAG (16B)][CIPHERTEXT]
 *
 * @param {Object} options
 * @param {string} options.inputPath - Path to unencrypted archive (.archive / .tar)
 * @param {string} options.outputPath - Destination path for encrypted archive (.enc)
 * @param {string} options.passphrase - Strong secret passphrase
 * @param {number} [options.iterations=600000] - PBKDF2 iteration count (default: 600,000)
 * @param {boolean} [options.wipeSource=false] - Whether to securely wipe the input archive after success
 * @returns {Promise<{ bytesWritten: number, sha256: string, iterations: number }>}
 */
async function encryptArchive({ inputPath, outputPath, passphrase, iterations = DEFAULT_PBKDF2_ITERATIONS, wipeSource = false }) {
    if (!fs.existsSync(inputPath)) {
        throw new Error(`Input archive not found: ${inputPath}`);
    }

    const salt = crypto.randomBytes(SALT_LEN);
    const iv = crypto.randomBytes(IV_LEN);
    const key = deriveKey(passphrase, salt, iterations);

    const iterBuf = Buffer.alloc(4);
    iterBuf.writeUInt32BE(iterations, 0);

    // Associated Data: Magic + Iterations + Salt + IV
    const aad = Buffer.concat([MAGIC_HEADER_V2, iterBuf, salt, iv]);

    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    cipher.setAAD(aad);
    
    // Create temporary file for atomic write safety
    const tempOutput = `${outputPath}.tmp_${Date.now()}`;
    let outStream;

    try {
        outStream = fs.createWriteStream(tempOutput);

        // Read input and encrypt in memory or chunks
        const inputStream = fs.createReadStream(inputPath);
        const chunks = [];

        // Stream through cipher
        await pipeline(inputStream, cipher, async function* (source) {
            for await (const chunk of source) {
                chunks.push(chunk);
            }
        });

        const tag = cipher.getAuthTag();
        if (tag.length !== TAG_LEN) {
            throw new Error('Authentication tag length mismatch');
        }

        // Write header: MAGIC + ITERATIONS + SALT + IV + TAG
        outStream.write(MAGIC_HEADER_V2);
        outStream.write(iterBuf);
        outStream.write(salt);
        outStream.write(iv);
        outStream.write(tag);

        // Write ciphertext chunks
        for (const chunk of chunks) {
            outStream.write(chunk);
        }

        await new Promise((resolve, reject) => {
            outStream.end((err) => {
                if (err) reject(err);
                else resolve();
            });
        });

        // Rename atomic temp file to final destination
        fs.renameSync(tempOutput, outputPath);
    } catch (err) {
        // Guarantee temporary file cleanup on failure
        if (fs.existsSync(tempOutput)) {
            try {
                fs.unlinkSync(tempOutput);
            } catch (_) {}
        }
        throw err;
    }

    // Securely wipe source unencrypted file if requested
    if (wipeSource) {
        secureWipeFile(inputPath);
    }

    // Calculate SHA-256 of the encrypted file for checksum publication
    const fileBuf = fs.readFileSync(outputPath);
    const sha256 = crypto.createHash('sha256').update(fileBuf).digest('hex');

    return {
        bytesWritten: fileBuf.length,
        sha256,
        iterations
    };
}

/**
 * Decrypts an AES-256-GCM encrypted archive and validates authenticity.
 * Automatically supports both V2 (with AAD & dynamic iterations) and V1 (legacy 100,000 iterations).
 * Throws if authentication tag verification fails or if any byte has been tampered with.
 *
 * @param {Object} options
 * @param {string} options.inputPath - Path to encrypted archive (.enc)
 * @param {string} options.outputPath - Destination path for decrypted archive
 * @param {string} options.passphrase - Passphrase used during encryption
 * @returns {Promise<{ bytesDecrypted: number, sha256: string, version: string, iterations: number }>}
 */
async function decryptArchive({ inputPath, outputPath, passphrase }) {
    if (!fs.existsSync(inputPath)) {
        throw new Error(`Encrypted file not found: ${inputPath}`);
    }

    const fileBuf = fs.readFileSync(inputPath);
    const minHeaderLen = MAGIC_HEADER_V1.length + SALT_LEN + IV_LEN + TAG_LEN;

    if (fileBuf.length < minHeaderLen) {
        throw new Error('FATAL: Corrupted or truncated archive (header incomplete).');
    }

    let offset = 0;
    const magic = fileBuf.subarray(offset, offset + MAGIC_HEADER_V1.length);
    offset += MAGIC_HEADER_V1.length;

    let isV2 = false;
    let iterations = DEFAULT_PBKDF2_ITERATIONS;

    if (magic.equals(MAGIC_HEADER_V2)) {
        isV2 = true;
        if (fileBuf.length < minHeaderLen + 4) {
            throw new Error('FATAL: Corrupted or truncated V2 archive (header incomplete).');
        }
        iterations = fileBuf.readUInt32BE(offset);
        offset += 4;
    } else if (magic.equals(MAGIC_HEADER_V1)) {
        isV2 = false;
        iterations = V1_PBKDF2_ITERATIONS;
    } else {
        throw new Error('FATAL: Invalid archive format (magic header mismatch).');
    }

    const salt = fileBuf.subarray(offset, offset + SALT_LEN);
    offset += SALT_LEN;

    const iv = fileBuf.subarray(offset, offset + IV_LEN);
    offset += IV_LEN;

    const tag = fileBuf.subarray(offset, offset + TAG_LEN);
    offset += TAG_LEN;

    const ciphertext = fileBuf.subarray(offset);

    const key = deriveKey(passphrase, salt, iterations);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);

    // In V2, verify Associated Data: Magic + Iterations + Salt + IV
    if (isV2) {
        const iterBuf = Buffer.alloc(4);
        iterBuf.writeUInt32BE(iterations, 0);
        const aad = Buffer.concat([MAGIC_HEADER_V2, iterBuf, salt, iv]);
        decipher.setAAD(aad);
    }

    // Decrypt — decipher.final() will THROW if tag or AAD does not match
    let decrypted;
    try {
        decrypted = Buffer.concat([
            decipher.update(ciphertext),
            decipher.final()
        ]);
        fs.writeFileSync(outputPath, decrypted);
    } catch (err) {
        if (fs.existsSync(outputPath)) {
            try {
                fs.unlinkSync(outputPath);
            } catch (_) {}
        }
        throw err;
    }

    const sha256 = crypto.createHash('sha256').update(decrypted).digest('hex');
    return {
        bytesDecrypted: decrypted.length,
        sha256,
        version: isV2 ? 'V2' : 'V1',
        iterations
    };
}

module.exports = {
    encryptArchive,
    decryptArchive,
    deriveKey,
    secureWipeFile,
    MAGIC_HEADER_V1,
    MAGIC_HEADER_V2,
    DEFAULT_PBKDF2_ITERATIONS,
    MIN_PBKDF2_ITERATIONS,
    MAX_PBKDF2_ITERATIONS,
    V1_PBKDF2_ITERATIONS
};
