process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'sistec_test_secure_jwt_secret_stop_verify_777';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');

const Route = require('../models/Route');
const User = require('../models/User');
const Driver = require('../models/Driver');
const Manager = require('../models/Manager');
const StopVerification = require('../models/StopVerification');
const StopVerificationState = require('../models/StopVerificationState');
const createStopVerificationRouter = require('../routes/stop_verification_routes');
const service = require('../services/stop_verification_service');
const config = require('../config/stop_verification_config');

// In-memory stores for isolated testing (0 production DB touches)
const mem = {
  routes: new Map(),
  verifications: [],
  states: new Map(),
  accounts: new Map(),
};

function resetMem() {
  mem.routes.clear();
  mem.verifications = [];
  mem.states.clear();
  mem.accounts.clear();

  const route1Id = new mongoose.Types.ObjectId('6ab085331891ca28045fac01');
  const route2Id = new mongoose.Types.ObjectId('6ab085331891ca28045fac02');
  const stop1Id = new mongoose.Types.ObjectId('6ab085331891ca28045fa101');
  const stop2Id = new mongoose.Types.ObjectId('6ab085331891ca28045fa102');
  const stop3Id = new mongoose.Types.ObjectId('6ab085331891ca28045fa201');

  const route1 = {
    _id: route1Id,
    name: 'Bus 07 - Gehnu Kheda & Kolar Route',
    stops: [
      { _id: stop1Id, name: 'Kolar Road', lat: 23.1750, lng: 77.4200, time: '07:45 AM' },
      { _id: stop2Id, name: 'Banjari', lat: 23.180302, lng: 77.302695, time: '07:50 AM' },
    ],
    async save() {
      mem.routes.set(this._id.toString(), this);
      return this;
    },
  };

  const route2 = {
    _id: route2Id,
    name: 'Bus 02 - Kolar Road & DPS School Route',
    stops: [
      { _id: stop3Id, name: '610 Colony', lat: 23.180302, lng: 77.302695, time: '07:30 AM' },
    ],
    async save() {
      mem.routes.set(this._id.toString(), this);
      return this;
    },
  };

  mem.routes.set(route1Id.toString(), route1);
  mem.routes.set(route2Id.toString(), route2);

  mem.accounts.set('student1', { _id: 'student1', role: 'user', status: 'Active', tokenVersion: 0 });
  mem.accounts.set('student2', { _id: 'student2', role: 'user', status: 'Active', tokenVersion: 0 });
  mem.accounts.set('student3', { _id: 'student3', role: 'user', status: 'Active', tokenVersion: 0 });
  mem.accounts.set('driver1', { _id: 'driver1', role: 'driver', status: 'Active', tokenVersion: 0 });
  mem.accounts.set('manager1', { _id: 'manager1', role: 'manager', status: 'Active', tokenVersion: 0 });
  mem.accounts.set('guest1', { _id: 'guest1', role: 'guest', status: 'Active', tokenVersion: 0 });
}

// Lightweight query chain helper
function makeFindChain(items) {
  const chain = {
    _items: [...items],
    sort(spec) {
      if (spec && spec.timestamp === -1) {
        this._items.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
      }
      return this;
    },
    select() { return this; },
    limit(n) { this._items = this._items.slice(0, n); return this; },
    lean() { return Promise.resolve(this._items); },
    then(resolve, reject) { return Promise.resolve(this._items).then(resolve, reject); },
  };
  return chain;
}

