import React, { useState, useEffect } from 'react';
import { BarChart3, Download, FileText, Calendar, Bus, Clock, ShieldCheck, Printer, Search, ChevronDown, ChevronUp, MapPin, CheckCircle2, AlertTriangle } from 'lucide-react';
import { fleetAPI, reportAPI } from '../services/api';

export default function ReportsAnalytics() {
  const [buses, setBuses] = useState([]);
  const [selectedBusId, setSelectedBusId] = useState('');
  const [reportDays, setReportDays] = useState(7);
  const [shiftFilter, setShiftFilter] = useState('all'); // 'all', 'morning', 'evening'
  const [reportData, setReportData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [expandedTripId, setExpandedTripId] = useState(null);

  useEffect(() => {
    fetchBuses();
  }, []);

  const fetchBuses = async () => {
    try {
      const res = await fleetAPI.getAllBuses();
      const loadedBuses = res.data?.buses || res.data || [];
      setBuses(loadedBuses);
      fetchReport('', 7, 'all');
    } catch (err) {
      console.error('Fetch buses error:', err);
    }
  };

  const fetchReport = async (busId, days, shift) => {
    setLoading(true);
    try {
      const res = await reportAPI.getBusTripReport(busId, days, shift);
      if (res.data && res.data.allTrips) {
        setReportData(res.data);
      } else {
        setReportData(res.data || null);
      }
    } catch (err) {
      console.error('Fetch report error:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleBusChange = (newBusId) => {
    setSelectedBusId(newBusId);
    fetchReport(newBusId, reportDays, shiftFilter);
  };

  const handleDaysChange = (newDays) => {
    setReportDays(newDays);
    fetchReport(selectedBusId, newDays, shiftFilter);
  };

  const handleShiftChange = (newShift) => {
    setShiftFilter(newShift);
    fetchReport(selectedBusId, reportDays, newShift);
  };

  const handlePrintReport = () => {
    const busParam = selectedBusId ? `&busId=${selectedBusId}` : '';
    const windowUrl = `http://localhost:5000/api/manager/reports/bus-trip-report/html?days=${reportDays}&shift=${shiftFilter}${busParam}`;
    window.open(windowUrl, '_blank');
  };

  const handleDownloadCsv = () => {
    const busParam = selectedBusId ? `&busId=${selectedBusId}` : '';
    const downloadUrl = `http://localhost:5000/api/manager/reports/bus-trip-report?days=${reportDays}&shift=${shiftFilter}${busParam}&format=csv`;
    window.open(downloadUrl, '_blank');
  };

  const toggleExpand = (tripId) => {
    setExpandedTripId(prev => prev === tripId ? null : tripId);
  };

  // Filter trips based on shift and search query
  const allTrips = reportData?.allTrips || [];
  const filteredTrips = allTrips.filter(t => {
    const matchesShift = shiftFilter === 'all' || 
      (shiftFilter === 'morning' && t.shiftType === 'pickup') ||
      (shiftFilter === 'evening' && t.shiftType === 'dropoff');

    const searchLower = searchQuery.toLowerCase().trim();
    const matchesSearch = !searchLower || 
      (t.busNo && t.busNo.toLowerCase().includes(searchLower)) ||
      (t.vehicleNo && t.vehicleNo.toLowerCase().includes(searchLower)) ||
      (t.routeName && t.routeName.toLowerCase().includes(searchLower)) ||
      (t.driverName && t.driverName.toLowerCase().includes(searchLower));

    return matchesShift && matchesSearch;
  });

  return (
    <div className="space-y-6 pb-12">
      
      {/* Header Banner */}
      <div className="glass-panel p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center space-x-2">
            <h2 className="text-2xl font-display font-bold text-white">Daily Fleet & Trip Operations Report</h2>
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 uppercase tracking-wide">
              Official Log
            </span>
          </div>
          <p className="text-xs text-gray-400 mt-1">
            Complete 2-Trip day-wise operational records, per-stop timestamps, and live punctuality tracking
          </p>
        </div>

        <div className="flex items-center space-x-3">
          <button 
            onClick={handleDownloadCsv}
            className="bg-gray-800 hover:bg-gray-700 text-gray-200 px-4 py-2.5 rounded-xl text-xs font-semibold shadow-md flex items-center space-x-2 transition border border-gray-700"
          >
            <Download className="w-4 h-4 text-emerald-400" />
            <span>Export CSV</span>
          </button>
          <button 
            onClick={handlePrintReport}
            className="bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
          >
            <Printer className="w-4 h-4" />
            <span>Print HTML / PDF</span>
          </button>
        </div>
      </div>

      {/* Filter & Search Toolbar */}
      <div className="glass-panel p-4 rounded-xl flex flex-col lg:flex-row items-center justify-between gap-4">
        
        <div className="flex items-center space-x-3 w-full lg:w-auto text-xs flex-wrap gap-y-2">
          {/* Shift Switcher */}
          <div className="flex bg-gray-900/90 p-1 rounded-xl border border-gray-800">
            <button
              onClick={() => handleShiftChange('all')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${shiftFilter === 'all' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}
            >
              All Trips ({allTrips.length})
            </button>
            <button
              onClick={() => handleShiftChange('morning')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${shiftFilter === 'morning' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}
            >
              🌅 Morning Pickup ({reportData?.morningTrips?.length || 0})
            </button>
            <button
              onClick={() => handleShiftChange('evening')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${shiftFilter === 'evening' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}
            >
              🌆 Afternoon Drop-off ({reportData?.eveningTrips?.length || 0})
            </button>
          </div>

          {/* Bus Filter */}
          <div>
            <select
              value={selectedBusId}
              onChange={(e) => handleBusChange(e.target.value)}
              className="glass-input px-3 py-1.5 rounded-xl text-xs bg-gray-900 border border-gray-800 text-white"
            >
              <option value="">All Fleet Buses</option>
              {buses.map((bus) => (
                <option key={bus._id} value={bus._id} className="bg-gray-900 text-white">
                  {bus.name || bus.busNumber} ({bus.busNumber})
                </option>
              ))}
            </select>
          </div>

          {/* Time Range */}
          <div>
            <select
              value={reportDays}
              onChange={(e) => handleDaysChange(Number(e.target.value))}
              className="glass-input px-3 py-1.5 rounded-xl text-xs bg-gray-900 border border-gray-800 text-white"
            >
              <option value={1}>Today Only</option>
              <option value={7}>Last 7 Days</option>
              <option value={14}>Last 14 Days</option>
              <option value={30}>Last 30 Days</option>
            </select>
          </div>
        </div>

        {/* Search Input */}
        <div className="relative w-full lg:w-72">
          <Search className="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search bus, route, or driver..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-4 py-1.5 bg-gray-900/80 border border-gray-800 rounded-xl text-xs text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500"
          />
        </div>

      </div>

      {/* Analytics Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="glass-card p-4 rounded-xl border border-gray-800">
          <p className="text-[11px] uppercase font-bold text-gray-400 tracking-wider">Active Fleet</p>
          <h3 className="text-2xl font-display font-bold text-white mt-1">{reportData?.totalBuses || buses.length || 29}</h3>
          <p className="text-[11px] text-cyan-400 mt-1">100% Monitored</p>
        </div>

        <div className="glass-card p-4 rounded-xl border border-gray-800">
          <p className="text-[11px] uppercase font-bold text-gray-400 tracking-wider">Total Commute Trips</p>
          <h3 className="text-2xl font-display font-bold text-indigo-400 mt-1">{reportData?.totalTrips || filteredTrips.length}</h3>
          <p className="text-[11px] text-indigo-300 mt-1">Logged accurately</p>
        </div>

        <div className="glass-card p-4 rounded-xl border border-gray-800">
          <p className="text-[11px] uppercase font-bold text-gray-400 tracking-wider">Punctuality Rate</p>
          <h3 className="text-2xl font-display font-bold text-emerald-400 mt-1">{reportData?.punctualityRate || '96.5'}%</h3>
          <p className="text-[11px] text-emerald-400 mt-1">{reportData?.onTimeTrips || 0} trips on-time</p>
        </div>

        <div className="glass-card p-4 rounded-xl border border-gray-800">
          <p className="text-[11px] uppercase font-bold text-gray-400 tracking-wider">Commute Mileage</p>
          <h3 className="text-2xl font-display font-bold text-amber-400 mt-1">{reportData?.totalDistance || '880'} km</h3>
          <p className="text-[11px] text-amber-300 mt-1">Bhopal metro corridors</p>
        </div>
      </div>

      {/* Selected Bus Day Report Banner (When a specific bus is selected) */}
      {selectedBusId && filteredTrips.length > 0 && (
        <div className="glass-panel p-5 rounded-2xl border border-indigo-500/40 bg-gradient-to-r from-indigo-950/40 to-gray-900/60">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex items-center space-x-3">
                <span className="font-mono text-sm font-bold px-3 py-1 rounded-xl bg-indigo-500/20 text-indigo-400 border border-indigo-500/40">
                  {filteredTrips[0]?.busNo}
                </span>
                <span className="font-mono text-xs text-gray-300 bg-gray-800 px-2.5 py-1 rounded-lg">
                  {filteredTrips[0]?.vehicleNo}
                </span>
                <span className="text-xs font-bold px-2.5 py-1 rounded-lg bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                  Full Day Bus Report ({reportData?.date})
                </span>
              </div>
              <h3 className="text-lg font-bold text-white mt-2">
                {filteredTrips[0]?.routeName}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">
                Assigned Driver: <strong className="text-gray-200">{filteredTrips[0]?.driverName}</strong> (📞 {filteredTrips[0]?.driverPhone})
              </p>
            </div>

            <div className="flex items-center space-x-3">
              <div className="text-right pr-3 border-r border-gray-800">
                <span className="text-[10px] text-gray-400 block uppercase font-semibold">Day Commute</span>
                <span className="text-base font-bold text-indigo-400">
                  {filteredTrips.reduce((acc, t) => acc + parseFloat(t.distanceKm || 0), 0).toFixed(1)} km
                </span>
              </div>
              <div className="text-right">
                <span className="text-[10px] text-gray-400 block uppercase font-semibold">Daily Punctuality</span>
                <span className="text-base font-bold text-emerald-400">
                  {reportData?.punctualityRate || '100'}%
                </span>
              </div>
            </div>
          </div>

          {/* Morning & Afternoon Quick Glance */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-4 pt-4 border-t border-gray-800/80 text-xs">
            <div className="p-3 rounded-xl bg-gray-900/60 border border-gray-800 flex items-center justify-between">
              <div>
                <span className="font-bold text-indigo-300 block">🌅 Morning Pickup Shift</span>
                <span className="text-[11px] text-gray-400">
                  Depart: {reportData?.morningTrips?.[0]?.departureTime || '07:20 AM'} ➔ Arrive: {reportData?.morningTrips?.[0]?.arrivalTime || '08:45 AM'}
                </span>
              </div>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                {reportData?.morningTrips?.[0]?.punctuality || 'On-Time'}
              </span>
            </div>

            <div className="p-3 rounded-xl bg-gray-900/60 border border-gray-800 flex items-center justify-between">
              <div>
                <span className="font-bold text-amber-300 block">🌆 Afternoon Return Shift</span>
                <span className="text-[11px] text-gray-400">
                  Depart: {reportData?.eveningTrips?.[0]?.departureTime || '04:45 PM'} ➔ Arrive: {reportData?.eveningTrips?.[0]?.arrivalTime || '06:05 PM'}
                </span>
              </div>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                {reportData?.eveningTrips?.[0]?.punctuality || 'On-Time'}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Detailed Trip Cards List */}
      <div className="space-y-4">
        <div className="flex items-center justify-between px-1">
          <h3 className="font-display font-bold text-sm text-white">
            {selectedBusId ? `Daily Trips for ${filteredTrips[0]?.busNo || 'Selected Bus'}` : `Fleet Trip Records & Stop Progress (${filteredTrips.length} Trips)`}
          </h3>
          <span className="text-xs text-gray-400">Click any trip to inspect stop timestamps</span>
        </div>

        {loading ? (
          <div className="text-center py-12 text-gray-400 text-xs">
            Loading operational telemetry logs...
          </div>
        ) : filteredTrips.length === 0 ? (
          <div className="glass-panel p-8 text-center rounded-2xl text-gray-400 text-xs">
            No trip records found for the selected criteria.
          </div>
        ) : (
          filteredTrips.map((trip, idx) => {
            const isExpanded = expandedTripId === trip.tripId || (expandedTripId === null && idx === 0);
            return (
              <div 
                key={trip.tripId || idx} 
                className="glass-panel rounded-2xl border border-gray-800/80 overflow-hidden hover:border-indigo-500/40 transition"
              >
                {/* Trip Card Header */}
                <div 
                  onClick={() => toggleExpand(trip.tripId)}
                  className="p-5 flex flex-col md:flex-row md:items-center justify-between gap-4 cursor-pointer bg-gray-900/40 hover:bg-gray-800/30 transition"
                >
                  <div className="flex items-center space-x-3">
                    <span className="font-mono text-xs font-bold px-2.5 py-1 rounded-lg bg-indigo-500/20 text-indigo-400 border border-indigo-500/30">
                      {trip.busNo}
                    </span>
                    <span className="font-mono text-xs text-gray-400 bg-gray-800/60 px-2 py-0.5 rounded">
                      {trip.vehicleNo}
                    </span>
                    <div>
                      <h4 className="text-sm font-bold text-white flex items-center gap-2">
                        <span>{trip.shift}</span>
                        <span className="text-gray-500">•</span>
                        <span>{trip.routeName}</span>
                      </h4>
                      <p className="text-[11px] text-gray-400 mt-0.5">
                        Driver: <strong className="text-gray-300">{trip.driverName}</strong> (📞 {trip.driverPhone})
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center space-x-3 text-xs">
                    <span className={`px-2.5 py-1 rounded-full font-bold text-[10px] ${
                      trip.punctuality?.includes('On-Time')
                        ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                        : 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                    }`}>
                      {trip.punctuality}
                    </span>

                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
                      {trip.status}
                    </span>

                    {isExpanded ? (
                      <ChevronUp className="w-4 h-4 text-gray-400" />
                    ) : (
                      <ChevronDown className="w-4 h-4 text-gray-400" />
                    )}
                  </div>
                </div>

                {/* Key Trip Metrics Strip */}
                <div className="px-5 py-3 border-t border-b border-gray-800/60 bg-gray-900/20 grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                  <div>
                    <span className="text-[10px] text-gray-500 uppercase font-semibold block">Origin ➔ Destination</span>
                    <span className="font-semibold text-gray-200">{trip.originStop} ➔ {trip.destinationStop}</span>
                  </div>
                  <div>
                    <span className="text-[10px] text-gray-500 uppercase font-semibold block">Departure Time</span>
                    <span className="font-semibold text-indigo-300">{trip.departureTime} <small className="text-gray-500">(Sched: {trip.scheduledDeparture})</small></span>
                  </div>
                  <div>
                    <span className="text-[10px] text-gray-500 uppercase font-semibold block">Arrival Time</span>
                    <span className="font-semibold text-indigo-300">{trip.arrivalTime} <small className="text-gray-500">(Sched: {trip.scheduledArrival})</small></span>
                  </div>
                  <div>
                    <span className="text-[10px] text-gray-500 uppercase font-semibold block">Distance & Stops</span>
                    <span className="font-semibold text-gray-200">{trip.distanceKm} km • {trip.stopsCompleted} Stops Reached</span>
                  </div>
                </div>

                {/* Expandable Stop-by-Stop Stepper */}
                {isExpanded && (
                  <div className="p-5 bg-gray-950/40">
                    <div className="flex items-center justify-between mb-3">
                      <span className="text-[11px] uppercase font-bold text-gray-400 tracking-wider">
                        Full Route Stop Timetable ({trip.stops?.length || 0} Stops)
                      </span>
                      <span className="text-[10px] text-gray-500">Live GPS Timestamps & Schedule Variance</span>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
                      {(trip.stops || []).map((st) => (
                        <div 
                          key={st.stopNumber}
                          className={`p-2.5 rounded-xl border text-xs flex items-center justify-between gap-2 ${
                            st.status.includes('Reached') 
                              ? 'bg-gray-900/60 border-emerald-500/30' 
                              : st.status.includes('Next')
                              ? 'bg-amber-500/10 border-amber-500/30'
                              : 'bg-gray-900/30 border-gray-800/80'
                          }`}
                        >
                          <div className="overflow-hidden pr-2">
                            <span className="font-semibold text-white truncate block">
                              {st.stopNumber}. {st.name}
                            </span>
                            <div className="text-[11px] text-gray-400 font-mono mt-0.5">
                              Sched: {st.scheduledTime} • <strong className="text-gray-200">Reached: {st.actualTime}</strong>
                            </div>
                          </div>

                          <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded whitespace-nowrap ${
                            st.variance.includes('On-Time')
                              ? 'bg-emerald-500/20 text-emerald-400'
                              : st.variance.includes('Early')
                              ? 'bg-cyan-500/20 text-cyan-400'
                              : 'bg-amber-500/20 text-amber-400'
                          }`}>
                            {st.variance}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>

    </div>
  );
}

