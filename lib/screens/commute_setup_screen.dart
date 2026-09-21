import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';
import 'user_dashboard.dart';

class CommuteSetupScreen extends StatefulWidget {
  final bool isInitialSetup;
  const CommuteSetupScreen({super.key, this.isInitialSetup = true});

  @override
  State<CommuteSetupScreen> createState() => _CommuteSetupScreenState();
}

class _CommuteSetupScreenState extends State<CommuteSetupScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _localAddressController = TextEditingController();

  List<RouteModel> _routes = [];
  RouteModel? _selectedRoute;
  String? _selectedStop;
  bool _isLoadingRoutes = true;
  bool _isLocating = false;
  bool _isSaving = false;
  String? _locationStatusText;
  String? _selectedHubName;

  List<Map<String, dynamic>> _recommendedStops = [];

  final List<Map<String, dynamic>> _bhopalHubs = const [
    {'name': 'Indrapuri', 'icon': Icons.school_rounded, 'color': Color(0xFF38BDF8), 'lat': 23.2500, 'lng': 77.4650},
    {'name': 'MP Nagar', 'icon': Icons.business_rounded, 'color': Color(0xFF818CF8), 'lat': 23.2330, 'lng': 77.4350},
    {'name': 'Ayodhya Bypass', 'icon': Icons.alt_route_rounded, 'color': Color(0xFF34D399), 'lat': 23.2750, 'lng': 77.4580},
    {'name': 'Piplani / BHEL', 'icon': Icons.precision_manufacturing_rounded, 'color': Color(0xFFFBBF24), 'lat': 23.2450, 'lng': 77.4800},
    {'name': 'Anand Nagar', 'icon': Icons.home_rounded, 'color': Color(0xFFA78BFA), 'lat': 23.2480, 'lng': 77.4900},
    {'name': 'Lalghati', 'icon': Icons.flight_takeoff_rounded, 'color': Color(0xFFF472B6), 'lat': 23.2800, 'lng': 77.3600},
    {'name': 'Kolar Road', 'icon': Icons.park_rounded, 'color': Color(0xFF4ADE80), 'lat': 23.1800, 'lng': 77.4200},
    {'name': 'Ashoka Garden', 'icon': Icons.yard_rounded, 'color': Color(0xFF2DD4BF), 'lat': 23.2650, 'lng': 77.4250},
    {'name': 'New Market', 'icon': Icons.shopping_bag_rounded, 'color': Color(0xFFFB923C), 'lat': 23.2350, 'lng': 77.4000},
    {'name': 'Hostel / Campus', 'icon': Icons.account_balance_rounded, 'color': Color(0xFF60A5FA), 'lat': 23.2980, 'lng': 77.4080},
  ];

  @override
  void initState() {
    super.initState();
    _initUserAndRoutes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _localAddressController.dispose();
    super.dispose();
  }

  Future<void> _initUserAndRoutes() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.currentUser;
    if (user != null) {
      _nameController.text = user.name ?? user.username;
      if (user.localAddress != null && user.localAddress!.trim().isNotEmpty) {
        _localAddressController.text = user.localAddress!;
      }
    }
    await _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() => _isLoadingRoutes = true);

    try {
      final data = await _apiService.get('routes');
      if (data is List) {
        if (!mounted) return;
        final parsed = data.map((json) => RouteModel.fromJson(json)).toList();
        final auth = Provider.of<AuthService>(context, listen: false);
        final user = auth.currentUser;

        RouteModel? initialRoute;
        String? initialStop;

        if (user?.routeId != null) {
          initialRoute = parsed.where((r) => r.id == user!.routeId).firstOrNull;
          if (initialRoute != null && user?.pickupPoint != null) {
            final matched = initialRoute.stops.where((s) => s['name'] == user!.pickupPoint).firstOrNull;
            if (matched != null) {
              initialStop = matched['name'];
            }
          }
        }

        if (mounted) {
          setState(() {
            _routes = parsed;
            _selectedRoute = initialRoute ?? (parsed.isNotEmpty ? parsed.first : null);
            final bool hasStop = _selectedRoute?.stops.any((s) => s['name'] == initialStop) ?? false;
            _selectedStop = hasStop
                ? initialStop
                : (_selectedRoute?.stops.isNotEmpty == true
                    ? _selectedRoute!.stops.first['name']
                    : null);
            _isLoadingRoutes = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRoutes = false);
      }
    }
  }

  Future<void> _detectGPSLocation() async {
    setState(() {
      _isLocating = true;
      _locationStatusText = 'Fetching precise GPS coordinates...';
    });
    HapticFeedback.selectionClick();

    try {
      if (!kIsWeb) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            _showCustomSnackBar(
              'Location permission needed to auto-detect nearest stop.',
              isError: true,
            );
          }
          setState(() {
            _isLocating = false;
            _locationStatusText = null;
          });
          return;
        }
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _calculateAndRankNearestStops(pos.latitude, pos.longitude, 'GPS Location');
    } catch (e) {
      debugPrint('Error getting GPS location: $e');
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationStatusText = 'Could not fetch GPS. Select an area below:';
        });
      }
    }
  }

  void _calculateAndRankNearestStops(double userLat, double userLng, String label) {
    if (_routes.isEmpty) return;

    final List<Map<String, dynamic>> results = [];

    for (final route in _routes) {
      for (final stop in route.stops) {
        final double stopLat = (stop['lat'] as num?)?.toDouble() ?? 0.0;
        final double stopLng = (stop['lng'] as num?)?.toDouble() ?? 0.0;
        final String stopName = stop['name']?.toString() ?? '';

        if (stopLat != 0.0 && stopLng != 0.0 && stopName.trim().isNotEmpty) {
          final double distanceMeters = Geolocator.distanceBetween(userLat, userLng, stopLat, stopLng);

          String distText;
          if (distanceMeters < 1000) {
            distText = '${distanceMeters.toStringAsFixed(0)} m away';
          } else {
            distText = '${(distanceMeters / 1000).toStringAsFixed(1)} km away';
          }

          results.add({
            'stopName': stopName,
            'route': route,
            'distanceMeters': distanceMeters,
            'distanceText': distText,
          });
        }
      }
    }

    results.sort((a, b) => (a['distanceMeters'] as double).compareTo(b['distanceMeters'] as double));

    final Set<String> seenStops = {};
    final List<Map<String, dynamic>> topUnique = [];
    for (final item in results) {
      final key = '${item["stopName"]}_${item["route"].id}';
      if (!seenStops.contains(key)) {
        seenStops.add(key);
        topUnique.add(item);
        if (topUnique.length >= 3) break;
      }
    }

    setState(() {
      _recommendedStops = topUnique;
      _isLocating = false;
      _locationStatusText = 'Nearest recommendations for $label:';
      if (topUnique.isNotEmpty) {
        _selectedRoute = topUnique.first['route'] as RouteModel;
        _selectedStop = topUnique.first['stopName'] as String;
      }
    });

    HapticFeedback.mediumImpact();
  }

  void _selectHub(Map<String, dynamic> hub) {
    setState(() => _selectedHubName = hub['name'] as String);
    _localAddressController.text = '${hub["name"]}, Bhopal';
    _calculateAndRankNearestStops(hub['lat'] as double, hub['lng'] as double, hub['name'] as String);
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.info_outline_rounded : Icons.check_circle_rounded,
              color: isError ? AppColors.danger : AppColors.accentGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFF1E1524) : const Color(0xFF13222A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isError ? AppColors.danger.withValues(alpha: 0.3) : AppColors.accentGreen.withValues(alpha: 0.3),
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Future<void> _saveCommuteSetup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showCustomSnackBar('Please enter your full name', isError: true);
      return;
    }

    if (_selectedRoute == null) {
      _showCustomSnackBar('Please select your daily bus route', isError: true);
      return;
    }

    if (_selectedStop == null || _selectedStop!.trim().isEmpty) {
      _showCustomSnackBar('Please select your nearest pickup stop', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.updateCommuteSetup(
        name: name,
        routeId: _selectedRoute!.id,
        pickupPoint: _selectedStop!.trim(),
        localAddress: _localAddressController.text.trim(),
      );

      if (!mounted) return;

      _showCustomSnackBar('Commute preferences saved for $_selectedStop!');

      // Immediate & reliable navigation transition to UserDashboard
      if (widget.isInitialSetup) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (context, anim, secAnim) => const UserDashboard(),
            transitionsBuilder: (context, anim, secAnim, child) {
              return FadeTransition(opacity: anim, child: child);
            },
            transitionDuration: const Duration(milliseconds: 350),
          ),
          (route) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar('Notice: Continuing to dashboard ($e)', isError: true);
      if (widget.isInitialSetup) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UserDashboard()),
          (route) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _skipToDashboard() {
    HapticFeedback.lightImpact();
    if (widget.isInitialSetup) {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, anim, secAnim) => const UserDashboard(),
          transitionsBuilder: (context, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
        (route) => false,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isInitialSetup,
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 300,
              left: -80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: _isLoadingRoutes
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: const CircularProgressIndicator(
                              color: AppColors.accent,
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading transit network...',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildTopBar(),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeroHeader(),
                                const SizedBox(height: 22),
                                _buildStepCard(
                                  stepNumber: '01',
                                  stepTitle: 'CONFIRM YOUR FULL NAME',
                                  icon: Icons.person_rounded,
                                  accentColor: AppColors.primaryLight,
                                  child: _buildSoftTextField(
                                    controller: _nameController,
                                    hintText: 'e.g. Denim H',
                                    icon: Icons.account_circle_outlined,
                                  ),
                                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),
                                const SizedBox(height: 16),
                                _buildStepCard(
                                  stepNumber: '02',
                                  stepTitle: 'LOCAL BHOPAL RESIDENCE / PG / HOSTEL',
                                  icon: Icons.home_work_rounded,
                                  accentColor: AppColors.accent,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSoftTextField(
                                        controller: _localAddressController,
                                        hintText: 'e.g. 347/2, Shakti Nagar, Bhopal',
                                        icon: Icons.location_city_rounded,
                                      ),
                                      const SizedBox(height: 12),
                                      _buildGPSButton(),
                                      if (_locationStatusText != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _locationStatusText!,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppColors.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      Text(
                                        'Or tap your Bhopal residential hub:',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildHubPills(),
                                    ],
                                  ),
                                ).animate().fadeIn(duration: 350.ms, delay: 80.ms).slideY(begin: 0.06, end: 0),
                                if (_recommendedStops.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  _buildRecommendedStopsCard()
                                      .animate()
                                      .fadeIn(duration: 400.ms)
                                      .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1)),
                                ],
                                const SizedBox(height: 16),
                                _buildStepCard(
                                  stepNumber: '03',
                                  stepTitle: 'CONFIRM DAILY BUS ROUTE',
                                  icon: Icons.directions_bus_rounded,
                                  accentColor: AppColors.primary,
                                  child: _buildRouteSelector(),
                                ).animate().fadeIn(duration: 400.ms, delay: 140.ms).slideY(begin: 0.06, end: 0),
                                const SizedBox(height: 16),
                                _buildStepCard(
                                  stepNumber: '04',
                                  stepTitle: 'CONFIRM PICKUP STOP',
                                  icon: Icons.pin_drop_rounded,
                                  accentColor: AppColors.accentGreen,
                                  child: _buildStopSelector(),
                                ).animate().fadeIn(duration: 450.ms, delay: 200.ms).slideY(begin: 0.06, end: 0),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        _buildBottomActionBar(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!widget.isInitialSetup)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 40),
          TextButton(
            onPressed: _skipToDashboard,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isInitialSetup ? 'Skip for now' : 'Cancel',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.explore_rounded, color: Colors.white, size: 28),
          ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms),
          const SizedBox(height: 14),
          Text(
            'Local Commute Setup',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Link your Bhopal residence, PG, or hostel to discover the nearest bus stop and schedule alerts.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required String stepTitle,
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111726).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor.withValues(alpha: 0.3), accentColor.withValues(alpha: 0.1)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  stepNumber,
                  style: GoogleFonts.plusJakartaSans(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stepTitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSoftTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
          prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildGPSButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isLocating ? null : _detectGPSLocation,
        icon: _isLocating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              )
            : const Icon(Icons.my_location_rounded, size: 16, color: AppColors.accent),
        label: Text(
          _isLocating ? 'Detecting GPS Coordinates...' : 'Use Current GPS Location',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.accent.withValues(alpha: 0.08),
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildHubPills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _bhopalHubs.map((hub) {
          final isSelected = _selectedHubName == hub['name'];
          final IconData iconData = hub['icon'] as IconData;
          final Color hubColor = hub['color'] as Color;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => _selectHub(hub),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? hubColor.withValues(alpha: 0.18)
                      : const Color(0xFF141D2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? hubColor : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: (isSelected ? hubColor : Colors.white).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        iconData,
                        size: 13,
                        color: isSelected ? hubColor : Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      hub['name'] as String,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecommendedStopsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E24).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGreen.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.accentGreen, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'RECOMMENDED NEAREST STOPS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accentGreen,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: _recommendedStops.map((rec) {
              final route = rec['route'] as RouteModel;
              final stopName = rec['stopName'] as String;
              final distText = rec['distanceText'] as String;
              final isSelected = _selectedRoute?.id == route.id && _selectedStop == stopName;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accentGreen.withValues(alpha: 0.15) : const Color(0xFF142930),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSelected ? Icons.check_rounded : Icons.location_pin,
                      color: isSelected ? Colors.white : AppColors.accentGreen,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    stopName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${route.name} • $distText',
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? AppColors.accentGreen : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isSelected ? 'Selected' : 'Use This',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedRoute = route;
                      _selectedStop = stopName;
                    });
                    HapticFeedback.selectionClick();
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RouteModel>(
          value: _selectedRoute,
          isExpanded: true,
          dropdownColor: const Color(0xFF141C2E),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryLight),
          items: _routes.map((route) {
            return DropdownMenuItem<RouteModel>(
              value: route,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.directions_bus_rounded, color: AppColors.primaryLight, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      route.name,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newRoute) {
            if (newRoute != null) {
              setState(() {
                _selectedRoute = newRoute;
                _selectedStop = newRoute.stops.isNotEmpty ? newRoute.stops.first['name'] : null;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildStopSelector() {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'No stops found on this route.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    final hasStop = _selectedRoute!.stops.any((s) => s['name'] == _selectedStop);
    final currentValue = hasStop ? _selectedStop : _selectedRoute!.stops.first['name'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: const Color(0xFF141C2E),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.accentGreen),
          items: _selectedRoute!.stops.map((stop) {
            final String stopName = stop['name']?.toString() ?? '';
            return DropdownMenuItem<String>(
              value: stopName,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.pin_drop_rounded, color: AppColors.accentGreen, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stopName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (newStop) {
            setState(() => _selectedStop = newStop);
          },
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveCommuteSetup,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'CONFIRM & START TRACKING',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
