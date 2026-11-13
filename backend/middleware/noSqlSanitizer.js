/**
 * noSqlSanitizer.js — Enterprise NoSQL Operator Injection Protection Middleware
 *
 * Responsibilities:
 * 1. Recursively detects and removes prohibited MongoDB operators (keys starting with '$' or containing '.')
 *    from req.body, req.query, and req.params.
 * 2. Preserves legitimate values containing '$' or '.' (passwords, email addresses, version numbers, prices).
 * 3. Preserves legitimate nested objects and arrays of documents.
 * 4. Provides type validation helpers for authentication credentials, IDs, and pagination.
 * 5. Defense-in-depth against type confusion attacks (e.g. passing objects where strings are expected).
 */

const mongoose = require('mongoose');

/**
 * Checks whether a key is prohibited in MongoDB input.
 * MongoDB reserves keys starting with '$' as query/update operators and keys with '.' as dot-notation paths.
 *
 * @param {string} key
 * @returns {boolean}
 */
function isProhibitedKey(key) {
    if (typeof key !== 'string') return false;
    return key.startsWith('$') || key.includes('.');
}

/**
 * Recursively sanitizes an object or array in place by deleting prohibited keys.
 * String and numeric values are preserved completely unmutated.
 *
 * @param {any} target - Target object, array, or primitive
 * @param {Object} [state] - Tracking state for logging / audit
 * @returns {any} Sanitized target
 */
function sanitizeInput(target, state = { stripped: [] }) {
    if (!target || typeof target !== 'object') {
        return target;
    }

    if (Array.isArray(target)) {
        for (let i = 0; i < target.length; i++) {
            target[i] = sanitizeInput(target[i], state);
        }
        return target;
    }

    const keys = Object.keys(target);
    for (const key of keys) {
        if (isProhibitedKey(key)) {
            state.stripped.push(key);
            delete target[key];
        } else if (target[key] && typeof target[key] === 'object') {
            sanitizeInput(target[key], state);
        }
    }

    return target;
}

/**
 * Express middleware to sanitize req.body, req.query, and req.params.
 */
function noSqlSanitizeMiddleware(req, res, next) {
    const state = { stripped: [] };

    if (req.body && typeof req.body === 'object') {
        sanitizeInput(req.body, state);
    }
    if (req.query && typeof req.query === 'object') {
        sanitizeInput(req.query, state);
    }
    if (req.params && typeof req.params === 'object') {
        sanitizeInput(req.params, state);
    }

    if (state.stripped.length > 0) {
        req._sanitizationStripped = state.stripped;
        if (process.env.NODE_ENV !== 'test') {
            console.warn(`🛡️ [NoSQL-Sanitize] Stripped ${state.stripped.length} prohibited key(s) from request ${req.method} ${req.originalUrl}:`, state.stripped);
        }
    }

    next();
}

/**
 * Validates that specified request body fields are strictly strings.
 * Prevents type confusion attacks where an attacker passes an object or array.
 *
 * @param {string[]} requiredFields - List of field names that must be strings
 * @param {string[]} [optionalFields] - List of field names that, if present, must be strings
 * @returns {Function} Express middleware
 */
function validateStringInputs(requiredFields = [], optionalFields = []) {
    return (req, res, next) => {
        if (!req.body || typeof req.body !== 'object') {
            return res.status(400).json({ error: 'Request body must be a valid JSON object' });
        }

        for (const field of requiredFields) {
            const val = req.body[field];
            if (val === undefined || val === null) {
                return res.status(400).json({ error: `Field "${field}" is required` });
            }
            if (typeof val !== 'string') {
                return res.status(400).json({ error: `Field "${field}" must be a string` });
            }
        }

        for (const field of optionalFields) {
            const val = req.body[field];
            if (val !== undefined && val !== null && typeof val !== 'string') {
                return res.status(400).json({ error: `Field "${field}", if provided, must be a string` });
            }
        }

        next();
    };
}

/**
 * Middleware to sanitize and validate pagination query parameters (page, limit).
 * Prevents out-of-range limits, negative pages, or operator injection in pagination.
 *
 * @param {Object} options
 * @param {number} [options.defaultPage=1]
 * @param {number} [options.defaultLimit=50]
 * @param {number} [options.maxLimit=200]
 * @returns {Function} Express middleware
 */
function validatePagination({ defaultPage = 1, defaultLimit = 50, maxLimit = 200 } = {}) {
    return (req, res, next) => {
        if (!req.query) req.query = {};

        // Sanitize page
        let page = defaultPage;
        if (req.query.page !== undefined) {
            const parsed = parseInt(req.query.page, 10);
            if (!isNaN(parsed) && parsed >= 1) {
                page = parsed;
            }
        }
        req.query.page = page;

        // Sanitize limit
        let limit = defaultLimit;
        if (req.query.limit !== undefined) {
            const parsed = parseInt(req.query.limit, 10);
            if (!isNaN(parsed) && parsed >= 1) {
                limit = Math.min(parsed, maxLimit);
            }
        }
        req.query.limit = limit;
        req.pagination = { page, limit, skip: (page - 1) * limit };

        next();
    };
}

/**
 * Middleware to validate that URL route parameter(s) are valid 24-character hexadecimal ObjectIds.
 * Supports a single parameter name (e.g. 'id') or an array of parameter names (e.g. ['id', 'docId']).
 *
 * @param {string|string[]} [paramNames='id'] - The parameter key or array of keys in req.params
 * @returns {Function} Express middleware
 */
function validateObjectIdParam(paramNames = 'id') {
    const list = Array.isArray(paramNames) ? paramNames : [paramNames];
    return (req, res, next) => {
        for (const paramName of list) {
            const id = req.params && req.params[paramName];
            if (!id || typeof id !== 'string') {
                return res.status(400).json({ error: `Missing or invalid ${paramName}` });
            }
            if (!mongoose.Types.ObjectId.isValid(id)) {
                return res.status(400).json({ error: `Invalid ${paramName} format. Must be a 24-character hex ObjectId.` });
            }
        }
        next();
    };
}

module.exports = {
    isProhibitedKey,
    sanitizeInput,
    noSqlSanitizeMiddleware,
    validateStringInputs,
    validatePagination,
    validateObjectIdParam
};
