import React, { useState, useEffect } from 'react';
import { Route as RouteIcon, Plus, MapPin, Trash2, Edit, Save, Compass } from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import { routeAPI } from '../services/api';

const stopMarkerIcon = L.divIcon({
  className: 'custom-stop-marker',
  html: `<div style="background:#4F46E5; width:24px; height:24px; border-radius:50%; border:2px solid white; display:flex; align-items:center; justify-content:center; color:white; font-size:10px; font-weight:bold;">📍</div>`,
  iconSize: [24, 24],
  iconAnchor: [12, 12],
});

// Map click component for picking stop lat/lng
function LocationPicker({ onLocationSelect }) {
  useMapEvents({
    click(e) {
      onLocationSelect(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

export default function RouteManager() {
  const [routes, setRoutes] = useState([]);
  const [selectedRoute, setSelectedRoute] = useState(null);
  const [newRouteName, setNewRouteName] = useState('');
  const [newRouteColor, setNewRouteColor] = useState('#4F46E5');
  const [isAddingRoute, setIsAddingRoute] = useState(false);

  // New Stop State
  const [newStopName, setNewStopName] = useState('');
  const [newStopLat, setNewStopLat] = useState(23.2599);
  const [newStopLng, setNewStopLng] = useState(77.4126);

  useEffect(() => {
    fetchRoutes();
  }, []);

  const fetchRoutes = async () => {
    try {
      const res = await routeAPI.getAllRoutes();
      const loadedRoutes = res.data?.routes || res.data || [
        { 
          _id: 'r1', 
          name: 'Indrapuri Route 01', 
          color: '#4F46E5', 
          stops: [
            { name: 'BHEL Gate 1', lat: 23.2500, lng: 77.4200 },
            { name: 'Indrapuri C Sector', lat: 23.2580, lng: 77.4350 },
            { name: 'SISTec Campus', lat: 23.2800, lng: 77.4600 }
          ] 
        },
        { 
          _id: 'r2', 
          name: 'MP Nagar Shuttle', 
          color: '#06B6D4', 
          stops: [
            { name: 'Board Office Square', lat: 23.2315, lng: 77.4326 },
            { name: 'Jyoti Talkies', lat: 23.2350, lng: 77.4380 },
            { name: 'SISTec Campus', lat: 23.2800, lng: 77.4600 }
          ] 
        }
      ];
      setRoutes(loadedRoutes);
      if (loadedRoutes.length > 0) setSelectedRoute(loadedRoutes[0]);
    } catch (err) {
      console.error('Failed to fetch routes:', err);
    }
  };

  const handleCreateRoute = async () => {
    if (!newRouteName) return;
    try {
      await routeAPI.createRoute({ name: newRouteName, color: newRouteColor, stops: [] });
      setNewRouteName('');
      setIsAddingRoute(false);
      fetchRoutes();
    } catch (err) {
      console.error('Create route error:', err);
    }
  };

  const handleDeleteRoute = async (id) => {
    if (!window.confirm('Delete this route?')) return;
    try {
      await routeAPI.deleteRoute(id);
      fetchRoutes();
    } catch (err) {
      console.error('Delete route error:', err);
    }
  };

  const handleAddStopToRoute = async () => {
    if (!selectedRoute || !newStopName) return;
    const updatedStops = [...(selectedRoute.stops || []), { name: newStopName, lat: Number(newStopLat), lng: Number(newStopLng) }];
    
    try {
      await routeAPI.updateRoute(selectedRoute._id, { ...selectedRoute, stops: updatedStops });
      setNewStopName('');
      fetchRoutes();
    } catch (err) {
      console.error('Add stop error:', err);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      
      {/* Header */}
      <div className="glass-panel p-6 rounded-2xl flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-display font-bold text-white">Route & Stop Builder</h2>
          <p className="text-xs text-gray-400 mt-1">Configure campus bus routes, sequence stops, and pin Lat/Lng coordinates</p>
        </div>

        <button 
          onClick={() => setIsAddingRoute(true)}
          className="bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
        >
          <Plus className="w-4 h-4" />
          <span>Add New Route</span>
        </button>
      </div>

      {/* Main Split Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left Column: Route List & Stop Sequence */}
        <div className="space-y-4">
          
          {/* Route Selector Cards */}
          <div className="glass-panel p-4 rounded-2xl space-y-3">
            <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider">Active Campus Routes</h3>

            <div className="space-y-2 max-h-48 overflow-y-auto pr-1">
              {routes.map((route) => {
                const isSelected = selectedRoute?._id === route._id;
                return (
                  <div
                    key={route._id}
                    onClick={() => setSelectedRoute(route)}
                    className={`glass-card p-3 rounded-xl cursor-pointer flex items-center justify-between transition ${
                      isSelected ? 'border-indigo-500 bg-indigo-600/20' : 'hover:border-gray-700'
                    }`}
                  >
                    <div className="flex items-center space-x-3">
                      <div className="w-3 h-3 rounded-full" style={{ backgroundColor: route.color || '#4F46E5' }} />
                      <div>
                        <p className="text-xs font-bold text-white">{route.name}</p>
                        <p className="text-[10px] text-gray-400">{route.stops?.length || 0} Bus Stops</p>
                      </div>
                    </div>

                    <button 
                      onClick={(e) => { e.stopPropagation(); handleDeleteRoute(route._id); }}
                      className="text-gray-500 hover:text-red-400 p-1"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Stop Editor Form for Selected Route */}
          {selectedRoute && (
            <div className="glass-panel p-4 rounded-2xl space-y-4">
              <h3 className="text-xs font-bold text-white flex items-center space-x-2">
                <MapPin className="w-4 h-4 text-cyan-400" />
                <span>Add Stop to "{selectedRoute.name}"</span>
              </h3>

              <div className="space-y-3 text-xs">
                <div>
                  <label className="block text-gray-400 mb-1">Stop Name</label>
                  <input 
                    type="text" 
                    value={newStopName}
                    onChange={(e) => setNewStopName(e.target.value)}
                    placeholder="e.g. Board Office Square"
                    className="w-full glass-input px-3 py-2 rounded-xl"
                  />
                </div>

                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <label className="block text-gray-400 mb-1">Latitude (Optional)</label>
                    <input 
                      type="text" 
                      step="any"
                      placeholder="Auto-resolved if empty"
                      value={newStopLat || ''}
                      onChange={(e) => setNewStopLat(e.target.value)}
                      className="w-full glass-input px-3 py-2 rounded-xl"
                    />
                  </div>
                  <div>
                    <label className="block text-gray-400 mb-1">Longitude (Optional)</label>
                    <input 
                      type="text" 
                      step="any"
                      placeholder="Auto-resolved if empty"
                      value={newStopLng || ''}
                      onChange={(e) => setNewStopLng(e.target.value)}
                      className="w-full glass-input px-3 py-2 rounded-xl"
                    />
                  </div>
                </div>

                <p className="text-[10px] text-cyan-400 font-medium">✨ Auto-Geocoding Enabled: Type a stop name like "Indrapuri" or "MP Nagar" and coordinates will resolve automatically!</p>

                <button
                  onClick={handleAddStopToRoute}
                  className="w-full bg-cyan-600 hover:bg-cyan-500 text-white font-semibold py-2.5 rounded-xl transition shadow-lg glow-cyan"
                >
                  Add Stop to Route
                </button>
              </div>
            </div>
          )}

        </div>

        {/* Right 2 Cols: Interactive Stop Mapping */}
        <div className="lg:col-span-2 glass-panel p-2 rounded-2xl h-[550px] relative overflow-hidden">
          <MapContainer 
            center={[23.2599, 77.4126]} 
            zoom={12} 
            style={{ width: '100%', height: '100%', borderRadius: '0.75rem' }}
          >
            <TileLayer
              url="https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}"
              attribution='&copy; Google Maps'
            />
            <LocationPicker onLocationSelect={(lat, lng) => {
              setNewStopLat(lat.toFixed(5));
              setNewStopLng(lng.toFixed(5));
            }} />

            {selectedRoute?.stops?.map((stop, idx) => (
              <Marker 
                key={idx}
                position={[stop.lat, stop.lng]}
                icon={stopMarkerIcon}
              >
                <Popup>
                  <div className="text-xs">
                    <p className="font-bold text-indigo-400">Stop #{idx + 1}: {stop.name}</p>
                    <p className="text-gray-300">Lat: {stop.lat}, Lng: {stop.lng}</p>
                  </div>
                </Popup>
              </Marker>
            ))}
          </MapContainer>
        </div>

      </div>

      {/* Add New Route Modal */}
      {isAddingRoute && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-panel p-6 rounded-2xl max-w-md w-full border border-gray-800 space-y-4">
            <h3 className="font-display font-bold text-lg text-white">Create New Bus Route</h3>

            <div className="space-y-3 text-xs">
              <div>
                <label className="block text-gray-300 mb-1">Route Name</label>
                <input 
                  type="text" 
                  value={newRouteName}
                  onChange={(e) => setNewRouteName(e.target.value)}
                  placeholder="e.g. Kolar Highway Express"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>

              <div>
                <label className="block text-gray-300 mb-1">Route Theme Color</label>
                <input 
                  type="color" 
                  value={newRouteColor}
                  onChange={(e) => setNewRouteColor(e.target.value)}
                  className="w-full h-10 bg-transparent cursor-pointer rounded-xl"
                />
              </div>
            </div>

            <div className="flex space-x-3 pt-2">
              <button 
                onClick={() => setIsAddingRoute(false)}
                className="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 font-semibold text-xs py-2.5 rounded-xl"
              >
                Cancel
              </button>
              <button 
                onClick={handleCreateRoute}
                className="flex-1 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs py-2.5 rounded-xl"
              >
                Save Route
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
