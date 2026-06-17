
import { io, Socket } from 'socket.io-client';
import { create } from 'zustand';

import Constants from 'expo-constants';
import * as SecureStore from 'expo-secure-store';
import { Bus, CAMPUS_CENTER, MOCK_BUSES, MOCK_ROUTES, MOCK_STOPS, Route, Stop } from '../constants/mockData';

// Helper to get dynamic API URL
import { Platform } from 'react-native';

// Helper to get dynamic API URL
const getApiUrl = () => {
    const debuggerHost = Constants.expoConfig?.hostUri;
    const localhost = debuggerHost?.split(':')[0];

    // If using Tunnel (ngrok/expo), debuggerHost might be a domain.
    // Port 5000 is NOT tunneled by default. We must use the LAN IP.
    // DETECTED IP: 172.24.2.86
    const LAN_IP = '172.24.2.86';

    if (!localhost) {
        if (Platform.OS === 'android') {
            return 'http://10.0.2.2:5000';
        }
        return `http://${LAN_IP}:5000`; // Fallback to LAN IP
    }

    // Determine Environment
    if (Platform.OS === 'android' && (localhost === 'localhost' || localhost === '127.0.0.1')) {
        return 'http://10.0.2.2:5000';
    }

    // If localhost looks like a domain (tunnel), return LAN IP
    if (localhost.includes('exp.direct') || localhost.includes('ngrok')) {
        return `http://${LAN_IP}:5000`;
    }

    return `http://${localhost}:5000`;
}

export const API_URL = getApiUrl();


let socket: Socket;

interface AppState {
    userRole: 'user' | 'driver' | 'admin' | 'manager' | null;
    buses: Bus[];
    stops: Stop[];
    routes: Route[];
    selectedRouteId: string | null;
    selectedStopId: string | null;
    // Low Data Mode
    isLowDataMode: boolean;
    socketConnected: boolean;

    // Driver Mode
    isDriverMode: boolean;
    driverBus: Bus | null;
    // User Data
    username: string | null;
    authToken: string | null; // Auth Token
    setUsername: (name: string) => void;

    // Actions
    login: (username: string, password: string, role: string) => Promise<{ success: boolean; error?: string }>;
    logout: () => void;
    setUserRole: (role: 'user' | 'driver' | 'admin' | 'manager') => void;
    setLowDataMode: (enabled: boolean) => void;
    setSelectedRoute: (routeId: string | null) => void;
    setSelectedStop: (stopId: string | null) => void;
    updateBusLocation: (busId: string, lat: number, lng: number) => void;
    fetchInitialData: () => void;

    // Driver Actions
    startDriving: (busNumber: number) => void;
    stopDriving: () => void;
    updateDriverLocation: (lat: number, lng: number, heading: number, speed: number) => void;
}

/**
 * Global application state store using Zustand.
 * Handles user authentication, socket connections, and real-time mapped entities (Buses, Routes).
 */
