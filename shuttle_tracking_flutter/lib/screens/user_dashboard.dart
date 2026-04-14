import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../components/bus_map.dart';
import '../components/linear_tracking_view.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';
import '../services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final ApiService _apiService = ApiService();
  RouteModel? _selectedRoute;
  Bus? _activeBus;
  List<RouteModel> _routes = [];
  final Map<String, Bus> _buses = {}; 
  bool _showLinearView = false;
  bool _isLoading = true;
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _alertHistory = [];
  bool _isSosActive = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _initSocket();
  }

  Future<void> _fetchData() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final endpoint = auth.isGuest ? 'guest/routes' : 'routes';
    try {
      final List<dynamic> data = await _apiService.get(endpoint);
      setState(() {
        _routes = data.map((r) => RouteModel.fromJson(r)).toList();
        _isLoading = false;
        
        // Auto-select route if user has one assigned
        if (auth.currentUser?.routeId != null) {
          _selectedRoute = _routes.firstWhere(
            (r) => r.id == auth.currentUser!.routeId,
            orElse: () => _routes.first,
          );
        }
      });
      
      final busEndpoint = auth.isGuest ? 'guest/buses' : 'buses';
      final List<dynamic> busData = await _apiService.get(busEndpoint);
      setState(() {
        for (var b in busData) {
          final bus = Bus.fromJson(b);
          _buses[bus.id] = bus;
          
          if (_selectedRoute != null && bus.routeId == _selectedRoute!.id) {
            _activeBus = bus;
          }
        }
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.initSocket();
    socketService.listenToBusUpdates((data) {
      if (mounted) {
        setState(() {
          final updatedBus = Bus.fromJson(data);
          _buses[updatedBus.id] = updatedBus;
          if (_selectedRoute != null && updatedBus.routeId == _selectedRoute!.id) {
            _activeBus = updatedBus;
          }
        });
      }
    });
    
    socketService.listenToBusApproach((data) {
      if (mounted) {
        final currentUser = auth.currentUser;
        if (currentUser != null && currentUser.routeId == data['routeId'] && currentUser.pickupPoint == data['stopName']) {
          final distance = (data['distanceKm'] as num).toStringAsFixed(2);
          final mins = data['minutes'];
          
          // Refresh alerts if on alert tab
          if (_currentIndex == 1) {
            _fetchAlerts();
          }

          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                   Container(
                     padding: const EdgeInsets.all(8),
                     decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                     child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       mainAxisSize: MainAxisSize.min,
                       children: [
                          Text('Bus Approaching!', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                          Text('Arriving at ${data['stopName']} in $mins min ($distance km away)', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11)),
                       ],
                     ),
                   ),
                ],
              ),
              action: SnackBarAction(
                label: 'TRACK',
                textColor: const Color(0xFF38ef7d),
                onPressed: () {
                  setState(() => _currentIndex = 0);
                },
              ),
              backgroundColor: const Color(0xFF1A4CFF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
              duration: const Duration(seconds: 8),
            )
          );
        }
      }
    });
  }

  void _showRouteSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 48), // spacer for balance
                      Text('SELECT YOUR ROUTE', style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white24),
                        onPressed: _fetchData,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _routes.isEmpty 
                    ? _buildEmptyState('No active routes found', Icons.map_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _routes.length,
                        itemBuilder: (context, index) {
                          final route = _routes[index];
                          final color = Color(int.parse(route.color.replaceAll('#', '0xFF')));
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: color.withValues(alpha: 0.2)),
                            ),
                            child: ListTile(
                              onTap: () {
                                setState(() {
                                  _selectedRoute = route;
                                  _activeBus = _buses.values.firstWhere(
                                    (b) => b.routeId == route.id, 
                                    orElse: () => _buses.values.isNotEmpty ? _buses.values.first : Bus(
                                      id: '', 
                                      routeId: '', 
                                      routeName: '', 
                                      routeColor: '#000000', 
                                      currentLat: 0, 
                                      currentLng: 0, 
                                      heading: 0, 
                                      speed: 0, 
                                      status: 'Offline', 
                                      lastUpdated: DateTime.now()
                                    )
                                  );
                                  if (_activeBus?.id == '') _activeBus = null;
                                });
                                Navigator.pop(context);
                              },
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: Icon(Icons.directions_bus_filled_rounded, color: color, size: 24),
                              ),
                              title: Text(route.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                              subtitle: Text('${route.stops.length} STOPS • LIVE NOW', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500)),
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                                child: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                              ),
                            ),
                          ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1);
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _buildAppBar(auth),
      body: _buildBody(auth),
      floatingActionButton: _currentIndex == 0 ? _buildSOSButton(auth) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar(AuthService auth) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withValues(alpha: 0.2),
          ),
        ),
      ),
      title: Text(
        _currentIndex == 0 ? 'LIVE TRACKER' : (_currentIndex == 1 ? 'ALERTS' : 'PROFILE'),
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.5,
          fontSize: 18,
        ),
      ),
      actions: [
        if (_currentIndex == 0 && _selectedRoute != null)
          IconButton(
            icon: Icon(_showLinearView ? Icons.map_outlined : Icons.alt_route_rounded, color: Colors.white),
            onPressed: () => setState(() => _showLinearView = !_showLinearView),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () => auth.logout(),
          ),
        )
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 25),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            elevation: 0,
            backgroundColor: Colors.transparent,
            selectedItemColor: const Color(0xFF38ef7d),
            unselectedItemColor: Colors.white24,
            showSelectedLabels: true,
            showUnselectedLabels: false,
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Track'),
              BottomNavigationBarItem(icon: Icon(Icons.notifications_active_rounded), label: 'Alerts'),
              BottomNavigationBarItem(icon: Icon(Icons.person_pin_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutCubic);
  }

  Future<void> _triggerSOS(AuthService auth) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      Position? position;
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      }

      final socketService = Provider.of<SocketService>(context, listen: false);
      final user = auth.currentUser;
      
      final payload = {
        'userId': user?.id ?? 'guest',
        'name': user?.username ?? 'Guest User',
        'role': user?.role ?? 'user',
        'latitude': position?.latitude ?? 0.0,
        'longitude': position?.longitude ?? 0.0,
        'timestamp': DateTime.now().toIso8601String(),
        'routeId': _selectedRoute?.id,
        'routeName': _selectedRoute?.name,
      };

      socketService.emitSOSAlert(payload);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS EMERGENCY REPORTED!', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
          )
        );
      }
    } catch (e) {
      debugPrint('SOS Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSosActive = false);
      }
    }
  }

  Widget _buildSOSButton(AuthService auth) {
    return GestureDetector(
      onLongPress: () => _triggerSOS(auth),
      child: Container(
        margin: const EdgeInsets.only(bottom: 90), // clear bottom nav
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent,
          boxShadow: [
            BoxShadow(color: Colors.redAccent.withValues(alpha: 0.6), blurRadius: 20, spreadRadius: 5),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
        ),
        child: _isSosActive 
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                  Text('HOLD 2s', style: GoogleFonts.outfit(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.05, 1.05), duration: 1.seconds);
  }

  Widget _buildBody(AuthService auth) {
    switch (_currentIndex) {
      case 1: return _buildAlertHistory();
      case 2: return _buildProfile(auth);
      default: return _buildTrackingView();
    }
  }

  Widget _buildTrackingView() {
    return Stack(
      children: [
        // Map Engine
        _showLinearView && _activeBus != null && _selectedRoute != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: LinearTrackingView(bus: _activeBus!, route: _selectedRoute!),
                ),
              )
            : BusMap(
                buses: _buses.values.where((b) => _selectedRoute == null || b.routeId == _selectedRoute!.id).toList(),
                selectedRoute: _selectedRoute,
              ),

        // Dynamic Island Status Pill
        Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF38ef7d), shape: BoxShape.circle),
                  ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(1,1), end: const Offset(1.5,1.5), duration: 1000.ms).fadeOut(),
                  const SizedBox(width: 8),
                  Text(
                    'SISTec LIVE • SYSTEM ONLINE',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn().slideY(begin: -0.5, end: 0),
        ),

        // Route Selection / Active Route Card
        Positioned(
          bottom: 120,
          left: 20,
          right: 20,
          child: _selectedRoute == null ? _buildSelectRouteButton() : _buildActiveRouteCard(),
        ),
      ],
    );
  }

  Widget _buildSelectRouteButton() {
    return GestureDetector(
      onTap: _showRouteSelection,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF38ef7d).withValues(alpha: 0.2), const Color(0xFF11998e).withValues(alpha: 0.2)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: const Color(0xFF38ef7d).withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.map_rounded, color: Color(0xFF38ef7d)),
                const SizedBox(width: 15),
                Text('SELECT ROUTE TO TRACK', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ],
            ),
          ),
        ),
      ),
    ).animate().scale(delay: 200.ms);
  }

  Widget _buildActiveRouteCard() {
    final routeColor = Color(int.parse(_selectedRoute!.color.replaceAll('#', '0xFF')));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: routeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: routeColor.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(Icons.directions_bus_filled_rounded, color: routeColor, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedRoute!.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('Tracking Active...', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white38), onPressed: () => setState(() => _selectedRoute = null)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric('STOPS', '${_selectedRoute!.stops.length}'),
              _buildMetric('STATUS', _activeBus != null ? 'LIVE' : 'WAITING', color: _activeBus != null ? Colors.green : Colors.orange),
              _buildMetric('SEATS', _activeBus?.occupancy ?? 'N/A'),
            ],
          )
        ],
      ),
    ).animate().slideY(begin: 0.5, end: 0);
  }

  Widget _buildMetric(String label, String value, {Color color = Colors.white70}) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value, style: GoogleFonts.outfit(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAlertHistory() {
    return _isLoading 
      ? _buildLoadingState()
      : RefreshIndicator(
          onRefresh: _fetchAlerts,
          backgroundColor: const Color(0xFF0F172A),
          color: const Color(0xFF1A4CFF),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 120, 24, 120),
            itemCount: _alertHistory.isEmpty ? 1 : _alertHistory.length,
            itemBuilder: (context, index) {
              if (_alertHistory.isEmpty) {
                return _buildEmptyState('No recent alerts', Icons.notifications_none_rounded);
              }
              final alert = _alertHistory[index];
              return _buildAlertCard(alert, index);
            },
          ),
        );
  }

  Future<void> _fetchAlerts() async {
    try {
      final List<dynamic> data = await _apiService.get('notifications');
      setState(() {
        _alertHistory.clear();
        _alertHistory.addAll(data.cast<Map<String, dynamic>>());
      });
    } catch (e) {
      debugPrint('Error fetching alerts: $e');
    }
  }

  Widget _buildAlertCard(Map<String, dynamic> alert, int index) {
    final DateTime date = DateTime.parse(alert['createdAt'] ?? DateTime.now().toIso8601String());
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A4CFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('SYSTEM ALERT', style: GoogleFonts.outfit(color: const Color(0xFF1A4CFF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                    Text('${date.hour}:${date.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(alert['message'] ?? 'No message content', style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white24),
                    const SizedBox(width: 6),
                    Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.2);
  }

  Widget _buildProfile(AuthService auth) {
    final user = auth.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 120),
      child: Column(
        children: [
          _buildProfileHeader(user),
          const SizedBox(height: 32),
          _buildProfileSection('ACCOUNT DETAILS', [
            _buildProfileTile('Username', user?.username ?? 'Guest', Icons.person_outline_rounded),
            _buildProfileTile('Role', (user?.role ?? 'GUEST').toUpperCase(), Icons.badge_outlined),
            if (user?.userId != null) _buildProfileTile('User ID', user!.userId!, Icons.numbers_rounded),
          ]),
          const SizedBox(height: 24),
          _buildProfileSection('TRANSPORTATION', [
            _buildProfileTile('Assigned Route', _selectedRoute?.name ?? 'Not Assigned', Icons.alt_route_rounded),
            _buildProfileTile('Pickup Point', auth.currentUser?.pickupPoint ?? 'Main Gate', Icons.location_on_outlined),
          ]),
          const SizedBox(height: 24),
          _buildProfileSection('PREFERENCES', [
            _buildProfileTile('Notifications', 'Enabled', Icons.notifications_none_rounded),
            _buildProfileTile('Theme', 'Dark Pro', Icons.dark_mode_outlined),
          ]),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => auth.logout(),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text('LOGOUT SESSION', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildProfileHeader(dynamic user) {
    return Column(
      children: [
        Container(
          height: 100, width: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1A4CFF), Color(0xFF6366F1)]),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF1A4CFF).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)],
          ),
          child: Center(
            child: Text(
              (user?.username ?? 'G')[0].toUpperCase(),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(user?.username ?? 'Guest Explorer', style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        Text(user?.role ?? 'Visitor', style: GoogleFonts.outfit(color: const Color(0xFF1A4CFF), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
      ],
    );
  }

  Widget _buildProfileSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(title, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileTile(String label, String value, IconData icon) {
    return ListTile(
      onTap: null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: Colors.white38, size: 20),
      title: Text(label, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
      trailing: Text(value, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 120),
      itemCount: 4,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          Text(msg, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 18)),
        ],
      ),
    );
  }
}
