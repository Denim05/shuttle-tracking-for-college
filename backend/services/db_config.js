/**
 * SISTec Chalo — Database Configuration & Environment Validation Service
 *
 * Responsibilities:
 * - Safely resolves and validates MongoDB connection URI and target database name.
 * - Enforces database isolation between Development, Staging, and Production.
 * - Prevents staging from accidentally connecting to the production 'sistecChalo' database.
 * - Zero logging of passwords, tokens, or raw credentials.
 */

/**
 * Validates whether a database name string complies with MongoDB naming rules.
 * Database names cannot contain spaces, slashes, dots, or special control characters.
 *
 * @param {string} name
 * @returns {boolean}
 */
function isValidDbName(name) {
    if (!name || typeof name !== 'string') return false;
    const trimmed = name.trim();
    if (trimmed.length < 1 || trimmed.length > 64) return false;
    // Disallow reserved and prohibited MongoDB database name characters
    return /^[a-zA-Z0-9_\-]+$/.test(trimmed);
}

/**
 * Sanitizes a MongoDB connection URI for safe logging.
 * Replaces credentials (username:password) with asterisks and strips query parameters.
 *
 * @param {string} uri
 * @returns {string}
 */
function sanitizeUriForLogging(uri) {
    if (!uri || typeof uri !== 'string') return 'UNAVAILABLE';
    return uri
        .replace(/\/\/[^@/]+@/, '//****:****@')
        .replace(/\?.*$/, '');
}

/**
 * Resolves effective database name and connection URI.
 *
 * Safety Rules:
 * 1. NODE_ENV=staging:
 *    - MUST explicitly specify MONGODB_DB_NAME (or a non-default database in URI).
 *    - MUST NOT resolve to 'sistecChalo' (production DB). Throws FATAL error if it does.
 * 2. NODE_ENV=production:
 *    - Defaults to 'sistecChalo' unless explicitly configured via MONGODB_DB_NAME.
 * 3. NODE_ENV=development:
 *    - Defaults to 'sistecChalo' (or MONGODB_DB_NAME if provided).
 *
 * @param {Object} params
 * @param {string} params.rawUri - Raw MongoDB URI from environment
 * @param {string} [params.nodeEnv] - Active NODE_ENV (default: process.env.NODE_ENV)
 * @param {string} [params.envDbName] - Optional explicit database name from MONGODB_DB_NAME
 * @returns {{ effectiveDb: string, effectiveUri: string, options: Object }}
 */
function resolveDatabaseConfig({ rawUri, nodeEnv = process.env.NODE_ENV, envDbName = process.env.MONGODB_DB_NAME } = {}) {
    if (!rawUri || typeof rawUri !== 'string' || rawUri.trim().length === 0) {
        throw new Error('FATAL: MONGODB_URI environment variable is strictly required.');
    }

    const trimmedUri = rawUri.trim();
    const env = (nodeEnv || 'development').toLowerCase().trim();
    const explicitDbName = envDbName ? envDbName.trim() : '';

    if (explicitDbName && !isValidDbName(explicitDbName)) {
        throw new Error(`FATAL: Invalid MONGODB_DB_NAME '${explicitDbName}'. Must contain only alphanumeric characters, underscores, or dashes (max 64 chars).`);
    }

    // Parse and validate MongoDB URI structure: mongodb(+srv)://authority[/database][?query]
    const uriParts = trimmedUri.match(/^(mongodb(?:\+srv)?):\/\/([^/?#\s]+)(?:\/([^?#\s]*))?(\?[^#\s]*)?$/i);
    if (!uriParts) {
        throw new Error('FATAL: Malformed or unsupported MONGODB_URI format.');
    }

    const scheme = uriParts[1];
    const authority = uriParts[2];
    const rawPathDb = uriParts[3] || '';
    const query = uriParts[4] || '';

    // Reject missing host authority, multiple unencoded '@' delimiters, empty ports, or ambiguous nested paths
    const hasMultipleAt = authority.indexOf('@') !== authority.lastIndexOf('@');
    const hostSegment = authority.includes('@') ? authority.slice(authority.lastIndexOf('@') + 1) : authority;
    const hasInvalidHostOrPort = hostSegment.split(',').some(h => !h || h.startsWith(':') || h.endsWith(':'));
    if (!hostSegment || hasMultipleAt || hasInvalidHostOrPort || authority.startsWith('@') || rawPathDb.includes('/')) {
        throw new Error('FATAL: Malformed or ambiguous MONGODB_URI authority or database path.');
    }

    const uriDbName = rawPathDb.trim();
    if (uriDbName && !isValidDbName(uriDbName)) {
        throw new Error(`FATAL: Invalid database name in MONGODB_URI path.`);
    }

    let effectiveDb = '';

    if (env === 'staging') {
        // Staging MUST be explicitly configured
        effectiveDb = explicitDbName || (uriDbName && uriDbName.toLowerCase() !== 'test' ? uriDbName : '');

        if (!effectiveDb) {
            throw new Error("FATAL: Staging environment requires an explicit MONGODB_DB_NAME (e.g. 'sistecChalo_staging'). Startup aborted.");
        }

        // Staging is STRICTLY prohibited from targeting the production database
        if (effectiveDb.toLowerCase() === 'sistecchalo') {
            throw new Error("FATAL SAFETY ERROR: Staging environment is strictly prohibited from connecting to the production database 'sistecChalo'.");
        }
    } else if (env === 'production') {
        effectiveDb = explicitDbName || (uriDbName && uriDbName.toLowerCase() !== 'test' ? uriDbName : 'sistecChalo');
    } else {
        // Development / Test
        effectiveDb = explicitDbName || (uriDbName && uriDbName.toLowerCase() !== 'test' ? uriDbName : 'sistecChalo');
    }

    if (!isValidDbName(effectiveDb)) {
        throw new Error(`FATAL: Resolved database name '${effectiveDb}' is invalid.`);
    }

    // Reconstruct the normalized URI with the validated database path while preserving query parameters
    const effectiveUri = `${scheme}://${authority}/${effectiveDb}${query}`;

    return {
        effectiveDb,
        effectiveUri,
        options: { dbName: effectiveDb }
    };
}

module.exports = {
    isValidDbName,
    sanitizeUriForLogging,
    resolveDatabaseConfig
};
