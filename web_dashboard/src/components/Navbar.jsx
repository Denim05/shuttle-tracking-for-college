import React, { useState, useEffect } from 'react';
import { Bus, ShieldAlert, Bell, Search, LogOut, User, Wifi, WifiOff, Clock } from 'lucide-react';

export default function Navbar({ user, onLogout, activeSOS, onClearSOS }) {
  const [time, setTime] = useState(new Date());
  const [isSocketOnline, setIsSocketOnline] = useState(true);

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  return (
    <header className="sticky top-0 z-40 bg-[#0E1524]/90 backdrop-blur-md border-b border-gray-800/80 px-6 py-3 transition-all">
      <div className="flex items-center justify-between">
        
        {/* Left: Brand & Title */}
        <div className="flex items-center space-x-4">
          <div className="flex items-center space-x-3 bg-gradient-to-r from-indigo-600 to-cyan-500 p-2.5 rounded-xl shadow-lg glow-primary">
            <Bus className="w-6 h-6 text-white" />
          </div>
          <div>
            <div className="flex items-center space-x-2">
              <h1 className="font-display font-bold text-xl text-white tracking-wide">
                SISTec<span className="text-cyan-400">Chalo</span>
              </h1>
              <span className="text-xs bg-indigo-500/20 text-indigo-300 font-semibold px-2 py-0.5 rounded-full border border-indigo-500/30">
                PRO DASHBOARD
              </span>
            </div>
            <p className="text-xs text-gray-400 hidden sm:block">Campus Transport Executive Control Center</p>
          </div>
        </div>

        {/* Middle: Active SOS Banner (If Emergency active) */}
        {activeSOS ? (
          <div className="flex items-center space-x-3 bg-red-600/90 text-white px-4 py-2 rounded-xl shadow-lg glow-danger animate-pulse border border-red-400">
            <ShieldAlert className="w-5 h-5 text-white" />
            <div className="text-xs font-semibold">
              <span className="font-bold uppercase tracking-wider">EMERGENCY SOS:</span> Bus {activeSOS.busId || 'Alert'} - {activeSOS.name || 'User'}
            </div>
            <button 
              onClick={onClearSOS} 
              className="text-xs bg-black/30 hover:bg-black/50 px-2 py-1 rounded-md font-mono"
            >
              DISMISS
            </button>
          </div>
        ) : (
          <div className="hidden md:flex items-center bg-gray-900/60 border border-gray-800 rounded-xl px-3.5 py-1.5 w-72 focus-within:border-indigo-500/50 transition">
            <Search className="w-4 h-4 text-gray-400 mr-2" />
            <input 
              type="text" 
              placeholder="Search buses, drivers, routes..." 
              className="bg-transparent text-xs text-gray-200 placeholder-gray-500 outline-none w-full"
            />
          </div>
        )}

        {/* Right: Socket Status, Clock & Profile */}
        <div className="flex items-center space-x-4">
          
          {/* Real-time Socket Indicator */}
          <div className="hidden lg:flex items-center space-x-2 bg-gray-900/80 px-3 py-1.5 rounded-xl border border-gray-800/80 text-xs">
            <div className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse glow-emerald" />
            <span className="text-gray-300 font-medium">LIVE SOCKET</span>
          </div>

          {/* Clock Widget */}
          <div className="hidden sm:flex items-center space-x-2 bg-gray-900/80 px-3 py-1.5 rounded-xl border border-gray-800/80 text-xs text-gray-300">
            <Clock className="w-3.5 h-3.5 text-cyan-400" />
            <span>{time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</span>
          </div>

          {/* User Profile Info & Logout */}
          <div className="flex items-center space-x-3 pl-2 border-l border-gray-800">
            <div className="text-right hidden md:block">
              <p className="text-xs font-semibold text-white">{user?.name || 'Transport Manager'}</p>
              <p className="text-[10px] text-cyan-400 font-mono uppercase">{user?.role || 'MANAGER'}</p>
            </div>
            <button 
              onClick={onLogout}
              title="Logout"
              className="p-2 rounded-xl bg-gray-900 hover:bg-red-500/20 text-gray-400 hover:text-red-400 border border-gray-800 transition"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>

        </div>

      </div>
    </header>
  );
}