// Install model stubs
function installStubs() {
  const selectWrapper = (doc) => ({
    select: async () => doc,
    then: (res, rej) => Promise.resolve(doc).then(res, rej),
  });

  User.findById = (id) => selectWrapper(mem.accounts.get(String(id)) || null);
  Driver.findById = (id) => selectWrapper(mem.accounts.get(String(id)) || null);
  Manager.findById = (id) => selectWrapper(mem.accounts.get(String(id)) || null);

  Route.findById = async (id) => mem.routes.get(String(id)) || null;
  Route.findOne = async (query) => {
    if (query && query['stops._id']) {
      const sid = String(query['stops._id']);
      for (const r of mem.routes.values()) {
        if (r.stops.some((s) => s._id.toString() === sid)) return r;
      }
    }
    return null;
  };

  StopVerification.create = async (doc) => {
    const record = {
      _id: new mongoose.Types.ObjectId(),
      timestamp: new Date(),
      status: 'ACTIVE',
      ...doc,
    };
    mem.verifications.push(record);
    return record;
  };

  StopVerification.findOne = async (query) => {
    const matches = mem.verifications.filter((v) => {
      if (query.stopId && v.stopId !== query.stopId) return false;
      if (query.userId && v.userId !== query.userId) return false;
      if (query.timestamp && query.timestamp.$gte && new Date(v.timestamp) < query.timestamp.$gte) return false;
      return true;
    });
    return matches[matches.length - 1] || null;
  };

  StopVerification.countDocuments = async (query) => {
    return mem.verifications.filter((v) => {
      if (query.stopId && v.stopId !== query.stopId) return false;
      if (query.userId && v.userId !== query.userId) return false;
      if (query.status && v.status !== query.status) return false;
      return true;
    }).length;
  };

  StopVerification.find = (query) => {
    const matches = mem.verifications.filter((v) => {
      if (query.stopId && v.stopId !== query.stopId) return false;
      if (query.status && query.status.$ne && v.status === query.status.$ne) return false;
      return true;
    });
    return makeFindChain(matches);
  };

  StopVerification.updateMany = async (query, update) => {
    for (const v of mem.verifications) {
      if (query.stopId && v.stopId !== query.stopId) continue;
      if (query.status && v.status !== query.status) continue;
      if (update.$set && update.$set.status) v.status = update.$set.status;
    }
  };

  StopVerificationState.findOne = (query) => {
    const doc = mem.states.get(String(query.stopId)) || null;
    return {
      lean: async () => (doc ? JSON.parse(JSON.stringify(doc)) : null),
      then: (res, rej) => Promise.resolve(doc).then(res, rej),
    };
  };

  StopVerificationState.find = (filter = {}) => {
    const items = [...mem.states.values()].filter((s) => {
      if (filter.routeId && String(s.routeId) !== String(filter.routeId)) return false;
      if (filter.verificationStatus && s.verificationStatus !== filter.verificationStatus) return false;
      return true;
    });
    return makeFindChain(items);
  };

  // Monkey-patch prototype save for StopVerificationState
  StopVerificationState.prototype.save = async function () {
    const plain = this.toObject ? this.toObject() : { ...this };
    const wrapped = {
      ...plain,
      save: async () => {
        mem.states.set(plain.stopId, wrapped);
        return wrapped;
      },
    };
    mem.states.set(plain.stopId, wrapped);
    return wrapped;
  };
}

function makeToken(id, role) {
  return jwt.sign({ user: { id, role, tokenVersion: 0 } }, process.env.JWT_SECRET, { expiresIn: '1h' });
}

let server;
let baseUrl;

test.before(async () => {
  installStubs();
  const app = express();
  app.use(express.json());
  const emitted = [];
  const io = { emit: (ev, data) => emitted.push({ ev, data }) };
  app.use('/api', createStopVerificationRouter(io));
  await new Promise((resolve) => {
    server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      baseUrl = `http://127.0.0.1:${addr.port}`;
      resolve();
    });
  });
});

test.after(async () => {
  if (server) await new Promise((r) => server.close(r));
});

test.beforeEach(() => {
  resetMem();
});

async function api(path, method = 'GET', body = null, token = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  return { status: res.status, json };
}

const STOP1 = '6ab085331891ca28045fa101';
const STOP2 = '6ab085331891ca28045fa102';
const STOP3 = '6ab085331891ca28045fa201';
const ROUTE1 = '6ab085331891ca28045fac01';

test('1. Valid verification & 7. Confirmation event (does NOT mutate canonical coord)', async () => {
  const token = makeToken('student1', 'user');
  const res = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'CONFIRMED',
    suggestedLatitude: 23.1750,
    suggestedLongitude: 77.4200,
    selectedLatitude: 23.1750,
    selectedLongitude: 77.4200,
  }, token);

  assert.equal(res.status, 201);
  assert.equal(res.json.success, true);
  assert.equal(res.json.action, 'CONFIRMED');
  assert.equal(res.json.verificationStatus, 'NEEDS_REVIEW');
  assert.equal(mem.verifications[0].source, 'USER');
  assert.equal(mem.routes.get(ROUTE1).stops[0].lat, 23.1750);
});

test('2. Invalid latitude rejected (NaN, >90, <-90)', async () => {
  const token = makeToken('student1', 'user');
  for (const lat of [91.5, -90.1, 'not-a-number']) {
    const res = await api(`/api/stops/${STOP1}/verification`, 'POST', {
      routeId: ROUTE1,
      action: 'ADJUSTED',
      selectedLatitude: lat,
      selectedLongitude: 77.42,
    }, token);
    assert.equal(res.status, 400);
  }
});

test('3. Invalid longitude rejected (>180, <-180, null island 0,0)', async () => {
  const token = makeToken('student1', 'user');
  const res1 = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'ADJUSTED',
    selectedLatitude: 23.17,
    selectedLongitude: 181.2,
  }, token);
  assert.equal(res1.status, 400);

  const res2 = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'ADJUSTED',
    selectedLatitude: 0,
    selectedLongitude: 0,
  }, token);
  assert.equal(res2.status, 400);
});

