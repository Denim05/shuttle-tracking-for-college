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
  Navigation,
  Layers,
  Plus,
  Minus,
  Sliders
} from 'lucide-react';
import { motion } from 'framer-motion';
import { MapContainer, TileLayer, Marker, Popup, Polyline, CircleMarker } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { fleetAPI, registrationAPI, routeAPI } from '../services/api';
import socketService from '../services/socket';

const createBusIcon = (status, isSelected = false) => {
  const isWarning = status === 'Delayed';
  const color = isWarning ? '#FF3B30' : (status === 'On-time' || status === 'Active' ? '#34C759' : '#00F0FF');
  return L.divIcon({
    className: 'custom-bus-telemetry-icon',
    html: `
      <div style="position: relative; display: flex; align-items: center; justify-content: center;">
        ${isSelected ? `<div style="position: absolute; width: 44px; height: 44px; border-radius: 50%; border: 2px dashed ${color}; opacity: 0.7; animation: radarSweep 4s linear infinite;"></div>` : ''}
        <div style="background: rgba(13, 19, 34, 0.95); border: 2px solid ${color}; width: 34px; height: 34px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 16px ${color}80;">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-1.1 0-2 .9-2 2v7c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>
          </svg>
        </div>
      </div>
    `,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
  });
};

export default function DashboardOverview({ setActiveTab }) {
  const [buses, setBuses] = useState([]);
  const [routes, setRoutes] = useState([]);
  const [registrations, setRegistrations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeSOSList, setActiveSOSList] = useState([]);
  const [recentUpdates, setRecentUpdates] = useState([]);
  const [selectedBusId, setSelectedBusId] = useState(null);
  const [mapZoom, setMapZoom] = useState(12);
  const [center, setCenter] = useState([23.2599, 77.4126]);

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

      const busName = data.name || data.busNumber || 'Fleet Vehicle';
      setRecentUpdates(prev => [
        { id: Date.now() + Math.random(), text: `${busName} updated telemetry (${data.speed || 35} km/h)`, time: new Date() },
        ...prev.slice(0, 5)
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
  const offlineBuses = buses.filter(b => b.status === 'Offline');
  const pendingRegistrations = registrations.filter(r => r.status === 'pending');

  const sampleRouteCoords = [
    [23.2900, 77.3600],
    [23.2750, 77.3800],
    [23.2600, 77.4000],
    [23.2500, 77.4150],
    [23.2400, 77.4250],
    [23.2200, 77.4400],
  ];

  return (
    <motion.div 
      initial={{ opacity: 0, y: 15 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className="space-y-6 pb-12"
    >
      
      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* 1. TOP BANNER HEADER WITH QUICK ACTIONS */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 glass-panel p-6 rounded-2xl border border-white/[0.08] shadow-2xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-80 h-80 bg-indigo-600/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10">
          <div className="flex items-center space-x-2 text-xs font-semibold text-cyan-400 mb-1">
            <Zap className="w-4 h-4 text-cyan-400" />
            <span>SISTec ENTERPRISE TRANSPORT COMMAND HUB</span>
          </div>
          <h2 className="text-2xl font-display font-extrabold text-white tracking-wide">
            Traffic & Fleet Operations Overview
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

      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* 2. TOP METRICS & OPERATIONAL EFFICIENCY KPI GRID */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        
        {/* Fleet Status Summary Card */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl border-l-4 border-emerald-500 flex flex-col justify-between">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">Fleet Availability</span>
            <Bus className="w-5 h-5 text-emerald-400" />
          </div>
          <div className="mt-3 flex items-baseline space-x-3">
            <span className="text-3xl font-display font-bold text-white">{buses.length || 30}</span>
            <span className="text-xs text-emerald-400 font-semibold flex items-center">
              <span className="w-2 h-2 rounded-full bg-emerald-400 mr-1.5 animate-pulse" />
              {activeBuses.length || 24} Online
            </span>
          </div>
          <div className="mt-2 text-[11px] text-gray-400 font-mono flex items-center space-x-3">
            <span>Online: <strong className="text-emerald-400">{activeBuses.length || 24}</strong></span>
            <span>Offline: <strong className="text-red-400">{offlineBuses.length || 4}</strong></span>
          </div>
        </motion.div>

        {/* Operational Efficiency KPI Card */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl border-l-4 border-cyan-500 flex flex-col justify-between">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">Operational Efficiency</span>
            <ArrowUpRight className="w-4 h-4 text-cyan-400" />
          </div>
          <div className="mt-2">
            <span className="text-3xl font-display font-bold text-white">78.3<span className="text-lg text-gray-400">%</span></span>
            <span className="text-[11px] text-slate-500 ml-2 font-mono">Target: 80%</span>
          </div>
          <div className="pt-1">
            <svg className="w-full h-8" viewBox="0 0 200 40">
              <line x1="0" y1="15" x2="200" y2="15" stroke="rgba(255,255,255,0.15)" strokeDasharray="3,3" />
              <path d="M 0 25 Q 30 35, 60 20 T 120 30 T 180 15 T 200 25" fill="none" stroke="#00F0FF" strokeWidth="2" />
            </svg>
          </div>
        </motion.div>

        {/* SGI Campus Routes Card */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl border-l-4 border-indigo-500 flex flex-col justify-between">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">SGI Campus Routes</span>
            <MapPin className="w-5 h-5 text-indigo-400" />
          </div>
          <div className="mt-3">
            <span className="text-3xl font-display font-bold text-white">{routes.length || 5}</span>
            <span className="text-xs text-indigo-300 font-medium ml-2">Active Lines</span>
          </div>
          <p className="text-[11px] text-gray-400 mt-2 font-mono">Indrapuri, MP Nagar, Lalghati & Kolar</p>
        </motion.div>

        {/* Pending Pass Approvals */}
        <motion.div whileHover={{ y: -3 }} className="glass-card p-5 rounded-2xl border-l-4 border-amber-500 flex flex-col justify-between">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">Pending Pass Approvals</span>
            <UserCheck className="w-5 h-5 text-amber-400" />
          </div>
          <div className="mt-3 flex items-baseline space-x-2">
            <span className="text-3xl font-display font-bold text-amber-400">{pendingRegistrations.length}</span>
            <span className="text-xs text-amber-300 font-medium">Applications</span>
          </div>
          <button
            onClick={() => setActiveTab('registrations')}
            className="mt-2 text-[11px] bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 px-3 py-1 rounded-lg font-semibold w-fit border border-amber-500/30 transition"
          >
            Review Applications →
          </button>
        </motion.div>

      </div>

      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* 3. MAIN SECTION: SATELLITE RADAR MAP + OPERATIONS & TELEMETRY PANEL */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        
        {/* Left 8 Cols: Satellite Fleet Telemetry Radar Map */}
        <div className="lg:col-span-8 glass-panel p-5 rounded-2xl flex flex-col justify-between h-[520px] relative">
          
          {/* Header Bar Over Map */}
          <div className="flex items-center justify-between mb-4 z-20">
            <div className="flex items-center space-x-3">
              <div className="w-3 h-3 rounded-full bg-emerald-400 animate-ping" />
              <h3 className="font-display font-bold text-base text-white">Traffic Management Telemetry Radar</h3>
            </div>
            
            <div className="flex items-center space-x-3">
              <span className="text-xs bg-slate-800 text-slate-300 px-3 py-1 rounded-xl border border-white/10 font-mono">
                Map 2 (Satellite)
              </span>
              <button 
                onClick={() => setActiveTab('radar')}
                className="text-xs bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/40 px-3 py-1.5 rounded-xl font-semibold flex items-center space-x-1 transition"
              >
                <span>Full Radar Screen</span>
                <ArrowUpRight className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Leaflet Map Canvas */}
          <div className="flex-1 rounded-2xl overflow-hidden relative border border-white/[0.08] bg-[#070B14]">
            <MapContainer 
              center={center} 
              zoom={mapZoom} 
              zoomControl={false}
              className="w-full h-full"
            >
              {/* Esri World Imagery Satellite Tiles */}
              <TileLayer
                url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                attribution="Esri, Maxar, Earthstar Geographics"
              />

              <Polyline positions={sampleRouteCoords} pathOptions={{ color: '#00F0FF', weight: 4, opacity: 0.85, dashArray: '8, 6' }} />

              {buses.map((bus) => (
                <Marker 
                  key={bus._id || bus.id}
                  position={[bus.currentLat || 23.2599, bus.currentLng || 77.4126]}
                  icon={createBusIcon(bus.status, selectedBusId === (bus._id || bus.id))}
                  eventHandlers={{
                    click: () => setSelectedBusId(bus._id || bus.id)
                  }}
                >
                  <Popup className="master-traffic-popup">
                    <div className="text-xs p-2 bg-[#0F1424]/90 text-white rounded-xl">
                      <p className="font-bold text-cyan-400">{bus.name || bus.busNumber}</p>
                      <p className="text-gray-300">Route: {bus.routeName}</p>
                      <p className="text-gray-300">Speed: {bus.speed || 0} km/h</p>
                      <p className="text-emerald-400 font-semibold mt-1">Status: {bus.status}</p>
                    </div>
                  </Popup>
                </Marker>
              ))}

              <CircleMarker center={[23.2750, 77.3800]} radius={6} pathOptions={{ color: '#FFFFFF', fillColor: '#00F0FF', fillOpacity: 0.9 }} />
              <CircleMarker center={[23.2500, 77.4150]} radius={6} pathOptions={{ color: '#FFFFFF', fillColor: '#34C759', fillOpacity: 0.9 }} />
            </MapContainer>

            {/* Bottom-left Map Zoom Controls */}
            <div className="absolute bottom-4 left-4 z-20 flex flex-col space-y-1 bg-[#0F1424]/90 backdrop-blur-md p-1 rounded-xl border border-white/10">
              <button onClick={() => setMapZoom(z => Math.min(z + 1, 18))} className="p-1.5 text-slate-300 hover:text-white"><Plus className="w-4 h-4" /></button>
              <button onClick={() => setCenter([23.2599, 77.4126])} className="p-1.5 text-cyan-400"><Navigation className="w-4 h-4" /></button>
              <button onClick={() => setMapZoom(z => Math.max(z - 1, 8))} className="p-1.5 text-slate-300 hover:text-white"><Minus className="w-4 h-4" /></button>
            </div>
          </div>

        </div>

        {/* Right 4 Cols: Operations Panel, Warning Alerts & Live Socket Stream */}
        <div className="lg:col-span-4 space-y-4">
          
          {/* Operations Warning Card */}
          <div className="glass-panel p-4 rounded-2xl border border-white/[0.08] space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-display font-bold text-white tracking-wider uppercase">Warning</h3>
              <span className="text-[10px] text-red-400 font-mono bg-red-500/10 px-2 py-0.5 rounded-full border border-red-500/20">Capacity issues (2 lines)</span>
            </div>

            <div className="bg-[#1A121A]/90 p-3 rounded-xl border border-red-500/30 space-y-1.5">
              <div className="flex items-center justify-between text-xs text-red-400 font-bold">
                <span>~180 passengers left behind</span>
                <span className="text-[10px] text-slate-500">4m ago</span>
              </div>
              <div className="text-[11px] text-slate-400 pl-3 border-l border-red-500/20">
                <p>• Central Station (115 waiting)</p>
                <p>• University Campus (65 waiting)</p>
              </div>
              <p className="text-[10px] text-cyan-400 font-semibold pt-1">Recommend: Dispatching reserve E-Bus</p>
            </div>
          </div>

          {/* Live Telemetry Activity Stream & Pending Approvals List */}
          <div className="glass-panel p-4 rounded-2xl border border-white/[0.08] space-y-3 max-h-[300px] overflow-y-auto">
            <div className="flex items-center justify-between border-b border-gray-800 pb-2">
              <div className="flex items-center space-x-2 text-xs font-bold text-white">
                <Activity className="w-4 h-4 text-cyan-400" />
                <span>Live Socket Telemetry Stream</span>
              </div>
              <span className="text-[10px] bg-cyan-500/20 text-cyan-300 px-2 py-0.5 rounded-md font-mono">LIVE</span>
            </div>

            <div className="space-y-2">
              {recentUpdates.length > 0 ? (
                recentUpdates.map((act) => (
                  <div key={act.id} className="glass-card p-2.5 rounded-xl flex items-center space-x-2.5 border-l-2 border-cyan-400 text-xs">
                    <div className="w-2 h-2 rounded-full bg-cyan-400 animate-pulse flex-shrink-0" />
                    <div className="flex-1">
                      <p className="text-gray-200 font-medium">{act.text}</p>
                      <p className="text-[10px] text-gray-500">{act.time.toLocaleTimeString()}</p>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-4 text-gray-500 text-xs">
                  <Activity className="w-5 h-5 text-gray-600 mx-auto mb-1 animate-spin" />
                  <p>Listening for real-time telemetry updates...</p>
                </div>
              )}
            </div>
          </div>

        </div>

      </div>

      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* 4. BOTTOM ANALYTICS PANELS: SCHEDULE OFFSET & LIVE PASSENGER VOLUME */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        
        {/* Schedule Offset Card */}
        <div className="glass-panel p-5 rounded-2xl border border-white/[0.08] space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">Schedule Offset</span>
            <ArrowUpRight className="w-4 h-4 text-gray-400" />
          </div>

          <div className="flex items-baseline space-x-2">
            <span className="text-2xl font-display font-bold text-white">± 2.5 min</span>
            <span className="text-xs text-gray-500">Average Variance</span>
          </div>

          <div className="space-y-2 pt-1 font-mono text-xs">
            <div className="grid grid-cols-6 text-gray-500 pb-1 border-b border-gray-800">
              <span>Route</span>
              <span>L1</span>
              <span>L12</span>
              <span>L14</span>
              <span>L18</span>
              <span>L24</span>
            </div>

            <div className="grid grid-cols-6 text-gray-300 items-center">
              <span className="bg-slate-800 text-slate-200 px-1.5 py-0.5 rounded text-[10px] w-fit">L 45623</span>
              <span className="text-emerald-400">-2min</span>
              <span className="text-yellow-400">+1min</span>
              <span className="text-red-400">+1.5min</span>
              <span className="text-emerald-400">-1min</span>
              <span className="text-emerald-400">-1min</span>
            </div>

            <div className="grid grid-cols-6 text-gray-300 items-center">
              <span className="bg-slate-800 text-slate-200 px-1.5 py-0.5 rounded text-[10px] w-fit">L 34654</span>
              <span className="text-emerald-400">-1min</span>
              <span className="text-emerald-400">-2min</span>
              <span className="text-yellow-400">+2min</span>
              <span className="text-emerald-400">-2.5min</span>
              <span className="text-emerald-400">-2min</span>
            </div>
          </div>
        </div>

        {/* Live Passenger Volume Card */}
        <div className="glass-panel p-5 rounded-2xl border border-white/[0.08] space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400 font-medium">Live Passenger Volume</span>
            <ArrowUpRight className="w-4 h-4 text-gray-400" />
          </div>

          <div className="flex items-baseline space-x-2">
            <span className="text-2xl font-display font-bold text-white">142,580</span>
            <span className="text-xs text-gray-500">today</span>
          </div>

          <div className="pt-2">
            <div className="flex justify-between text-[10px] text-gray-500 font-mono mb-1">
              <span>55k <span className="text-emerald-400">-0%</span></span>
              <span>57k <span className="text-red-400">-8%</span></span>
              <span>50k <span className="text-gray-400">-6%</span></span>
              <span>55k <span className="text-emerald-400">-0%</span></span>
              <span>52k <span className="text-red-400">-12%</span></span>
              <span>55k <span className="text-emerald-400">-0%</span></span>
              <span>60k</span>
            </div>

            <div className="h-10 flex items-end justify-between space-x-1 pt-1">
              {[40, 65, 50, 75, 45, 80, 60, 90, 70, 85, 95, 60, 70].map((val, idx) => (
                <div 
                  key={idx} 
                  className="flex-1 bg-gradient-to-t from-cyan-500/20 to-cyan-400/80 rounded-t-sm hover:brightness-125 transition-all"
                  style={{ height: `${val}%` }}
                />
              ))}
            </div>
          </div>

        </div>

      </div>

    </motion.div>
  );
}
