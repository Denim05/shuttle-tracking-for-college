import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Lock, ShieldAlert, Key, CheckCircle, Eye, EyeOff, AlertTriangle } from 'lucide-react';
import axios from 'axios';

export default function ForcePasswordModal({ user, onPasswordUpdated, onLogout }) {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // Password strength calculation (0 to 3)
  const calculateStrength = (pwd) => {
    let s = 0;
    if (pwd.length >= 6) s++;
    if (/[a-zA-Z]/.test(pwd) && /[0-9]/.test(pwd)) s++;
    if (pwd.length >= 8 && /[^a-zA-Z0-9]/.test(pwd)) s++;
    return s;
  };

  const strength = calculateStrength(newPassword);

  const getStrengthMeta = () => {
    switch (strength) {
      case 1: return { label: 'Weak', color: 'bg-red-500', text: 'text-red-400' };
      case 2: return { label: 'Moderate', color: 'bg-amber-500', text: 'text-amber-400' };
      case 3: return { label: 'Strong & Secure', color: 'bg-emerald-500', text: 'text-emerald-400' };
      default: return { label: 'Too short (min. 6 chars)', color: 'bg-gray-600', text: 'text-gray-400' };
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setSuccess('');

    if (!currentPassword) {
      setError('Please enter your current temporary password.');
      return;
    }

    if (newPassword.length < 6) {
      setError('New password must be at least 6 characters long.');
      return;
    }

    if (newPassword === currentPassword) {
      setError('New password cannot be the same as your temporary password.');
      return;
    }

    if (newPassword !== confirmPassword) {
      setError('New passwords do not match. Please verify.');
      return;
    }

    setLoading(true);

    try {
      const token = localStorage.getItem('sistec_token');
      const res = await axios.post('/api/auth/force-change-password', {
        username: user?.username,
        currentPassword: currentPassword.trim(),
        newPassword: newPassword.trim(),
      }, {
        headers: token ? { Authorization: `Bearer ${token}` } : {}
      });

      if (res.data?.token) {
        localStorage.setItem('sistec_token', res.data.token);
      }
      if (res.data?.user) {
        localStorage.setItem('sistec_user', JSON.stringify(res.data.user));
      }

      setSuccess('Password updated successfully! Activating session...');
      setTimeout(() => {
        onPasswordUpdated(res.data?.user || { ...user, mustChangePassword: false });
      }, 1000);

    } catch (err) {
      setError(err.response?.data?.error || err.message || 'Failed to update password');
    } finally {
      setLoading(false);
    }
  };

  const strengthMeta = getStrengthMeta();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <motion.div
        initial={{ opacity: 0, scale: 0.9, y: 20 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        className="w-full max-w-lg overflow-hidden border shadow-2xl bg-[#0d1322] border-white/10 rounded-3xl"
      >
        {/* Glowing Top Banner */}
        <div className="relative p-6 text-center bg-gradient-to-r from-blue-600/20 via-cyan-500/10 to-indigo-600/20 border-b border-white/10">
          <div className="inline-flex items-center justify-center w-16 h-16 mb-3 border rounded-2xl bg-gradient-to-tr from-blue-600 to-cyan-400 border-white/20 shadow-lg shadow-blue-500/30">
            <Lock className="w-8 h-8 text-white" />
          </div>

          <h2 className="text-2xl font-black tracking-tight text-white font-display">
            Welcome, {user?.name || user?.username}!
          </h2>

          <div className="inline-flex items-center gap-1.5 px-3 py-1 mt-2 text-xs font-black tracking-wider text-amber-300 uppercase rounded-full bg-amber-500/15 border border-amber-500/30">
            <ShieldAlert className="w-3.5 h-3.5" />
            Mandatory First-Time Security Setup
          </div>

          <p className="max-w-sm mx-auto mt-2 text-xs leading-relaxed text-gray-400">
            You are logged in with an initial temporary password. To secure your account, please set a new personal password before accessing the system.
          </p>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 text-xs font-semibold text-red-300 border rounded-xl bg-red-500/10 border-red-500/30">
              <AlertTriangle className="w-4 h-4 text-red-400 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {success && (
            <div className="flex items-center gap-2 p-3 text-xs font-semibold text-emerald-300 border rounded-xl bg-emerald-500/10 border-emerald-500/30">
              <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0" />
              <span>{success}</span>
            </div>
          )}

          {/* Current Password */}
          <div>
            <label className="block mb-1.5 text-xs font-bold tracking-wider text-gray-400 uppercase">
              Current Temporary Password
            </label>
            <div className="relative">
              <Key className="absolute w-4 h-4 text-blue-400 -translate-y-1/2 left-3.5 top-1/2" />
              <input
                type={showCurrent ? 'text' : 'password'}
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                placeholder="Enter password sent to you (e.g. 123456)"
                className="w-full py-2.5 pl-10 pr-10 text-sm text-white placeholder-gray-500 border rounded-xl bg-white/5 border-white/10 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
                required
              />
              <button
                type="button"
                onClick={() => setShowCurrent(!showCurrent)}
                className="absolute text-gray-400 -translate-y-1/2 right-3 top-1/2 hover:text-white"
              >
                {showCurrent ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          {/* New Password */}
          <div>
            <label className="block mb-1.5 text-xs font-bold tracking-wider text-gray-400 uppercase">
              New Personal Password
            </label>
            <div className="relative">
              <Lock className="absolute w-4 h-4 text-cyan-400 -translate-y-1/2 left-3.5 top-1/2" />
              <input
                type={showNew ? 'text' : 'password'}
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Minimum 6 characters"
                className="w-full py-2.5 pl-10 pr-10 text-sm text-white placeholder-gray-500 border rounded-xl bg-white/5 border-white/10 focus:border-cyan-500 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
                required
              />
              <button
                type="button"
                onClick={() => setShowNew(!showNew)}
                className="absolute text-gray-400 -translate-y-1/2 right-3 top-1/2 hover:text-white"
              >
                {showNew ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>

            {/* Password strength meter */}
            {newPassword && (
              <div className="mt-2 space-y-1">
                <div className="flex items-center justify-between text-[11px]">
                  <span className="text-gray-400">Password Strength:</span>
                  <span className={`font-black ${strengthMeta.text}`}>{strengthMeta.label}</span>
                </div>
                <div className="w-full h-1.5 overflow-hidden rounded-full bg-white/10">
                  <div
                    className={`h-full transition-all duration-300 ${strengthMeta.color}`}
                    style={{ width: `${(strength / 3) * 100}%` }}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Confirm Password */}
          <div>
            <label className="block mb-1.5 text-xs font-bold tracking-wider text-gray-400 uppercase">
              Confirm New Password
            </label>
            <div className="relative">
              <CheckCircle className="absolute w-4 h-4 text-emerald-400 -translate-y-1/2 left-3.5 top-1/2" />
              <input
                type={showConfirm ? 'text' : 'password'}
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Re-enter your new password"
                className="w-full py-2.5 pl-10 pr-10 text-sm text-white placeholder-gray-500 border rounded-xl bg-white/5 border-white/10 focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                required
              />
              <button
                type="button"
                onClick={() => setShowConfirm(!showConfirm)}
                className="absolute text-gray-400 -translate-y-1/2 right-3 top-1/2 hover:text-white"
              >
                {showConfirm ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="pt-2">
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 text-sm font-black tracking-wider text-white uppercase transition-all shadow-lg rounded-xl bg-gradient-to-r from-blue-600 to-cyan-500 hover:from-blue-500 hover:to-cyan-400 shadow-blue-500/25 disabled:opacity-50"
            >
              {loading ? 'Updating Password...' : 'Save & Activate Account'}
            </button>
          </div>

          {/* Sign Out */}
          <div className="text-center">
            <button
              type="button"
              onClick={onLogout}
              className="text-xs font-medium text-gray-500 transition-colors hover:text-gray-300"
            >
              Not your account? Sign Out
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}
