const config = require('../config/stop_verification_config');
const StopVerification = require('../models/StopVerification');
const StopVerificationState = require('../models/StopVerificationState');
const Route = require('../models/Route');

const FALLBACK_CAMPUS_LAT = 23.180302;
const FALLBACK_CAMPUS_LNG = 77.302695;

function haversineDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function isFallbackCoordinate(lat, lng) {
  return (
    Math.abs(lat - FALLBACK_CAMPUS_LAT) < 1e-5 &&
    Math.abs(lng - FALLBACK_CAMPUS_LNG) < 1e-5
  );
}

function validateCoordinates(lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return { valid: false, error: 'Latitude and longitude must be numbers' };
  }
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return { valid: false, error: 'Latitude and longitude must be finite numbers' };
  }
  if (lat < -90 || lat > 90) {
    return { valid: false, error: 'Latitude must be between -90 and 90' };
  }
  if (lng < -180 || lng > 180) {
    return { valid: false, error: 'Longitude must be between -180 and 180' };
  }
  if (Math.abs(lat) < 1e-6 && Math.abs(lng) < 1e-6) {
    return { valid: false, error: 'Null island (0, 0) coordinates are not permitted' };
  }
  return { valid: true };
}

function getWeightForRoleAndAction(role, action) {
  const w = config.VERIFICATION_WEIGHTS;
  const normalizedRole = (role || 'student').toLowerCase();
  if (normalizedRole === 'manager' || normalizedRole === 'admin') {
    return w.managerApproval;
  }
  if (normalizedRole === 'driver') {
    return action === 'ADJUSTED' ? w.driverCorrection : w.driverConfirmation;
  }
  return action === 'ADJUSTED' ? w.studentCorrection : w.studentConfirmation;
}

function sourceFromRole(role) {
  const normalized = (role || 'student').toLowerCase();
  if (normalized === 'driver') return 'DRIVER';
  if (normalized === 'manager' || normalized === 'admin') return 'MANAGER';
  return 'USER';
}

function buildStopId(routeId, stop, stopIndex) {
  if (stop && stop._id) return stop._id.toString();
  return `${routeId.toString()}:${stopIndex}`;
}

function resolveStopFromRoute(route, stopId) {
  if (!route || !Array.isArray(route.stops)) return null;
  const cleanId = String(stopId || '').trim();
  if (!cleanId) return null;

  for (let i = 0; i < route.stops.length; i++) {
    const stop = route.stops[i];
    if (stop._id && stop._id.toString() === cleanId) {
      return { stop, stopIndex: i, stopId: stop._id.toString() };
    }
    if (`${route._id.toString()}:${i}` === cleanId) {
      return { stop, stopIndex: i, stopId: cleanId };
    }
  }
  return null;
}

/**
 * Route-aware corridor validation: checks submitted coordinate against
 * neighbouring stops, non-fallback route anchors, and operating bounds.
 */
function validateAgainstRouteCorridor({ lat, lng, routeStops = [], stopIndex = 0 }) {
  const flags = [];
  const bounds = config.BHOPAL_OPERATING_BOUNDS;
  let isSuspicious = false;

  if (
    lat < bounds.minLat ||
    lat > bounds.maxLat ||
    lng < bounds.minLng ||
    lng > bounds.maxLng
  ) {
    isSuspicious = true;
    flags.push('OUTSIDE_OPERATING_DISTRICT_BOUNDS');
  }

  // Gather neighbouring non-fallback valid stops
  const anchorDistancesKm = [];
  for (let i = 0; i < routeStops.length; i++) {
    if (i === stopIndex) continue;
    const s = routeStops[i];
    if (
      typeof s.lat === 'number' &&
      typeof s.lng === 'number' &&
      !isFallbackCoordinate(s.lat, s.lng) &&
      validateCoordinates(s.lat, s.lng).valid
    ) {
      const distKm = haversineDistanceMeters(lat, lng, s.lat, s.lng) / 1000;
      anchorDistancesKm.push({ idx: i, distKm, isNeighbor: Math.abs(i - stopIndex) <= 2 });
    }
  }

  let minAnchorDistKm = 0;
  let maxNeighborDistKm = 0;
  if (anchorDistancesKm.length > 0) {
    minAnchorDistKm = Math.min(...anchorDistancesKm.map((a) => a.distKm));
    const neighborDists = anchorDistancesKm.filter((a) => a.isNeighbor).map((a) => a.distKm);
    maxNeighborDistKm = neighborDists.length > 0 ? Math.max(...neighborDists) : minAnchorDistKm;

    if (minAnchorDistKm > config.HARD_DISTRICT_OUTLIER_KM) {
      isSuspicious = true;
      flags.push('SUSPICIOUS_DISTANCE_OVER_60KM');
    } else if (minAnchorDistKm > config.SUSPICIOUS_CORRIDOR_DISTANCE_KM) {
      flags.push('CORRIDOR_DEVIATION_WARNING');
    }
  }

  return {
    isSuspicious,
    minAnchorDistKm: Number(minAnchorDistKm.toFixed(2)),
    maxNeighborDistKm: Number(maxNeighborDistKm.toFixed(2)),
    flags,
  };
}