export const useAppStore = create<AppState>((set, get) => ({
    userRole: null,
    buses: [],
    stops: [],
    routes: [],
    selectedRouteId: null,
    selectedStopId: null,
    isLowDataMode: false,
    socketConnected: false,

    isDriverMode: false,
    driverBus: null,

    username: null,
    authToken: null,
    setUsername: (name) => set({ username: name }),

    /**
     * Authenticates a user against the Node.js backend to retrieve a JWT session token.
     * On success, secure-stores the credentials context.
     *
     * @param {string} username - User identifier.
     * @param {string} password - User secret.
     * @param {string} role - Scope of access ('admin' | 'manager' | 'user').
     * @returns {Promise<{success: boolean, error?: string}>} Authentication result status.
     */
    login: async (username, password, role) => {
        try {
            console.time('LoginFetch');
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 sec timeout

            const response = await fetch(`${getApiUrl()}/api/auth/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, password, role }),
                signal: controller.signal
            });
            clearTimeout(timeoutId);
            console.timeEnd('LoginFetch');

            const data = await response.json();

            if (response.ok) {
                await SecureStore.setItemAsync('authToken', data.token);
                await SecureStore.setItemAsync('userRole', role);

                set({
                    authToken: data.token,
                    userRole: role as any,
                    username: data.user.username
                });

                return { success: true };
            } else {
                return { success: false, error: data.error || 'Login failed' };
            }
        } catch (err: any) {
            console.warn("Network request failed, falling back to mock login:", err.message);

            // Fallback MOCK LOGIN for demo/testing purposes
            // Allow login if username and password are provided
            if (username && password) {
                await SecureStore.setItemAsync('authToken', 'mock-token-123');
                await SecureStore.setItemAsync('userRole', role);

                set({
                    authToken: 'mock-token-123',
                    userRole: role as any,
                    username: username
                });

                return { success: true };
            }

            return { success: false, error: 'Network error' };
        }
    },

    logout: async () => {
        await SecureStore.deleteItemAsync('authToken');
        await SecureStore.deleteItemAsync('userRole');
        set({ authToken: null, userRole: null, username: null, isDriverMode: false, driverBus: null });
    },

    setUserRole: (role) => set({ userRole: role }),
    setLowDataMode: (enabled) => set({ isLowDataMode: enabled }),
    setSelectedRoute: (routeId) => set({ selectedRouteId: routeId }),
    setSelectedStop: (stopId) => set({ selectedStopId: stopId }),

    updateBusLocation: (busId, lat, lng) =>
        set((state) => ({
            buses: state.buses.map((bus) =>
                bus.id === busId ? { ...bus, currentLat: lat, currentLng: lng } : bus
            ),
        })),

    startDriving: (busNumber) => {
        // Generate a consistent color based on bus number
        const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEEAD', '#D4A5A5', '#9B59B6'];
        const busColor = colors[(busNumber - 1) % colors.length];

        const newBus: Bus = {
            id: `bus-${busNumber}`,
            busNumber: `Pvt ${busNumber}`,
            routeId: `route-${busNumber}`, // Placeholder or can be linked to dynamic route later
            routeName: `Bus ${busNumber}`,
            routeColor: busColor,
            currentLat: CAMPUS_CENTER.lat,
            currentLng: CAMPUS_CENTER.lng,
            occupancyLevel: 'Low',
            status: 'On-time',
            heading: 0,
            nextStopId: '',
        };
        set((state) => ({
            isDriverMode: true,
            driverBus: newBus,
            // Remove strictly any existing self from buses to avoid duplication
            buses: state.buses.filter(b => b.id !== `bus-${busNumber}`)
        }));
    },

    stopDriving: () => set((state) => ({
        isDriverMode: false,
        driverBus: null,
        buses: state.buses.filter(b => b.id !== state.driverBus?.id)
    })),

    updateDriverLocation: (lat, lng, heading, speed) => set((state) => {
        const updatedDriverBus = state.driverBus ? { ...state.driverBus, currentLat: lat, currentLng: lng, heading, speed: speed || 0 } : null;

        // Emit to server
        if (socket && state.driverBus) {
            socket.emit('driverLocationUpdate', updatedDriverBus);
        }

        // Do NOT update state.buses with self, as they are kept separate to avoid duplication in UI which typically merges them
        return { driverBus: updatedDriverBus };
    }),

    /* ... inside create<AppState> ... */
    fetchInitialData: async () => {
        // Initialize with Mock Data immediately (Fast Render)
        set({
            routes: MOCK_ROUTES,
            stops: MOCK_STOPS,
            buses: MOCK_BUSES
        });

        try {
            // Attempt to fetch from backend
            const response = await fetch(`${getApiUrl()}/api/guest/routes`);
            const data = await response.json();
            
            if (data.routes && Array.isArray(data.routes)) {
                // Map DB routes to app format
                const mappedRoutes: Route[] = data.routes.map((r: any) => ({
                    id: r._id,
                    name: r.name,
                    color: r.color,
                    coordinates: r.coordinates || []
                }));
                
                // Also fetch buses to show real fleet
                const busResponse = await fetch(`${getApiUrl()}/api/guest/buses`);
                const busesData = await busResponse.json();
                
                const mappedBuses: Bus[] = busesData.map((b: any) => ({
                    id: b._id,
                    busNumber: b.busNumber || 'N/A',
                    routeId: b.routeId,
                    routeName: b.routeName,
                    routeColor: b.routeColor,
                    currentLat: b.currentLat,
                    currentLng: b.currentLng,
                    occupancyLevel: b.occupancy || 'Low',
                    status: b.status || 'On-time',
                    heading: b.heading || 0,
                    nextStopId: '',
                    speed: b.speed
                }));

                // Extract and flatten stops from routes
                const stopsMap: { [key: string]: Stop } = {};
                data.routes.forEach((r: any) => {
                    if (r.stops && Array.isArray(r.stops)) {
                        r.stops.forEach((s: any) => {
                            if (!stopsMap[s.name]) {
                                stopsMap[s.name] = {
                                    id: s._id || `stop-${s.name}`,
                                    name: s.name,
                                    lat: s.lat || 0,
                                    lng: s.lng || 0,
                                    routes: [r.name],
                                    nextArrivals: []
                                };
                            } else {
                                if (!stopsMap[s.name].routes.includes(r.name)) {
                                    stopsMap[s.name].routes.push(r.name);
                                }
                            }
                        });
                    }
                });

                set({ 
                    routes: mappedRoutes,
                    buses: mappedBuses,
                    stops: Object.values(stopsMap)
                });
                console.log(`✅ Loaded ${mappedRoutes.length} real routes and ${Object.keys(stopsMap).length} unique stops from backend.`);
            }

            // Setup Socket.io - SINGLETON CHECK
            if (!socket) {
                socket = io(API_URL);

                socket.on('connect', () => {
                    console.log('Socket Connected:', socket.id);
                    set({ socketConnected: true });
                });

                socket.on('disconnect', () => {
                    console.log('Socket Disconnected');
                    set({ socketConnected: false });
                });

                socket.on('busLocationUpdate', (busData: any) => {
                    set((state) => {
                        const busId = busData._id || busData.id;
                        if (!busId) return state;

                        // Check if bus exists
                        const existingBusIndex = state.buses.findIndex(b => b.id === busId);
                        let newBuses = [...state.buses];

                        const mappedBus: Bus = {
                            id: busId,
                            busNumber: busData.busNumber || 'N/A',
                            routeId: busData.routeId,
                            routeName: busData.routeName,
                            routeColor: busData.routeColor,
                            currentLat: busData.currentLat || busData.latitude,
                            currentLng: busData.currentLng || busData.longitude,
                            occupancyLevel: busData.occupancy || busData.occupancyLevel || 'Low',
                            status: busData.status || 'On-time',
                            heading: busData.heading || 0,
                            nextStopId: busData.nextStopId || '',
                            speed: busData.speed
                        };

                        // If driver mode is active, don't let incoming socket update overwrite our local driver bus representation with standard offline/seeded values
                        if (state.isDriverMode && state.driverBus && busId === state.driverBus.id) {
                            return state;
                        }

                        if (existingBusIndex >= 0) {
                            newBuses[existingBusIndex] = { ...newBuses[existingBusIndex], ...mappedBus };
                        } else {
                            newBuses.push(mappedBus);
                        }

                        return { buses: newBuses };
                    });
                });
            }

        } catch (error: any) {
            console.error('Network request failed, continuing with mock data:', error.message);
            // Already set mock data above
        }
    },
}));
