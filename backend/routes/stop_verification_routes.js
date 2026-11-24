const express = require('express');
const rateLimit = require('express-rate-limit');
const mongoose = require('mongoose');
const Route = require('../models/Route');
const StopVerification = require('../models/StopVerification');
const StopVerificationState = require('../models/StopVerificationState');
const config = require('../config/stop_verification_config');
const { authMiddleware, managerMiddleware } = require('../middleware/authMiddleware');
const {
  buildStopId,
  resolveStopFromRoute,
  generateAutomatedCandidate,
  submitStopVerification,
  applyManagerDecision,
} = require('../services/stop_verification_service');

function createStopVerificationRouter(io) {
  const router = express.Router();

  const verificationLimiter = rateLimit({
    windowMs: config.RATE_LIMIT_WINDOW_MS,
    max: config.RATE_LIMIT_MAX_REQUESTS,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many stop verification requests. Please try again later.' },
  });

  async function findRouteAndStop(stopId, routeIdHint = null) {
    const cleanStopId = String(stopId || '').trim();
    if (!cleanStopId || cleanStopId.length > 120 || !/^[a-zA-Z0-9:_-]+$/.test(cleanStopId)) {
      return null;
    }

    if (routeIdHint && mongoose.Types.ObjectId.isValid(routeIdHint)) {
      const route = await Route.findById(routeIdHint);
      if (route) {
        const resolved = resolveStopFromRoute(route, cleanStopId);
        if (resolved) return { route, ...resolved };
      }
    }

    // Fallback: parse routeId:index format
    if (cleanStopId.includes(':')) {
      const [rid] = cleanStopId.split(':');
      if (mongoose.Types.ObjectId.isValid(rid)) {
        const route = await Route.findById(rid);
        if (route) {
          const resolved = resolveStopFromRoute(route, cleanStopId);
          if (resolved) return { route, ...resolved };
        }
      }
    }

    // Fallback: search by embedded stop subdocument _id
    if (mongoose.Types.ObjectId.isValid(cleanStopId)) {
      const route = await Route.findOne({ 'stops._id': cleanStopId });
      if (route) {
        const resolved = resolveStopFromRoute(route, cleanStopId);
        if (resolved) return { route, ...resolved };
      }
    }

    return null;
  }

  // POST /api/stops/:stopId/verification — Student/Driver/Manager submits CONFIRMED or ADJUSTED
  router.post('/stops/:stopId/verification', authMiddleware, verificationLimiter, async (req, res) => {
    try {
      const role = (req.user?.role || '').toLowerCase();
      if (!['user', 'student', 'driver', 'manager', 'admin'].includes(role)) {
        return res.status(403).json({ error: 'Unauthorized role for stop verification' });
      }

      const {
        routeId,
        busId,
        action,
        suggestedLatitude,
        suggestedLongitude,
        selectedLatitude,
        selectedLongitude,
        metadata,
      } = req.body || {};

      if (!action || !['CONFIRMED', 'ADJUSTED'].includes(action)) {
        return res.status(400).json({ error: 'action must be CONFIRMED or ADJUSTED' });
      }

      const target = await findRouteAndStop(req.params.stopId, routeId);
      if (!target) {
        return res.status(404).json({ error: 'Stop not found' });
      }

      const selLat = Number(selectedLatitude);
      const selLng = Number(selectedLongitude);
      const sugLat = suggestedLatitude !== undefined ? Number(suggestedLatitude) : target.stop.lat;
      const sugLng = suggestedLongitude !== undefined ? Number(suggestedLongitude) : target.stop.lng;

      const result = await submitStopVerification({
        route: target.route,
        stop: target.stop,
        stopIndex: target.stopIndex,
        stopId: target.stopId,
        busId: busId && mongoose.Types.ObjectId.isValid(busId) ? busId : null,
        userId: req.user.id || req.user._id,
        role,
        action,
        suggestedLatitude: sugLat,
        suggestedLongitude: sugLng,
        selectedLatitude: selLat,
        selectedLongitude: selLng,
        metadata: metadata && typeof metadata === 'object' ? { accuracy: metadata.accuracy, note: metadata.note } : {},
      });

      return res.status(201).json({
        success: true,
        stopId: target.stopId,
        action,
        verificationStatus: result.state.verificationStatus,
        confidenceScore: result.state.confidenceScore,
        confidenceReasons: result.state.confidenceReasons,
        recommendedLatitude: result.state.recommendedLatitude,
        recommendedLongitude: result.state.recommendedLongitude,
        canonicalLatitude: result.state.canonicalLatitude,
        canonicalLongitude: result.state.canonicalLongitude,
        routeValidation: result.routeValidation,
      });
    } catch (err) {
      const status = err.statusCode || 500;
      return res.status(status).json({ error: err.message || 'Failed to record stop verification' });
    }
  });

  // GET /api/stops/:stopId/verification-summary — Summary for Student/Driver verification UI
  router.get('/stops/:stopId/verification-summary', authMiddleware, async (req, res) => {
    try {
      const target = await findRouteAndStop(req.params.stopId, req.query.routeId);
      if (!target) {
        return res.status(404).json({ error: 'Stop not found' });
      }

      let state = await StopVerificationState.findOne({ stopId: target.stopId }).lean();
      if (!state) {
        const candidate = generateAutomatedCandidate({
          stop: target.stop,
          routeStops: target.route.stops,
          stopIndex: target.stopIndex,
        });
        state = {
          stopId: target.stopId,
          routeId: target.route._id,
          routeName: target.route.name,
          stopIndex: target.stopIndex,
          stopName: target.stop.name,
          canonicalLatitude: target.stop.lat,
          canonicalLongitude: target.stop.lng,
          candidateLatitude: candidate ? candidate.candidateLatitude : null,
          candidateLongitude: candidate ? candidate.candidateLongitude : null,
          candidateSource: candidate ? candidate.candidateSource : null,
          candidateConfidence: candidate ? candidate.candidateConfidence : null,
          recommendedLatitude: candidate ? candidate.candidateLatitude : target.stop.lat,
          recommendedLongitude: candidate ? candidate.candidateLongitude : target.stop.lng,
          verificationStatus: candidate ? 'CANDIDATE' : 'UNVERIFIED',
          confidenceScore: candidate ? candidate.candidateConfidence : 0,
          confidenceReasons: candidate ? [`Automated candidate (${candidate.candidateSource})`] : ['Unverified stop'],
          stats: {
            confirmations: 0,
            corrections: 0,
            studentConfirmations: 0,
            studentCorrections: 0,
            driverConfirmations: 0,
            driverCorrections: 0,
            conflictingClusters: 0,
            outlierCount: 0,
            clusterSpreadMeters: 0,
          },
        };
      }

      return res.json({
        success: true,
        summary: {
          stopId: state.stopId,
          routeId: state.routeId,
          routeName: state.routeName,
          stopIndex: state.stopIndex,
          stopName: state.stopName,
          canonicalLatitude: state.canonicalLatitude,
          canonicalLongitude: state.canonicalLongitude,
          suggestedLatitude: state.recommendedLatitude || state.candidateLatitude || state.canonicalLatitude,
          suggestedLongitude: state.recommendedLongitude || state.candidateLongitude || state.canonicalLongitude,
          candidateLatitude: state.candidateLatitude,
          candidateLongitude: state.candidateLongitude,
          candidateSource: state.candidateSource,
          verificationStatus: state.verificationStatus,
          confidenceScore: state.confidenceScore,
          confidenceReasons: state.confidenceReasons,
          stats: state.stats,
          routeContext: {
            totalStops: target.route.stops.length,
            previousStop: target.stopIndex > 0 ? target.route.stops[target.stopIndex - 1]?.name : null,
            nextStop: target.stopIndex < target.route.stops.length - 1 ? target.route.stops[target.stopIndex + 1]?.name : null,
          },
        },
      });
    } catch (err) {
      return res.status(500).json({ error: 'Failed to load stop verification summary' });
    }
  });

  // GET /api/manager/stops/verification — Manager dashboard list (no sensitive PII)
  router.get('/manager/stops/verification', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const filter = {};
      if (req.query.routeId && mongoose.Types.ObjectId.isValid(req.query.routeId)) {
        filter.routeId = req.query.routeId;
      }
      if (req.query.status) {
        filter.verificationStatus = String(req.query.status).toUpperCase();
      }

      const states = await StopVerificationState.find(filter)
        .select('-__v')
        .sort({ verificationStatus: 1, confidenceScore: -1, updatedAt: -1 })
        .limit(250)
        .lean();

      return res.json({
        success: true,
        count: states.length,
        stops: states.map((s) => ({
          stopId: s.stopId,
          routeId: s.routeId,
          routeName: s.routeName,
          stopIndex: s.stopIndex,
          stopName: s.stopName,
          canonicalLatitude: s.canonicalLatitude,
          canonicalLongitude: s.canonicalLongitude,
          recommendedLatitude: s.recommendedLatitude,
          recommendedLongitude: s.recommendedLongitude,
          candidateLatitude: s.candidateLatitude,
          candidateLongitude: s.candidateLongitude,
          verificationStatus: s.verificationStatus,
          confidenceScore: s.confidenceScore,
          confidenceReasons: s.confidenceReasons,
          stats: s.stats,
          updatedAt: s.updatedAt,
        })),
      });
    } catch (err) {
      return res.status(500).json({ error: 'Failed to load manager stop verifications' });
    }
  });

  // GET /api/manager/stops/:stopId/verification — Detailed manager view (sanitized, no user PII)
  router.get('/manager/stops/:stopId/verification', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const state = await StopVerificationState.findOne({ stopId: req.params.stopId }).lean();
      if (!state) {
        return res.status(404).json({ error: 'Stop verification record not found' });
      }

      const events = await StopVerification.find({ stopId: req.params.stopId })
        .select('role action source selectedLatitude selectedLongitude distanceFromSuggested confidenceContribution status routeValidation timestamp')
        .sort({ timestamp: -1 })
        .limit(50)
        .lean();

      return res.json({
        success: true,
        state,
        submissions: events,
      });
    } catch (err) {
      return res.status(500).json({ error: 'Failed to load stop verification details' });
    }
  });

  // POST /api/manager/stops/:stopId/approve-location
  router.post('/manager/stops/:stopId/approve-location', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const { reason } = req.body || {};
      const result = await applyManagerDecision({
        stopId: req.params.stopId,
        decision: 'APPROVE',
        managerId: req.user.id || req.user._id,
        managerRole: req.user.role,
        reason,
      });

      if (io) {
        io.emit('route_stop_calibrated', {
          routeId: result.route._id,
          routeName: result.route.name,
          stopName: result.updatedStop.name,
          newLat: result.updatedStop.lat,
          newLng: result.updatedStop.lng,
          message: `Manager approved verified location for "${result.updatedStop.name}".`,
        });
      }

      return res.json({
        success: true,
        message: 'Recommended stop location approved and canonical coordinate updated.',
        state: result.state,
      });
    } catch (err) {
      return res.status(err.statusCode || 500).json({ error: err.message || 'Approval failed' });
    }
  });

  // POST /api/manager/stops/:stopId/adjust-location
  router.post('/manager/stops/:stopId/adjust-location', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const { latitude, longitude, reason } = req.body || {};
      const result = await applyManagerDecision({
        stopId: req.params.stopId,
        decision: 'ADJUST',
        managerId: req.user.id || req.user._id,
        managerRole: req.user.role,
        newLatitude: Number(latitude),
        newLongitude: Number(longitude),
        reason,
      });

      if (io) {
        io.emit('route_stop_calibrated', {
          routeId: result.route._id,
          routeName: result.route.name,
          stopName: result.updatedStop.name,
          newLat: result.updatedStop.lat,
          newLng: result.updatedStop.lng,
          message: `Manager adjusted location for "${result.updatedStop.name}".`,
        });
      }

      return res.json({
        success: true,
        message: 'Stop location adjusted by manager and canonical coordinate updated.',
        state: result.state,
      });
    } catch (err) {
      return res.status(err.statusCode || 500).json({ error: err.message || 'Adjustment failed' });
    }
  });

  // POST /api/manager/stops/:stopId/reject-submissions
  router.post('/manager/stops/:stopId/reject-submissions', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const { reason } = req.body || {};
      const result = await applyManagerDecision({
        stopId: req.params.stopId,
        decision: 'REJECT',
        managerId: req.user.id || req.user._id,
        managerRole: req.user.role,
        reason,
      });
      return res.json({ success: true, message: 'Pending submissions rejected.', state: result.state });
    } catch (err) {
      return res.status(err.statusCode || 500).json({ error: err.message || 'Rejection failed' });
    }
  });

  // POST /api/manager/stops/:stopId/field-verify
  router.post('/manager/stops/:stopId/field-verify', authMiddleware, managerMiddleware, async (req, res) => {
    try {
      const { reason } = req.body || {};
      const result = await applyManagerDecision({
        stopId: req.params.stopId,
        decision: 'FIELD_VERIFY',
        managerId: req.user.id || req.user._id,
        managerRole: req.user.role,
        reason,
      });
      return res.json({ success: true, message: 'Stop marked for field verification.', state: result.state });
    } catch (err) {
      return res.status(err.statusCode || 500).json({ error: err.message || 'Field verify update failed' });
    }
  });

  return router;
}

module.exports = createStopVerificationRouter;