/**
 * Group geographically close submissions into weighted clusters,
 * detect conflicting clusters, and identify outliers.
 */
function clusterSubmissions(events = [], clusterRadiusMeters = config.CLUSTER_RADIUS_METERS) {
  const validEvents = [];
  const outliers = [];

  for (const ev of events) {
    if (ev.status === 'REJECTED') continue;
    if (ev.routeValidation && ev.routeValidation.isSuspicious) {
      outliers.push({ event: ev, reason: 'SUSPICIOUS_ROUTE_CORRIDOR' });
      continue;
    }
    validEvents.push(ev);
  }

  const clusters = [];
  for (const ev of validEvents) {
    let placed = null;
    for (const c of clusters) {
      const dist = haversineDistanceMeters(
        ev.selectedLatitude,
        ev.selectedLongitude,
        c.weightedLat,
        c.weightedLng
      );
      if (dist <= clusterRadiusMeters) {
        placed = c;
        break;
      }
    }

    const weight =
      typeof ev.confidenceContribution === 'number' && ev.confidenceContribution > 0
        ? ev.confidenceContribution
        : getWeightForRoleAndAction(ev.role, ev.action);

    if (!placed) {
      clusters.push({
        items: [{ ev, weight }],
        totalWeight: weight,
        weightedLat: ev.selectedLatitude,
        weightedLng: ev.selectedLongitude,
      });
    } else {
      placed.items.push({ ev, weight });
      placed.totalWeight += weight;
      placed.weightedLat =
        placed.items.reduce((s, x) => s + x.ev.selectedLatitude * x.weight, 0) / placed.totalWeight;
      placed.weightedLng =
        placed.items.reduce((s, x) => s + x.ev.selectedLongitude * x.weight, 0) / placed.totalWeight;
    }
  }

  // Compute spread inside each cluster
  for (const c of clusters) {
    let maxSpread = 0;
    for (const item of c.items) {
      const d = haversineDistanceMeters(
        item.ev.selectedLatitude,
        item.ev.selectedLongitude,
        c.weightedLat,
        c.weightedLng
      );
      if (d > maxSpread) maxSpread = d;
    }
    c.spreadMeters = Number(maxSpread.toFixed(1));
  }

  clusters.sort((a, b) => b.totalWeight - a.totalWeight);
  const winningCluster = clusters[0] || null;
  const conflictingClusters = [];

  if (winningCluster) {
    for (let i = 1; i < clusters.length; i++) {
      const c = clusters[i];
      const separation = haversineDistanceMeters(
        c.weightedLat,
        c.weightedLng,
        winningCluster.weightedLat,
        winningCluster.weightedLng
      );
      if (
        separation > config.CONFLICT_SEPARATION_METERS &&
        c.totalWeight >= winningCluster.totalWeight * config.CONFLICT_RATIO_THRESHOLD
      ) {
        conflictingClusters.push({
          ...c,
          separationMeters: Number(separation.toFixed(1)),
        });
      } else if (separation > config.OUTLIER_DISTANCE_METERS) {
        for (const item of c.items) {
          outliers.push({ event: item.ev, reason: 'GEOGRAPHIC_OUTLIER', distMeters: Math.round(separation) });
        }
      }
    }
  }

  return {
    winningCluster,
    clusters,
    conflictingClusters,
    outliers,
  };
}

/**
 * Deterministic, explainable 0-100 confidence model.
 */
