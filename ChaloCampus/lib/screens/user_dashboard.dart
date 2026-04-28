import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/bus_store.dart';
import '../components/bus_map.dart';
import '../components/linear_tracking_view.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

import 'fleet_radar_screen.dart';
import 'schedule_screen.dart';
import 'complaint_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final ApiService _apiService = ApiService();
  
  List<RouteModel> _routes = [];
  bool _isLoading = true;
  RouteModel? _selectedRoute;
  Bus? _activeBus;
  int _currentIndex = 0;
  bool _showDebugOverlay = false;
  int _tapCounter = 0;
  
  final List<Map<String, dynamic>> _alertHistory = [];
  bool _isSosActive = false;

  // ── New Feature State ──────────────────────────────────────────────────────
  int? _etaMinutes;          // ETA to user's assigned pickup stop
  bool _etaLoading = false;
  bool _delaySubscribed = false; // Whether user subscribed to delay alerts

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
      if (!mounted) return;
      setState(() {
        _routes = data.map((r) => RouteModel.fromJson(r)).toList();
        _isLoading = false;
        
        if (auth.currentUser?.routeId != null) {
          _selectedRoute = _routes.firstWhere(
            (r) => r.id == auth.currentUser!.routeId,
            orElse: () => _routes.first,
          );
        }
      });
      
      final busEndpoint = auth.isGuest ? 'guest/buses' : 'buses';
      final List<dynamic> busData = await _apiService.get(busEndpoint);
      if (!mounted) return;
      
      final busStore = Provider.of<BusStore>(context, listen: false);
      busStore.seedBuses(busData);
      
      setState(() {
        _updateActiveBus(busStore);
      });

      // Load notification history (only for logged-in users)
      if (!auth.isGuest) {
        try {
          final notifData = await _apiService.get('notifications');
          busStore.seedNotifications(notifData as List);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.initSocket();

    // Proximity approach alert (existing)
    socketService.listenToBusApproach((data) {
      if (mounted) {
        final auth = Provider.of<AuthService>(context, listen: false);
        final currentUser = auth.currentUser;
        if (currentUser != null && 
            currentUser.proximityAlertsEnabled &&
            currentUser.routeId == data['routeId'] && 
            currentUser.pickupPoint == data['stopName']) {
          
          NotificationService().showNotification(
            title: 'ChaloCampus Alert: Bus Nearby',
            body: data['message'] ?? 'Your shuttle is arriving!',
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Shuttle arriving at ${data['stopName']}!'),
              backgroundColor: const Color(0xFF2D5BFF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            )
          );
        }
      }
    });

    // ── Delay alert listener (new) ──────────────────────────────────────────
    socketService.listenToBusDelayed((data) {
      if (!mounted) return;
      final auth = Provider.of<AuthService>(context, listen: false);
      final myRouteId = auth.currentUser?.routeId ?? _selectedRoute?.id;
      if (myRouteId == null) return;
      // Only notify if this delay concerns the user's route
      if (data['routeId'] == myRouteId) {
        final msg = data['message'] ?? 'Your bus is running late.';
        NotificationService().showNotification(
          title: '⚠️ Bus Delay Alert',
          body: msg,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    });
  }

  // Fetch ETA to user's pickup stop from backend
  Future<void> _fetchETA() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final routeId = _selectedRoute?.id ?? auth.currentUser?.routeId;
    final stopName = auth.currentUser?.pickupPoint;
    if (routeId == null || stopName == null || stopName.isEmpty) return;

    setState(() => _etaLoading = true);
    try {
      final data = await _apiService.get(
        'eta?routeId=${Uri.encodeQueryComponent(routeId)}&stopName=${Uri.encodeQueryComponent(stopName)}',
      );
      if (mounted) {
        setState(() {
          _etaMinutes = data['eta'] as int?;
          _etaLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _etaLoading = false);
    }
  }

  // Subscribe user to delay notifications for selected route
  Future<void> _subscribeToDelay() async {
    final routeId = _selectedRoute?.id;
    if (routeId == null) return;
    try {
      await _apiService.post('subscribe-delay', { 'routeId': routeId });
      if (mounted) {
        setState(() => _delaySubscribed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ You will be notified if the bus is late!'),
            backgroundColor: const Color(0xFF2D5BFF),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (_) {}
  }

  void _updateActiveBus(BusStore busStore) {
    if (_selectedRoute == null) {
      _activeBus = null;
      return;
    }
    
    final busesOnRoute = busStore.allBuses.where((b) => b.routeId == _selectedRoute!.id).toList();
    
    if (busesOnRoute.isEmpty) {
      _activeBus = null;
    } else {
      busesOnRoute.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      _activeBus = busesOnRoute.first;
    }
  }


  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Compute active bus inline — always fresh on every BusStore rebuild
        if (_selectedRoute != null) {
          final busesOnRoute = busStore.allBuses
              .where((b) => b.routeId == _selectedRoute!.id)
              .toList();
          if (busesOnRoute.isEmpty) {
            _activeBus = null;
          } else {
            busesOnRoute.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
            _activeBus = busesOnRoute.first;
          }
        } else {
          _activeBus = null;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: ValueListenableBuilder<bool>(
            valueListenable: socketService.connectionStatus,
            builder: (context, isConnected, child) {
              return Stack(
                children: [
                  child!,
                  if (!isConnected)
                    Positioned(
                      top: MediaQuery.of(context).padding.top,
                      left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color: Colors.redAccent.withValues(alpha: 0.8),
                        child: Center(
                          child: Text(
                            '📡 SYNCHRONIZING Tracker...',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                          ),
                        ),
                      ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                    ),
                  if (_showDebugOverlay) _buildDebugOverlay(busStore),
                  if (_currentIndex == 0) _buildFloatingHeader(busStore),
                ],
              );
            },
            child: _getViewForIndex(auth, _currentIndex, busStore),
          ),
          bottomNavigationBar: _buildModernBottomNav(),
          floatingActionButton: _currentIndex == 0 ? _buildSOSButton(auth) : null,
        );
      },
    );
  }

  Widget _buildDebugOverlay(BusStore busStore) {
    final buses = busStore.allBuses;
    return Positioned(
      top: 150, left: 20, right: 20,
      child: Container(
        height: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Debug Data', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white24, size: 16), onPressed: () => setState(() => _showDebugOverlay = false)),
              ],
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: buses.isEmpty 
                ? const Center(child: Text('NO DATA RECEIVED YET', style: TextStyle(color: Colors.white24, fontSize: 10)))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: buses.length,
                    itemBuilder: (context, i) {
                      final bus = buses[i];
                      final isFresh = DateTime.now().difference(bus.lastUpdated).inSeconds < 10;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: isFresh ? Colors.green : Colors.red, shape: BoxShape.circle)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ID: ${bus.id.substring(math.max(0, bus.id.length - 6))}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  Text('Route: ${bus.routeName}', style: const TextStyle(color: Colors.white38, fontSize: 8)),
                                ],
                              ),
                            ),
                            Text('${bus.speed.toInt()} KM/H', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildFloatingHeader(BusStore busStore) {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 10, left: 16, right: 16,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        decoration: BoxDecoration(
          color: Color(0xFF1E1E1E).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                _tapCounter++;
                if (_tapCounter >= 3) {
                  setState(() => _showDebugOverlay = !_showDebugOverlay);
                  _tapCounter = 0;
                }
                Future.delayed(1.seconds, () => _tapCounter = 0);
              },
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5BFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus_filled_rounded, color: Color(0xFF2D5BFF), size: 17),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Shuttle Tracker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      ValueListenableBuilder<DateTime?>(
                        valueListenable: socketService.lastDataReceived,
                        builder: (context, lastPacket, _) {
                          return Container(
                            width: 5, height: 5,
                            key: ValueKey(lastPacket?.millisecondsSinceEpoch ?? 0),
                            decoration: const BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                            ),
                          ).animate(key: ValueKey(lastPacket?.millisecondsSinceEpoch ?? 0))
                           .scale(begin: const Offset(1,1), end: const Offset(2, 2), duration: 200.ms)
                           .fadeOut(duration: 400.ms);
                        },
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _selectedRoute?.name ?? 'Tap ⇄ to select route',
                          style: TextStyle(
                            color: _selectedRoute != null ? Colors.blueAccent : Colors.white30,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _showRouteSelection,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: Colors.white60, size: 18),
              ),
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: -0.1),
    );
  }

  Widget _getViewForIndex(AuthService auth, int index, BusStore busStore) {
    switch (index) {
      case 1: return _buildAlertsTab();
      case 2: return _buildProfileTab(auth);
      default:
        if (_isLoading) {
          return Container(
            color: const Color(0xFF121212),
            child: Center(child: _buildShimmerLoader()),
          );
        }
        return _buildTrackingTab(busStore);
    }
  }

  Widget _buildTrackingTab(BusStore busStore) {
    return Stack(
      children: [
        BusMap(
          buses: busStore.allBuses.where((b) => 
            b.routeId == _selectedRoute?.id && 
            b.status != 'Offline'
          ).toList(),
          selectedRoute: _selectedRoute,
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.3,
          minChildSize: 0.15,
          maxChildSize: 0.75,
          snap: true,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Color(0xFF1E1E1E).withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 40)],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 140),
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 35),
                if (_selectedRoute == null) ...[
                   Text('Home', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF2D5BFF), letterSpacing: 2)),
                   const SizedBox(height: 8),
                   Text('Ready for Departure', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                   Text('Select a route to track your transit.', style: TextStyle(fontSize: 13, color: Colors.white38, height: 1.5)),
                   const SizedBox(height: 40),
                   _buildActionCard('Active Fleet Radar', 'View all shuttle locations', Icons.radar_rounded, () {
                     Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetRadarScreen()));
                   }),
                   const SizedBox(height: 16),
                   _buildActionCard('Select Route', 'Synchronize with a specific shuttle channel', Icons.alt_route_rounded, _showRouteSelection),
                ] else ...[
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(_selectedRoute!.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis),
                             const SizedBox(height: 4),
                             Row(
                               children: [
                                 Container(
                                   width: 8, height: 8,
                                   decoration: BoxDecoration(
                                     color: _activeBus != null && _activeBus!.status != 'Offline' ? Colors.blueAccent : Colors.white10,
                                     shape: BoxShape.circle,
                                     boxShadow: _activeBus != null && _activeBus!.status != 'Offline' ? [const BoxShadow(color: Colors.blueAccent, blurRadius: 6)] : null,
                                   ),
                                 ).animate(onPlay: (c) => _activeBus != null && _activeBus!.status != 'Offline' ? c.repeat() : c.stop()).fadeOut(duration: 1.seconds),
                                 const SizedBox(width: 10),
                                 Text(
                                   _activeBus != null && _activeBus!.status != 'Offline' ? 'Live' : 'Offline', 
                                   style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _activeBus != null && _activeBus!.status != 'Offline' ? Colors.blueAccent : Colors.white24, letterSpacing: 1.5)
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                         decoration: BoxDecoration(
                           color: (_activeBus != null && _activeBus!.status != 'Offline' ? Colors.blueAccent : Colors.white).withValues(alpha: 0.1), 
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(color: (_activeBus != null && _activeBus!.status != 'Offline' ? Colors.blueAccent : Colors.white10).withValues(alpha: 0.2)),
                         ),
                         child: Text(
                           _activeBus != null && _activeBus!.status != 'Offline' ? 'ON TIME' : 'STATIONARY', 
                           style: TextStyle(color: _activeBus != null && _activeBus!.status != 'Offline' ? Colors.blueAccent : Colors.white38, fontSize: 10, fontWeight: FontWeight.w900)
                         ),
                       ),
                     ],
                   ),
                   const SizedBox(height: 35),
                   _buildStatGrid(),
                   const SizedBox(height: 35),
                   if (_activeBus != null && _activeBus!.status != 'Offline')
                     LinearTrackingView(bus: _activeBus!, route: _selectedRoute!)
                   else
                     _buildStopsList(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatGrid() {
    final isLive = _activeBus != null && _activeBus!.status != 'Offline';
    final auth = Provider.of<AuthService>(context, listen: false);
    final hasPickup = (auth.currentUser?.pickupPoint ?? '').isNotEmpty;

    // Prefer real stop-specific ETA fetched from backend
    String etaDisplay = '--';
    if (_etaLoading) {
      etaDisplay = '...';
    } else if (_etaMinutes != null) {
      etaDisplay = '$_etaMinutes MIN';
    } else if (isLive) {
      if (_activeBus!.etas.isNotEmpty) {
        etaDisplay = '${_activeBus!.etas.first.minutes} MIN';
      }
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: hasPickup && isLive ? _fetchETA : null,
                child: Stack(
                  children: [
                    _buildStatItem(
                      hasPickup ? 'ETA TO STOP' : 'ETA',
                      etaDisplay,
                      Icons.timer_outlined,
                    ),
                    if (hasPickup && isLive)
                      Positioned(
                        top: 10, right: 10,
                        child: Icon(
                          Icons.refresh_rounded,
                          color: const Color(0xFF2D5BFF).withValues(alpha: 0.5),
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildStatItem('VELOCITY', isLive ? '${_activeBus!.speed.toInt()} KM/H' : '--', Icons.speed_rounded)),
          ],
        ),
        if (hasPickup && _selectedRoute != null) ...[
          const SizedBox(height: 12),
          Text(
            'MY STOP: ${auth.currentUser!.pickupPoint!.toUpperCase()}',
            style: TextStyle(
              color: Colors.blueAccent.withValues(alpha: 0.6),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 20),
        // Quick Actions Row
        Row(
          children: [
            Expanded(child: _buildQuickAction(
              icon: Icons.schedule_rounded,
              label: 'SCHEDULE',
              color: Colors.blueAccent,
              onTap: _selectedRoute != null
                  ? () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ScheduleScreen(route: _selectedRoute!)))
                  : null,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(
              icon: _delaySubscribed
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              label: _delaySubscribed ? 'NOTIFYING' : 'NOTIFY LATE',
              color: _delaySubscribed ? const Color(0xFF38EF7D) : const Color(0xFFFFB347),
              onTap: _delaySubscribed || _selectedRoute == null ? null : _subscribeToDelay,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(
              icon: Icons.report_gmailerrorred_rounded,
              label: 'REPORT',
              color: Colors.redAccent,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ComplaintScreen(
                      selectedRoute: _selectedRoute,
                      activeBus: _activeBus,
                    ))),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.02)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: disabled
                ? Colors.white.withValues(alpha: 0.03)
                : color.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: disabled ? Colors.white24 : color, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: disabled ? Colors.white24 : color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2D5BFF), size: 20),
          const SizedBox(height: 12),
          Text(val, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, String sub, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2D5BFF).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF2D5BFF)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(sub, style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Mark all read when tab is open
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (busStore.unreadCount > 0) busStore.markAllRead();
        });

        final allAlerts = busStore.notifications;

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              backgroundColor: const Color(0xFF121212),
              flexibleSpace: FlexibleSpaceBar(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NOTIFICATIONS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
                    if (allAlerts.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5BFF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.3)),
                        ),
                        child: Text('${allAlerts.length}', style: TextStyle(color: const Color(0xFF2D5BFF), fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ],
                ),
                centerTitle: true,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: allAlerts.isEmpty
                ? SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(60),
                      child: Column(
                        children: [
                          const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 60),
                          const SizedBox(height: 16),
                          Text('NO ALERTS YET', style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          const SizedBox(height: 8),
                          Text('Manager broadcasts will appear here in real-time', style: TextStyle(color: Colors.white12, fontSize: 11)),
                        ],
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNotificationCard(
                        {
                          'message' : allAlerts[index].message,
                          'timestamp': allAlerts[index].timestamp.toIso8601String(),
                          'priority' : allAlerts[index].type == 'critical' ? 'critical' : 'important',
                        },
                        index,
                      ),
                      childCount: allAlerts.length,
                    ),
                  ),
            ),
          ],
        );
      },
    );
  }

  String _formatAlertTime(String? timestamp) {
    if (timestamp == null) return 'JUST NOW';
    final date = DateTime.parse(timestamp).toLocal();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes} MINS AGO';
    return '${diff.inHours} HOURS AGO';
  }

  Widget _buildNotificationCard(Map<String, dynamic> alert, int index) {
    final isCritical = alert['priority'] == 'critical';
    final accentColor = isCritical ? Colors.redAccent : const Color(0xFF2D5BFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(isCritical ? Icons.warning_rounded : Icons.bolt_rounded, color: accentColor, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCritical ? 'CRITICAL ALERT' : 'SYSTEM DIRECTIVE', 
                  style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(alert['message'] ?? '', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Text(_formatAlertTime(alert['timestamp']), style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
  }

  Widget _buildProfileTab(AuthService auth) {
    final user = auth.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 100),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2D5BFF), Colors.blueAccent]),
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [BoxShadow(color: const Color(0xFF2D5BFF).withValues(alpha: 0.2), blurRadius: 30)],
                ),
                child: Center(
                  child: Text(
                    (user?.username ?? 'G')[0].toUpperCase(),
                    style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(user?.username ?? 'Guest User', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              Text((user?.role ?? 'explorer').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF2D5BFF), letterSpacing: 2)),
              if (user?.userId != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    'Enrollment: ${user!.userId}',
                    style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 50),
        Consumer<BusStore>(
          builder: (context, busStore, _) {
            final latestNotifs = busStore.notifications.take(3).toList();
            return _buildProfileSection('NOTIFICATION FEED', [
              if (latestNotifs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('NO RECENT ACTIVITY', style: TextStyle(color: Colors.white12, fontSize: 10, fontWeight: FontWeight.bold))),
                )
              else
                ...latestNotifs.map((n) => ListTile(
                  dense: true,
                  leading: Icon(
                    n.type == 'critical' ? Icons.warning_rounded : Icons.info_outline_rounded,
                    color: n.type == 'critical' ? Colors.redAccent : Colors.blueAccent,
                    size: 16,
                  ),
                  title: Text(n.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(_formatAlertTime(n.timestamp.toIso8601String()), style: const TextStyle(color: Colors.white24, fontSize: 9)),
                  onTap: () => setState(() => _currentIndex = 1),
                )),
              if (latestNotifs.isNotEmpty)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _currentIndex = 1),
                    child: Text('VIEW ALL HISTORY', style: TextStyle(color: const Color(0xFF2D5BFF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 24),
        _buildProfileSection('PREFERENCES', [
          _buildToggleTile('PROXIMITY ALERTS', 'Notify when bus is near', user?.proximityAlertsEnabled ?? true, (v) => auth.updateProximityAlerts(v)),
          _buildProfileTile('THEME', 'NEON DEPTH', Icons.dark_mode_outlined),
        ]),
        const SizedBox(height: 24),
        _buildProfileSection('TRANSPORT', [
          _buildProfileTile('PICKUP', user?.pickupPoint ?? 'NOT SET', Icons.location_on_outlined),
          _buildProfileTile('ROUTE', _selectedRoute?.name ?? 'NOT ASSIGNED', Icons.alt_route_rounded),
        ]),
        const SizedBox(height: 24),
        // ── Account / Security ─────────────────────────────────────────────
        _buildProfileSection('ACCOUNT', [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: Colors.deepPurpleAccent, size: 18),
            ),
            title: Text('Change Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Update your login password', style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            onTap: () => _showChangePasswordSheet(auth),
          ),
        ]),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => auth.logout(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: Text('TERMINATE SESSION', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ),
      ],
    ).animate().fadeIn();
  }

  void _showChangePasswordSheet(AuthService auth) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    bool showCurrent = false;
    bool showNew     = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final cur = currentCtrl.text.trim();
            final nw  = newCtrl.text.trim();
            final cnf = confirmCtrl.text.trim();
            if (cur.isEmpty || nw.isEmpty || cnf.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All fields are required.'), backgroundColor: Colors.redAccent));
              return;
            }
            if (nw.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New password must be at least 6 characters.'), backgroundColor: Colors.redAccent));
              return;
            }
            if (nw != cnf) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New passwords do not match.'), backgroundColor: Colors.redAccent));
              return;
            }
            // Capture before async gap
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(ctx);
            setSheetState(() => saving = true);
            try {
              await auth.changePassword(cur, nw);
              if (mounted) {
                nav.pop();
                messenger.showSnackBar(SnackBar(
                  content: const Text('✅ Password changed successfully!'),
                  backgroundColor: const Color(0xFF38EF7D),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ));
              }
            } catch (e) {
              setSheetState(() => saving = false);
              final msg = e.toString().replaceFirst('Exception: ', '');
              messenger.showSnackBar(SnackBar(
                content: Text(msg),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ));
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Text('Change Password', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Enter your current password, then set a new one.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 24),
                  _pwField(ctx, 'Current Password', currentCtrl, showCurrent, () => setSheetState(() => showCurrent = !showCurrent)),
                  const SizedBox(height: 14),
                  _pwField(ctx, 'New Password (min 6 chars)', newCtrl, showNew, () => setSheetState(() => showNew = !showNew)),
                  const SizedBox(height: 14),
                  _pwField(ctx, 'Confirm New Password', confirmCtrl, showNew, null),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D5BFF),
                        padding: const EdgeInsets.all(18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('UPDATE PASSWORD', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pwField(BuildContext ctx, String hint, TextEditingController ctrl, bool visible, VoidCallback? onToggle) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: !visible,
        style: TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          suffixIcon: onToggle != null
              ? IconButton(
                  icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white24, size: 20),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildProfileSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileTile(String label, String val, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Colors.white24, size: 20),
      title: Text(label, style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
      trailing: Text(val, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }

  Widget _buildToggleTile(String title, String sub, bool val, Function(bool) onChanged) {
    return ListTile(
      title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      subtitle: Text(sub, style: TextStyle(color: Colors.white24, fontSize: 10)),
      trailing: Switch(
        value: val,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF2D5BFF),
      ),
    );
  }

  Widget _buildModernBottomNav() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPadding > 0 ? bottomPadding : 20),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.explore_rounded, 'TRACK', 0),
              _buildNavItem(1, Icons.notifications_rounded, 'ALERTS', busStore.unreadCount),
              _buildNavItem(2, Icons.person_rounded, 'PROFILE', 0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, int badge) {
    bool isSel = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: 300.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF2D5BFF).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: isSel ? const Color(0xFF2D5BFF) : Colors.white24, size: 22),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
            if (isSel) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton(AuthService auth) {
    return FloatingActionButton(
      onPressed: () {}, // Long press handles it
      backgroundColor: Colors.redAccent,
      child: GestureDetector(
        onLongPress: () => _triggerSOS(auth),
        child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      ),
    );
  }

  Future<void> _triggerSOS(AuthService auth) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);

    // Cache BEFORE any awaits
    final socketService = context.read<SocketService>();

    try {
      Position pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      socketService.emitSOSAlert({
        'name': auth.currentUser?.username ?? 'Guest',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EMERGENCY SOS SENT!'), backgroundColor: Colors.red));
    } catch (e) {
      debugPrint('SOS Error: $e');
    } finally {
      if (mounted) setState(() => _isSosActive = false);
    }
  }

  void _showRouteSelection() {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Color(0xFF1E1E1E).withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Available Routes', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16, letterSpacing: 1)),
                        Text('Select a route to track', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                    if (_selectedRoute != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRoute = null;
                            _activeBus = null;
                          });
                          Navigator.pop(context);
                        },
                        child: Text('CLEAR', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: TextField(
                    onChanged: (v) => setModalState(() => searchQuery = v),
                    style: TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Filter routes...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search_rounded, color: Colors.white24, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).length,
                  itemBuilder: (context, i) {
                    final filteredRoutes = _routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                    final route = filteredRoutes[i];
                    final isSel = _selectedRoute?.id == route.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF2D5BFF).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: isSel ? const Color(0xFF2D5BFF).withValues(alpha: 0.3) : Colors.transparent),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        onTap: () {
                          final busStore = Provider.of<BusStore>(context, listen: false);
                          setState(() {
                            _selectedRoute = route;
                            _updateActiveBus(busStore);
                          });
                          Navigator.pop(context);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isSel ? const Color(0xFF2D5BFF) : Colors.white24).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.alt_route_rounded, color: isSel ? const Color(0xFF2D5BFF) : Colors.white38, size: 20),
                        ),
                        title: Text(route.name, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        subtitle: Text('${route.stops.length} stops', style: TextStyle(color: Colors.white24, fontSize: 10)),
                        trailing: isSel 
                          ? const Icon(Icons.check_circle_rounded, color: Colors.blueAccent, size: 20)
                          : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
                      ),
                    ).animate().fadeIn(delay: (i * 30).ms).slideX(begin: 0.05);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Route Details', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const Spacer(),
            Text('${_selectedRoute!.stops.length} STOPS', style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 24),
        ...List.generate(_selectedRoute!.stops.length, (index) {
          final stop = _selectedRoute!.stops[index];
          final isLast = index == _selectedRoute!.stops.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: index == 0 ? Colors.blueAccent : Colors.transparent,
                        border: Border.all(color: const Color(0xFF2D5BFF), width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.white10,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop['name'],
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'LAT: ${stop['lat'].toStringAsFixed(4)} | LNG: ${stop['lng'].toStringAsFixed(4)}',
                        style: TextStyle(color: Colors.white10, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildShimmerLoader() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Column(children: List.generate(4, (i) => Container(height: 100, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))))),
    );
  }
}
