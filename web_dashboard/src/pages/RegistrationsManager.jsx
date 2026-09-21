import React, { useState, useEffect } from 'react';
import { 
  UserCheck, UserX, Search, Download, CheckCircle, XCircle, 
  ShieldCheck, Key, RefreshCw, UploadCloud, UserPlus, FileSpreadsheet,
  Trash2, Mail, Phone, MapPin, Eye, Check, AlertCircle
} from 'lucide-react';
import { registrationAPI } from '../services/api';
import BulkRegistrationModal from '../components/BulkRegistrationModal';
import AddStudentModal from '../components/AddStudentModal';

export default function RegistrationsManager() {
  const [registrations, setRegistrations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('pending');
  const [selectedIds, setSelectedIds] = useState([]);
  const [credentialsModal, setCredentialsModal] = useState(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [isBulkModalOpen, setIsBulkModalOpen] = useState(false);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);

  useEffect(() => {
    fetchRegistrations();
  }, []);

  const fetchRegistrations = async () => {
    setLoading(true);
    try {
      const res = await registrationAPI.getAll();
      setRegistrations(res.data?.submissions || res.data || []);
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
      alert('Failed to approve registration.');
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async (id) => {
    const note = prompt('Enter rejection reason for student notification:');
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
    if (!window.confirm(`Approve transport access and generate login credentials for ${selectedIds.length} selected students?`)) return;
    
    setActionLoading(true);
    try {
      await registrationAPI.bulkApprove(selectedIds);
      setSelectedIds([]);
      fetchRegistrations();
      alert(`Successfully approved ${selectedIds.length} student registrations!`);
    } catch (err) {
      console.error('Bulk approval failed:', err);
      alert('Bulk approval failed.');
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
    const headers = ["Student Name", "Student ID / Roll No", "Phone", "Route Name", "Pickup Stop", "Course", "Status", "Generated Username", "Password"];
    const rows = filteredData.map(r => [
      `"${r.name}"`,
      `"${r.studentId}"`,
      `"${r.phone}"`,
      `"${r.routeName || ''}"`,
      `"${r.pickupStop || ''}"`,
      `"${r.courseName || ''}"`,
      `"${r.status}"`,
      `"${r.generatedUsername || ''}"`,
      `"${r.generatedPassword || ''}"`
    ]);

    const csvContent = "data:text/csv;charset=utf-8," + [headers.join(","), ...rows.map(e => e.join(","))].join("\n");
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `sistecchalo_registrations_${filterStatus}_${new Date().toISOString().slice(0,10)}.csv`);
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
      
      {/* Top Header & Actions */}
      <div className="glass-panel p-6 rounded-3xl flex flex-col lg:flex-row lg:items-center justify-between gap-4 border border-gray-800/80 shadow-2xl">
        <div>
          <div className="flex items-center space-x-2.5">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
            <h2 className="text-2xl font-display font-bold text-white tracking-tight">Student Registrations & Passes</h2>
          </div>
          <p className="text-xs text-gray-400 mt-1">
            Import Excel/CSV spreadsheets, approve student bus passes, and auto-dispatch login credentials
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          
          {/* Add Single Student */}
          <button 
            onClick={() => setIsAddModalOpen(true)}
            className="bg-gray-800 hover:bg-gray-700 text-white border border-gray-700 px-4 py-2.5 rounded-2xl text-xs font-semibold flex items-center space-x-2 shadow-lg transition active:scale-95"
          >
            <UserPlus className="w-4 h-4 text-emerald-400" />
            <span>+ Add Single Student</span>
          </button>

          {/* Bulk Import by Excel / CSV / JSON */}
          <button 
            onClick={() => setIsBulkModalOpen(true)}
            className="bg-indigo-600 hover:bg-indigo-500 text-white px-5 py-2.5 rounded-2xl text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition active:scale-95"
          >
            <FileSpreadsheet className="w-4 h-4 text-white" />
            <span>📁 Import Excel / CSV File</span>
          </button>

          {/* Bulk Approve (if items selected) */}
          {selectedIds.length > 0 && (
            <button 
              onClick={handleBulkApprove}
              disabled={actionLoading}
              className="bg-emerald-600 hover:bg-emerald-500 text-white px-4 py-2.5 rounded-2xl text-xs font-semibold shadow-lg glow-emerald flex items-center space-x-2 transition"
            >
              <CheckCircle className="w-4 h-4" />
              <span>Approve Selected ({selectedIds.length})</span>
            </button>
          )}

          {/* Export CSV */}
          <button 
            onClick={exportCSV}
            className="bg-gray-900/80 hover:bg-gray-800 text-gray-300 border border-gray-800 px-4 py-2.5 rounded-2xl text-xs font-semibold flex items-center space-x-2 transition"
          >
            <Download className="w-4 h-4 text-cyan-400" />
            <span>Export Sheet</span>
          </button>
        </div>
      </div>

      {/* Filter & Search Bar */}
      <div className="glass-panel p-4 rounded-2xl flex flex-col sm:flex-row items-center justify-between gap-4 border border-gray-800">
        
        {/* Search */}
        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-gray-400 absolute left-3.5 top-3" />
          <input 
            type="text" 
            value={search} 
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search student name, roll no, route, stop..."
            className="w-full glass-input pl-10 pr-3 py-2 rounded-xl text-xs"
          />
        </div>

        {/* Status Tabs */}
        <div className="flex items-center space-x-2 text-xs w-full sm:w-auto overflow-x-auto pb-1 sm:pb-0">
          {['pending', 'approved', 'rejected', 'ALL'].map((st) => (
            <button
              key={st}
              onClick={() => setFilterStatus(st)}
              className={`px-4 py-2 rounded-xl font-semibold capitalize whitespace-nowrap transition ${
                filterStatus === st 
                  ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30' 
                  : 'bg-gray-900/60 text-gray-400 hover:text-gray-200 border border-gray-800'
              }`}
            >
              {st} ({registrations.filter(r => st === 'ALL' ? true : r.status === st).length})
            </button>
          ))}
        </div>

      </div>

      {/* Main Table */}
      <div className="glass-panel rounded-3xl overflow-hidden border border-gray-800 shadow-2xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-gray-900/90 text-gray-400 font-semibold border-b border-gray-800 uppercase tracking-wider text-[10px]">
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
              {loading ? (
                <tr>
                  <td colSpan="7" className="p-10 text-center text-gray-400">
                    <RefreshCw className="w-6 h-6 animate-spin mx-auto text-indigo-400 mb-2" />
                    <span>Loading student registrations...</span>
                  </td>
                </tr>
              ) : filteredData.length === 0 ? (
                <tr>
                  <td colSpan="7" className="p-12 text-center text-gray-500 space-y-3">
                    <FileSpreadsheet className="w-10 h-10 mx-auto text-gray-600 mb-2" />
                    <p className="text-sm font-semibold text-gray-400">No registrations found.</p>
                    <p className="text-xs text-gray-500">Click "Import Excel / CSV File" above to bulk register students from your college files.</p>
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
                      <p className="text-[11px] text-cyan-400 flex items-center space-x-1 mt-0.5">
                        <MapPin className="w-3 h-3" />
                        <span>{reg.pickupStop || 'Assigned Stop'}</span>
                      </p>
                    </td>

                    <td className="p-4 text-gray-300">
                      <p className="font-mono text-[11px] flex items-center space-x-1">
                        <Phone className="w-3 h-3 text-gray-500" />
                        <span>{reg.phone}</span>
                      </p>
                      {reg.email && (
                        <p className="text-[10px] text-gray-400 flex items-center space-x-1 mt-0.5">
                          <Mail className="w-3 h-3 text-gray-500" />
                          <span>{reg.email}</span>
                        </p>
                      )}
                    </td>

                    <td className="p-4 text-gray-400">
                      <span className="px-2.5 py-1 rounded-lg bg-gray-800/60 border border-gray-700/60 text-[11px] text-gray-300">
                        {reg.courseName || 'Student'}
                      </span>
                    </td>

                    <td className="p-4">
                      {reg.status === 'approved' && (
                        <span className="px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[11px] font-semibold flex items-center space-x-1 w-max">
                          <CheckCircle className="w-3 h-3" />
                          <span>Approved & Active</span>
                        </span>
                      )}
                      {reg.status === 'pending' && (
                        <span className="px-2.5 py-1 rounded-lg bg-amber-500/10 border border-amber-500/20 text-amber-400 text-[11px] font-semibold flex items-center space-x-1 w-max">
                          <RefreshCw className="w-3 h-3" />
                          <span>Pending Review</span>
                        </span>
                      )}
                      {reg.status === 'rejected' && (
                        <span className="px-2.5 py-1 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-400 text-[11px] font-semibold flex items-center space-x-1 w-max">
                          <XCircle className="w-3 h-3" />
                          <span>Rejected</span>
                        </span>
                      )}
                    </td>

                    <td className="p-4 text-right">
                      {reg.status === 'pending' && (
                        <div className="flex items-center justify-end space-x-2">
                          <button
                            onClick={() => handleApprove(reg._id)}
                            disabled={actionLoading}
                            className="p-1.5 rounded-xl bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/30 text-emerald-400 hover:text-emerald-300 transition"
                            title="Approve & Generate Credentials"
                          >
                            <Check className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => handleReject(reg._id)}
                            disabled={actionLoading}
                            className="p-1.5 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 text-rose-400 hover:text-rose-300 transition"
                            title="Reject Application"
                          >
                            <XCircle className="w-4 h-4" />
                          </button>
                        </div>
                      )}

                      {reg.status === 'approved' && (
                        <button
                          onClick={() => setCredentialsModal({
                            name: reg.name,
                            username: reg.generatedUsername || reg.studentId,
                            password: reg.generatedPassword || 'Pass#' + reg.studentId.slice(-4)
                          })}
                          className="px-3 py-1 rounded-xl bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/30 text-indigo-400 text-[11px] font-semibold flex items-center space-x-1 ml-auto transition"
                        >
                          <Key className="w-3 h-3" />
                          <span>View Credentials</span>
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

      {/* Credentials Modal */}
      {credentialsModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
          <div className="w-full max-w-md bg-[#0B1120] border border-gray-800 rounded-3xl p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between border-b border-gray-800/80 pb-4">
              <div className="flex items-center space-x-2">
                <ShieldCheck className="w-5 h-5 text-emerald-400" />
                <h4 className="font-bold text-white text-base font-display">Student Pass Credentials</h4>
              </div>
              <button 
                onClick={() => setCredentialsModal(null)}
                className="text-gray-400 hover:text-white"
              >
                ✕
              </button>
            </div>

            <p className="text-xs text-gray-300">
              Student account details for <strong className="text-white">{credentialsModal.name}</strong>:
            </p>

            <div className="glass-panel p-4 rounded-2xl border border-indigo-500/30 space-y-2.5 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Username / Roll No:</span>
                <span className="font-mono font-bold text-indigo-400">{credentialsModal.username}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-400">Initial Password:</span>
                <span className="font-mono font-bold text-emerald-400 bg-emerald-950/40 px-2 py-0.5 rounded border border-emerald-500/30">
                  {credentialsModal.password}
                </span>
              </div>
            </div>

            <button
              onClick={() => setCredentialsModal(null)}
              className="w-full py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-lg glow-primary transition"
            >
              Close
            </button>
          </div>
        </div>
      )}

      {/* Bulk Registration File Upload Modal */}
      <BulkRegistrationModal 
        isOpen={isBulkModalOpen}
        onClose={() => setIsBulkModalOpen(false)}
        onSuccess={() => {
          fetchRegistrations();
        }}
      />

      {/* Single Student Registration Modal */}
      <AddStudentModal 
        isOpen={isAddModalOpen}
        onClose={() => setIsAddModalOpen(false)}
        onSuccess={() => {
          fetchRegistrations();
        }}
      />

    </div>
  );
}
