const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Driver = require('../models/Driver');
const Manager = require('../models/Manager');
const Admin = require('../models/Admin');

const getAccountByIdAndRole = async (id, role) => {
    if (!id || !role) return null;
    switch (role) {
        case 'user':
            return await User.findById(id).select('status tokenVersion mustChangePassword enrollmentNumber name');
        case 'driver':
            return await Driver.findById(id).select('status tokenVersion mustChangePassword username name assignedBus');
        case 'manager':
            return await Manager.findById(id).select('status tokenVersion mustChangePassword username name');
        case 'admin':
            return await Admin.findById(id).select('status tokenVersion username name');
        default:
            return null;
    }
};

function getJwtSecret() {
    const secret = process.env.JWT_SECRET;
    if (!secret || secret.trim().length === 0) {
        if (process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'staging') {
            throw new Error(`FATAL SECURITY ERROR: JWT_SECRET environment variable is missing in ${process.env.NODE_ENV} environment.`);
        }
        return 'SISTecChalo_secret_key_777';
    }
    if ((process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'staging') && secret.trim().length < 32) {
        throw new Error(`FATAL SECURITY ERROR: JWT_SECRET in ${process.env.NODE_ENV} environment must be at least 32 characters long.`);
    }
    return secret;
}

/**
 * Express middleware to authenticate a request using a JWT token.
 * Rejects tokens restricted to password change and validates tokenVersion.
 */
const authMiddleware = async (req, res, next) => {
    const token = req.header('Authorization');

    if (!token) {
        return res.status(401).json({ error: 'No token, authorization denied' });
    }

    try {
        const tokenString = token.startsWith('Bearer ') ? token.slice(7) : token;
        const decoded = jwt.verify(tokenString, getJwtSecret());

        // Prevent restricted first-login tokens from accessing ordinary protected resources
        if (decoded.scope === 'password_change') {
            return res.status(403).json({
                error: 'Password change required before accessing other resources',
                mustChangePassword: true
            });
        }

        const account = await getAccountByIdAndRole(decoded.user?.id, decoded.user?.role);
        if (!account) {
            return res.status(401).json({ error: 'Account no longer exists' });
        }

        if (account.status && account.status === 'Suspended') {
            return res.status(403).json({ error: 'Account suspended' });
        }

        const tokenVersion = decoded.user?.tokenVersion;
        const currentVersion = account.tokenVersion || 0;
        if (tokenVersion === undefined || tokenVersion !== currentVersion) {
            return res.status(401).json({ error: 'Session expired. Please log in again.', sessionRevoked: true });
        }

        req.user = decoded.user;
        next();
    } catch (_err) {
        res.status(401).json({ error: 'Token is not valid or expired' });
    }
};

/**
 * Dedicated authentication middleware for password-change operations.
 * Allows tokens with scope 'password_change' or 'normal'.
 */
const passwordChangeAuth = async (req, res, next) => {
    const token = req.header('Authorization');

    if (!token) {
        return res.status(401).json({ error: 'Authentication token required' });
    }

    try {
        const tokenString = token.startsWith('Bearer ') ? token.slice(7) : token;
        const decoded = jwt.verify(tokenString, getJwtSecret());

        if (decoded.scope && decoded.scope !== 'password_change' && decoded.scope !== 'normal') {
            return res.status(403).json({ error: 'Invalid token scope for password change' });
        }

        const account = await getAccountByIdAndRole(decoded.user?.id, decoded.user?.role);
        if (!account) {
            return res.status(401).json({ error: 'Account no longer exists' });
        }

        if (account.status && account.status === 'Suspended') {
            return res.status(403).json({ error: 'Account suspended' });
        }

        const tokenVersion = decoded.user?.tokenVersion;
        const currentVersion = account.tokenVersion || 0;
        if (tokenVersion === undefined || tokenVersion !== currentVersion) {
            return res.status(401).json({ error: 'Session expired. Please log in again.', sessionRevoked: true });
        }

        req.user = decoded.user;
        next();
    } catch (_err) {
        res.status(401).json({ error: 'Invalid or expired token' });
    }
};

/**
 * Optional authentication middleware: attaches req.user if valid and unrevoked,
 * but allows unauthenticated access to continue.
 */
const optionalAuth = async (req, res, next) => {
    const token = req.header('Authorization');
    if (!token) {
        return next();
    }
    try {
        const tokenString = token.startsWith('Bearer ') ? token.slice(7) : token;
        const decoded = jwt.verify(tokenString, getJwtSecret());
        if (decoded.scope !== 'password_change') {
            const account = await getAccountByIdAndRole(decoded.user?.id, decoded.user?.role).catch(() => null);
            if (account && (!account.status || account.status !== 'Suspended')) {
                const currentVersion = account.tokenVersion || 0;
                if (decoded.user?.tokenVersion === currentVersion) {
                    req.user = decoded.user;
                }
            }
        }
    } catch (_err) {
        // Token is invalid, continue without user
    }
    next();
};

/**
 * Middleware strictly requiring Root Admin privileges.
 */
const adminMiddleware = (req, res, next) => {
    if (req.user && req.user.role === 'admin') {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Root administrator privileges required.' });
};

/**
 * Middleware requiring Manager or Admin privileges.
 */
const managerMiddleware = (req, res, next) => {
    if (req.user && (req.user.role === 'manager' || req.user.role === 'admin')) {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Fleet Manager or Administrator privileges required.' });
};

/**
 * Middleware requiring Driver, Manager, or Admin privileges.
 */
const driverMiddleware = (req, res, next) => {
    if (req.user && (req.user.role === 'driver' || req.user.role === 'manager' || req.user.role === 'admin')) {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Driver or Dispatcher privileges required.' });
};

/**
 * Middleware requiring Student (user) privileges.
 */
const studentMiddleware = (req, res, next) => {
    if (req.user && (req.user.role === 'user' || req.user.role === 'manager' || req.user.role === 'admin')) {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Student access privileges required.' });
};

// Export callable function as default and named exports for backward compatibility
module.exports = authMiddleware;
module.exports.authMiddleware = authMiddleware;
module.exports.passwordChangeAuth = passwordChangeAuth;
module.exports.optionalAuth = optionalAuth;
module.exports.adminMiddleware = adminMiddleware;
module.exports.managerMiddleware = managerMiddleware;
module.exports.driverMiddleware = driverMiddleware;
module.exports.studentMiddleware = studentMiddleware;
module.exports.getAccountByIdAndRole = getAccountByIdAndRole;
module.exports.getJwtSecret = getJwtSecret;



