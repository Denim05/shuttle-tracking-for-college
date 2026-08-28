import React, { useState, useEffect } from 'react';
import { BarChart3, Download, FileText, Calendar, Bus, Clock, ShieldCheck, Printer } from 'lucide-react';
import { fleetAPI, reportAPI } from '../services/api';

export default function ReportsAnalytics() {
  const [buses, setBuses] = useState([]);
  const [selectedBusId, setSelectedBusId] = useState('');
  const [reportDays, setReportDays] = useState(7);
  const [reportData, setReportData] = useState(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    fetchBuses();
  }, []);

  const fetchBuses = async () => {
    try {
      const res = await fleetAPI.getAllBuses();
      const loadedBuses = res.data?.buses || res.data || [
        { _id: '1', busNumber: 'MP-04-HB-1001', name: 'Bus 01' },
        { _id: '2', busNumber: 'MP-04-HB-1002', name: 'Bus 02' }
      ];
      setBuses(loadedBuses);
      if (loadedBuses.length > 0) {
        setSelectedBusId(loadedBuses[0]._id);
        fetchReport(loadedBuses[0]._id, 7);
      }
    } catch (err) {
      console.error('Fetch buses error:', err);
    }
  };

  const fetchReport = async (busId, days) => {
    if (!busId) return;
    setLoading(true);
    try {
      const res = await reportAPI.getBusTripReport(busId, days);
      setReportData(res.data || {
        totalTrips: 14,
        onTimeRate: '92%',
        avgSpeed: '38 km/h',
        logs: [
          { date: '2026-08-15', tripType: 'pickup', startTime: '07:30 AM', endTime: '08:15 AM', status: 'Completed', avgSpeed: '40 km/h' },
          { date: '2026-08-14', tripType: 'dropoff', startTime: '04:30 PM', endTime: '05:20 PM', status: 'Completed', avgSpeed: '36 km/h' },
        ]
      });
    } catch (err) {
      console.error('Fetch report error:', err);
    } finally {
      setLoading(false);
    }
  };

  const handlePrintReport = () => {
    const windowUrl = `http://localhost:5000/api/manager/reports/bus-trip-report/html?busId=${selectedBusId}&days=${reportDays}`;
    window.open(windowUrl, '_blank');
  };

  return (
    <div className="space-y-6 pb-12">
      
      {/* Header */}
      <div className="glass-panel p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-display font-bold text-white">Performance Analytics & Trip Logs</h2>
          <p className="text-xs text-gray-400 mt-1">Audit fleet performance, export official trip logs, and print delay reports</p>
        </div>

        <div className="flex items-center space-x-3">
          <button 
            onClick={handlePrintReport}
            className="bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
          >
            <Printer className="w-4 h-4" />
            <span>Print Official HTML/PDF Report</span>
          </button>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="glass-panel p-4 rounded-xl flex flex-col sm:flex-row items-center justify-between gap-4">
        
        <div className="flex items-center space-x-4 w-full sm:w-auto text-xs">
          <div>
            <label className="block text-gray-400 text-[10px] uppercase font-bold mb-1">Select Bus</label>
            <select
              value={selectedBusId}
              onChange={(e) => {
                setSelectedBusId(e.target.value);
                fetchReport(e.target.value, reportDays);
              }}
              className="glass-input px-3 py-2 rounded-xl text-xs"
            >
              {buses.map((bus) => (
                <option key={bus._id} value={bus._id} className="bg-gray-900 text-white">
                  {bus.name || bus.busNumber} ({bus.busNumber})
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-gray-400 text-[10px] uppercase font-bold mb-1">Time Range</label>
            <select
              value={reportDays}
              onChange={(e) => {
                setReportDays(Number(e.target.value));
                fetchReport(selectedBusId, Number(e.target.value));
              }}
              className="glass-input px-3 py-2 rounded-xl text-xs"
            >
              <option value={7} className="bg-gray-900 text-white">Last 7 Days</option>
              <option value={14} className="bg-gray-900 text-white">Last 14 Days</option>
              <option value={30} className="bg-gray-900 text-white">Last 30 Days</option>
            </select>
          </div>
        </div>

      </div>

      {/* Analytics Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
        <div className="glass-card p-5 rounded-2xl">
          <p className="text-xs text-gray-400 font-medium">Total Trips Recorded</p>
          <h3 className="text-2xl font-display font-bold text-white mt-1">{reportData?.totalTrips || 14}</h3>
          <p className="text-[11px] text-cyan-400 mt-1">Completed safely</p>
        </div>

        <div className="glass-card p-5 rounded-2xl">
          <p className="text-xs text-gray-400 font-medium">On-Time Compliance</p>
          <h3 className="text-2xl font-display font-bold text-emerald-400 mt-1">{reportData?.onTimeRate || '94%'}</h3>
          <p className="text-[11px] text-emerald-400 mt-1">Within schedule window</p>
        </div>

        <div className="glass-card p-5 rounded-2xl">
          <p className="text-xs text-gray-400 font-medium">Average Fleet Speed</p>
          <h3 className="text-2xl font-display font-bold text-indigo-400 mt-1">{reportData?.avgSpeed || '38 km/h'}</h3>
          <p className="text-[11px] text-indigo-300 mt-1">Safe campus speed</p>
        </div>
      </div>

      {/* Trip Log Table */}
      <div className="glass-panel rounded-2xl overflow-hidden border border-gray-800">
        <div className="p-4 border-b border-gray-800 flex items-center justify-between">
          <h3 className="font-display font-bold text-sm text-white">Detailed Daily Trip Logs</h3>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-gray-900/80 text-gray-400 font-semibold border-b border-gray-800 uppercase tracking-wider text-[10px]">
              <tr>
                <th className="p-4">Date</th>
                <th className="p-4">Shift Type</th>
                <th className="p-4">Start Time</th>
                <th className="p-4">End Time</th>
                <th className="p-4">Average Speed</th>
                <th className="p-4">Trip Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-800/60">
              {reportData?.logs?.map((log, idx) => (
                <tr key={idx} className="hover:bg-gray-800/30 transition">
                  <td className="p-4 font-mono text-gray-200">{log.date}</td>
                  <td className="p-4 uppercase font-semibold text-cyan-400">{log.tripType}</td>
                  <td className="p-4 text-gray-300">{log.startTime}</td>
                  <td className="p-4 text-gray-300">{log.endTime}</td>
                  <td className="p-4 font-mono text-indigo-300">{log.avgSpeed}</td>
                  <td className="p-4">
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                      {log.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

    </div>
  );
}
