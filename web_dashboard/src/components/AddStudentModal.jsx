import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { UserPlus, X, CheckCircle, RefreshCw, Key, ShieldCheck, Mail, Phone, MapPin, Bus, User, BookOpen } from 'lucide-react';
import { routeAPI, registrationAPI } from '../services/api';

export default function AddStudentModal({ isOpen, onClose, onSuccess }) {
  const [formData, setFormData] = useState({
    name: '',
    studentId: '',
    phone: '',
    email: '',
    routeId: '',
    routeName: '',
    pickupStop: '',
    courseName: 'B.Tech CSE',
    fatherName: '',
    fatherPhone: '',
    gender: 'Male',
    autoApprove: true
  });

  const [routes, setRoutes] = useState([]);
  const [availableStops, setAvailableStops] = useState([]);
  const [loadingRoutes, setLoadingRoutes] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [createdCredentials, setCreatedCredentials] = useState(null);

  useEffect(() => {
    if (isOpen) {
      fetchRoutes();
      setCreatedCredentials(null);
    }
  }, [isOpen]);

  const fetchRoutes = async () => {
    setLoadingRoutes(true);
    try {
      const res = await routeAPI.getAllRoutes();
      const fetchedRoutes = res.data?.routes || res.data || [];
      setRoutes(fetchedRoutes);
      if (fetchedRoutes.length > 0) {
        setFormData(prev => ({
          ...prev,
          routeId: fetchedRoutes[0]._id,
          routeName: fetchedRoutes[0].name,
          pickupStop: fetchedRoutes[0].stops?.[0]?.name || 'Main Gate'
        }));
        setAvailableStops(fetchedRoutes[0].stops || []);
      }
    } catch (err) {
      console.error('Failed to load routes:', err);
    } finally {
      setLoadingRoutes(false);
    }
  };

  const handleRouteChange = (routeId) => {
    const selected = routes.find(r => r._id === routeId);
    if (selected) {
      setFormData(prev => ({
        ...prev,
        routeId: selected._id,
        routeName: selected.name,
        pickupStop: selected.stops?.[0]?.name || ''
      }));
      setAvailableStops(selected.stops || []);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.name || !formData.studentId || !formData.phone || !formData.pickupStop) {
      alert('Please fill in Student Name, Roll Number, Phone, and Pickup Stop.');
      return;
    }

    setSubmitting(true);
    try {
      const res = await registrationAPI.bulkUpload([{
        name: formData.name,
        studentId: formData.studentId,
        phone: formData.phone,
        email: formData.email,
        routeId: formData.routeId,
        routeName: formData.routeName,
        pickupStop: formData.pickupStop,
        courseName: formData.courseName,
        fatherName: formData.fatherName,
        fatherPhone: formData.fatherPhone,
        gender: formData.gender
      }]);

      if (res.data?.success) {
        // If auto-approved, fetch the pending item and approve it
        if (formData.autoApprove) {
          try {
            const allSubs = await registrationAPI.getAll();
            const list = allSubs.data?.submissions || allSubs.data || [];
            const matching = list.find(s => s.studentId === formData.studentId.trim());
            if (matching) {
              const approveRes = await registrationAPI.approve(matching._id);
              const updated = approveRes.data?.submission;
              if (updated) {
                setCreatedCredentials({
                  name: updated.name,
                  username: updated.generatedUsername || updated.studentId,
                  password: updated.generatedPassword || 'Pass#' + updated.studentId.slice(-4)
                });
              }
            }
          } catch (_) {}
        }

        if (!formData.autoApprove) {
          alert('Student application successfully submitted to pending list!');
          onClose();
        }
        if (onSuccess) onSuccess();
      }
    } catch (err) {
      console.error('Registration failed:', err);
      alert(err.response?.data?.error || 'Registration failed. Check if student ID already exists.');
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <motion.div 
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.96 }}
        className="w-full max-w-2xl bg-[#0B1120] border border-gray-800 rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
      >
        {/* Header */}
        <div className="p-6 border-b border-gray-800/80 flex items-center justify-between bg-gray-900/40">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
              <UserPlus className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white font-display">New Student Transport Registration</h3>
              <p className="text-xs text-gray-400">Register and generate bus transit credentials for an individual student</p>
            </div>
          </div>

          <button 
            onClick={onClose}
            className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-gray-800/60 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6 overflow-y-auto flex-1">
          {createdCredentials ? (
            <div className="text-center py-6 space-y-4">
              <div className="w-16 h-16 rounded-full bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center text-emerald-400 mx-auto glow-emerald">
                <ShieldCheck className="w-8 h-8" />
              </div>

              <h4 className="text-xl font-bold text-white font-display">Student Pass Activated!</h4>
              <p className="text-xs text-gray-400 max-w-sm mx-auto">
                Account created and transport pass credentials issued for <strong className="text-white">{createdCredentials.name}</strong>.
              </p>

              <div className="glass-panel p-5 rounded-2xl border border-indigo-500/30 max-w-md mx-auto text-left space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-gray-400">Username / Roll No:</span>
                  <span className="text-sm font-mono font-bold text-indigo-400">{createdCredentials.username}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-gray-400">Initial Password:</span>
                  <span className="text-sm font-mono font-bold text-emerald-400 bg-emerald-950/40 px-2 py-0.5 rounded border border-emerald-500/30">{createdCredentials.password}</span>
                </div>
              </div>

              <div className="pt-4 flex justify-center">
                <button
                  onClick={onClose}
                  className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-lg glow-primary transition"
                >
                  Done
                </button>
              </div>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4 text-xs">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                
                {/* Full Name */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <User className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Student Full Name *</span>
                  </label>
                  <input 
                    type="text" 
                    required
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    placeholder="e.g. Rahul Sharma"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                  />
                </div>

                {/* Roll Number / Student ID */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <Key className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Roll Number / Student ID *</span>
                  </label>
                  <input 
                    type="text" 
                    required
                    value={formData.studentId}
                    onChange={(e) => setFormData({ ...formData, studentId: e.target.value })}
                    placeholder="e.g. 0192CS221045"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs uppercase"
                  />
                </div>

                {/* Phone */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <Phone className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Student Mobile Number *</span>
                  </label>
                  <input 
                    type="tel" 
                    required
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    placeholder="e.g. 9826012345"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                  />
                </div>

                {/* Email */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <Mail className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Student Email</span>
                  </label>
                  <input 
                    type="email" 
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    placeholder="e.g. student@sistec.ac.in"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                  />
                </div>

                {/* Route Selection */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <Bus className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Assigned Bus Route</span>
                  </label>
                  <select 
                    value={formData.routeId}
                    onChange={(e) => handleRouteChange(e.target.value)}
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs bg-gray-900 border-gray-700 text-gray-200"
                  >
                    {routes.map(r => (
                      <option key={r._id} value={r._id}>{r.name}</option>
                    ))}
                  </select>
                </div>

                {/* Pickup Stop */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <MapPin className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Pickup Stop / Point *</span>
                  </label>
                  {availableStops.length > 0 ? (
                    <select 
                      value={formData.pickupStop}
                      onChange={(e) => setFormData({ ...formData, pickupStop: e.target.value })}
                      className="w-full glass-input px-3 py-2 rounded-xl text-xs bg-gray-900 border-gray-700 text-gray-200"
                    >
                      {availableStops.map((stop, idx) => (
                        <option key={idx} value={stop.name || stop}>{stop.name || stop}</option>
                      ))}
                    </select>
                  ) : (
                    <input 
                      type="text"
                      required
                      value={formData.pickupStop}
                      onChange={(e) => setFormData({ ...formData, pickupStop: e.target.value })}
                      placeholder="e.g. Board Office Square"
                      className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                    />
                  )}
                </div>

                {/* Course */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300 flex items-center space-x-1.5">
                    <BookOpen className="w-3.5 h-3.5 text-indigo-400" />
                    <span>Course / Branch</span>
                  </label>
                  <input 
                    type="text" 
                    value={formData.courseName}
                    onChange={(e) => setFormData({ ...formData, courseName: e.target.value })}
                    placeholder="e.g. B.Tech CSE (4th Sem)"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                  />
                </div>

                {/* Father's Name */}
                <div className="space-y-1.5">
                  <label className="font-semibold text-gray-300">Father's / Guardian Name</label>
                  <input 
                    type="text" 
                    value={formData.fatherName}
                    onChange={(e) => setFormData({ ...formData, fatherName: e.target.value })}
                    placeholder="e.g. Rajesh Sharma"
                    className="w-full glass-input px-3 py-2 rounded-xl text-xs"
                  />
                </div>

              </div>

              {/* Auto-Approve Option */}
              <div className="pt-3 border-t border-gray-800/60 flex items-center justify-between">
                <label className="flex items-center space-x-2 cursor-pointer">
                  <input 
                    type="checkbox"
                    checked={formData.autoApprove}
                    onChange={(e) => setFormData({ ...formData, autoApprove: e.target.checked })}
                    className="rounded bg-gray-800 border-gray-700 text-indigo-600 focus:ring-0"
                  />
                  <span className="text-gray-300 font-semibold">Auto-Approve and Generate Login Pass Credentials Immediately</span>
                </label>
              </div>

              <div className="pt-4 flex items-center justify-end space-x-3">
                <button
                  type="button"
                  onClick={onClose}
                  className="px-4 py-2 rounded-xl bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-semibold transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-6 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white text-xs font-semibold shadow-lg glow-emerald flex items-center space-x-2 transition"
                >
                  {submitting ? (
                    <>
                      <RefreshCw className="w-4 h-4 animate-spin" />
                      <span>Registering...</span>
                    </>
                  ) : (
                    <>
                      <CheckCircle className="w-4 h-4" />
                      <span>Create Registration</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          )}
        </div>
      </motion.div>
    </div>
  );
}