test('4. Unauthenticated submission rejected with 401', async () => {
  const res = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'CONFIRMED',
    selectedLatitude: 23.175,
    selectedLongitude: 77.42,
  });
  assert.equal(res.status, 401);
});

test('5. Unauthorized role rejected (non-manager on manager endpoint & guest on verification)', async () => {
  const studentToken = makeToken('student1', 'user');
  const mgrRes = await api(`/api/manager/stops/${STOP1}/approve-location`, 'POST', {}, studentToken);
  assert.equal(mgrRes.status, 403);

  const guestToken = makeToken('guest1', 'guest');
  const guestRes = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'CONFIRMED',
    selectedLatitude: 23.175,
    selectedLongitude: 77.42,
  }, guestToken);
  assert.equal(guestRes.status, 401);
});

test('6. Duplicate / spam protection enforces cooldown per user per stop', async () => {
  const token = makeToken('student1', 'user');
  const first = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'CONFIRMED',
    selectedLatitude: 23.175,
    selectedLongitude: 77.42,
  }, token);
  assert.equal(first.status, 201);

  const second = await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'CONFIRMED',
    selectedLatitude: 23.175,
    selectedLongitude: 77.42,
  }, token);
  assert.equal(second.status, 429);
});

test('8. Adjusted coordinate stored as suggestion without overwriting canonical stop', async () => {
  const token = makeToken('student1', 'user');
  const res = await api(`/api/stops/${STOP2}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'ADJUSTED',
    suggestedLatitude: 23.180302,
    suggestedLongitude: 77.302695,
    selectedLatitude: 23.17727,
    selectedLongitude: 77.424092,
  }, token);

  assert.equal(res.status, 201);
  assert.equal(res.json.canonicalLatitude, 23.180302);
  assert.equal(res.json.recommendedLatitude, 23.17727);
  assert.equal(mem.routes.get(ROUTE1).stops[1].lat, 23.180302);
});

test('9. Multiple submissions, 10. Clustering, 11. Weighted consensus (Driver=5 > Student=1)', async () => {
  const events = [
    { role: 'student', action: 'ADJUSTED', selectedLatitude: 23.180100, selectedLongitude: 77.302900, confidenceContribution: config.VERIFICATION_WEIGHTS.studentCorrection, timestamp: new Date() },
    { role: 'student', action: 'ADJUSTED', selectedLatitude: 23.180150, selectedLongitude: 77.302950, confidenceContribution: config.VERIFICATION_WEIGHTS.studentCorrection, timestamp: new Date() },
    { role: 'driver', action: 'ADJUSTED', selectedLatitude: 23.180130, selectedLongitude: 77.302920, confidenceContribution: config.VERIFICATION_WEIGHTS.driverCorrection, timestamp: new Date() },
  ];
  const { winningCluster, conflictingClusters, outliers } = service.clusterSubmissions(events);
  assert.ok(winningCluster);
  assert.equal(winningCluster.totalWeight, 7);
  assert.equal(conflictingClusters.length, 0);
  assert.equal(outliers.length, 0);
  // Weighted centroid should be pulled strongly toward driver's 23.180130
  assert.ok(Math.abs(winningCluster.weightedLat - 23.180129) < 0.00001);
});

test('12. Conflicting clusters detected when secondary cluster >= 30% weight & >100m away', () => {
  const events = [
    { role: 'driver', action: 'ADJUSTED', selectedLatitude: 23.1772, selectedLongitude: 77.4240, confidenceContribution: 5, timestamp: new Date() },
    { role: 'student', action: 'ADJUSTED', selectedLatitude: 23.1850, selectedLongitude: 77.4300, confidenceContribution: 1, timestamp: new Date() },
    { role: 'student', action: 'ADJUSTED', selectedLatitude: 23.1851, selectedLongitude: 77.4301, confidenceContribution: 1, timestamp: new Date() },
  ];
  const { winningCluster, conflictingClusters } = service.clusterSubmissions(events);
  assert.ok(winningCluster);
  assert.equal(conflictingClusters.length, 1);
});

test('13. Outlier rejection & 18. Route-aware validation flags >60 km district outlier', async () => {
  const token = makeToken('student1', 'user');
  const res = await api(`/api/stops/${STOP2}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'ADJUSTED',
    selectedLatitude: 23.7500, // > 60km away
    selectedLongitude: 76.5000,
  }, token);
  assert.equal(res.status, 201);
  assert.equal(res.json.routeValidation.isSuspicious, true);
  assert.ok(res.json.routeValidation.flags.includes('SUSPICIOUS_DISTANCE_OVER_60KM'));
  assert.equal(res.json.verificationStatus, 'FIELD_VERIFY');
});

