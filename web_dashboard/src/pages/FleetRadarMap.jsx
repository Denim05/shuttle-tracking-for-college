import React, { useState, useEffect } from 'react';
import { Bus, MapPin, Search, Phone, ShieldAlert, Navigation, Compass, Gauge, User } from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import L from 'leaflet';
import { fleetAPI, routeAPI } from '../services/api';
import socketService from '../services/socket';

// Bus Marker Generator with Status Colors
const getBusMarkerIcon = (status, speed) => {
  const isSpeeding = speed > 65;
  const color = isSpeeding ? '#EF4444' : (status === 'Delayed' ? '#F59E0B' : (status === 'On-time' ? '#10B981' : '#6B7280'));
  
  return L.divIcon({
    className: 'custom-radar-bus-marker',
    html: `
      <div style="
        background: ${color}; 
        width: 40px; 
        height: 40px; 
        border-radius: 50%; 
        border: 2px solid white; 
        display: flex; 
        align-items: center; 
        justify-content: center; 
        box-shadow: 0 0 15px ${color};
        animation: ${isSpeeding ? 'pulseGlow 1s infinite' : 'none'};
      ">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2">
          <path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-1.1 0-2 .9-2 2v7c0 .6.4 1 1 1h2"/>
          <circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>
        </svg>
      </div>`,
    iconSize: [40, 40],
    iconAnchor: [20, 20],
  });
};

const mapTileProviders = {
  google_hybrid: {
    name: 'Google Satellite',
    url: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    attribution: '&copy; Google Maps'
  },
  google_roadmap: {
    name: 'Google Maps',
    url: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    attribution: '&copy; Google Maps'
  },
  google_terrain: {
    name: 'Google Terrain',
    url: 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
    attribution: '&copy; Google Maps'
  },
  dark_mode: {
    name: 'Dark Radar',
    url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; OpenStreetMap &copy; CARTO'
  }
};

