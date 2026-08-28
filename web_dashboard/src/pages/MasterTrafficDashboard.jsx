import React, { useState, useEffect } from 'react';
import { 
  Bus, 
  MapPin, 
  Users, 
  AlertTriangle, 
  Clock, 
  Radio, 
  Search, 
  Bell, 
  Settings, 
  Wifi, 
  Headphones, 
  ChevronDown, 
  ChevronUp, 
  ArrowUpRight, 
  RotateCcw, 
  Plus, 
  Minus, 
  Info, 
  Sliders, 
  Navigation,
  ShieldAlert,
  Layers,
  Activity,
  CheckCircle2,
  AlertCircle
} from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, CircleMarker } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { fleetAPI, routeAPI, registrationAPI } from '../services/api';
import socketService from '../services/socket';

// --- Custom Bus Map Icons matching reference ---
const createCustomBusIcon = (busId, isSelected, status) => {
  const isWarning = status === 'Delayed';
  const color = isWarning ? '#FF3B30' : (isSelected ? '#00F0FF' : '#34C759');
  return L.divIcon({
    className: 'custom-master-bus-marker',
    html: `
      <div style="position: relative; display: flex; align-items: center; justify-content: center;">
        ${isSelected ? `<div style="position: absolute; width: 48px; height: 48px; border-radius: 50%; border: 2px dashed ${color}; opacity: 0.6; animation: radarSweep 4s linear infinite;"></div>` : ''}
        <div style="background: rgba(15, 23, 42, 0.9); border: 2px solid ${color}; width: 32px; height: 32px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 16px ${color}80;">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-1.1 0-2 .9-2 2v7c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>
          </svg>
        </div>
      </div>
    `,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
  });
};

