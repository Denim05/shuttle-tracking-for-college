import React, { useState, useEffect } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import Navbar from './components/Navbar';
import Sidebar from './components/Sidebar';
import Login from './pages/Login';
import MasterTrafficDashboard from './pages/MasterTrafficDashboard';
import DashboardOverview from './pages/DashboardOverview';
import FleetRadarMap from './pages/FleetRadarMap';
import RegistrationsManager from './pages/RegistrationsManager';
import RouteManager from './pages/RouteManager';
import DriverFleetManager from './pages/DriverFleetManager';
import BroadcastSystem from './pages/BroadcastSystem';
import ReportsAnalytics from './pages/ReportsAnalytics';
import socketService from './services/socket';
import { registrationAPI } from './services/api';

export default function App() {
  const [user, setUser] = useState(null);
  const [activeTab, setActiveTab] = useState('overview');
  const [activeSOS, setActiveSOS] = useState(null);
  const [pendingRegistrationsCount, setPendingRegistrationsCount] = useState(0);

  useEffect(() => {
    // Check saved user token
    const token = localStorage.getItem('sistec_token');
    const savedUser = localStorage.getItem('sistec_user');
    if (token && savedUser) {
      try {
        setUser(JSON.parse(savedUser));
      } catch (e) {
        setUser({ name: 'Transport Manager', role: 'manager' });
      }
    }

    // Connect socket
    socketService.connect();

    // Listen for emergency SOS alerts
    socketService.onSOSAlert((alertData) => {
      setActiveSOS(alertData);
    });

    // Fetch initial pending registration count
    fetchPendingCount();

  }, []);

  const fetchPendingCount = async () => {
    try {
      const res = await registrationAPI.getAll();
      const subs = res.data?.submissions || res.data || [];
      const pending = subs.filter(s => s.status === 'pending');
      setPendingRegistrationsCount(pending.length);
    } catch (e) {
      // fallback
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('sistec_token');
    localStorage.removeItem('sistec_user');
    setUser(null);
    socketService.disconnect();
  };

  if (!user) {
    return <Login onLoginSuccess={(loggedInUser) => setUser(loggedInUser)} />;
  }

  // Full-screen executive layout matching reference image when in Master Traffic view ('overview')
  if (activeTab === 'overview') {
    return (
      <MasterTrafficDashboard activeTab={activeTab} setActiveTab={setActiveTab} />
    );
  }

  return (
    <div className="min-h-screen bg-[#060911] text-gray-100 flex flex-col font-sans">
      
      {/* Top Navbar */}
      <Navbar 
        user={user} 
        onLogout={handleLogout} 
        activeSOS={activeSOS}
        onClearSOS={() => setActiveSOS(null)}
      />

      <div className="flex flex-1 overflow-hidden">
        
        {/* Navigation Sidebar */}
        <Sidebar 
          activeTab={activeTab} 
          setActiveTab={setActiveTab} 
          pendingRegistrationsCount={pendingRegistrationsCount}
        />

        {/* Main Content Workspace with Framer Motion transitions */}
        <main className="flex-1 p-6 overflow-y-auto min-h-[calc(100vh-4rem)]">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeTab}
              initial={{ opacity: 0, x: 10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -10 }}
              transition={{ duration: 0.25 }}
            >
              {activeTab === 'overview' && (
                <MasterTrafficDashboard activeTab={activeTab} setActiveTab={setActiveTab} />
              )}

              {activeTab === 'radar' && (
                <FleetRadarMap />
              )}

              {activeTab === 'registrations' && (
                <RegistrationsManager />
              )}

              {activeTab === 'routes' && (
                <RouteManager />
              )}

              {activeTab === 'drivers' && (
                <DriverFleetManager />
              )}

              {activeTab === 'broadcast' && (
                <BroadcastSystem />
              )}

              {activeTab === 'reports' && (
                <ReportsAnalytics />
              )}
            </motion.div>
          </AnimatePresence>
        </main>

      </div>

    </div>
  );
}

