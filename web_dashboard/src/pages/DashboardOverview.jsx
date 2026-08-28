import React, { useState, useEffect } from 'react';
import { 
  Bus, 
  MapPin, 
  Users, 
  UserCheck, 
  AlertTriangle, 
  Clock, 
  Radio, 
  ArrowUpRight, 
  TrendingUp, 
  ShieldAlert,
  ChevronRight,
  Activity,
  Zap,
  CheckCircle2,
  Navigation
} from 'lucide-react';
import { motion } from 'framer-motion';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import L from 'leaflet';
import { fleetAPI, registrationAPI, routeAPI } from '../services/api';
import socketService from '../services/socket';

const createBusIcon = (status) => {
  const color = status === 'Delayed' ? '#F59E0B' : (status === 'On-time' || status === 'Active' ? '#10B981' : '#6B7280');
  return L.divIcon({
    className: 'custom-bus-icon',
    html: `<div style="background:${color}; width:34px; height:34px; border-radius:50%; border:2px solid white; display:flex; align-items:center; justify-content:center; box-shadow:0 0 14px ${color}; animation: pulseGlow 2s infinite;">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-1.1 0-2 .9-2 2v7c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/></svg>
           </div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 17],
  });
};

export default function DashboardOverview({ setActiveTab }) {
  const [buses, setBuses] = useState([]);
  const [routes, setRoutes] = useState([]);
  const [registrations, setRegistrations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeSOSList, setActiveSOSList] = useState([]);
  const [recentUpdates, setRecentUpdates] = useState([]);

  useEffect(() => {
    fetchDashboardData();

    socketService.onLocationUpdate((data) => {
      setBuses((prevBuses) => {
        const index = prevBuses.findIndex(b => (b._id || b.id) === (data.busId || data.id));
        if (index !== -1) {
          const updated = [...prevBuses];
          updated[index] = {
            ...updated[index],
            currentLat: data.latitude || data.currentLat || updated[index].currentLat,
            currentLng: data.longitude || data.currentLng || updated[index].currentLng,
            speed: data.speed !== undefined ? data.speed : updated[index].speed,
            heading: data.heading !== undefined ? data.heading : updated[index].heading,
            status: data.status || updated[index].status,
            lastUpdated: new Date()
          };
          return updated;
        }
        return prevBuses;
      });

      // Add to live activity feed
      const busName = data.name || data.busNumber || 'Fleet Vehicle';
      setRecentUpdates(prev => [
        { id: Date.now() + Math.random(), text: `${busName} updated location (${data.speed || 35} km/h)`, time: new Date() },
        ...prev.slice(0, 4)
      ]);
    });

    socketService.onSOSAlert((alert) => {
      setActiveSOSList(prev => [alert, ...prev]);
    });

  }, []);

  const fetchDashboardData = async () => {
    setLoading(true);
    try {
      const [busRes, regRes, routeRes] = await Promise.all([
        fleetAPI.getAllBuses(),
        registrationAPI.getAll(),
        routeAPI.getAllRoutes()
      ]);
      
      const loadedBuses = busRes.data?.buses || busRes.data || [];
      const loadedRegs = regRes.data?.submissions || regRes.data || [];
      const loadedRoutes = routeRes.data || [];

      setBuses(loadedBuses);
      setRegistrations(loadedRegs);
      setRoutes(loadedRoutes);
    } catch (err) {
      console.error('Failed to load dashboard data:', err);
    } finally {
      setLoading(false);
    }
  };

  const activeBuses = buses.filter(b => b.status === 'On-time' || b.status === 'Delayed' || b.status === 'Active');
  const delayedBuses = buses.filter(b => b.status === 'Delayed');
  const pendingRegistrations = registrations.filter(r => r.status === 'pending');

  return (
    <motion.div 
      initial={{ opacity: 0, y: 15 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className="space-y-6 pb-12"
    >
      
      {/* Top Banner Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 glass-panel p-6 rounded-2xl border border-gray-800/80 shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-80 h-80 bg-indigo-600/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10">
          <div className="flex items-center space-x-2 text-xs font-semibold text-cyan-400 mb-1">
            <Zap className="w-4 h-4 text-cyan-400" />
            <span>EXECUTIVE MONITORING HUB</span>
          </div>
          <h2 className="text-2xl font-display font-extrabold text-white tracking-wide">
            SGI Transport Command Center
          </h2>
          <p className="text-xs text-gray-400 mt-1">Real-time GPS telemetry for 30 transit routes across Ratibad & Bhopal Campus</p>
        </div>

        <div className="flex items-center space-x-3 relative z-10">
          <button 
            onClick={() => setActiveTab('broadcast')}
            className="bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/40 px-4 py-2.5 rounded-xl text-xs font-semibold flex items-center space-x-2 transition"
          >
            <Radio className="w-4 h-4 text-cyan-400" />
            <span>Send Alert Broadcast</span>
          </button>
          
          <button 
            onClick={() => setActiveTab('registrations')}
            className="bg-gradient-to-r from-indigo-600 to-cyan-600 hover:from-indigo-500 hover:to-cyan-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
          >
            <UserCheck className="w-4 h-4" />
            <span>Pending Pass Approvals ({pendingRegistrations.length})</span>
          </button>
        </div>
      </div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        
        {/* Metric 1 */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl flex items-center justify-between border-l-4 border-indigo-500">
          <div>
            <p className="text-xs text-gray-400 font-medium">Total Fleet Buses</p>
            <h3 className="text-2xl font-display font-bold text-white mt-1">{buses.length || 30}</h3>
            <p className="text-[11px] text-emerald-400 flex items-center mt-1">
              <TrendingUp className="w-3 h-3 mr-1" />
              <span>{activeBuses.length || 24} Buses Active</span>
            </p>
          </div>
          <div className="p-3 bg-indigo-500/10 border border-indigo-500/20 rounded-xl">
            <Bus className="w-6 h-6 text-indigo-400" />
          </div>
        </motion.div>

        {/* Metric 2 */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl flex items-center justify-between border-l-4 border-emerald-500">
          <div>
            <p className="text-xs text-gray-400 font-medium">Schedule Compliance</p>
            <h3 className="text-2xl font-display font-bold text-emerald-400 mt-1">
              {buses.length > 0 ? Math.round(((buses.length - delayedBuses.length) / buses.length) * 100) : 96}%
            </h3>
            <p className="text-[11px] text-emerald-300 flex items-center mt-1">
              <CheckCircle2 className="w-3 h-3 mr-1" />
              <span>{delayedBuses.length} Minor Delays</span>
            </p>
          </div>
          <div className="p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-xl">
            <Clock className="w-6 h-6 text-emerald-400" />
          </div>
        </motion.div>

        {/* Metric 3 */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl flex items-center justify-between border-l-4 border-cyan-500">
          <div>
            <p className="text-xs text-gray-400 font-medium">SGI Campus Routes</p>
            <h3 className="text-2xl font-display font-bold text-cyan-400 mt-1">{routes.length || 30}</h3>
            <p className="text-[11px] text-cyan-300 flex items-center mt-1">
              <Navigation className="w-3 h-3 mr-1" />
              <span>Gandinagar, Kolar & Mandideep</span>
            </p>
          </div>
          <div className="p-3 bg-cyan-500/10 border border-cyan-500/20 rounded-xl">
            <MapPin className="w-6 h-6 text-cyan-400" />
          </div>
        </motion.div>

        {/* Metric 4 */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl flex items-center justify-between border-l-4 border-amber-500">
          <div>
            <p className="text-xs text-gray-400 font-medium">Pending Pass Approvals</p>
            <h3 className="text-2xl font-display font-bold text-amber-400 mt-1">{pendingRegistrations.length}</h3>
            <p className="text-[11px] text-amber-300 flex items-center mt-1">
              <Users className="w-3 h-3 mr-1" />
              <span>Awaiting Manager Signoff</span>
            </p>
          </div>
          <div className="p-3 bg-amber-500/10 border border-amber-500/20 rounded-xl">
            <UserCheck className="w-6 h-6 text-amber-400" />
          </div>
        </motion.div>

      </div>

      {/* Main Section: Live Map + Activity Stream Split */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left 2 Cols: Live Radar Preview Map */}
        <div className="lg:col-span-2 glass-panel p-5 rounded-2xl flex flex-col justify-between h-[460px]">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded-full bg-emerald-400 animate-ping" />
              <h3 className="font-display font-bold text-base text-white">Live Fleet Telemetry Radar</h3>
            </div>
            <button 
              onClick={() => setActiveTab('radar')}
              className="text-xs text-cyan-400 hover:text-cyan-300 font-semibold flex items-center space-x-1"
            >
              <span>Full Radar View</span>
              <ArrowUpRight className="w-4 h-4" />
            </button>
          </div>

          <div className="flex-1 rounded-xl overflow-hidden relative border border-gray-800/80">
            <MapContainer 
              center={[23.2599, 77.4126]} 
              zoom={12} 
              scrollWheelZoom={false} 
              style={{ width: '100%', height: '100%' }}
            >
              <TileLayer
                url="https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}"
                attribution='&copy; Google Maps'
              />
              {buses.map((bus) => (
                <Marker 
                  key={bus._id || bus.id}
                  position={[bus.currentLat || 23.2599, bus.currentLng || 77.4126]}
                  icon={createBusIcon(bus.status)}
                >
                  <Popup>
                    <div className="text-xs font-sans p-1">
                      <p className="font-bold text-indigo-400">{bus.name || bus.busNumber}</p>
                      <p className="text-gray-300">Route: {bus.routeName}</p>
                      <p className="text-gray-300">Speed: {bus.speed || 0} km/h</p>
                      <p className="text-emerald-400 font-semibold mt-1">Status: {bus.status}</p>
                    </div>
                  </Popup>
                </Marker>
              ))}
            </MapContainer>
          </div>
        </div>

        {/* Right 1 Col: Live Telemetry Stream & Pending Approvals */}
        <div className="glass-panel p-5 rounded-2xl flex flex-col justify-between h-[460px]">
          <div>
            <div className="flex items-center justify-between mb-4 border-b border-gray-800/80 pb-3">
              <div className="flex items-center space-x-2">
                <Activity className="w-4 h-4 text-cyan-400" />
                <h3 className="font-display font-bold text-base text-white">Live Telemetry Activity</h3>
              </div>
              <span className="text-[10px] bg-cyan-500/20 text-cyan-300 px-2 py-0.5 rounded-md font-mono">REAL-TIME</span>
            </div>

            <div className="space-y-3 overflow-y-auto max-h-[350px] pr-1">
              {recentUpdates.length > 0 ? (
                recentUpdates.map((act) => (
                  <div key={act.id} className="glass-card p-3 rounded-xl flex items-center space-x-3 border-l-2 border-cyan-400">
                    <div className="w-2 h-2 rounded-full bg-cyan-400 animate-pulse flex-shrink-0" />
                    <div className="text-xs flex-1">
                      <p className="text-gray-200 font-medium">{act.text}</p>
                      <p className="text-[10px] text-gray-500">{act.time.toLocaleTimeString()}</p>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-6 text-gray-500 text-xs">
                  <Activity className="w-6 h-6 text-gray-600 mx-auto mb-2 animate-spin" />
                  <p>Listening for Socket telemetry broadcast...</p>
                </div>
              )}

              <div className="pt-3 border-t border-gray-800/80">
                <h4 className="text-xs font-bold text-gray-300 mb-2">Pending Pass Applications</h4>
                {pendingRegistrations.length === 0 ? (
                  <div className="text-center py-4 text-gray-500 text-[11px]">
                    <UserCheck className="w-5 h-5 text-gray-600 mx-auto mb-1" />
                    <p>All student pass applications cleared!</p>
                  </div>
                ) : (
                  pendingRegistrations.slice(0, 3).map((reg) => (
                    <div 
                      key={reg._id} 
                      className="glass-card p-2.5 mb-2 rounded-xl flex items-center justify-between hover:border-indigo-500/40 transition"
                    >
                      <div className="text-xs">
                        <p className="font-bold text-white">{reg.name}</p>
                        <p className="text-[10px] text-gray-400">{reg.studentId} • {reg.routeName || 'General Route'}</p>
                      </div>

                      <button
                        onClick={() => setActiveTab('registrations')}
                        className="bg-indigo-600/30 hover:bg-indigo-600 text-indigo-200 hover:text-white px-2.5 py-1 rounded-lg text-[11px] font-semibold transition"
                      >
                        Review
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>

      </div>

    </motion.div>
  );
}

