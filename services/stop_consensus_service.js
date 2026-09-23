/**
 * stop_consensus_service.js
 * 
 * Community-driven consensus & auto-calibration engine for bus stop GPS coordinates.
 * Inspired by the "Where Is My Train" crowdsourced railway station calibration algorithm.
 */

const StopFeedback = require('../models/StopFeedback');
const Route = require('../models/Route');

// Maximum distance in meters between two GPS reports to be considered the same physical bus stop cluster
const CLUSTER_RADIUS_METERS = 45.0;

// Minimum weighted score required to trigger automatic database calibration
const CONSENSUS_WEIGHT_THRESHOLD = 3.0;

// Haversine distance in meters
function haversineDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth radius in meters
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// User role weights: Drivers have verified hardware on the bus; admins are authoritative
function getRoleWeight(role) {
  switch (role) {
    case 'admin':
    case 'manager':
      return 3.0;
    case 'driver':
      return 2.5;
    case 'student':
    case 'user':
    default:
      return 1.0;
  }
}

/**
 * Process new stop feedback and evaluate if consensus is reached
 */
async function processStopFeedback(feedbackData) {
  const {
    routeId,
    routeName,
    stopName,
    userId,
    userName,
    userRole,
    feedbackType,
    suggestedLat,
    suggestedLng,
    accuracy,
    comment,
  } = feedbackData;

  // 1. Create and save new feedback record
  const newFeedback = new StopFeedback({
    routeId,
    routeName,
    stopName: stopName.trim(),
    userId,
    userName: userName || 'Anonymous Passenger',
    userRole: userRole || 'student',
    feedbackType,
    suggestedLat,
    suggestedLng,
    accuracy: accuracy || 10,
    comment,
    status: 'pending',
  });

  await newFeedback.save();

  // If user is just confirming existing location is correct (👍)
  if (feedbackType === 'confirm_correct' || !suggestedLat || !suggestedLng) {
    return {
      feedbackId: newFeedback._id,
      feedbackType,
      autoApplied: false,
      message: 'Thank you! Your verification has been recorded.',
    };
  }

  // 2. Query all pending location suggestions for this stop
  const pendingSuggestions = await StopFeedback.find({
    routeId,
    stopName: new RegExp(`^${escapeRegex(stopName.trim())}$`, 'i'),
    feedbackType: { $in: ['suggest_location', 'stop_moved'] },
    status: 'pending',
    suggestedLat: { $ne: null },
    suggestedLng: { $ne: null },
  });

  // 3. Cluster suggestions by proximity (within CLUSTER_RADIUS_METERS)
  const clusters = [];
  for (const item of pendingSuggestions) {
    let placedInCluster = false;
    for (const cluster of clusters) {
      const dist = haversineDistanceMeters(
        item.suggestedLat,
        item.suggestedLng,
        cluster.centerLat,
        cluster.centerLng
      );
      if (dist <= CLUSTER_RADIUS_METERS) {
        cluster.items.push(item);
        // Recalculate simple midpoint for cluster boundary check
        cluster.centerLat = cluster.items.reduce((s, x) => s + x.suggestedLat, 0) / cluster.items.length;
        cluster.centerLng = cluster.items.reduce((s, x) => s + x.suggestedLng, 0) / cluster.items.length;
        placedInCluster = true;
        break;
      }
    }
    if (!placedInCluster) {
      clusters.push({
        centerLat: item.suggestedLat,
        centerLng: item.suggestedLng,
        items: [item],
      });
    }
  }

  // 4. Find largest/highest-weight cluster
  let winningCluster = null;
  let maxWeight = 0;

  for (const cluster of clusters) {
    let totalWeight = 0;
    for (const item of cluster.items) {
      totalWeight += getRoleWeight(item.userRole);
    }
    cluster.totalWeight = totalWeight;
    if (totalWeight > maxWeight) {
      maxWeight = totalWeight;
      winningCluster = cluster;
    }
  }

  // 5. If weight meets or exceeds consensus threshold, auto-apply!
  if (winningCluster && winningCluster.totalWeight >= CONSENSUS_WEIGHT_THRESHOLD) {
    // Calculate precision weighted centroid
    let weightedLatSum = 0;
    let weightedLngSum = 0;
    let sumWeight = 0;

    for (const item of winningCluster.items) {
      const w = getRoleWeight(item.userRole);
      weightedLatSum += item.suggestedLat * w;
      weightedLngSum += item.suggestedLng * w;
      sumWeight += w;
    }

    const consensusLat = Number((weightedLatSum / sumWeight).toFixed(6));
    const consensusLng = Number((weightedLngSum / sumWeight).toFixed(6));

    // Update Route stop in MongoDB
    const route = await Route.findById(routeId);
    if (route && route.stops) {
      const stopIndex = route.stops.findIndex(
        s => s.name && s.name.trim().toLowerCase() === stopName.trim().toLowerCase()
      );

      if (stopIndex !== -1) {
        const oldLat = route.stops[stopIndex].lat;
        const oldLng = route.stops[stopIndex].lng;

        route.stops[stopIndex].lat = consensusLat;
        route.stops[stopIndex].lng = consensusLng;
        await route.save();

        // Mark items as applied
        const itemIds = winningCluster.items.map(i => i._id);
        await StopFeedback.updateMany(
          { _id: { $in: itemIds } },
          { $set: { status: 'applied' } }
        );

        return {
          feedbackId: newFeedback._id,
          autoApplied: true,
          oldLat,
          oldLng,
          newLat: consensusLat,
          newLng: consensusLng,
          consensusVotes: winningCluster.items.length,
          totalWeight: winningCluster.totalWeight,
          message: `Consensus reached! Stop "${stopName}" coordinates automatically calibrated to (${consensusLat}, ${consensusLng}).`,
        };
      }
    }
  }

  // If consensus threshold not reached yet
  const currentVotes = winningCluster ? winningCluster.items.length : 1;
  const remainingWeight = Math.max(0, CONSENSUS_WEIGHT_THRESHOLD - (winningCluster ? winningCluster.totalWeight : 1.0));

  return {
    feedbackId: newFeedback._id,
    autoApplied: false,
    currentVotes,
    remainingWeight,
    message: `Suggestion recorded! Awaiting ${Math.ceil(remainingWeight)} more vote(s) to auto-calibrate stop coordinates.`,
  };
}