test('14. Deterministic explainable confidence calculation', () => {
  const events = [
    { role: 'student', action: 'CONFIRMED', selectedLatitude: 23.1772, selectedLongitude: 77.4240, confidenceContribution: 1, timestamp: new Date() },
    { role: 'driver', action: 'CONFIRMED', selectedLatitude: 23.17721, selectedLongitude: 77.42401, confidenceContribution: 5, timestamp: new Date() },
  ];
  const { winningCluster, conflictingClusters, outliers } = service.clusterSubmissions(events);
  const conf = service.computeDeterministicConfidence({
    winningCluster,
    conflictingClusters,
    outliers,
    events,
    routeValidation: { isSuspicious: false },
    hasManagerApproval: false,
  });
  assert.ok(conf.score >= 55 && conf.score <= 100);
  assert.ok(conf.reasons.some((r) => r.includes('1 student confirmation')));
  assert.ok(conf.reasons.some((r) => r.includes('1 driver confirmation')));
  assert.ok(conf.reasons.some((r) => r.includes('0 conflicting cluster')));
});

test('15. Manager approval, 16. Manager adjustment, & 17. Audit trail', async () => {
  const driverToken = makeToken('driver1', 'driver');
  await api(`/api/stops/${STOP2}/verification`, 'POST', {
    routeId: ROUTE1,
    action: 'ADJUSTED',
    selectedLatitude: 23.17727,
    selectedLongitude: 77.424092,
  }, driverToken);

  const mgrToken = makeToken('manager1', 'manager');
  const approveRes = await api(`/api/manager/stops/${STOP2}/approve-location`, 'POST', {
    reason: 'Verified against Kolar corridor',
  }, mgrToken);
  assert.equal(approveRes.status, 200);
  assert.equal(approveRes.json.state.verificationStatus, 'VERIFIED');
  assert.equal(mem.routes.get(ROUTE1).stops[1].lat, 23.17727);
  assert.equal(approveRes.json.state.auditTrail.length, 1);
  assert.equal(approveRes.json.state.auditTrail[0].action, 'MANAGER_APPROVED');
  assert.equal(approveRes.json.state.auditTrail[0].oldLatitude, 23.180302);
  assert.equal(approveRes.json.state.auditTrail[0].newLatitude, 23.17727);

  const adjustRes = await api(`/api/manager/stops/${STOP2}/adjust-location`, 'POST', {
    latitude: 23.1775,
    longitude: 77.4242,
    reason: 'Fine-tuned boarding bay',
  }, mgrToken);
  assert.equal(adjustRes.status, 200);
  assert.equal(mem.routes.get(ROUTE1).stops[1].lat, 23.1775);
  assert.equal(adjustRes.json.state.auditTrail.length, 2);
  assert.equal(adjustRes.json.state.auditTrail[1].action, 'MANAGER_ADJUSTED');
});

test('19. Stop isolation, 20. Multiple routes, & 21. Multiple buses', async () => {
  const s1 = makeToken('student1', 'user');
  const s2 = makeToken('student2', 'user');
  const busA = new mongoose.Types.ObjectId().toString();
  const busB = new mongoose.Types.ObjectId().toString();

  await api(`/api/stops/${STOP1}/verification`, 'POST', {
    routeId: ROUTE1,
    busId: busA,
    action: 'CONFIRMED',
    selectedLatitude: 23.175,
    selectedLongitude: 77.420,
  }, s1);

  await api(`/api/stops/${STOP3}/verification`, 'POST', {
    busId: busB,
    action: 'ADJUSTED',
    selectedLatitude: 23.245,
    selectedLongitude: 77.419,
  }, s2);

  const sum1 = await api(`/api/stops/${STOP1}/verification-summary`, 'GET', null, s1);
  const sum3 = await api(`/api/stops/${STOP3}/verification-summary`, 'GET', null, s2);
  assert.equal(sum1.json.summary.stopName, 'Kolar Road');
  assert.equal(sum3.json.summary.stopName, '610 Colony');
  assert.notEqual(sum1.json.summary.routeName, sum3.json.summary.routeName);
});

test('22. Concurrent submissions from multiple users converge cleanly', async () => {
  const tokens = [
    makeToken('student1', 'user'),
    makeToken('student2', 'user'),
    makeToken('driver1', 'driver'),
  ];
  const results = await Promise.all(
    tokens.map((tok, i) =>
      api(`/api/stops/${STOP2}/verification`, 'POST', {
        routeId: ROUTE1,
        action: 'ADJUSTED',
        selectedLatitude: 23.1772 + i * 0.00001,
        selectedLongitude: 77.4240 + i * 0.00001,
      }, tok)
    )
  );
  assert.ok(results.every((r) => r.status === 201));
  const summary = await api(`/api/stops/${STOP2}/verification-summary`, 'GET', null, tokens[0]);
  assert.equal(summary.status, 200);
  assert.equal(summary.json.summary.stats.studentCorrections, 2);
  assert.equal(summary.json.summary.stats.driverCorrections, 1);
});
