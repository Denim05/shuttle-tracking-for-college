import React, { useState, useEffect } from 'react';
import { UserCheck, UserX, Search, Download, CheckCircle, XCircle, ShieldCheck, Key, RefreshCw } from 'lucide-react';
import { registrationAPI } from '../services/api';

export default function RegistrationsManager() {
  const [registrations, setRegistrations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('pending');
  const [selectedIds, setSelectedIds] = useState([]);
  const [credentialsModal, setCredentialsModal] = useState(null);
  const [actionLoading, setActionLoading] = useState(false);

  useEffect(() => {
    fetchRegistrations();
  }, []);

  const fetchRegistrations = async () => {
    setLoading(true);
    try {
      const res = await registrationAPI.getAll();
      setRegistrations(res.data?.submissions || res.data || [
        { _id: 's1', name: 'Rahul Sharma', studentId: '0192CS211045', phone: '9876543210', routeName: 'Indrapuri Express', pickupStop: 'BHEL Gate 1', courseName: 'B.Tech CSE', status: 'pending', submittedAt: new Date() },
        { _id: 's2', name: 'Ananya Verma', studentId: '0192EC211019', phone: '9876543211', routeName: 'MP Nagar Shuttle', pickupStop: 'Board Office', courseName: 'B.Tech ECE', status: 'pending', submittedAt: new Date() },
        { _id: 's3', name: 'Vikas Kumar', studentId: '0192ME211002', phone: '9876543212', routeName: 'Bairagarh Direct', pickupStop: 'Halalpur Bus Stand', courseName: 'B.Tech ME', status: 'approved', generatedUsername: '0192ME211002', generatedPassword: 'Pass#9876', submittedAt: new Date() },
      ]);
    } catch (err) {
      console.error('Failed to fetch registrations:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleApprove = async (id) => {
    setActionLoading(true);
    try {
      const res = await registrationAPI.approve(id);
      const updated = res.data?.submission;
      if (updated && updated.generatedPassword) {
        setCredentialsModal({
          name: updated.name,
          username: updated.generatedUsername || updated.studentId,
          password: updated.generatedPassword
        });
      }
      fetchRegistrations();
    } catch (err) {
      console.error('Approval failed:', err);
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async (id) => {
    const note = prompt('Enter rejection reason:');
    if (note === null) return;
    setActionLoading(true);
    try {
      await registrationAPI.reject(id, note);
      fetchRegistrations();
    } catch (err) {
      console.error('Rejection failed:', err);
    } finally {
      setActionLoading(false);
    }
  };

  const handleBulkApprove = async () => {
    if (selectedIds.length === 0) return;
    if (!window.confirm(`Approve transport access for ${selectedIds.length} selected students?`)) return;
    
    setActionLoading(true);
    try {
      await registrationAPI.bulkApprove(selectedIds);
      setSelectedIds([]);
      fetchRegistrations();
    } catch (err) {
      console.error('Bulk approval failed:', err);
    } finally {
      setActionLoading(false);
    }
  };

  const toggleSelect = (id) => {
    setSelectedIds(prev => 
      prev.includes(id) ? prev.filter(i => i !== id) : [...prev, id]
    );
  };

  const toggleSelectAll = () => {
    if (selectedIds.length === filteredData.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filteredData.map(r => r._id));
    }
  };

  const exportCSV = () => {
    const headers = ["Student Name", "Student ID", "Phone", "Route Name", "Pickup Stop", "Course", "Status"];
    const rows = filteredData.map(r => [
      `"${r.name}"`,
      `"${r.studentId}"`,
      `"${r.phone}"`,
      `"${r.routeName || ''}"`,
      `"${r.pickupStop || ''}"`,
      `"${r.courseName || ''}"`,
      `"${r.status}"`
    ]);

    const csvContent = "data:text/csv;charset=utf-8," + [headers.join(","), ...rows.map(e => e.join(","))].join("\n");
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `transport_registrations_${filterStatus}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const filteredData = registrations.filter(r => {
    const matchesSearch = (r.name + r.studentId + r.phone + (r.routeName || '') + (r.pickupStop || '')).toLowerCase().includes(search.toLowerCase());
    const matchesStatus = filterStatus === 'ALL' || r.status === filterStatus;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-6 pb-12">
      
      {/* Top Header */}
      <div className="glass-panel p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-display font-bold text-white">Student Transport Registrations</h2>
          <p className="text-xs text-gray-400 mt-1">Review student applications, issue transport passes, and manage approvals</p>
        </div>

        <div className="flex items-center space-x-3">
          {selectedIds.length > 0 && (
            <button 
              onClick={handleBulkApprove}
              disabled={actionLoading}
              className="bg-emerald-600 hover:bg-emerald-500 text-white px-4 py-2.5 rounded-xl text-xs font-semibold shadow-lg glow-emerald flex items-center space-x-2 transition"
            >
              <CheckCircle className="w-4 h-4" />
              <span>Bulk Approve Selected ({selectedIds.length})</span>
            </button>
          )}

          <button 
            onClick={exportCSV}
            className="bg-gray-800 hover:bg-gray-700 text-gray-200 border border-gray-700 px-4 py-2.5 rounded-xl text-xs font-semibold flex items-center space-x-2 transition"
          >
            <Download className="w-4 h-4 text-cyan-400" />
            <span>Export CSV</span>
          </button>
        </div>
      </div>

      {/* Filter & Search Bar */}
      <div className="glass-panel p-4 rounded-xl flex flex-col sm:flex-row items-center justify-between gap-4">
        
        {/* Search */}
        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-gray-400 absolute left-3 top-3" />
          <input 
            type="text" 
            value={search} 
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search student name, ID, route, stop..."
            className="w-full glass-input pl-9 pr-3 py-2 rounded-xl text-xs"
          />
        </div>

        {/* Status Tabs */}
        <div className="flex items-center space-x-2 text-xs">
          {['pending', 'approved', 'rejected', 'ALL'].map((st) => (
            <button
              key={st}
              onClick={() => setFilterStatus(st)}
              className={`px-4 py-2 rounded-xl font-semibold capitalize transition ${
                filterStatus === st 
                  ? 'bg-indigo-600 text-white shadow-lg' 
                  : 'bg-gray-800/60 text-gray-400 hover:text-gray-200'
              }`}
            >
              {st} ({registrations.filter(r => st === 'ALL' ? true : r.status === st).length})
            </button>
          ))}
        </div>

      </div>

      {/* Main Table */}
      <div className="glass-panel rounded-2xl overflow-hidden border border-gray-800">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-gray-900/80 text-gray-400 font-semibold border-b border-gray-800 uppercase tracking-wider text-[10px]">
              <tr>
                <th className="p-4 w-10 text-center">
                  <input 
                    type="checkbox" 
                    checked={selectedIds.length > 0 && selectedIds.length === filteredData.length}
                    onChange={toggleSelectAll}
                    className="rounded bg-gray-800 border-gray-700 text-indigo-600 focus:ring-0"
                  />
                </th>
                <th className="p-4">Student Info</th>
                <th className="p-4">Route & Stop</th>
                <th className="p-4">Contact</th>
                <th className="p-4">Course</th>
                <th className="p-4">Status</th>
                <th className="p-4 text-right">Actions</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-gray-800/60">
              {filteredData.length === 0 ? (
                <tr>
                  <td colSpan="7" className="p-8 text-center text-gray-500">
                    No registrations found matching criteria.
                  </td>
                </tr>
              ) : (
                filteredData.map((reg) => (
                  <tr key={reg._id} className="hover:bg-gray-800/30 transition">
                    <td className="p-4 text-center">
                      <input 
                        type="checkbox" 
                        checked={selectedIds.includes(reg._id)}
                        onChange={() => toggleSelect(reg._id)}
                        className="rounded bg-gray-800 border-gray-700 text-indigo-600 focus:ring-0"
                      />
                    </td>

                    <td className="p-4">
                      <p className="font-bold text-white">{reg.name}</p>
                      <p className="text-[11px] text-indigo-400 font-mono">{reg.studentId}</p>
                    </td>

                    <td className="p-4">
                      <p className="font-semibold text-gray-200">{reg.routeName || 'General Route'}</p>
                      <p className="text-[11px] text-cyan-400">Stop: {reg.pickupStop}</p>
                    </td>

                    <td className="p-4 text-gray-300">
                      <p>{reg.phone}</p>
                      <p className="text-[10px] text-gray-500">{reg.email || 'No email'}</p>
                    </td>

                    <td className="p-4 text-gray-400">
                      {reg.courseName || 'N/A'}
                    </td>

                    <td className="p-4">
                      <span className={`text-[10px] font-bold px-2.5 py-1 rounded-full uppercase tracking-wider ${
                        reg.status === 'approved' ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' :
                        reg.status === 'rejected' ? 'bg-red-500/20 text-red-400 border border-red-500/30' :
                        'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                      }`}>
                        {reg.status}
                      </span>
                    </td>

                    <td className="p-4 text-right space-x-2">
                      {reg.status === 'pending' && (
                        <>
                          <button
                            onClick={() => handleApprove(reg._id)}
                            disabled={actionLoading}
                            className="bg-emerald-600/30 hover:bg-emerald-600 text-emerald-300 hover:text-white px-3 py-1.5 rounded-lg font-semibold transition"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => handleReject(reg._id)}
                            disabled={actionLoading}
                            className="bg-red-600/30 hover:bg-red-600 text-red-300 hover:text-white px-3 py-1.5 rounded-lg font-semibold transition"
                          >
                            Reject
                          </button>
                        </>
                      )}

                      {reg.status === 'approved' && (
                        <button
                          onClick={() => setCredentialsModal({
                            name: reg.name,
                            username: reg.generatedUsername || reg.studentId,
                            password: reg.generatedPassword || 'Pass#Updated'
                          })}
                          className="bg-indigo-600/20 hover:bg-indigo-600 text-indigo-300 hover:text-white px-3 py-1.5 rounded-lg font-semibold flex items-center space-x-1 ml-auto"
                        >
                          <Key className="w-3.5 h-3.5" />
                          <span>Credentials</span>
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Generated Pass Credentials Modal */}
      {credentialsModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="glass-panel p-6 rounded-2xl max-w-md w-full border border-indigo-500/40 shadow-2xl space-y-4">
            <div className="flex items-center space-x-3 text-emerald-400">
              <ShieldCheck className="w-6 h-6" />
              <h3 className="font-display font-bold text-lg text-white">Student Transport Pass Generated</h3>
            </div>

            <p className="text-xs text-gray-300">
              Share these mobile app login credentials with student <strong>{credentialsModal.name}</strong>:
            </p>

            <div className="glass-card p-4 rounded-xl space-y-2 text-xs font-mono">
              <div className="flex justify-between">
                <span className="text-gray-400">Username:</span>
                <span className="text-cyan-400 font-bold">{credentialsModal.username}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Password:</span>
                <span className="text-amber-400 font-bold">{credentialsModal.password}</span>
              </div>
            </div>

            <button 
              onClick={() => setCredentialsModal(null)}
              className="w-full bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs py-2.5 rounded-xl transition"
            >
              Done & Close
            </button>
          </div>
        </div>
      )}

    </div>
  );
}