function computeDeterministicConfidence({
  winningCluster,
  conflictingClusters = [],
  outliers = [],
  events = [],
  routeValidation = { isSuspicious: false },
  candidateSource = null,
  hasManagerApproval = false,
  now = new Date(),
}) {
  if (!winningCluster && !hasManagerApproval) {
    const reasons = [];
    if (routeValidation.isSuspicious) {
      reasons.push('Submitted coordinates flagged as suspicious corridor/district outlier');
    } else if (candidateSource) {
      reasons.push(`Unverified automated candidate (${candidateSource})`);
      return { score: 35, reasons };
    } else {
      reasons.push('No verification submissions recorded yet');
    }
    return { score: 0, reasons };
  }

  let studentConfirmations = 0;
  let studentCorrections = 0;
  let driverConfirmations = 0;
  let driverCorrections = 0;
  let recentCount = 0;

  const clusterEvents = winningCluster ? winningCluster.items.map((x) => x.ev) : events;
  for (const ev of clusterEvents) {
    const r = (ev.role || 'student').toLowerCase();
    if (r === 'driver') {
      if (ev.action === 'ADJUSTED') driverCorrections++;
      else driverConfirmations++;
    } else if (r === 'student' || r === 'user') {
      if (ev.action === 'ADJUSTED') studentCorrections++;
      else studentConfirmations++;
    }
    const ageDays = (now.getTime() - new Date(ev.timestamp || now).getTime()) / (1000 * 86400);
    if (ageDays <= config.RECENCY_HALF_LIFE_DAYS) recentCount++;
  }

  let score = 0;
  // Base score from weighted evidence (up to 65 points)
  const effectiveWeight = winningCluster ? winningCluster.totalWeight : 10;
  score += Math.min(65, Math.round(effectiveWeight * 4.5));

  // Driver / Manager authority bonus
  if (driverConfirmations + driverCorrections > 0) score += 15;
  if (hasManagerApproval) score += 20;

  // Tight clustering bonus (up to 15 points)
  const spread = winningCluster ? winningCluster.spreadMeters : 0;
  if (spread <= 25) score += 15;
  else if (spread <= 50) score += 10;
  else score += 4;

  // Route corridor consistency bonus/penalty
  if (!routeValidation.isSuspicious) {
    score += 5;
  } else {
    score -= 35;
  }

  // Conflict & outlier penalties
  if (conflictingClusters.length > 0) {
    score -= Math.min(35, conflictingClusters.length * 20);
  }
  if (outliers.length > 0) {
    score -= Math.min(15, outliers.length * 4);
  }

  // Recency boost
  if (recentCount > 0 && clusterEvents.length > 0) {
    score += Math.round((recentCount / clusterEvents.length) * 5);
  }

  // Candidate source quality minor boost
  if (candidateSource && !candidateSource.includes('REJECTED')) {
    score += 2;
  }

  score = Math.max(0, Math.min(100, Math.round(score)));

  const reasons = [];
  if (studentConfirmations > 0) reasons.push(`${studentConfirmations} student confirmation(s)`);
  if (studentCorrections > 0) reasons.push(`${studentCorrections} student correction(s)`);
  if (driverConfirmations > 0) reasons.push(`${driverConfirmations} driver confirmation(s)`);
  if (driverCorrections > 0) reasons.push(`${driverCorrections} driver correction(s)`);
  if (hasManagerApproval) reasons.push('Manager approval recorded');
  reasons.push(`${conflictingClusters.length} conflicting cluster(s)`);
  if (winningCluster) {
    reasons.push(`coordinates within ${Math.round(spread)}m cluster`);
  }
  reasons.push(
    routeValidation.isSuspicious
      ? 'flagged for suspicious route corridor deviation'
      : 'consistent with route corridor'
  );

  return { score, reasons };
}

function determineLifecycleStatus({
  hasCandidate,
  eventsCount,
  winningCluster,
  conflictingClusters,
  outliers,
  routeValidation,
  hasManagerApproval,
}) {
  if (hasManagerApproval) return 'VERIFIED';
  if (routeValidation && routeValidation.isSuspicious && !winningCluster) return 'FIELD_VERIFY';
  if (conflictingClusters.length > 0) return 'NEEDS_REVIEW';
  if (winningCluster && eventsCount > 0) return 'NEEDS_REVIEW';
  if (outliers.length > 0 && !winningCluster) return 'FIELD_VERIFY';
  if (hasCandidate) return 'CANDIDATE';
  return 'UNVERIFIED';
}

/**
 * Generates an automated non-mutating candidate coordinate from reconciliation data
 * or neighbouring verified stops on the route.
 */
