const jwt = require('jsonwebtoken');

/**
 * Express middleware to authenticate a request using a JWT token.
 * It expects the token to be provided in the 'Authorization' header,
 * optionally prefixed with 'Bearer '.
 *
 * @param {import('express').Request} req - The Express request object.
 * @param {import('express').Response} res - The Express response object.
 * @param {import('express').NextFunction} next - The next middleware function.
 * @returns {void} Returns a 401 response if authentication fails.
 */
const authMiddleware = (req, res, next) => {
    // Get token from header
    const token = req.header('Authorization');

    // Check if no token
    if (!token) {
        return res.status(401).json({ error: 'No token, authorization denied' });
    }

    // Verify token
    try {
        // Remove "Bearer " prefix if present
        const tokenString = token.startsWith('Bearer ') ? token.slice(7, token.length) : token;

        const decoded = jwt.verify(tokenString, process.env.JWT_SECRET || 'chalocampus_secret_key_777');

        req.user = decoded.user;
        next();
    } catch (_err) {
        res.status(401).json({ error: 'Token is not valid or expired' });
    }
};

module.exports = authMiddleware;
