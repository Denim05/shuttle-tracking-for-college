/**
 * seed_real_routes.js
 * Explicit route seeding interface for SISTecChalo.
 * 
 * Safety Guarantees:
 * - Zero execution on require() / import.
 * - Does NOT open, manage, or disconnect secondary Mongoose connections.
 * - Uses only the caller's validated active database connection.
 * - Never executes unrequested standalone timetable synchronization as a side effect.
 */

/**
 * Seed route helper invoked only when explicitly called.
 *
 * @param {boolean} [disconnect=false]
 * @returns {Promise<{ success: boolean, seeded: number }>}
 */
async function seed(disconnect = false) {
    console.log('ℹ️ [SEED] Explicit route seeding interface invoked (no-op: 0 routes created).');
    return { success: true, seeded: 0, status: 'no-op' };
}

module.exports = { seed };