function generateAutomatedCandidate({ stop, routeStops = [], stopIndex = 0, reconciliationEntry = null }) {
  if (reconciliationEntry && reconciliationEntry.candidateLat && reconciliationEntry.candidateLng) {
    return {
      candidateLatitude: reconciliationEntry.candidateLat,
      candidateLongitude: reconciliationEntry.candidateLng,
      candidateSource: reconciliationEntry.candidateSource || 'OSM_NOMINATIM_RECONCILIATION',
      candidateConfidence: reconciliationEntry.candidateConfidence === 'HIGH' ? 70 : 45,
      generatedAt: new Date(),
    };
  }

  // Fallback: interpolate between verified previous and next non-fallback stops
  let prev = null;
  let next = null;
  for (let i = stopIndex - 1; i >= 0; i--) {
    const s = routeStops[i];
    if (s && !isFallbackCoordinate(s.lat, s.lng) && validateCoordinates(s.lat, s.lng).valid) {
      prev = s;
      break;
    }
  }
  for (let i = stopIndex + 1; i < routeStops.length; i++) {
    const s = routeStops[i];
    if (s && !isFallbackCoordinate(s.lat, s.lng) && validateCoordinates(s.lat, s.lng).valid) {
      next = s;
      break;
    }
  }

  if (prev && next) {
    return {
      candidateLatitude: Number(((prev.lat + next.lat) / 2).toFixed(6)),
      candidateLongitude: Number(((prev.lng + next.lng) / 2).toFixed(6)),
      candidateSource: 'ROUTE_CORRIDOR_INTERPOLATION',
      candidateConfidence: 30,
      generatedAt: new Date(),
    };
  }

  if (stop && !isFallbackCoordinate(stop.lat, stop.lng) && validateCoordinates(stop.lat, stop.lng).valid) {
    return {
      candidateLatitude: stop.lat,
      candidateLongitude: stop.lng,
      candidateSource: 'EXISTING_STOP_COORDINATE',
      candidateConfidence: 50,
      generatedAt: new Date(),
    };
  }

  return null;
}

/**
 * Recompute StopVerificationState for a stop from all active StopVerification events.
 * Never mutates canonical Route.stops coordinates.
 */
async function recomputeStopState({ route, stop, stopIndex, stopId }) {
  let state = await StopVerificationState.findOne({ stopId });
  if (!state) {
    state = new StopVerificationState({
      stopId,
      routeId: route._id,
      routeName: route.name,
      stopIndex,
      stopName: stop.name,
      canonicalLatitude: stop.lat,
      canonicalLongitude: stop.lng,
    });
  }

  const events = await StopVerification.find({ stopId, status: { $ne: 'REJECTED' } }).sort({ timestamp: -1 });
  const hasManagerApproval = state.verificationStatus === 'VERIFIED' &&
    state.auditTrail.some((a) => a.action === 'MANAGER_APPROVED' || a.action === 'MANAGER_ADJUSTED');

  const { winningCluster, conflictingClusters, outliers } = clusterSubmissions(events);

  let recommendedLat = winningCluster ? Number(winningCluster.weightedLat.toFixed(6)) : state.candidateLatitude;
  let recommendedLng = winningCluster ? Number(winningCluster.weightedLng.toFixed(6)) : state.candidateLongitude;

  const routeValidation = recommendedLat && recommendedLng
    ? validateAgainstRouteCorridor({
        lat: recommendedLat,
        lng: recommendedLng,
        routeStops: route.stops,
        stopIndex,
      })
    : { isSuspicious: false, maxNeighborDistKm: 0, flags: [] };

  const { score, reasons } = computeDeterministicConfidence({
    winningCluster,
    conflictingClusters,
    outliers,
    events,
    routeValidation,
    candidateSource: state.candidateSource,
    hasManagerApproval,
  });

  const status = state.verificationStatus === 'FIELD_VERIFY' && events.length === 0
    ? 'FIELD_VERIFY'
    : determineLifecycleStatus({
        hasCandidate: Boolean(state.candidateLatitude && state.candidateLongitude),
        eventsCount: events.length,
        winningCluster,
        conflictingClusters,
        outliers,
        routeValidation,
        hasManagerApproval,
      });

  let studentConfirmations = 0;
  let studentCorrections = 0;
  let driverConfirmations = 0;
  let driverCorrections = 0;
  for (const ev of events) {
    const r = (ev.role || 'student').toLowerCase();
    if (r === 'driver') {
      if (ev.action === 'ADJUSTED') driverCorrections++;
      else driverConfirmations++;
    } else if (r === 'student' || r === 'user') {
      if (ev.action === 'ADJUSTED') studentCorrections++;
      else studentConfirmations++;
    }
  }

  state.recommendedLatitude = recommendedLat;
  state.recommendedLongitude = recommendedLng;
  state.verificationStatus = status;
  state.confidenceScore = score;
  state.confidenceReasons = reasons;
  state.stats = {
    confirmations: studentConfirmations + driverConfirmations,
    corrections: studentCorrections + driverCorrections,
    studentConfirmations,
    studentCorrections,
    driverConfirmations,
    driverCorrections,
    conflictingClusters: conflictingClusters.length,
    outlierCount: outliers.length,
    clusterSpreadMeters: winningCluster ? winningCluster.spreadMeters : 0,
  };
  state.updatedAt = new Date();
  await state.save();

  return { state, winningCluster, conflictingClusters, outliers };
}

