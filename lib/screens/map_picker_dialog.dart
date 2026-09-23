import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

class MapPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String stopName;
  final Color themeColor;

  const MapPickerDialog({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.stopName,
    this.themeColor = const Color(0xFF06B6D4),
  });

  @override
  State<MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<MapPickerDialog> {
  late LatLng _selectedLocation;
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isSearching = false;
  bool _isFetchingGps = false;

  // Curated prominent landmarks in Bhopal and SISTec Campuses
  static const List<Map<String, dynamic>> _quickLandmarks = [
    {'name': 'SISTec Ratibad', 'lat': 23.180302, 'lng': 77.302695},
    {'name': 'SISTec Gandhi Nagar', 'lat': 23.30825, 'lng': 77.34852},
    {'name': 'MP Nagar Zone 1', 'lat': 23.23321, 'lng': 77.43512},
    {'name': 'Lalghati', 'lat': 23.27350, 'lng': 77.37880},
    {'name': 'ISBT Habibganj', 'lat': 23.21850, 'lng': 77.43850},
    {'name': 'Bhopal Station', 'lat': 23.26860, 'lng': 77.41260},
    {'name': 'Roshanpura', 'lat': 23.23845, 'lng': 77.40150},
    {'name': 'Jawahar Chowk', 'lat': 23.23360, 'lng': 77.39820},
    {'name': 'Karond Mandi', 'lat': 23.29860, 'lng': 77.40220},
    {'name': 'Ashoka Garden', 'lat': 23.26460, 'lng': 77.43120},
  ];

  @override
  void initState() {
    super.initState();
    final double validLat = (widget.initialLat != 0.0) ? widget.initialLat : 23.2599;
    final double validLng = (widget.initialLng != 0.0) ? widget.initialLng : 77.4126;
    _selectedLocation = LatLng(validLat, validLng);
    _searchController.text = widget.stopName;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _selectedLocation = position;
    });
  }

  // ─── 1-Tap Capture Live GPS from Phone ──────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() => _isFetchingGps = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showToast('Location permission is required to capture GPS.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showToast('Please enable Location permissions in device settings.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _selectedLocation = newPos;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newPos, 16.5));
      _showToast('📍 Pinned your live GPS location!');
    } catch (e) {
      _showToast('Could not get GPS location: $e');
    } finally {
      if (mounted) setState(() => _isFetchingGps = false);
    }
  }

  // ─── Instant Landmark / Stop Name Search ────────────────────────────────
  Future<void> _searchPlace(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    // First check quick local landmark dictionary
    for (final lm in _quickLandmarks) {
      if (lm['name'].toString().toLowerCase().contains(clean.toLowerCase())) {
        final pos = LatLng(lm['lat'], lm['lng']);
        setState(() => _selectedLocation = pos);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16.0));
        return;
      }
    }

    // Call backend geocoding service
    setState(() => _isSearching = true);
    try {
      final res = await _apiService.get('routes/geocode-stop?name=${Uri.encodeComponent(clean)}');
      if (res != null && res['lat'] != null && res['lng'] != null) {
        final double lat = (res['lat'] as num).toDouble();
        final double lng = (res['lng'] as num).toDouble();
        final pos = LatLng(lat, lng);
        setState(() => _selectedLocation = pos);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16.0));
        _showToast('Found location for "$clean"');
      } else {
        _showToast('No exact landmark match found. You can tap on the map to pin.');
      }
    } catch (_) {
      _showToast('Search unavailable. Please pin directly on the map.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: const Color(0xFF131D33),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: widget.themeColor.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 35,
              spreadRadius: 6,
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Header Bar ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.themeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.pin_drop_rounded, color: widget.themeColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SET EXACT STOP LOCATION',
                              style: GoogleFonts.plusJakartaSans(
                                color: widget.themeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              widget.stopName.isNotEmpty ? widget.stopName : 'Pin Stop Position',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Live Search & GPS Tag Bar ─────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                            textInputAction: TextInputAction.search,
                            onSubmitted: _searchPlace,
                            decoration: InputDecoration(
                              hintText: 'Search place, square, or landmark...',
                              hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                              prefixIcon: _isSearching
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: widget.themeColor),
                                      ),
                                    )
                                  : Icon(Icons.search_rounded, color: widget.themeColor, size: 18),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // GPS Button
                      InkWell(
                        onTap: _isFetchingGps ? null : _useCurrentLocation,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              _isFetchingGps
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                    )
                                  : const Icon(Icons.my_location_rounded, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'My GPS',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF10B981),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Quick Landmark Chips Carousel ─────────────────
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _quickLandmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (ctx, i) {
                        final lm = _quickLandmarks[i];
                        return GestureDetector(
                          onTap: () {
                            final pos = LatLng(lm['lat'], lm['lng']);
                            setState(() {
                              _selectedLocation = pos;
                              _searchController.text = lm['name'];
                            });
                            _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16.0));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              lm['name'],
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Interactive Google Map ──────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedLocation,
                      zoom: 15.0,
                    ),
                    onMapCreated: (controller) => _mapController = controller,
                    onTap: _onMapTapped,
                    markers: {
                      Marker(
                        markerId: const MarkerId('picked_stop_marker'),
                        position: _selectedLocation,
                        draggable: true,
                        onDragEnd: (newPos) => setState(() => _selectedLocation = newPos),
                        infoWindow: InfoWindow(title: widget.stopName),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                      )
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),

                  // Helper Instruction Pill
                  Positioned(
                    bottom: 12,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_rounded, color: widget.themeColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap anywhere or drag the cyan pin to adjust stop position',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Footer Coordinate Display & Confirm Button ──────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _coordBadge('LATITUDE', _selectedLocation.latitude.toStringAsFixed(6)),
                      const SizedBox(width: 10),
                      _coordBadge('LONGITUDE', _selectedLocation.longitude.toStringAsFixed(6)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: Text(
                        'Confirm Stop Location',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context, _selectedLocation);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack, duration: 250.ms);
  }

  Widget _coordBadge(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
