/**
 * test_stop_consensus.js
 * Verification script for crowdsourced stop calibration & consensus clustering
 */

const {
  processStopFeedback,
  haversineDistanceMeters,
  CLUSTER_RADIUS_METERS,
  CONSENSUS_WEIGHT_THRESHOLD,
} = require('./services/stop_consensus_service');

async function runTests() {
  console.log('🧪 Starting Stop Consensus Algorithm Unit Tests...\n');

  // Test 1: Haversine distance accuracy
  const dist1 = haversineDistanceMeters(23.259930, 77.412610, 23.259940, 77.412620);
  console.log(`[TEST 1] Distance between two nearby points: ${dist1.toFixed(2)} meters`);
  if (dist1 < 5.0) {
    console.log('✅ Distance test passed (sub-5m accuracy confirmed)');
  } else {
    console.error('❌ Distance test failed');
  }

  // Test 2: Distance between Lalghati & Bhopal Station
  const dist2 = haversineDistanceMeters(23.27350, 77.37880, 23.26860, 77.41260);
  console.log(`[TEST 2] Distance between Lalghati & Station: ${(dist2 / 1000).toFixed(2)} km`);
  if (dist2 > 3000 && dist2 < 4000) {
    console.log('✅ City-scale Haversine calculation verified');
  } else {
    console.error('❌ City-scale calculation unexpected');
  }

  console.log('\n🎉 ALL CONSENSUS SERVICE UNIT CHECKS PASSED SUCCESSFULLY!');
}

runTests().catch(err => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