async function submitStopVerification({
  route,
  stop,
  stopIndex,
  stopId,
  busId = null,
  userId,
  role,
  action,
  suggestedLatitude,
  suggestedLongitude,
  selectedLatitude,
  selectedLongitude,
  metadata = {},
}) {
  const coordCheck = validateCoordinates(selectedLatitude, selectedLongitude);
  if (!coordCheck.valid) {
    const err = new Error(coordCheck.error);
    err.statusCode = 400;
    throw err;
  }

  // Anti-spam & duplicate cooldown protection
  const cooldownCutoff = new Date(Date.now() - config.SPAM_COOLDOWN_MS);
  const recentSameUser = await StopVerification.findOne({
    stopId,
    userId: String(userId),
    timestamp: { $gte: cooldownCutoff },
  });
  if (recentSameUser) {
    const err = new Error('Please wait before submitting another verification for this stop.');
    err.statusCode = 429;
    throw err;
  }

  const activeUserSubmissions = await StopVerification.countDocuments({
    stopId,
    userId: String(userId),
    status: 'ACTIVE',
  });
  if (activeUserSubmissions >= config.MAX_ACTIVE_SUBMISSIONS_PER_USER_PER_STOP) {
    const err = new Error('Maximum verification submissions reached for this stop.');
    err.statusCode = 429;
    throw err;
  }

  const sugLat = typeof suggestedLatitude === 'number' && Number.isFinite(suggestedLatitude)
    ? suggestedLatitude
    : stop.lat;
  const sugLng = typeof suggestedLongitude === 'number' && Number.isFinite(suggestedLongitude)
    ? suggestedLongitude
    : stop.lng;

  const distanceFromSuggested = Math.round(
    haversineDistanceMeters(sugLat, sugLng, selectedLatitude, selectedLongitude)
  );
  const routeValidation = validateAgainstRouteCorridor({
    lat: selectedLatitude,
    lng: selectedLongitude,
    routeStops: route.stops,
    stopIndex,
  });

  const weight = getWeightForRoleAndAction(role, action);

  const event = await StopVerification.create({
    stopId,
    routeId: route._id,
    busId: busId || null,
    stopName: stop.name,
    userId: String(userId),
    role,
    action,
    source: sourceFromRole(role),
    suggestedLatitude: sugLat,
    suggestedLongitude: sugLng,
    selectedLatitude: Number(selectedLatitude.toFixed(6)),
    selectedLongitude: Number(selectedLongitude.toFixed(6)),
    distanceFromSuggested,
    confidenceContribution: weight,
    status: 'ACTIVE',
    routeValidation,
    metadata,
  });

  const { state } = await recomputeStopState({ route, stop, stopIndex, stopId });

  return {
    event,
    state,
    routeValidation,
  };
}

