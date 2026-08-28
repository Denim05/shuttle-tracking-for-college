import React, { useState, useEffect } from 'react';
import { Users, Bus, Plus, Phone, ShieldCheck, FileText, Upload, Trash2, CheckCircle, AlertCircle } from 'lucide-react';
import { driverAPI, fleetAPI } from '../services/api';

export default function DriverFleetManager() {
  const [drivers, setDrivers] = useState([]);
  const [buses, setBuses] = useState([]);
  const [loading, setLoading] = useState(true);
  
  // Modals
  const [isAddDriverOpen, setIsAddDriverOpen] = useState(false);
  const [isAddBusOpen, setIsAddBusOpen] = useState(false);

  // New Driver Form
  const [driverName, setDriverName] = useState('');
  const [driverUsername, setDriverUsername] = useState('');
  const [driverPassword, setDriverPassword] = useState('');
  const [driverPhone, setDriverPhone] = useState('');
  const [driverLicense, setDriverLicense] = useState('');
  const [assignedBus, setAssignedBus] = useState('');

  // New Bus Form
  const [busNumber, setBusNumber] = useState('');
  const [busName, setBusName] = useState('');
  const [busRouteName, setBusRouteName] = useState('');

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const [driverRes, busRes] = await Promise.all([
        driverAPI.getAllDrivers(),
        fleetAPI.getAllBuses()
      ]);
      setDrivers(driverRes.data?.drivers || driverRes.data || [
        { _id: 'd1', name: 'Rajesh Kumar', username: 'driver_rajesh', contactNumber: '9876543210', licenseNumber: 'MP-04-DL-2018-9921', assignedBus: 'MP-04-HB-1001', status: 'Active' },
        { _id: 'd2', name: 'Vikram Singh', username: 'driver_vikram', contactNumber: '9876543211', licenseNumber: 'MP-04-DL-2019-1102', assignedBus: 'MP-04-HB-1002', status: 'Active' },
      ]);
      setBuses(busRes.data?.buses || busRes.data || [
        { _id: 'b1', busNumber: 'MP-04-HB-1001', name: 'Bus 01', routeName: 'Indrapuri Express' },
        { _id: 'b2', busNumber: 'MP-04-HB-1002', name: 'Bus 02', routeName: 'MP Nagar Shuttle' },
      ]);
    } catch (err) {
      console.error('Failed to fetch drivers/buses:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateDriver = async () => {
    if (!driverName || !driverUsername || !driverPassword) return;
    try {
      await driverAPI.createDriver({
        name: driverName,
        username: driverUsername,
        password: driverPassword,
        contactNumber: driverPhone,
        licenseNumber: driverLicense,
        assignedBus: assignedBus
      });
      setIsAddDriverOpen(false);
      fetchData();
    } catch (err) {
      console.error('Create driver error:', err);
    }
  };

  const handleCreateBus = async () => {
    if (!busNumber || !busName) return;
    try {
      await fleetAPI.createBus({
        busNumber,
        name: busName,
        routeName: busRouteName || 'General Route',
        routeId: 'route_gen'
      });
      setIsAddBusOpen(false);
      fetchData();
    } catch (err) {
      console.error('Create bus error:', err);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      
      {/* Header */}
      <div className="glass-panel p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-display font-bold text-white">Driver Roster & Fleet Hub</h2>
          <p className="text-xs text-gray-400 mt-1">Manage transport drivers, license records, and bus vehicle allocations</p>
        </div>

        <div className="flex items-center space-x-3">
          <button 
            onClick={() => setIsAddBusOpen(true)}
            className="bg-gray-800 hover:bg-gray-700 text-gray-200 border border-gray-700 px-4 py-2.5 rounded-xl text-xs font-semibold flex items-center space-x-2 transition"
          >
            <Bus className="w-4 h-4 text-cyan-400" />
            <span>Add Bus Vehicle</span>
          </button>

          <button 
            onClick={() => setIsAddDriverOpen(true)}
            className="bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
          >
            <Plus className="w-4 h-4" />
            <span>Add Driver</span>
          </button>
        </div>
      </div>

      {/* Driver Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {drivers.map((driver) => (
          <div key={driver._id} className="glass-card p-5 rounded-2xl space-y-4 relative border border-gray-800">
            
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-600 to-cyan-500 flex items-center justify-center font-bold text-white shadow">
                  {driver.name ? driver.name.substring(0, 2).toUpperCase() : 'DR'}
                </div>
                <div>
                  <h3 className="font-bold text-sm text-white">{driver.name}</h3>
                  <p className="text-[11px] text-cyan-400 font-mono">@{driver.username}</p>
                </div>
              </div>

              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                driver.status === 'Active' ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 'bg-red-500/20 text-red-400'
              }`}>
                {driver.status || 'Active'}
              </span>
            </div>

            <div className="space-y-2 text-xs text-gray-300 pt-2 border-t border-gray-800">
              <div className="flex justify-between">
                <span className="text-gray-400">License Number:</span>
                <span className="font-mono text-gray-200">{driver.licenseNumber || 'N/A'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Contact Phone:</span>
                <span className="text-cyan-400 font-semibold">{driver.contactNumber || 'N/A'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Assigned Bus:</span>
                <span className="text-indigo-400 font-bold">{driver.assignedBus || 'Unassigned'}</span>
              </div>
            </div>

          </div>
        ))}
      </div>

      {/* Add Driver Modal */}
      {isAddDriverOpen && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-panel p-6 rounded-2xl max-w-md w-full border border-gray-800 space-y-4">
            <h3 className="font-display font-bold text-lg text-white">Register New Transport Driver</h3>

            <div className="space-y-3 text-xs">
              <div>
                <label className="block text-gray-300 mb-1">Full Name</label>
                <input 
                  type="text" 
                  value={driverName} 
                  onChange={(e) => setDriverName(e.target.value)}
                  placeholder="e.g. Ramesh Chandra"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>

              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-gray-300 mb-1">Login Username</label>
                  <input 
                    type="text" 
                    value={driverUsername} 
                    onChange={(e) => setDriverUsername(e.target.value)}
                    placeholder="driver_ramesh"
                    className="w-full glass-input px-3 py-2 rounded-xl"
                  />
                </div>
                <div>
                  <label className="block text-gray-300 mb-1">Login Password</label>
                  <input 
                    type="password" 
                    value={driverPassword} 
                    onChange={(e) => setDriverPassword(e.target.value)}
                    placeholder="••••••••"
                    className="w-full glass-input px-3 py-2 rounded-xl"
                  />
                </div>
              </div>

              <div>
                <label className="block text-gray-300 mb-1">Driving License Number</label>
                <input 
                  type="text" 
                  value={driverLicense} 
                  onChange={(e) => setDriverLicense(e.target.value)}
                  placeholder="MP-04-DL-2020-XXXX"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>

              <div>
                <label className="block text-gray-300 mb-1">Contact Phone</label>
                <input 
                  type="text" 
                  value={driverPhone} 
                  onChange={(e) => setDriverPhone(e.target.value)}
                  placeholder="+91 98765 43210"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>
            </div>

            <div className="flex space-x-3 pt-2">
              <button 
                onClick={() => setIsAddDriverOpen(false)}
                className="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 font-semibold text-xs py-2.5 rounded-xl"
              >
                Cancel
              </button>
              <button 
                onClick={handleCreateDriver}
                className="flex-1 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs py-2.5 rounded-xl"
              >
                Save Driver
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Add Bus Modal */}
      {isAddBusOpen && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-panel p-6 rounded-2xl max-w-md w-full border border-gray-800 space-y-4">
            <h3 className="font-display font-bold text-lg text-white">Add New Fleet Bus</h3>

            <div className="space-y-3 text-xs">
              <div>
                <label className="block text-gray-300 mb-1">Vehicle Registration Number</label>
                <input 
                  type="text" 
                  value={busNumber} 
                  onChange={(e) => setBusNumber(e.target.value)}
                  placeholder="MP-04-AB-1234"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>

              <div>
                <label className="block text-gray-300 mb-1">Bus Display Name</label>
                <input 
                  type="text" 
                  value={busName} 
                  onChange={(e) => setBusName(e.target.value)}
                  placeholder="Bus 05"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>

              <div>
                <label className="block text-gray-300 mb-1">Assigned Route Name</label>
                <input 
                  type="text" 
                  value={busRouteName} 
                  onChange={(e) => setBusRouteName(e.target.value)}
                  placeholder="Bairagarh Express"
                  className="w-full glass-input px-3 py-2 rounded-xl"
                />
              </div>
            </div>

            <div className="flex space-x-3 pt-2">
              <button 
                onClick={() => setIsAddBusOpen(false)}
                className="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 font-semibold text-xs py-2.5 rounded-xl"
              >
                Cancel
              </button>
              <button 
                onClick={handleCreateBus}
                className="flex-1 bg-cyan-600 hover:bg-cyan-500 text-white font-semibold text-xs py-2.5 rounded-xl"
              >
                Register Bus
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
