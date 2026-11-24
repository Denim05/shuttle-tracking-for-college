/**
 * Central configuration for Stop Verification & Community-Assisted Coordinate Correction.
 * All trust weights, clustering radii, confidence weights, and route-aware thresholds live here.
 */

module.exports = {
  // Configurable trust weights per role + action
  VERIFICATION_WEIGHTS: {
    studentConfirmation: 1,
    studentCorrection: 1,
    driverConfirmation: 5,
    driverCorrection: 5,
    managerApproval: 10,
  },

  // Geographic clustering & outlier parameters
  CLUSTER_RADIUS_METERS: 50,
  CONFLICT_SEPARATION_METERS: 100,
  CONFLICT_RATIO_THRESHOLD: 0.30, // secondary cluster >= 30% of winning weight triggers NEEDS_REVIEW
  OUTLIER_DISTANCE_METERS: 250,

  // Route-aware corridor validation
  SUSPICIOUS_CORRIDOR_DISTANCE_KM: 35,
  HARD_DISTRICT_OUTLIER_KM: 60,
  BHOPAL_OPERATING_BOUNDS: {
    minLat: 22.40,
    maxLat: 23.60,
    minLng: 76.50,
    maxLng: 78.20,
  },

  // Consensus & lifecycle thresholds
  MIN_CONSENSUS_WEIGHT: 5,
  AUTO_VERIFIED_CONFIDENCE_THRESHOLD: 85,
  NEEDS_REVIEW_CONFIDENCE_THRESHOLD: 50,
  RECENCY_HALF_LIFE_DAYS: 30,

  // Security & anti-spam controls
  SPAM_COOLDOWN_MS: 60 * 1000, // 1 minute per user per stop
  MAX_ACTIVE_SUBMISSIONS_PER_USER_PER_STOP: 5,
  RATE_LIMIT_WINDOW_MS: 15 * 60 * 1000,
  RATE_LIMIT_MAX_REQUESTS: 30,
};