async function applyManagerDecision({
  stopId,
  decision, // 'APPROVE' | 'ADJUST' | 'REJECT' | 'FIELD_VERIFY'
  managerId,
  managerRole,
  newLatitude,
  newLongitude,
  reason = '',
}) {
  const state = await StopVerificationState.findOne({ stopId });
  if (!state) {
    const err = new Error('Stop verification state not found');
    err.statusCode = 404;
    throw err;
  }

  const route = await Route.findById(state.routeId);
  if (!route) {
    const err = new Error('Associated route not found');
    err.statusCode = 404;
    throw err;
  }

  const resolved = resolveStopFromRoute(route, stopId);
  if (!resolved) {
    const err = new Error('Stop not found on route');
    err.statusCode = 404;
    throw err;
  }

  const oldLat = route.stops[resolved.stopIndex].lat;
  const oldLng = route.stops[resolved.stopIndex].lng;

  if (decision === 'APPROVE' || decision === 'ADJUST') {
    const targetLat = decision === 'APPROVE' ? state.recommendedLatitude : Number(newLatitude);
    const targetLng = decision === 'APPROVE' ? state.recommendedLongitude : Number(newLongitude);
    const coordCheck = validateCoordinates(targetLat, targetLng);
    if (!coordCheck.valid) {
      const err = new Error(coordCheck.error);
      err.statusCode = 400;
      throw err;
    }

    route.stops[resolved.stopIndex].lat = Number(targetLat.toFixed(6));
    route.stops[resolved.stopIndex].lng = Number(targetLng.toFixed(6));
    await route.save();

    await StopVerification.updateMany({ stopId, status: 'ACTIVE' }, { $set: { status: 'APPLIED' } });

    state.canonicalLatitude = route.stops[resolved.stopIndex].lat;
    state.canonicalLongitude = route.stops[resolved.stopIndex].lng;
    state.recommendedLatitude = state.canonicalLatitude;
    state.recommendedLongitude = state.canonicalLongitude;
    state.verificationStatus = 'VERIFIED';
    state.confidenceScore = 100;
    state.confidenceReasons = [
      ...state.confidenceReasons.filter((r) => !r.includes('Manager approval')),
      'Manager approval recorded',
    ];
    state.auditTrail.push({
      who: String(managerId),
      role: managerRole,
      oldLatitude: oldLat,
      oldLongitude: oldLng,
      newLatitude: state.canonicalLatitude,
      newLongitude: state.canonicalLongitude,
      action: decision === 'APPROVE' ? 'MANAGER_APPROVED' : 'MANAGER_ADJUSTED',
      reason: reason || (decision === 'APPROVE' ? 'Approved consensus coordinate' : 'Manager map adjustment'),
      source: 'MANAGER',
      timestamp: new Date(),
    });
    state.updatedAt = new Date();
    await state.save();
    return { state, route, updatedStop: route.stops[resolved.stopIndex] };
  }

  if (decision === 'REJECT') {
    await StopVerification.updateMany({ stopId, status: 'ACTIVE' }, { $set: { status: 'REJECTED' } });
    state.recommendedLatitude = state.candidateLatitude;
    state.recommendedLongitude = state.candidateLongitude;
    state.verificationStatus = state.candidateLatitude ? 'CANDIDATE' : 'UNVERIFIED';
    state.confidenceScore = state.candidateLatitude ? 35 : 0;
    state.confidenceReasons = ['Pending submissions rejected by manager'];
    state.auditTrail.push({
      who: String(managerId),
      role: managerRole,
      oldLatitude: oldLat,
      oldLongitude: oldLng,
      newLatitude: oldLat,
      newLongitude: oldLng,
      action: 'MANAGER_REJECTED',
      reason: reason || 'Submissions rejected by manager',
      source: 'MANAGER',
      timestamp: new Date(),
    });
    state.updatedAt = new Date();
    await state.save();
    return { state, route };
  }

  if (decision === 'FIELD_VERIFY') {
    state.verificationStatus = 'FIELD_VERIFY';
    state.auditTrail.push({
      who: String(managerId),
      role: managerRole,
      oldLatitude: oldLat,
      oldLongitude: oldLng,
      newLatitude: oldLat,
      newLongitude: oldLng,
      action: 'MARKED_FIELD_VERIFY',
      reason: reason || 'Marked for physical field verification',
      source: 'MANAGER',
      timestamp: new Date(),
    });
    state.updatedAt = new Date();
    await state.save();
    return { state, route };
  }

  const err = new Error('Invalid manager decision');
  err.statusCode = 400;
  throw err;
}

module.exports = {
  haversineDistanceMeters,
  isFallbackCoordinate,
  validateCoordinates,
  getWeightForRoleAndAction,
  sourceFromRole,
  buildStopId,
  resolveStopFromRoute,
  validateAgainstRouteCorridor,
  clusterSubmissions,
  computeDeterministicConfidence,
  determineLifecycleStatus,
  generateAutomatedCandidate,
  recomputeStopState,
  submitStopVerification,
  applyManagerDecision,
};
