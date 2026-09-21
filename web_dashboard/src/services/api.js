import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'https://smart-shuttle-backend-2h13.onrender.com';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Interceptor to attach JWT token
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('sistec_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
}, (error) => {
  return Promise.reject(error);
});

// API Helper Functions
export const authAPI = {
  login: (credentials) => api.post('/api/auth/login', credentials),
  getProfile: () => api.get('/api/users/me'),
};

export const fleetAPI = {
  getAllBuses: () => api.get('/api/buses'),
  createBus: (data) => api.post('/api/manager/buses', data),
  updateBus: (id, data) => api.put(`/api/manager/buses/${id}`, data),
  patchBus: (id, data) => api.patch(`/api/manager/buses/${id}`, data),
  deleteBus: (id) => api.delete(`/api/manager/buses/${id}`),
};

export const routeAPI = {
  getAllRoutes: () => api.get('/api/routes'),
  createRoute: (data) => api.post('/api/manager/routes', data),
  updateRoute: (id, data) => api.put(`/api/manager/routes/${id}`, data),
  deleteRoute: (id) => api.delete(`/api/manager/routes/${id}`),
  geocodeStop: (name) => api.get(`/api/routes/geocode-stop?name=${encodeURIComponent(name)}`),
};

export const driverAPI = {
  getAllDrivers: () => api.get('/api/manager/drivers'),
  createDriver: (data) => api.post('/api/manager/drivers', data),
  updateDriver: (id, data) => api.put(`/api/manager/drivers/${id}`, data),
  deleteDriver: (id) => api.delete(`/api/manager/drivers/${id}`),
  uploadDocument: (id, formData) => api.post(`/api/manager/drivers/${id}/documents`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' }
  }),
};

export const registrationAPI = {
  getAll: () => api.get('/api/manager/registrations'),
  approve: (id) => api.put(`/api/manager/registrations/${id}/approve`),
  unapprove: (id) => api.put(`/api/manager/registrations/${id}/unapprove`),
  reject: (id, note) => api.put(`/api/manager/registrations/${id}/reject`, { note }),
  bulkApprove: (submissionIds) => api.post('/api/manager/registrations/bulk-approve', { submissionIds }),
  bulkUpload: (submissions) => api.post('/api/manager/registrations/bulk', { submissions }),
  createSingle: (data) => api.post('/api/users', data),
};

export const notificationAPI = {
  sendBroadcast: (data) => api.post('/api/manager/notifications', data),
  getAll: () => api.get('/api/notifications'),
  delete: (id) => api.delete(`/api/manager/notifications/${id}`),
};

export const reportAPI = {
  getBusTripReport: (busId, days = 7) => api.get(`/api/manager/reports/bus-trip-report?busId=${busId}&days=${days}`),
  getBusSummary: (busId) => api.get(`/api/manager/reports/bus/${busId}/summary`),
};

export const fuelAPI = {
  getFuelLogs: () => api.get('/api/manager/fuel-logs'),
  getFuelAnalytics: () => api.get('/api/manager/fuel-analytics'),
  logFuelRefill: (data) => api.post('/api/driver/fuel-log', data),
};

export default api;
