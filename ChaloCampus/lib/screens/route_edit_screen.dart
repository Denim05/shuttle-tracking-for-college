import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.route['name'] ?? '');
    _colorController = TextEditingController(text: widget.route['color'] ?? '#2D5BFF');
    
    // Copy the stops safely to avoid modifying the original until saved
    final rawStops = widget.route['stops'] as List? ?? [];
    _stops = rawStops.map<Map<String, dynamic>>((s) {
      return {
        'name': s['name']?.toString() ?? '',
        'lat': (s['lat'] ?? 0.0).toDouble(),
        'lng': (s['lng'] ?? 0.0).toDouble(),
      };
    }).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _addStop() {
    setState(() {
      _stops.add({
        'name': 'New Stop ${_stops.length + 1}',
        'lat': 23.2599, // default Bhopal coords
        'lng': 77.4126,
      });
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
    });
  }

  void _swapStops(int i, int j) {
    if (i < 0 || i >= _stops.length || j < 0 || j >= _stops.length) return;
    setState(() {
      final temp = _stops[i];
      _stops[i] = _stops[j];
      _stops[j] = temp;
    });
  }

  Future<void> _saveRoute() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Route name cannot be empty', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Route changes saved successfully!', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true); // return true to indicate changes were saved
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save route: $e', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
    return Colors.blueAccent;
  }

  @override
  Widget build(BuildContext context) {
    final parsedColor = _getParsedColor();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Edit Route Configuration',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2))
              : const Icon(Icons.save_rounded, color: Colors.blueAccent),
            onPressed: _isSaving ? null : _saveRoute,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ─── Header Configuration Card ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: parsedColor.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(color: parsedColor.withOpacity(0.03), blurRadius: 20, spreadRadius: 2),
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: parsedColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: parsedColor.withOpacity(0.2)),
                        ),
                        child: Icon(Icons.route_rounded, color: parsedColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CORE METRICS', style: GoogleFonts.plusJakartaSans(color: parsedColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          Text('Configure Identity', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Route Name Field
                  TextField(
                    controller: _nameController,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    decoration: InputDecoration(
                      labelText: 'ROUTE NAME',
                      labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: parsedColor.withOpacity(0.5)),
                      ),
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Route Color Field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _colorController,
                          onChanged: (_) => setState(() {}), // refresh picker color preview
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'THEMATIC COLOR (HEX)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(16)),
                              borderSide: BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(16)),
                              borderSide: BorderSide(color: parsedColor.withOpacity(0.5)),
                            ),
                            prefixIcon: const Icon(Icons.palette_rounded, color: Colors.white38),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Color preview dot
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: parsedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                          boxShadow: [
                            BoxShadow(color: parsedColor.withOpacity(0.3), blurRadius: 10, spreadRadius: 1)
                          ]
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.1),
          ),
          
          // ─── Stops Header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STOPS & COORDINATES',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Define the waypoint sequence for this route',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: parsedColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: parsedColor.withOpacity(0.2)),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.add_location_alt_rounded, color: parsedColor, size: 20),
                      onPressed: _addStop,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // ─── Stops List View ────────────────────────────────────────────────
          if (_stops.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.add_road_rounded, color: Colors.white24, size: 40),
                      const SizedBox(height: 12),
                      Text('NO WAYPOINTS CONFIGURED', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.add, color: Colors.blueAccent),
                        label: Text('Add First Waypoint', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                        onPressed: _addStop,
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final stop = _stops[index];
                    final String name = stop['name'] ?? '';
                    final double lat = stop['lat'] ?? 0.0;
                    final double lng = stop['lng'] ?? 0.0;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Index Circle / Reordering Indicators
                          Column(
                            children: [
                              GestureDetector(
                                onTap: index > 0 ? () => _swapStops(index, index - 1) : null,
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded, 
                                  color: index > 0 ? Colors.white30 : Colors.white12,
                                  size: 22
                                ),
                              ),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: parsedColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: parsedColor.withOpacity(0.2)),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: GoogleFonts.plusJakartaSans(color: parsedColor, fontSize: 12, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: index < _stops.length - 1 ? () => _swapStops(index, index + 1) : null,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded, 
                                  color: index < _stops.length - 1 ? Colors.white30 : Colors.white12,
                                  size: 22
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          
                          // Form Inputs
                          Expanded(
                            child: Column(
                              children: [
                                // Stop Name Input
                                TextFormField(
                                  initialValue: name,
                                  onChanged: (val) => stop['name'] = val,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: 'STOP NAME',
                                    labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: parsedColor.withOpacity(0.5))),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                
                                // Lat/Lng side-by-side
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: lat.toString(),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        onChanged: (val) => stop['lat'] = double.tryParse(val) ?? 0.0,
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
                                        decoration: InputDecoration(
                                          labelText: 'LATITUDE',
                                          labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: parsedColor.withOpacity(0.3))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: lng.toString(),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        onChanged: (val) => stop['lng'] = double.tryParse(val) ?? 0.0,
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
                                        decoration: InputDecoration(
                                          labelText: 'LONGITUDE',
                                          labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: parsedColor.withOpacity(0.3))),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          
                          // Delete Option
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () => _removeStop(index),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: (index * 40).ms).slideX(begin: 0.1);
                  },
                  childCount: _stops.length,
                ),
              ),
            ),
          
          const SliverToBoxAdapter(
            child: SizedBox(height: 50),
          )
        ],
      ),
    );
  }
}
