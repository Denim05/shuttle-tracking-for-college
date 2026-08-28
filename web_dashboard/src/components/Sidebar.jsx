import React from 'react';
import { 
  LayoutDashboard, 
  MapPin, 
  UserCheck, 
  Route as RouteIcon, 
  Users, 
  Radio, 
  BarChart3, 
  ChevronRight,
  ShieldCheck
} from 'lucide-react';
import { motion } from 'framer-motion';

export default function Sidebar({ activeTab, setActiveTab, pendingRegistrationsCount }) {
  const menuItems = [
    { id: 'overview', label: 'Command Overview', icon: LayoutDashboard },
    { id: 'radar', label: 'Live Fleet Radar', icon: MapPin, badge: 'LIVE' },
    { id: 'registrations', label: 'Registrations', icon: UserCheck, count: pendingRegistrationsCount },
    { id: 'routes', label: 'Routes & Stops', icon: RouteIcon },
    { id: 'drivers', label: 'Drivers & Fleet', icon: Users },
    { id: 'broadcast', label: 'Push Broadcast', icon: Radio },
    { id: 'reports', label: 'Reports & Logs', icon: BarChart3 },
  ];

  return (
    <aside className="w-64 bg-[#080C14] border-r border-gray-800/80 min-h-[calc(100vh-4rem)] p-4 flex flex-col justify-between select-none">
      <div className="space-y-6">
        
        {/* Section Header */}
        <div className="px-3 pt-2">
          <p className="text-[10px] font-bold text-gray-500 uppercase tracking-widest">NAVIGATION</p>
        </div>

        {/* Menu Items */}
        <nav className="space-y-1.5 relative">
          {menuItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeTab === item.id;

            return (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id)}
                className={`w-full relative flex items-center justify-between px-3.5 py-3 rounded-xl font-medium text-xs transition-colors z-10 ${
                  isActive
                    ? 'text-cyan-300 font-semibold'
                    : 'text-gray-400 hover:text-gray-200'
                }`}
              >
                {isActive && (
                  <motion.div 
                    layoutId="activeTabPill"
                    className="absolute inset-0 bg-gradient-to-r from-indigo-600/30 to-cyan-500/10 rounded-xl border border-indigo-500/40 shadow-md shadow-indigo-950/40 -z-10"
                    transition={{ type: "spring", stiffness: 400, damping: 30 }}
                  />
                )}

                <div className="flex items-center space-x-3">
                  <Icon className={`w-4 h-4 transition-colors ${isActive ? 'text-cyan-400' : 'text-gray-500'}`} />
                  <span>{item.label}</span>
                </div>

                <div className="flex items-center space-x-2">
                  {item.badge && (
                    <span className="text-[9px] font-extrabold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 px-1.5 py-0.5 rounded-md pulse-badge">
                      {item.badge}
                    </span>
                  )}
                  {item.count > 0 && (
                    <span className="text-[10px] font-bold bg-indigo-600 text-white px-2 py-0.5 rounded-full shadow">
                      {item.count}
                    </span>
                  )}
                  <ChevronRight className={`w-3.5 h-3.5 transition-transform ${isActive ? 'text-cyan-400 rotate-90' : 'text-gray-600 opacity-0 group-hover:opacity-100'}`} />
                </div>
              </button>
            );
          })}
        </nav>

      </div>

      {/* Footer / System Status */}
      <div className="pt-4 border-t border-gray-800/80">
        <div className="glass-card p-3 rounded-xl flex items-center space-x-3 border border-emerald-500/20 bg-emerald-950/10">
          <div className="relative">
            <ShieldCheck className="w-5 h-5 text-emerald-400 flex-shrink-0" />
            <div className="absolute -top-0.5 -right-0.5 w-2 h-2 bg-emerald-400 rounded-full animate-ping" />
          </div>
          <div className="text-[11px]">
            <p className="text-emerald-300 font-bold">Backend Online</p>
            <p className="text-gray-400 text-[10px]">30 Routes Telemetry Active</p>
          </div>
        </div>
      </div>
    </aside>
  );
}