/**
 * Get feedback summary & consensus status for all stops on a route
 */
async function getRouteFeedbackSummary(routeId) {
  const feedbacks = await StopFeedback.find({ routeId }).sort({ createdAt: -1 });

  const summary = {};

  for (const fb of feedbacks) {
    const sName = fb.stopName.trim();
    if (!summary[sName]) {
      summary[sName] = {
        stopName: sName,
        confirmationsCount: 0,
        pendingSuggestionsCount: 0,
        appliedCount: 0,
        recentFeedback: [],
        latestSuggestedCoords: null,
      };
    }

    if (fb.feedbackType === 'confirm_correct') {
      summary[sName].confirmationsCount++;
    } else if (fb.status === 'pending') {
      summary[sName].pendingSuggestionsCount++;
      if (!summary[sName].latestSuggestedCoords && fb.suggestedLat && fb.suggestedLng) {
        summary[sName].latestSuggestedCoords = {
          lat: fb.suggestedLat,
          lng: fb.suggestedLng,
          userName: fb.userName,
          userRole: fb.userRole,
        };
      }
    } else if (fb.status === 'applied') {
      summary[sName].appliedCount++;
    }

    if (summary[sName].recentFeedback.length < 5) {
      summary[sName].recentFeedback.push({
        id: fb._id,
        userName: fb.userName,
        userRole: fb.userRole,
        feedbackType: fb.feedbackType,
        status: fb.status,
        createdAt: fb.createdAt,
        comment: fb.comment,
        suggestedLat: fb.suggestedLat,
        suggestedLng: fb.suggestedLng,
      });
    }
  }

  return Object.values(summary);
}

function escapeRegex(text) {
  return text.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&');
}

module.exports = {
  processStopFeedback,
  getRouteFeedbackSummary,
  haversineDistanceMeters,
  CLUSTER_RADIUS_METERS,
  CONSENSUS_WEIGHT_THRESHOLD,
};
