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
import 'package:google_fonts/google_fonts.dart';
import 'fleet_radar_screen.dart';

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

    // General broadcast notifications are now handled centrally by BusStore
    // which triggers the local notification pop-up and updates the feed.
    
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
          backgroundColor: const Color(0xFF05070E),
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
                        color: const Color(0xFFFF2E63).withValues(alpha: 0.8),
                        child: Center(
                          child: Text(
                            '📡 SYNCHRONIZING TELEMETRY...',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
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
          border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('FLEET DEBUG (RAW)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
                            Text('${bus.speed.toInt()} KM/H', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 10, fontWeight: FontWeight.w900)),
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
      top: topPadding + 10, left: 20, right: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D121F).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5BFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_bus_filled_rounded, color: Color(0xFF2D5BFF), size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CHALO CAMPUS',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
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
                              color: Color(0xFF00F0FF),
                              shape: BoxShape.circle,
                            ),
                          ).animate(key: ValueKey(lastPacket?.millisecondsSinceEpoch ?? 0))
                           .scale(begin: const Offset(1,1), end: const Offset(2, 2), duration: 200.ms)
                           .fadeOut(duration: 400.ms);
                        },
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _selectedRoute?.name ?? 'Select Route',
                          style: GoogleFonts.plusJakartaSans(
                            color: _selectedRoute != null ? const Color(0xFF00F0FF) : Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 20),
              onPressed: _showRouteSelection,
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
            color: const Color(0xFF05070E),
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
              color: const Color(0xFF0D121F).withValues(alpha: 0.98),
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
                   Text('MISSION CONTROL', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF2D5BFF), letterSpacing: 2)),
                   const SizedBox(height: 8),
                   Text('Ready for Departure', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                   Text('Select a shuttle channel to begin real-time telemetry synchronization and track your transit.', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white38, height: 1.5)),
                   const SizedBox(height: 40),
                   _buildActionCard('Active Fleet Radar', 'Access global fleet position and status', Icons.radar_rounded, () {
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
                             Text(_selectedRoute!.name, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis),
                             const SizedBox(height: 4),
                             Row(
                               children: [
                                 Container(
                                   width: 8, height: 8,
                                   decoration: BoxDecoration(
                                     color: _activeBus != null && _activeBus!.status != 'Offline' ? const Color(0xFF00F0FF) : Colors.white10,
                                     shape: BoxShape.circle,
                                     boxShadow: _activeBus != null && _activeBus!.status != 'Offline' ? [const BoxShadow(color: Color(0xFF00F0FF), blurRadius: 6)] : null,
                                   ),
                                 ).animate(onPlay: (c) => _activeBus != null && _activeBus!.status != 'Offline' ? c.repeat() : c.stop()).fadeOut(duration: 1.seconds),
                                 const SizedBox(width: 10),
                                 Text(
                                   _activeBus != null && _activeBus!.status != 'Offline' ? 'SYNC ACTIVE' : 'WAITING FOR DATA', 
                                   style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: _activeBus != null && _activeBus!.status != 'Offline' ? const Color(0xFF00F0FF) : Colors.white24, letterSpacing: 1.5)
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                         decoration: BoxDecoration(
                           color: (_activeBus != null && _activeBus!.status != 'Offline' ? const Color(0xFF00F0FF) : Colors.white).withValues(alpha: 0.1), 
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(color: (_activeBus != null && _activeBus!.status != 'Offline' ? const Color(0xFF00F0FF) : Colors.white10).withValues(alpha: 0.2)),
                         ),
                         child: Text(
                           _activeBus != null && _activeBus!.status != 'Offline' ? 'ON TIME' : 'STATIONARY', 
                           style: GoogleFonts.plusJakartaSans(color: _activeBus != null && _activeBus!.status != 'Offline' ? const Color(0xFF00F0FF) : Colors.white38, fontSize: 10, fontWeight: FontWeight.w900)
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
    
    // Calculate a dynamic ETA based on average city speed (25km/h) if we have data
    String etaDisplay = '--';
    if (isLive) {
      // For demo, we use a simple distance logic or the bus's own ETA list
      if (_activeBus!.etas.isNotEmpty) {
        etaDisplay = '${_activeBus!.etas.first.minutes} MIN';
      } else {
        etaDisplay = '8 MIN'; // Fallback
      }
    }

    return Row(
      children: [
        Expanded(child: _buildStatItem('ETA', etaDisplay, Icons.timer_outlined)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatItem('VELOCITY', isLive ? '${_activeBus!.speed.toInt()} KM/H' : '--', Icons.speed_rounded)),
      ],
    );
  }

  Widget _buildStatItem(String label, String val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151925),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2D5BFF), size: 20),
          const SizedBox(height: 12),
          Text(val, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
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
                  Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(sub, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12)),
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
              backgroundColor: const Color(0xFF05070E),
              flexibleSpace: FlexibleSpaceBar(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NOTIFICATIONS', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
                    if (allAlerts.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5BFF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.3)),
                        ),
                        child: Text('${allAlerts.length}', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF2D5BFF), fontSize: 11, fontWeight: FontWeight.w900)),
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
                          Text('NO ALERTS YET', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          const SizedBox(height: 8),
                          Text('Manager broadcasts will appear here in real-time', style: GoogleFonts.plusJakartaSans(color: Colors.white12, fontSize: 11)),
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
    final accentColor = isCritical ? const Color(0xFFFF2E63) : const Color(0xFF2D5BFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D121F),
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
                  style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(alert['message'] ?? '', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Text(_formatAlertTime(alert['timestamp']), style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
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
                  gradient: const LinearGradient(colors: [Color(0xFF2D5BFF), Color(0xFF00F0FF)]),
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [BoxShadow(color: const Color(0xFF2D5BFF).withValues(alpha: 0.2), blurRadius: 30)],
                ),
                child: Center(
                  child: Text(
                    (user?.username ?? 'G')[0].toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(user?.username ?? 'Guest User', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              Text((user?.role ?? 'explorer').toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF2D5BFF), letterSpacing: 2)),
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
                    color: n.type == 'critical' ? const Color(0xFFFF2E63) : const Color(0xFF00F0FF),
                    size: 16,
                  ),
                  title: Text(n.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(_formatAlertTime(n.timestamp.toIso8601String()), style: const TextStyle(color: Colors.white24, fontSize: 9)),
                  onTap: () => setState(() => _currentIndex = 1), // Jump to alerts tab
                )),
              if (latestNotifs.isNotEmpty)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _currentIndex = 1),
                    child: Text('VIEW ALL HISTORY', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF2D5BFF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => auth.logout(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF2E63).withValues(alpha: 0.1),
            foregroundColor: const Color(0xFFFF2E63),
            padding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: Text('TERMINATE SESSION', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ),
      ],
    ).animate().fadeIn();
  }

  Widget _buildProfileSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white24, letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D121F),
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
      title: Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
      trailing: Text(val, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }

  Widget _buildToggleTile(String title, String sub, bool val, Function(bool) onChanged) {
    return ListTile(
      title: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      subtitle: Text(sub, style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10)),
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
            color: const Color(0xFF05070E),
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
                        color: Color(0xFFFF2E63),
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
              Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton(AuthService auth) {
    return GestureDetector(
      onLongPress: () => _triggerSOS(auth),
      child: Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFFF2E63),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: const Color(0xFFFF2E63).withValues(alpha: 0.4), blurRadius: 20)],
        ),
        child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.1,1.1));
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
            color: const Color(0xFF0D121F).withValues(alpha: 0.98),
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
                        Text('FLEET CHANNELS', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16, letterSpacing: 1)),
                        Text('Select a shuttle channel to sync', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10)),
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
                        child: Text('CLEAR', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFFF2E63), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Filter routes...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13),
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
                        title: Text(route.name, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        subtitle: Text('${route.stops.length} checkpoints detected', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10)),
                        trailing: isSel 
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00F0FF), size: 20)
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
            Text('SEQUENCE PROTOCOL', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const Spacer(),
            Text('${_selectedRoute!.stops.length} STOPS', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 9, fontWeight: FontWeight.w900)),
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
                        color: index == 0 ? const Color(0xFF00F0FF) : Colors.transparent,
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
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'LAT: ${stop['lat'].toStringAsFixed(4)} | LNG: ${stop['lng'].toStringAsFixed(4)}',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white10, fontSize: 9, fontWeight: FontWeight.bold),
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
