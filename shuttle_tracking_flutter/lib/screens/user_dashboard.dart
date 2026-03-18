import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final Map<String, Bus> _buses = {}; // Map busId to Bus model
  bool _showLinearView = false;
  bool _isLoading = true;
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _alertHistory = [];

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
      });
      
      // Fetch initial bus status
      final busEndpoint = auth.isGuest ? 'guest/buses' : 'buses';
      final List<dynamic> busData = await _apiService.get(busEndpoint);
      setState(() {
        for (var b in busData) {
          final bus = Bus.fromJson(b);
          _buses[bus.id] = bus;
        }
      });
    } catch (e) {
      debugPrint('Error fetching routes: $e');
      setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.initSocket();
    socketService.listenToBusUpdates((data) {
      if (mounted) {
        setState(() {
          final updatedBus = Bus.fromJson(data);
          _buses[updatedBus.id] = updatedBus;
          
          if (_selectedRoute != null && (_activeBus == null || _activeBus!.id == updatedBus.id)) {
            if (updatedBus.routeId == _selectedRoute!.id) {
              _activeBus = updatedBus;
            }
          }
        });
      }
    });

    socketService.socket?.on('notification', (data) {
      if (mounted) {
        setState(() {
          _alertHistory.insert(0, {
            'message': data['message'] ?? 'New Alert',
            'type': data['type'] ?? 'info',
            'timestamp': DateTime.now(),
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'New Alert'),
            backgroundColor: data['type'] == 'error' ? Colors.red : const Color(0xFF38ef7d),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Map<String, dynamic>? _selectedPickup;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117), // Premium dark background
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        elevation: 0,
        title: Text(_currentIndex == 0 ? (auth.isGuest ? 'Guest Tracker' : 'Student Dash') : (_currentIndex == 1 ? 'Alert History' : 'My Profile'),
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
        actions: [
          if (_currentIndex == 0 && _selectedRoute != null)
            IconButton(
              icon: Icon(_showLinearView ? Icons.map : Icons.linear_scale, color: Colors.white),
              onPressed: () => setState(() => _showLinearView = !_showLinearView),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => auth.logout(),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.5, -0.6),
            radius: 1.5,
            colors: [Color(0xFF16222A), Color(0xFF0D1117), Colors.black],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: _buildBody(auth),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              elevation: 0,
              backgroundColor: Colors.transparent,
              selectedItemColor: const Color(0xFF38ef7d),
              unselectedItemColor: Colors.white38,
              onTap: (index) => setState(() => _currentIndex = index),
              selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Track'),
                BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AuthService auth) {
    switch (_currentIndex) {
      case 1:
        return _buildAlertHistory();
      case 2:
        return _buildProfile(auth);
      default:
        return _buildTrackingView();
    }
  }

  Widget _buildTrackingView() {
    return Stack(
      children: [
        // Background - Map or Linear
        _showLinearView && _activeBus != null && _selectedRoute != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: LinearTrackingView(bus: _activeBus!, route: _selectedRoute!),
                ),
              )
            : BusMap(
                buses: _buses.values.where((b) => _selectedRoute == null || b.routeId == _selectedRoute!.id).toList(),
                selectedRoute: _selectedRoute,
              ),
        
        // Live Info Strip (Premium Feature)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wb_sunny_outlined, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text('Bhopal 24°C', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                      Text(
                        'SISTec LIVE • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10, letterSpacing: 1),
                      ),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF38ef7d), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('System Online', style: GoogleFonts.outfit(color: const Color(0xFF38ef7d), fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 800.ms),
        ),

        // Selected Route Info Overlay
        if (_selectedRoute != null)
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, spreadRadius: 5)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Color(int.parse(_selectedRoute!.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.directions_bus, size: 28, color: Color(int.parse(_selectedRoute!.color.replaceAll('#', '0xFF')))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_selectedRoute!.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  Text(_selectedPickup != null ? 'Pickup: ${_selectedPickup!['name']}' : 'No pickup selected', 
                                       style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                ],
                              ),
                            ),
                            if (_activeBus != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      const Text('Seats: ', style: TextStyle(color: Colors.white38, fontSize: 10)),
                                      Text(_activeBus!.occupancy, style: TextStyle(color: _activeBus!.occupancy == 'Low' ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Text('ETA', style: TextStyle(color: Color(0xFF38ef7d), fontSize: 10, fontWeight: FontWeight.bold)),
                                  Text('~8 mins', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                                ],
                              )
                          ],
                        ),
                        if (_selectedPickup == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFF38ef7d).withValues(alpha: 0.1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.location_on, color: Color(0xFF38ef7d), size: 18),
                                label: const Text('Set Your Pickup Stop', style: TextStyle(color: Color(0xFF38ef7d), fontWeight: FontWeight.bold)),
                                onPressed: _showPickupSelection,
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                ),
              ),
            ).animate().slideY(begin: -0.2, end: 0, duration: 400.ms).fadeIn(),
          ),
        
        // Route Selection Bottom Sheet Overlay
        if (_selectedRoute == null && !_isLoading)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: GestureDetector(
              onTap: _showRouteSelection,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF38ef7d).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.4)),
                  boxShadow: [BoxShadow(color: const Color(0xFF38ef7d).withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.explore, color: Color(0xFF38ef7d)),
                          const SizedBox(width: 12),
                          Text(
                            'Select Route to Track',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ).animate().slideY(begin: 0.2, end: 0, duration: 400.ms).fadeIn(),
          ),
        
        if (_isLoading)
          _buildShimmerOverlay(),
      ],
    );
  }

  Widget _buildShimmerOverlay() {
     return Center(
      child: Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          margin: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
          ),
          height: 200,
          width: double.infinity,
        ),
      ),
    );
  }

  Widget _buildAlertHistory() {
    if (_alertHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white12)),
              child: const Icon(Icons.notifications_off_outlined, color: Colors.white38, size: 64),
            ),
            const SizedBox(height: 24),
            Text('No recent alerts', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 100),
      itemCount: _alertHistory.length,
      itemBuilder: (context, index) {
        final alert = _alertHistory[index];
        final isError = alert['type'] == 'error';
        final accentColor = isError ? Colors.redAccent : const Color(0xFF38ef7d);
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.05),
                blurRadius: 15,
                spreadRadius: -5,
              )
            ]
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(isError ? Icons.error_outline : Icons.info_outline, color: accentColor, size: 24),
                ),
                title: Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Text(alert['message'], style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.3)),
                ),
                subtitle: Text(
                  '${alert['timestamp'].hour}:${alert['timestamp'].minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfile(AuthService auth) {
    final user = auth.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 40, left: 24, right: 24, bottom: 100),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF38ef7d), Color(0xFF11998e)]),
              boxShadow: [BoxShadow(color: const Color(0xFF38ef7d).withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)],
            ),
            child: const CircleAvatar(
              radius: 54,
              backgroundColor: Color(0xFF0D1117),
              child: Icon(Icons.person, size: 50, color: Color(0xFF38ef7d)),
            ),
          ),
          const SizedBox(height: 24),
          Text(user?.username ?? 'Student Name', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(user?.email ?? 'student@example.com', style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 48),
          Container(
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
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      _buildInfoRow('Role', (user?.role.toUpperCase() ?? 'STUDENT'), Icons.badge),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10)),
                      _buildInfoRow('Campus', 'Ratibad Campus', Icons.account_balance),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white10)),
                      _buildInfoRow('Status', 'Active Registered', Icons.verified_user, valueColor: const Color(0xFF38ef7d)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),
          const Text('SISTec Transport Management System', style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
        const Spacer(),
        Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  void _showRouteSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1c1c1e),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text('CHOOSE ROUTE', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemCount: _routes.length,
                itemBuilder: (context, index) {
                  final route = _routes[index];
                  final routeColor = Color(int.parse(route.color.replaceAll('#', '0xFF')));
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                         _selectedRoute = route;
                        _selectedPickup = null;
                        _activeBus = _buses.values.firstWhere(
                          (b) => b.routeId == route.id,
                          orElse: () => _buses.values.first, // or null
                        );
                      });
                      Navigator.pop(context);
                      _showPickupSelection();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: routeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: routeColor.withValues(alpha: 0.3), width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_bus_filled, color: routeColor, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            route.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text('${route.stops.length} Stops', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPickupSelection() {
    if (_selectedRoute == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1c1c1e),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CHOOSE PICKUP STOP', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 24),
            ..._selectedRoute!.stops.map((stop) => ListTile(
              leading: const Icon(Icons.location_on, color: Color(0xFF38ef7d)),
              title: Text(stop['name'] ?? '', style: const TextStyle(color: Colors.white)),
              onTap: () {
                setState(() => _selectedPickup = stop);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }
}