export default function FleetRadarMap() {
  const [buses, setBuses] = useState([]);
  const [selectedBus, setSelectedBus] = useState(null);
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('ALL');
  const [mapType, setMapType] = useState('google_hybrid');

  useEffect(() => {
    fetchBuses();

    socketService.onLocationUpdate((data) => {
      setBuses((prevBuses) => {
        return prevBuses.map((bus) => {
          if ((bus._id || bus.id) === (data.busId || data.id)) {
            const updated = {
              ...bus,
              currentLat: data.latitude || data.currentLat || bus.currentLat,
              currentLng: data.longitude || data.currentLng || bus.currentLng,
              speed: data.speed !== undefined ? data.speed : bus.speed,
              heading: data.heading !== undefined ? data.heading : bus.heading,
              status: data.status || bus.status,
              lastUpdated: new Date()
            };
            if (selectedBus && selectedBus._id === updated._id) {
              setSelectedBus(updated);
            }
            return updated;
          }
          return bus;
        });
      });
    });
  }, []);

  const fetchBuses = async () => {
    try {
      const res = await fleetAPI.getAllBuses();
      const loadedBuses = res.data?.buses || res.data || [
        { _id: '1', busNumber: 'MP-04-HB-1001', name: 'Bus 01', routeName: 'Indrapuri Express', status: 'On-time', speed: 42, heading: 90, currentLat: 23.2599, currentLng: 77.4126, driverName: 'Rajesh Kumar', driverPhone: '+91 98765 43210' },
        { _id: '2', busNumber: 'MP-04-HB-1002', name: 'Bus 02', routeName: 'MP Nagar Shuttle', status: 'On-time', speed: 38, heading: 180, currentLat: 23.2315, currentLng: 77.4326, driverName: 'Vikram Singh', driverPhone: '+91 98765 43211' },
        { _id: '3', busNumber: 'MP-04-HB-1003', name: 'Bus 03', routeName: 'Bairagarh Direct', status: 'Delayed', speed: 68, heading: 45, currentLat: 23.2800, currentLng: 77.3500, driverName: 'Suresh Patel', driverPhone: '+91 98765 43212' },
      ];
      setBuses(loadedBuses);
      if (loadedBuses.length > 0) setSelectedBus(loadedBuses[0]);
    } catch (err) {
      console.error('Failed to fetch buses:', err);
    }
  };

  const filteredBuses = buses.filter((b) => {
    const matchesSearch = (b.busNumber + b.name + b.routeName).toLowerCase().includes(search.toLowerCase());
    const matchesStatus = filterStatus === 'ALL' || b.status === filterStatus;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="h-[calc(100vh-6rem)] flex flex-col lg:flex-row gap-4 overflow-hidden">
      
      {/* Left Sidebar: Vehicle Roster */}
      <div className="w-full lg:w-80 glass-panel p-4 rounded-2xl flex flex-col justify-between h-full">
        <div className="space-y-4">
          <h2 className="font-display font-bold text-lg text-white">Fleet Radar Roster</h2>

          {/* Search */}
          <div className="relative">
            <Search className="w-4 h-4 text-gray-400 absolute left-3 top-3" />
            <input 
              type="text" 
              value={search} 
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by bus number or route..."
              className="w-full glass-input pl-9 pr-3 py-2 rounded-xl text-xs"
            />
          </div>

          {/* Filter Pills */}
          <div className="flex items-center space-x-1.5 overflow-x-auto pb-1 text-[11px]">
            {['ALL', 'On-time', 'Delayed', 'Offline'].map((st) => (
              <button
                key={st}
                onClick={() => setFilterStatus(st)}
                className={`px-3 py-1 rounded-lg font-medium transition ${
                  filterStatus === st 
                    ? 'bg-indigo-600 text-white shadow' 
                    : 'bg-gray-800/80 text-gray-400 hover:text-gray-200'
                }`}
              >
                {st}
              </button>
            ))}
          </div>

          {/* Bus Roster List */}
          <div className="space-y-2 overflow-y-auto max-h-[calc(100vh-18rem)] pr-1">
            {filteredBuses.map((bus) => {
              const isSelected = selectedBus?._id === bus._id;
              return (
                <div
                  key={bus._id}
                  onClick={() => setSelectedBus(bus)}
                  className={`glass-card p-3 rounded-xl cursor-pointer transition ${
                    isSelected ? 'border-indigo-500 bg-indigo-600/20 shadow-lg' : 'hover:border-gray-700'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-bold text-white">{bus.name || bus.busNumber}</p>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                      bus.status === 'On-time' ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' :
                      bus.status === 'Delayed' ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30' :
                      'bg-gray-500/20 text-gray-400'
                    }`}>
                      {bus.status}
                    </span>
                  </div>

                  <p className="text-[11px] text-gray-400 mt-1">{bus.routeName}</p>

                  <div className="flex items-center justify-between text-[10px] text-gray-500 mt-2 pt-2 border-t border-gray-800">
                    <span>Speed: <strong className="text-cyan-400">{bus.speed || 0} km/h</strong></span>
                    <span>Driver: {bus.driverName || 'Assigned'}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* Right Map Canvas */}
      <div className="flex-1 glass-panel p-2 rounded-2xl relative overflow-hidden h-full">
        
        {/* Selected Bus Info Overlay Header */}
        {selectedBus && (
          <div className="absolute top-4 left-4 z-[500] glass-panel p-4 rounded-xl max-w-sm border border-gray-700/80 shadow-2xl">
            <div className="flex items-center justify-between">
              <h3 className="font-display font-bold text-sm text-white">{selectedBus.name || selectedBus.busNumber}</h3>
              <span className="text-[10px] font-mono bg-cyan-500/20 text-cyan-300 px-2 py-0.5 rounded-md border border-cyan-500/30">
                {selectedBus.busNumber}
              </span>
            </div>
            <p className="text-xs text-indigo-300 font-medium mt-0.5">{selectedBus.routeName}</p>

            <div className="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-gray-800 text-xs">
              <div>
                <p className="text-[10px] text-gray-400">Current Speed</p>
                <p className="font-bold text-white text-sm">{selectedBus.speed || 0} <span className="text-xs font-normal text-gray-400">KM/H</span></p>
              </div>
              <div>
                <p className="text-[10px] text-gray-400">Driver Contact</p>
                <p className="font-bold text-cyan-400 text-xs flex items-center mt-0.5">
                  <Phone className="w-3 h-3 mr-1" />
                  <span>{selectedBus.driverPhone || 'Contact N/A'}</span>
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Map Type Switcher Floating Control */}
        <div className="absolute top-4 right-4 z-[500] glass-panel p-1.5 rounded-xl flex items-center space-x-1 border border-gray-700/80 shadow-2xl">
          {Object.keys(mapTileProviders).map((key) => (
            <button
              key={key}
              onClick={() => setMapType(key)}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-semibold transition ${
                mapType === key
                  ? 'bg-indigo-600 text-white shadow-md'
                  : 'text-gray-300 hover:bg-gray-800'
              }`}
            >
              {mapTileProviders[key].name}
            </button>
          ))}
        </div>

        <MapContainer 
          center={[selectedBus?.currentLat || 23.2599, selectedBus?.currentLng || 77.4126]} 
          zoom={13} 
          style={{ width: '100%', height: '100%', borderRadius: '0.75rem' }}
        >
          <TileLayer
            key={mapType}
            url={mapTileProviders[mapType].url}
            attribution={mapTileProviders[mapType].attribution}
          />
          {filteredBuses.map((bus) => (
            <Marker 
              key={bus._id || bus.id}
              position={[bus.currentLat || 23.2599, bus.currentLng || 77.4126]}
              icon={getBusMarkerIcon(bus.status, bus.speed || 0)}
              eventHandlers={{
                click: () => setSelectedBus(bus)
              }}
            >
              <Popup>
                <div className="text-xs">
                  <p className="font-bold text-white">{bus.name || bus.busNumber}</p>
                  <p className="text-indigo-400">{bus.routeName}</p>
                  <p className="text-gray-300">Speed: {bus.speed || 0} km/h</p>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>

      </div>

    </div>
  );
}
