import React, { useState, useEffect } from 'react';
import { Radio, Send, Bell, ShieldAlert, CheckCircle2, History, MessageSquare } from 'lucide-react';
import { notificationAPI, routeAPI } from '../services/api';

export default function BroadcastSystem() {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [targetGroup, setTargetGroup] = useState('ALL');
  const [routes, setRoutes] = useState([]);
  const [sending, setSending] = useState(false);
  const [history, setHistory] = useState([]);
  const [sentSuccess, setSentSuccess] = useState(false);

  useEffect(() => {
    fetchRoutes();
  }, []);

  const fetchRoutes = async () => {
    try {
      const res = await routeAPI.getAllRoutes();
      setRoutes(res.data?.routes || res.data || [
        { _id: 'r1', name: 'Indrapuri Route 01' },
        { _id: 'r2', name: 'MP Nagar Shuttle' }
      ]);
    } catch (err) {
      console.error('Fetch routes error:', err);
    }
  };

  const handleSendBroadcast = async (e) => {
    e.preventDefault();
    if (!title || !message) return;

    setSending(true);
    try {
      await notificationAPI.sendBroadcast({
        title,
        message,
        targetGroup,
        timestamp: new Date()
      });

      setHistory(prev => [{ title, message, targetGroup, date: new Date() }, ...prev]);
      setTitle('');
      setMessage('');
      setSentSuccess(true);
      setTimeout(() => setSentSuccess(false), 4000);
    } catch (err) {
      console.error('Broadcast failed:', err);
    } finally {
      setSending(false);
    }
  };

  const applyTemplate = (tmplTitle, tmplMsg) => {
    setTitle(tmplTitle);
    setMessage(tmplMsg);
  };

  return (
    <div className="space-y-6 pb-12">
      
      {/* Header */}
      <div className="glass-panel p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-display font-bold text-white">Broadcast & Emergency Dispatcher</h2>
          <p className="text-xs text-gray-400 mt-1">Send push alerts, traffic delay circulars, and announcements directly to student mobile apps</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Left 2 Cols: Notification Creator Form */}
        <div className="lg:col-span-2 glass-panel p-6 rounded-2xl space-y-5 border border-gray-800">
          
          <div className="flex items-center space-x-3 text-cyan-400">
            <Radio className="w-5 h-5" />
            <h3 className="font-display font-bold text-base text-white">Compose Broadcast Message</h3>
          </div>

          {sentSuccess && (
            <div className="p-4 bg-emerald-500/20 border border-emerald-500/40 rounded-xl text-emerald-300 text-xs flex items-center space-x-3 shadow-lg glow-emerald">
              <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
              <span>Broadcast alert dispatched successfully to student & driver mobile apps!</span>
            </div>
          )}

          <form onSubmit={handleSendBroadcast} className="space-y-4 text-xs">
            
            <div>
              <label className="block text-gray-300 font-semibold mb-1.5">Target Audience</label>
              <div className="grid grid-cols-3 gap-3">
                {[
                  { id: 'ALL', label: 'All Students & Staff' },
                  { id: 'DRIVERS', label: 'Bus Drivers Only' },
                  { id: 'DELAYED', label: 'Delayed Routes Only' },
                ].map((tg) => (
                  <button
                    type="button"
                    key={tg.id}
                    onClick={() => setTargetGroup(tg.id)}
                    className={`py-2.5 px-3 rounded-xl font-semibold border transition ${
                      targetGroup === tg.id
                        ? 'bg-indigo-600 border-indigo-400 text-white shadow'
                        : 'bg-gray-900/60 border-gray-800 text-gray-400 hover:text-gray-200'
                    }`}
                  >
                    {tg.label}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-gray-300 font-semibold mb-1.5">Broadcast Title</label>
              <input 
                type="text" 
                value={title} 
                onChange={(e) => setTitle(e.target.value)}
                placeholder="e.g. Bus Route #04 Delay Notice" 
                className="w-full glass-input px-4 py-3 rounded-xl"
                required
              />
            </div>

            <div>
              <label className="block text-gray-300 font-semibold mb-1.5">Announcement Content</label>
              <textarea 
                rows="4"
                value={message} 
                onChange={(e) => setMessage(e.target.value)}
                placeholder="Type your official announcement here..."
                className="w-full glass-input px-4 py-3 rounded-xl"
                required
              />
            </div>

            {/* Quick Templates */}
            <div className="pt-2">
              <p className="text-[11px] text-gray-400 mb-2 font-medium">Quick Announcement Templates:</p>
              <div className="flex flex-wrap gap-2">
                <button 
                  type="button"
                  onClick={() => applyTemplate('Traffic Delay Notice', 'Bus #02 is running 15 minutes behind schedule due to heavy traffic on MP Nagar square.')}
                  className="bg-gray-800/80 hover:bg-gray-700 text-cyan-300 text-[11px] px-3 py-1.5 rounded-lg border border-gray-700"
                >
                  ⚡ Traffic Delay (15 mins)
                </button>
                <button 
                  type="button"
                  onClick={() => applyTemplate('Route Change Alert', 'Bus #05 will take the Bypass road today due to road maintenance near Indrapuri.')}
                  className="bg-gray-800/80 hover:bg-gray-700 text-amber-300 text-[11px] px-3 py-1.5 rounded-lg border border-gray-700"
                >
                  🚧 Route Diversion Notice
                </button>
              </div>
            </div>

            <button 
              type="submit" 
              disabled={sending}
              className="w-full bg-gradient-to-r from-indigo-600 to-cyan-600 hover:from-indigo-500 hover:to-cyan-500 text-white font-semibold text-xs py-3 rounded-xl shadow-lg glow-primary flex items-center justify-center space-x-2 transition"
            >
              <Send className="w-4 h-4" />
              <span>{sending ? 'Dispatching Push Alert...' : 'Broadcast Instant Alert'}</span>
            </button>

          </form>

        </div>

        {/* Right 1 Col: Recent Broadcast History */}
        <div className="glass-panel p-5 rounded-2xl flex flex-col justify-between h-full">
          <div>
            <div className="flex items-center space-x-2 mb-4 text-gray-300">
              <History className="w-4 h-4 text-indigo-400" />
              <h3 className="font-display font-bold text-sm text-white">Broadcast History</h3>
            </div>

            <div className="space-y-3 overflow-y-auto max-h-[400px] pr-1">
              {history.length === 0 ? (
                <div className="text-center py-12 text-gray-500 text-xs">
                  <MessageSquare className="w-8 h-8 text-gray-600 mx-auto mb-2" />
                  <p>No recent broadcasts sent.</p>
                </div>
              ) : (
                history.map((item, idx) => (
                  <div key={idx} className="glass-card p-3 rounded-xl space-y-1">
                    <p className="text-xs font-bold text-white">{item.title}</p>
                    <p className="text-[11px] text-gray-400 line-clamp-2">{item.message}</p>
                    <p className="text-[10px] text-cyan-400 pt-1 font-mono">{new Date(item.date).toLocaleTimeString()}</p>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

      </div>

    </div>
  );
}