export default function MasterTrafficDashboard({ activeTab, setActiveTab }) {
  const [transportType, setTransportType] = useState('bus');
  const [selectedBus, setSelectedBus] = useState('Bus 6023');
  const [selectedMapMode, setSelectedMapMode] = useState('Map 2');
  const [mapZoom, setMapZoom] = useState(13);
  const [center, setCenter] = useState([23.2599, 77.4126]); // Bhopal coordinates
  
  // Real-time backend state
  const [buses, setBuses] = useState([]);
  const [routes, setRoutes] = useState([]);
  const [capacityWarningOpen, setCapacityWarningOpen] = useState(true);
  const [scheduleDevOpen, setScheduleDevOpen] = useState(true);

  useEffect(() => {
    fetchLiveData();

    socketService.onLocationUpdate((data) => {
      setBuses((prevBuses) => {
        const idx = prevBuses.findIndex(b => (b._id || b.id) === (data.busId || data.id));
        if (idx !== -1) {
          const updated = [...prevBuses];
          updated[idx] = {
            ...updated[idx],
            currentLat: data.latitude || data.currentLat || updated[idx].currentLat,
            currentLng: data.longitude || data.currentLng || updated[idx].currentLng,
            speed: data.speed !== undefined ? data.speed : updated[idx].speed,
            status: data.status || updated[idx].status,
            lastUpdated: new Date()
          };
          return updated;
        }
        return prevBuses;
      });
    });

  }, []);

  const fetchLiveData = async () => {
    try {
      const [busRes, routeRes] = await Promise.all([
        fleetAPI.getAllBuses(),
        routeAPI.getAllRoutes()
      ]);
      setBuses(busRes.data?.buses || busRes.data || []);
      setRoutes(routeRes.data || []);
    } catch (e) {
      console.error('Failed to fetch master traffic live data:', e);
    }
  };

  // Static mock routes matching reference map lines (Winding mountain/coastal vectors)
  const routePolyline = [
    [23.2900, 77.3600],
    [23.2750, 77.3800],
    [23.2600, 77.4000],
    [23.2500, 77.4150],
    [23.2400, 77.4250],
    [23.2200, 77.4400],
    [23.2000, 77.4600],
  ];

  const secondaryRoutePolyline = [
    [23.2850, 77.4200],
    [23.2650, 77.4180],
    [23.2500, 77.4150],
    [23.2350, 77.4100],
    [23.2100, 77.3900],
  ];

  return (
    <div className="min-h-screen bg-[#07090E] text-[#E2E8F0] font-sans flex flex-col antialiased selection:bg-cyan-500/30 selection:text-cyan-200">
      
      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* 1. TOP NAVIGATION HEADER BAR */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <header className="h-16 bg-[#0B0E17]/90 border-b border-white/[0.07] backdrop-blur-xl px-6 flex items-center justify-between sticky top-0 z-50">
        
        {/* Left: Brand Logo & Navigation Pills */}
        <div className="flex items-center space-x-8">
          
          {/* Logo Badge */}
          <div className="flex items-center space-x-3 cursor-pointer" onClick={() => setActiveTab && setActiveTab('overview')}>
            <div className="w-9 h-9 rounded-xl bg-gradient-to-tr from-white to-slate-300 flex items-center justify-center shadow-lg shadow-white/10">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M4 8L12 4L20 8L12 12L4 8Z" fill="#0F172A" />
                <path d="M4 12L12 16L20 12" stroke="#0F172A" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M4 16L12 20L20 16" stroke="#0F172A" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <span className="font-display text-lg font-bold tracking-tight text-white">
              SISTec<span className="text-cyan-400 font-extrabold ml-0.5">Control</span>
            </span>
          </div>

          {/* Nav Links Pill Bar matching exact reference design */}
          <nav className="hidden xl:flex items-center space-x-1 bg-[#121624]/80 p-1 rounded-full border border-white/[0.08]">
            {[
              { id: 'overview', label: 'Live Map' },
              { id: 'radar', label: 'Fleet' },
              { id: 'routes', label: 'Routes' },
              { id: 'reports', label: 'Analytics' },
              { id: 'drivers', label: 'Maintenance' },
              { id: 'broadcast', label: 'Incidents' },
              { id: 'registrations', label: 'Crew' },
            ].map((tab) => {
              const isActive = (activeTab === tab.id) || (tab.id === 'overview' && !activeTab);
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab && setActiveTab(tab.id)}
                  className={`px-4 py-1.5 rounded-full text-xs font-medium transition-all duration-200 ${
                    isActive
                      ? 'bg-[#1E2638] text-white shadow-md border border-white/10 font-semibold'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-white/[0.04]'
                  }`}
                >
                  {tab.label}
                </button>
              );
            })}
          </nav>
        </div>

        {/* Right Controls: Search, System Icons, Profile */}
        <div className="flex items-center space-x-4">
          
          {/* Global Search Input */}
          <div className="hidden md:flex items-center bg-[#111523] border border-white/[0.08] rounded-xl px-3.5 py-1.5 w-64 focus-within:border-cyan-500/50 transition-all">
            <Search className="w-3.5 h-3.5 text-slate-400 mr-2" />
            <input 
              type="text" 
              placeholder="Search Ctrl+Shift+F" 
              className="bg-transparent text-xs text-slate-200 placeholder-slate-500 outline-none w-full font-sans"
            />
          </div>

          {/* Status System Icons */}
          <div className="flex items-center space-x-1.5 text-slate-400">
            <button className="p-2 rounded-xl hover:bg-white/[0.06] hover:text-slate-200 transition">
              <Wifi className="w-4 h-4" />
            </button>
            <button className="p-2 rounded-xl hover:bg-white/[0.06] hover:text-slate-200 transition">
              <Headphones className="w-4 h-4" />
            </button>
            <button className="p-2 rounded-xl hover:bg-white/[0.06] hover:text-slate-200 transition relative">
              <Bell className="w-4 h-4" />
              <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-red-500 ring-2 ring-[#0B0E17]" />
            </button>
            <button className="p-2 rounded-xl hover:bg-white/[0.06] hover:text-slate-200 transition">
              <Settings className="w-4 h-4" />
            </button>
          </div>

          {/* User Profile Avatar */}
          <div className="flex items-center pl-3 border-l border-white/[0.08]">
            <div className="relative">
              <img 
                src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=120" 
                alt="Manager Avatar" 
                className="w-8 h-8 rounded-full object-cover ring-2 ring-cyan-500/40"
              />
              <span className="absolute bottom-0 right-0 w-2.5 h-2.5 rounded-full bg-emerald-500 ring-2 ring-[#0B0E17]" />
            </div>
          </div>

        </div>

      </header>

      {/* ─────────────────────────────────────────────────────────────────── */}
      {/* MAIN WORKSPACE GRID: SIDEBAR + CENTER MAP + RIGHT PANELS */}
      {/* ─────────────────────────────────────────────────────────────────── */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-4 p-4 overflow-hidden">
        
        {/* ───────────────────────────────────────────────────────────────── */}
        {/* 2. LEFT SIDEBAR: VEHICLE COUNTERS & FLEET CARDS (Col 3/12) */}
        {/* ───────────────────────────────────────────────────────────────── */}
        <aside className="lg:col-span-3 flex flex-col space-y-4 overflow-y-auto max-h-[calc(100vh-5rem)] pr-1">
          
          {/* Transport Category Chips */}
          <div className="grid grid-cols-4 gap-1.5 bg-[#0F1320] p-1.5 rounded-2xl border border-white/[0.07]">
            {[
              { id: 'bus', count: '24', label: 'Bus' },
              { id: 'taxi', count: '100', label: 'Taxi' },
              { id: 'train', count: '12', label: 'Trains' },
              { id: 'tram', count: '13', label: 'Trams' },
            ].map((item) => (
              <button
                key={item.id}
                onClick={() => setTransportType(item.id)}
                className={`py-2 px-1 rounded-xl text-center transition-all ${
                  transportType === item.id 
                    ? 'bg-[#1D2538] text-white border border-white/10 font-bold shadow-md' 
                    : 'text-slate-400 hover:text-slate-200 hover:bg-white/[0.03]'
                }`}
              >
                <div className="text-xs font-bold font-display">{item.count} <span className="font-normal text-[11px] text-slate-400">{item.label}</span></div>
              </button>
            ))}
          </div>

          {/* Operational Status Summary Card */}
          <div className="bg-[#0D111E]/80 backdrop-blur-md p-4 rounded-2xl border border-white/[0.07] grid grid-cols-2 gap-4">
            <div className="flex items-center space-x-3">
              <div className="w-3 h-3 rounded-full bg-emerald-500 shadow-lg shadow-emerald-500/50" />
              <div>
                <p className="text-[11px] text-slate-400 font-medium">Online</p>
                <p className="text-xl font-display font-bold text-white">12</p>
              </div>
            </div>

            <div className="flex items-center space-x-3 pl-3 border-l border-white/[0.08]">
              <div className="w-0 h-0 border-l-[6px] border-l-transparent border-r-[6px] border-r-transparent border-b-[10px] border-b-red-500 shadow-lg" />
              <div>
                <p className="text-[11px] text-slate-400 font-medium">Offline</p>
                <p className="text-xl font-display font-bold text-white">4</p>
              </div>
            </div>
          </div>

          {/* Operational Efficiency KPI Card */}
          <div className="bg-[#0D111E]/80 backdrop-blur-md p-4 rounded-2xl border border-white/[0.07] space-y-3 relative overflow-hidden">
            <div className="flex items-center justify-between">
              <span className="text-xs text-slate-400 font-medium">Operational Efficiency</span>
              <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
            </div>

            <div className="flex items-baseline space-x-2">
              <span className="text-3xl font-display font-bold text-white">78.3<span className="text-lg text-slate-400">%</span></span>
            </div>
            
            <div className="text-[11px] text-slate-500 font-medium">Target: <span className="text-slate-300">80%</span></div>

            {/* Sparkline Chart Canvas simulation */}
            <div className="pt-2">
              <svg className="w-full h-16" viewBox="0 0 300 60">
                <line x1="0" y1="20" x2="300" y2="20" stroke="rgba(255,255,255,0.12)" strokeDasharray="3,3" />
                <path 
                  d="M 0 35 Q 30 45, 60 30 T 120 40 T 180 22 T 240 45 T 300 25" 
                  fill="none" 
                  stroke="#00F0FF" 
                  strokeWidth="2" 
                />
                <circle cx="180" cy="22" r="3" fill="#00F0FF" />
                <circle cx="240" cy="45" r="3" fill="#FF3B30" />
              </svg>
              <div className="flex justify-between text-[10px] text-slate-500 font-mono mt-1">
                <span>06:00</span>
                <span>09:00</span>
                <span>12:00</span>
                <span>15:00</span>
                <span>18:00</span>
                <span>21:00</span>
              </div>
            </div>
          </div>

          {/* Compact Vehicle Cards List */}
          <div className="space-y-3">
            
            {/* Bus 6023 Card */}
            <div 
              onClick={() => setSelectedBus('Bus 6023')}
              className={`p-4 rounded-2xl border transition-all cursor-pointer ${
                selectedBus === 'Bus 6023' 
                  ? 'bg-[#13192B]/90 border-cyan-500/40 shadow-xl ring-1 ring-cyan-500/30' 
                  : 'bg-[#0D111E]/80 border-white/[0.07] hover:border-white/20'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <div>
                  <h4 className="text-sm font-display font-bold text-white">Bus 6023</h4>
                  <p className="text-[10px] text-slate-500 font-mono">08.03.2026, 02:57:53 AM</p>
                </div>
                <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
              </div>

              {/* Bus Vector Illustration & Route Badge */}
              <div className="bg-[#090C16] p-3 rounded-xl border border-white/[0.05] relative overflow-hidden mb-3">
                <div className="flex items-center justify-between text-[11px] mb-2">
                  <span className="bg-slate-800 text-slate-300 font-mono px-2 py-0.5 rounded-md border border-white/10">L 45623</span>
                  <div className="flex items-center space-x-2 text-[10px] text-slate-400">
                    <span className="flex items-center space-x-1"><span className="w-1.5 h-1.5 rounded-full bg-emerald-400" /> <span>Online</span></span>
                    <span>(((•))) GPS</span>
                    <span>LTE</span>
                  </div>
                </div>

                {/* Wireframe Vector Render */}
                <div className="h-12 border border-slate-700/60 rounded-lg flex items-center justify-center text-slate-500 text-xs font-mono bg-slate-900/50 relative">
                  <div className="absolute left-2 w-2 h-2 rounded-full bg-cyan-400" />
                  <div className="absolute right-2 w-2 h-2 rounded-full bg-emerald-400" />
                  <span>BUS // 6023 WIREFRAME</span>
                </div>
              </div>

              <div className="flex justify-between text-[10px] text-slate-500 font-mono">
                <span>06AM</span>
                <span>11PM</span>
              </div>
            </div>

            {/* Bus 4120 Card */}
            <div 
              onClick={() => setSelectedBus('Bus 4120')}
              className={`p-4 rounded-2xl border transition-all cursor-pointer ${
                selectedBus === 'Bus 4120' 
                  ? 'bg-[#13192B]/90 border-cyan-500/40 shadow-xl ring-1 ring-cyan-500/30' 
                  : 'bg-[#0D111E]/80 border-white/[0.07] hover:border-white/20'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <div>
                  <h4 className="text-sm font-display font-bold text-white">Bus 4120</h4>
                  <p className="text-[10px] text-slate-500 font-mono">10.03.2026, 11:22:18</p>
                </div>
                <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
              </div>

              <div className="bg-[#090C16] p-3 rounded-xl border border-white/[0.05] relative overflow-hidden mb-3">
                <div className="flex items-center justify-between text-[11px] mb-2">
                  <span className="bg-slate-800 text-slate-300 font-mono px-2 py-0.5 rounded-md border border-white/10">R 31564</span>
                  <div className="flex items-center space-x-2 text-[10px] text-slate-400">
                    <span className="flex items-center space-x-1"><span className="w-1.5 h-1.5 rounded-full bg-emerald-400" /> <span>Online</span></span>
                    <span>(((•))) GPS</span>
                    <span>LTE</span>
                  </div>
                </div>
                <div className="h-10 border border-slate-700/60 rounded-lg flex items-center justify-center text-slate-500 text-[10px] font-mono bg-slate-900/50">
                  BUS // 4120 WIREFRAME
                </div>
              </div>
            </div>

            {/* Bus 2209 Card */}
            <div className="p-4 rounded-2xl bg-[#0D111E]/80 border border-white/[0.07] hover:border-white/20 transition-all cursor-pointer">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-display font-bold text-white">Bus 2209</h4>
                  <p className="text-[10px] text-slate-500 font-mono">10.03.2026, 11:25:40</p>
                </div>
                <span className="bg-slate-800 text-slate-300 font-mono text-[10px] px-2 py-0.5 rounded-md border border-white/10">L 34654</span>
              </div>
            </div>

            {/* E-Bus 07 Card */}
            <div className="p-4 rounded-2xl bg-[#0D111E]/80 border border-white/[0.07] hover:border-white/20 transition-all cursor-pointer">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-display font-bold text-white">E-Bus 07</h4>
                  <p className="text-[10px] text-slate-500 font-mono">10.03.2026, 11:23:12</p>
                </div>
                <span className="bg-emerald-950 text-emerald-300 font-mono text-[10px] px-2 py-0.5 rounded-md border border-emerald-500/30">ELECTRIC</span>
              </div>
            </div>

          </div>

        </aside>

        {/* ───────────────────────────────────────────────────────────────── */}
        {/* 3. CENTRAL MAP AREA & RIGHT OPERATIONS OVERLAYS (Col 9/12) */}
        {/* ───────────────────────────────────────────────────────────────── */}
        <main className="lg:col-span-9 flex flex-col space-y-4 max-h-[calc(100vh-5rem)] overflow-y-auto pr-1">
          
          {/* Main Interactive Satellite Map Box */}
          <div className="relative h-[520px] rounded-3xl overflow-hidden border border-white/[0.08] shadow-2xl bg-[#080C16]">
            
            {/* Top Floating Map Controls & Selectors */}
            <div className="absolute top-4 left-4 z-20 flex items-center space-x-3">
              <h2 className="text-lg font-display font-bold text-white backdrop-blur-md bg-black/40 px-3 py-1.5 rounded-xl border border-white/10">
                Traffic Management
              </h2>
              
              <div className="flex items-center space-x-2 bg-[#121726]/90 backdrop-blur-md px-3 py-1.5 rounded-xl border border-white/10 text-xs font-semibold text-slate-200">
                <Bus className="w-3.5 h-3.5 text-cyan-400" />
                <span>{selectedBus}</span>
                <ChevronDown className="w-3.5 h-3.5 text-slate-400 ml-1" />
              </div>

              <div className="flex items-center space-x-2 bg-[#121726]/90 backdrop-blur-md px-3 py-1.5 rounded-xl border border-white/10 text-xs font-semibold text-slate-200">
                <Layers className="w-3.5 h-3.5 text-emerald-400" />
                <span>{selectedMapMode}</span>
              </div>
            </div>

            {/* Leaflet Satellite Map Render */}
            <MapContainer 
              center={center} 
              zoom={mapZoom} 
              zoomControl={false}
              className="w-full h-full z-10"
            >
              {/* Esri World Imagery Satellite Tiles */}
              <TileLayer
                url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                attribution="Esri, Maxar, Earthstar Geographics"
              />

              {/* Glowing Route Polylines */}
              <Polyline positions={routePolyline} pathOptions={{ color: '#00F0FF', weight: 4, opacity: 0.85, dashArray: '8, 6' }} />
              <Polyline positions={secondaryRoutePolyline} pathOptions={{ color: '#EAB308', weight: 3, opacity: 0.75 }} />

              {/* Selected Bus Marker with Passenger Load Floating Glass Card */}
              <Marker 
                position={[23.2600, 77.4000]} 
                icon={createCustomBusIcon('6023', true, 'On-time')}
              >
                <Popup className="master-traffic-popup" closeButton={false}>
                  <div className="p-3 bg-[#0F1424]/95 backdrop-blur-xl border border-white/15 rounded-2xl text-white shadow-2xl min-w-[180px]">
                    <div className="flex items-center justify-between text-[11px] text-slate-400 font-medium mb-1">
                      <span>Passenger Load</span>
                      <ArrowUpRight className="w-3 h-3 text-cyan-400" />
                    </div>
                    <p className="text-[10px] text-slate-500">Next: Central Station</p>
                    <p className="text-2xl font-display font-bold text-white mt-1">87<span className="text-sm font-normal text-slate-400">%</span></p>
                  </div>
                </Popup>
              </Marker>

              {/* Auxiliary Station Markers */}
              <CircleMarker center={[23.2750, 77.3800]} radius={6} pathOptions={{ color: '#FFFFFF', fillColor: '#00F0FF', fillOpacity: 0.9 }} />
              <CircleMarker center={[23.2500, 77.4150]} radius={6} pathOptions={{ color: '#FFFFFF', fillColor: '#34C759', fillOpacity: 0.9 }} />
              <CircleMarker center={[23.2400, 77.4250]} radius={6} pathOptions={{ color: '#FFFFFF', fillColor: '#FF3B30', fillOpacity: 0.9 }} />

            </MapContainer>

            {/* Floating Map Zoom Controls (Bottom Left) matching reference */}
            <div className="absolute bottom-6 left-6 z-20 flex flex-col space-y-1.5 bg-[#0F1424]/90 backdrop-blur-md p-1.5 rounded-2xl border border-white/10 shadow-2xl">
              <button 
                onClick={() => setMapZoom(z => Math.min(z + 1, 18))}
                className="p-2 rounded-xl text-slate-300 hover:text-white hover:bg-white/10 transition"
              >
                <Plus className="w-4 h-4" />
              </button>
              <button 
                onClick={() => setCenter([23.2599, 77.4126])}
                className="p-2 rounded-xl text-cyan-400 hover:bg-cyan-500/20 transition"
              >
                <Navigation className="w-4 h-4" />
              </button>
              <button 
                onClick={() => setMapZoom(z => Math.max(z - 1, 8))}
                className="p-2 rounded-xl text-slate-300 hover:text-white hover:bg-white/10 transition"
              >
                <Minus className="w-4 h-4" />
              </button>
            </div>

            {/* ───────────────────────────────────────────────────────────── */}
            {/* 4. RIGHT-SIDE OPERATIONS PANEL (Floating Glass Overlays) */}
            {/* ───────────────────────────────────────────────────────────── */}
            <div className="absolute top-4 right-4 z-20 w-80 space-y-3 pointer-events-auto">
              
              {/* Warning Box Header */}
              <div className="bg-[#121626]/90 backdrop-blur-xl p-4 rounded-2xl border border-white/10 shadow-2xl text-slate-200">
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-xs font-display font-bold text-white tracking-wider uppercase flex items-center space-x-1.5">
                    <span>Warning</span>
                  </h3>
                  <span className="text-[10px] text-red-400 font-mono font-semibold bg-red-500/10 px-2 py-0.5 rounded-full border border-red-500/20">
                    Capacity issues (2 lines)
                  </span>
                </div>

                {/* Critical Red Alert Card */}
                <div className="bg-[#1A121A]/90 p-3 rounded-xl border border-red-500/30 space-y-2 mt-2">
                  <div className="flex items-start justify-between text-xs">
                    <div className="flex items-center space-x-2 text-red-400 font-bold">
                      <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                      <span>~180 passengers left behind</span>
                    </div>
                    <span className="text-[10px] text-slate-500">4m ago</span>
                  </div>

                  <div className="pl-4 text-[11px] space-y-1 text-slate-400 border-l border-red-500/20">
                    <p className="font-medium text-slate-300">Affected stations:</p>
                    <p>• Central Station <span className="text-slate-500">(115 passengers waiting)</span></p>
                    <p>• University Campus <span className="text-slate-500">(65 passengers waiting)</span></p>
                  </div>

                  <div className="pt-1 flex items-center space-x-2 text-[10px] text-cyan-400 font-semibold">
                    <Sliders className="w-3 h-3 text-cyan-400" />
                    <span>Recommend: Dispatching reserve E-Bus</span>
                  </div>
                </div>

                {/* Schedule Deviations Warning */}
                <div className="bg-[#1C1A14]/90 p-3 rounded-xl border border-yellow-500/30 space-y-1 mt-2">
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-yellow-400 font-semibold text-[11px]">Schedule Deviations (Route 14)</span>
                    <span className="text-[10px] text-slate-500">12m ago</span>
                  </div>
                  <p className="text-[11px] text-slate-300">
                    <span className="font-bold text-white">Bus 4120</span> is 15 mins behind schedule
                  </p>
                </div>

              </div>

            </div>

          </div>

          {/* ───────────────────────────────────────────────────────────────── */}
          {/* 5. BOTTOM ANALYTICS PANELS: SCHEDULE OFFSET & LIVE PASSENGER VOLUME */}
          {/* ───────────────────────────────────────────────────────────────── */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            
            {/* Schedule Offset Card */}
            <div className="bg-[#0D111E]/80 backdrop-blur-md p-4 rounded-2xl border border-white/[0.07] space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Schedule Offset</span>
                <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
              </div>

              <div className="flex items-baseline space-x-2">
                <span className="text-2xl font-display font-bold text-white">± 2.5 min</span>
                <span className="text-xs text-slate-500">Average Variance</span>
              </div>

              {/* Route Deviation Grid Matrix */}
              <div className="space-y-2 pt-1 font-mono text-[11px]">
                <div className="grid grid-cols-6 text-slate-500 pb-1 border-b border-white/[0.06]">
                  <span>Route number</span>
                  <span>L1</span>
                  <span>L12</span>
                  <span>L14</span>
                  <span>L18</span>
                  <span>L24</span>
                </div>

                <div className="grid grid-cols-6 text-slate-300 items-center">
                  <span className="bg-slate-800 text-slate-200 px-1.5 py-0.5 rounded text-[10px] w-fit">L 45623</span>
                  <span className="text-emerald-400">-2min</span>
                  <span className="text-yellow-400">+1min</span>
                  <span className="text-red-400">+1.5min</span>
                  <span className="text-emerald-400">-1min</span>
                  <span className="text-emerald-400">-1min</span>
                </div>

                <div className="grid grid-cols-6 text-slate-300 items-center">
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
            <div className="bg-[#0D111E]/80 backdrop-blur-md p-4 rounded-2xl border border-white/[0.07] space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Live Passenger Volume</span>
                <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
              </div>

              <div className="flex items-baseline space-x-2">
                <span className="text-2xl font-display font-bold text-white">142,580</span>
                <span className="text-xs text-slate-500">today</span>
              </div>

              {/* Time-Series Density Graph with Labels */}
              <div className="pt-2">
                <div className="flex justify-between text-[10px] text-slate-500 font-mono mb-1">
                  <span>55k <span className="text-emerald-400">-0%</span></span>
                  <span>57k <span className="text-red-400">-8%</span></span>
                  <span>50k <span className="text-slate-400">-6%</span></span>
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

        </main>

      </div>

    </div>
  );
}
