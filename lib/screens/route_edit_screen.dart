import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import 'map_picker_dialog.dart';

class RouteEditScreen extends StatefulWidget {
  final Map<String, dynamic> route;
  
  const RouteEditScreen({super.key, required this.route});

  @override
  State<RouteEditScreen> createState() => _RouteEditScreenState();
}

class _RouteEditScreenState extends State<RouteEditScreen> {
  final ApiService _apiService = ApiService();
  late TextEditingController _nameController;
  late TextEditingController _colorController;
  late List<Map<String, dynamic>> _stops;
  final List<TextEditingController> _stopNameControllers = [];
  final List<TextEditingController> _latControllers = [];
  final List<TextEditingController> _lngControllers = [];
  
  bool _isSaving = false;
  bool _isBatchGeocoding = false;
  int? _geocodingIndex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.route['name'] ?? '');
    _colorController = TextEditingController(text: widget.route['color'] ?? '#06B6D4');
    
    final rawStops = widget.route['stops'] as List? ?? [];
    _stops = rawStops.map<Map<String, dynamic>>((s) {
      return {
        'name': s['name']?.toString() ?? '',
        'lat': (s['lat'] ?? 0.0).toDouble(),
        'lng': (s['lng'] ?? 0.0).toDouble(),
      };
    }).toList();

    _initControllers();
  }

  void _initControllers() {
    _stopNameControllers.clear();
    _latControllers.clear();
    _lngControllers.clear();

    for (final stop in _stops) {
      _stopNameControllers.add(TextEditingController(text: stop['name'] ?? ''));
      final double lat = (stop['lat'] ?? 0.0).toDouble();
      final double lng = (stop['lng'] ?? 0.0).toDouble();
      _latControllers.add(TextEditingController(text: lat != 0.0 ? lat.toStringAsFixed(5) : ''));
      _lngControllers.add(TextEditingController(text: lng != 0.0 ? lng.toStringAsFixed(5) : ''));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    for (final c in _stopNameControllers) { c.dispose(); }
    for (final c in _latControllers) { c.dispose(); }
    for (final c in _lngControllers) { c.dispose(); }
    super.dispose();
  }

  void _addStop() {
    setState(() {
      _stops.add({
        'name': 'Stop ${_stops.length + 1}',
        'lat': 0.0,
        'lng': 0.0,
      });
      _stopNameControllers.add(TextEditingController(text: 'Stop ${_stops.length}'));
      _latControllers.add(TextEditingController(text: ''));
      _lngControllers.add(TextEditingController(text: ''));
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
      _stopNameControllers[index].dispose();
      _stopNameControllers.removeAt(index);
      _latControllers[index].dispose();
      _latControllers.removeAt(index);
      _lngControllers[index].dispose();
      _lngControllers.removeAt(index);
    });
  }

  void _swapStops(int i, int j) {
    if (i < 0 || i >= _stops.length || j < 0 || j >= _stops.length) return;
    setState(() {
      final tempStop = _stops[i];
      _stops[i] = _stops[j];
      _stops[j] = tempStop;

      final tempName = _stopNameControllers[i].text;
      _stopNameControllers[i].text = _stopNameControllers[j].text;
      _stopNameControllers[j].text = tempName;

      final tempLat = _latControllers[i].text;
      _latControllers[i].text = _latControllers[j].text;
      _latControllers[j].text = tempLat;

      final tempLng = _lngControllers[i].text;
      _lngControllers[i].text = _lngControllers[j].text;
      _lngControllers[j].text = tempLng;
    });
  }

  // ─── Automated Geocoding for a Single Stop ─────────────────────────────────
  Future<void> _autoGeocodeStop(int index) async {
    final String stopName = _stopNameControllers[index].text.trim();
    if (stopName.isEmpty) {
      _showCustomSnackBar('Please enter a stop name first', isError: true);
      return;
    }

    setState(() => _geocodingIndex = index);

    try {
      final response = await _apiService.get('routes/geocode-stop?name=${Uri.encodeComponent(stopName)}');
      if (response != null && response['lat'] != null && response['lng'] != null) {
        final double lat = (response['lat'] as num).toDouble();
        final double lng = (response['lng'] as num).toDouble();

        setState(() {
          _stops[index]['lat'] = lat;
          _stops[index]['lng'] = lng;
          _latControllers[index].text = lat.toStringAsFixed(5);
          _lngControllers[index].text = lng.toStringAsFixed(5);
        });

        _showCustomSnackBar('Pinned "$stopName" to ($lat, $lng)', isSuccess: true);
      }
    } catch (e) {
      _showCustomSnackBar('Failed to auto-geocode "$stopName": $e', isError: true);
    } finally {
      if (mounted) setState(() => _geocodingIndex = null);
    }
  }

  // ─── Bulk Auto-Geocode All Stops in Route ──────────────────────────────────
  Future<void> _autoGeocodeAllStops() async {
    if (_stops.isEmpty) return;

    setState(() => _isBatchGeocoding = true);
    int resolvedCount = 0;

    for (int i = 0; i < _stops.length; i++) {
      final String stopName = _stopNameControllers[i].text.trim();
      if (stopName.isEmpty) continue;

      try {
        final response = await _apiService.get('routes/geocode-stop?name=${Uri.encodeComponent(stopName)}');
        if (response != null && response['lat'] != null && response['lng'] != null) {
          final double lat = (response['lat'] as num).toDouble();
          final double lng = (response['lng'] as num).toDouble();

          setState(() {
            _stops[i]['lat'] = lat;
            _stops[i]['lng'] = lng;
            _latControllers[i].text = lat.toStringAsFixed(5);
            _lngControllers[i].text = lng.toStringAsFixed(5);
          });
          resolvedCount++;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isBatchGeocoding = false);
      _showCustomSnackBar('Auto-geocoded $resolvedCount / ${_stops.length} stops', isSuccess: true);
    }
  }

  // ─── Interactive Map Picker ───────────────────────────────────────────────
  Future<void> _pickOnMap(int index) async {
    final double curLat = double.tryParse(_latControllers[index].text) ?? (_stops[index]['lat'] ?? 0.0);
    final double curLng = double.tryParse(_lngControllers[index].text) ?? (_stops[index]['lng'] ?? 0.0);
    final String stopName = _stopNameControllers[index].text.trim();

    final LatLng? picked = await showDialog<LatLng>(
      context: context,
      builder: (ctx) => MapPickerDialog(
        initialLat: curLat,
        initialLng: curLng,
        stopName: stopName,
        themeColor: _getParsedColor(),
      ),
    );

    if (picked != null) {
      setState(() {
        _stops[index]['lat'] = picked.latitude;
        _stops[index]['lng'] = picked.longitude;
        _latControllers[index].text = picked.latitude.toStringAsFixed(5);
        _lngControllers[index].text = picked.longitude.toStringAsFixed(5);
      });
      _showCustomSnackBar('Position updated for "${_stopNameControllers[index].text}"', isSuccess: true);
    }
  }

  // ─── Save Route ───────────────────────────────────────────────────────────
  Future<void> _saveRoute() async {
    if (_nameController.text.trim().isEmpty) {
      _showCustomSnackBar('Route name cannot be empty', isError: true);
      return;
    }

    for (int i = 0; i < _stops.length; i++) {
      _stops[i]['name'] = _stopNameControllers[i].text.trim();
      _stops[i]['lat'] = double.tryParse(_latControllers[i].text) ?? 0.0;
      _stops[i]['lng'] = double.tryParse(_lngControllers[i].text) ?? 0.0;
    }

    setState(() => _isSaving = true);
    
    try {
      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'color': _colorController.text.trim(),
        'stops': _stops,
      };

      await _apiService.put('manager/routes/${widget.route['_id']}', data);

      if (!mounted) return;
      _showCustomSnackBar('Route & waypoints saved successfully!', isSuccess: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar('Failed to save route: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showCustomSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: isError ? Colors.redAccent : const Color(0xFF00F0FF),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF131D33),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isError ? Colors.redAccent.withOpacity(0.4) : const Color(0xFF00F0FF).withOpacity(0.3)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Color _getParsedColor() {
    try {
      final colorStr = _colorController.text.trim().replaceAll('#', '');
      if (colorStr.length == 6) {
        return Color(int.parse('0xFF$colorStr'));
      } else if (colorStr.length == 8) {
        return Color(int.parse('0x$colorStr'));
      }
    } catch (_) {}
    return const Color(0xFF06B6D4);
  }

  @override
  Widget build(BuildContext context) {
    final parsedColor = _getParsedColor();
    final int configuredStopsCount = _stops.where((s) => (s['lat'] ?? 0.0) != 0.0 && (s['lng'] ?? 0.0) != 0.0).length;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit Route',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Text(
              '${_stops.length} Stops • $configuredStopsCount Pinned',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: parsedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          // Auto-Geocode All Button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00F0FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
            ),
            child: IconButton(
              tooltip: 'Auto-Geocode All Stops',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              icon: _isBatchGeocoding 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF00F0FF), strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F0FF), size: 18),
              onPressed: (_isBatchGeocoding || _isSaving) ? null : _autoGeocodeAllStops,
            ),
          ),
          
          // Save Button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: IconButton(
              tooltip: 'Save Changes',
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
              icon: _isSaving 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_rounded, color: Colors.white, size: 22),
              onPressed: (_isSaving || _isBatchGeocoding) ? null : _saveRoute,
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ─── Route Identity Card ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF131D33),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: parsedColor.withOpacity(0.25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: parsedColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.alt_route_rounded, color: parsedColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ROUTE CONFIGURATION',
                              style: GoogleFonts.plusJakartaSans(
                                color: parsedColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Identity & Theme Color',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Route Name Field
                  TextField(
                    controller: _nameController,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Route Name',
                      labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: parsedColor.withOpacity(0.6), width: 1.5),
                      ),
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.white38, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Route Color Picker
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _colorController,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Hex Color Accent',
                            labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: parsedColor.withOpacity(0.6), width: 1.5),
                            ),
                            prefixIcon: const Icon(Icons.palette_rounded, color: Colors.white38, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: parsedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                          boxShadow: [
                            BoxShadow(color: parsedColor.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.05),
          ),
          
          // ─── Waypoints Section Header (Flexible & Overflow-Free) ───────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WAYPOINTS & STOPS',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Sequence & accurate coordinates',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Add Waypoint Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: parsedColor.withOpacity(0.15),
                      foregroundColor: parsedColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: parsedColor.withOpacity(0.3)),
                      ),
                    ),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                    label: Text(
                      'Add Stop',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: _addStop,
                  ),
                ],
              ),
            ),
          ),
          
          // ─── Stops Waypoint List ───────────────────────────────────────────
          if (_stops.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D33),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.add_road_rounded, color: Colors.white24, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        'NO WAYPOINTS CONFIGURED',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F0FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Add First Waypoint', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: _addStop,
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final bool isGeocodingThis = _geocodingIndex == index;
                    final double lat = double.tryParse(_latControllers[index].text) ?? 0.0;
                    final double lng = double.tryParse(_lngControllers[index].text) ?? 0.0;
                    final bool hasCoords = lat != 0.0 && lng != 0.0;
                    final bool isFirst = index == 0;
                    final bool isLast = index == _stops.length - 1;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131D33),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: hasCoords ? Colors.white.withOpacity(0.08) : Colors.amber.withOpacity(0.4),
                          width: hasCoords ? 1 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Top Row: Reorder Handles + Stop Name + Delete ───
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Sequence Number Badge with Up/Down Controls
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isFirst)
                                    GestureDetector(
                                      onTap: () => _swapStops(index, index - 1),
                                      child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 18),
                                    )
                                  else
                                    const SizedBox(height: 6),
                                  
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: parsedColor.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: parsedColor.withOpacity(0.35)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: parsedColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (!isLast)
                                    GestureDetector(
                                      onTap: () => _swapStops(index, index + 1),
                                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 18),
                                    )
                                  else
                                    const SizedBox(height: 6),
                                ],
                              ),
                              const SizedBox(width: 12),
                              
                              // Stop Name Input
                              Expanded(
                                child: TextFormField(
                                  controller: _stopNameControllers[index],
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: isFirst ? 'START WAYPOINT' : isLast ? 'FINAL TERMINUS' : 'WAYPOINT STOP',
                                    labelStyle: GoogleFonts.plusJakartaSans(
                                      color: isFirst ? const Color(0xFF10B981) : isLast ? const Color(0xFFEF4444) : Colors.white38,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: parsedColor.withOpacity(0.7))),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              
                              // Delete Button
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () => _removeStop(index),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),

                          // ── Middle Row: Coordinate Status / Readout ─────────
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasCoords ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                  color: hasCoords ? const Color(0xFF10B981) : Colors.amber,
                                  size: 15,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hasCoords 
                                      ? '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})' 
                                      : 'Coordinates unpinned (tap auto-geocode or map)',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: hasCoords ? Colors.white70 : Colors.amber.shade200,
                                      fontSize: 11,
                                      fontWeight: hasCoords ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // ── Bottom Action Row: Auto-Geocode & Map Picker ───
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // 1-Tap Auto-Geocode Action
                              InkWell(
                                onTap: isGeocodingThis ? null : () => _autoGeocodeStop(index),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F0FF).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isGeocodingThis)
                                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Color(0xFF00F0FF), strokeWidth: 1.5))
                                      else
                                        const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF00F0FF), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Auto-Geocode',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: const Color(0xFF00F0FF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Pick on Map Action
                              InkWell(
                                onTap: () => _pickOnMap(index),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.map_rounded, color: Color(0xFF10B981), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Pick on Map',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: const Color(0xFF10B981),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: (index * 25).ms).slideX(begin: 0.04);
                  },
                  childCount: _stops.length,
                ),
              ),
            ),
          
          const SliverToBoxAdapter(
            child: SizedBox(height: 60),
          )
        ],
      ),
    );
  }
}
