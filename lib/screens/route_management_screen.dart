import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import 'route_edit_screen.dart';

class RouteManagementScreen extends StatefulWidget {
  final bool nested;
  const RouteManagementScreen({super.key, this.nested = false});

  @override
  State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}

class _RouteManagementScreenState extends State<RouteManagementScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.get('routes');
      if (mounted) {
        setState(() {
          _routes = response is List ? response : [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _routes = [];
        });
      }
    }
  }

  Color _parseColor(String? hexString) {
    if (hexString == null) return const Color(0xFF06B6D4);
    try {
      final clean = hexString.replaceAll('#', '').trim();
      if (clean.length == 6) return Color(int.parse('0xFF$clean'));
      if (clean.length == 8) return Color(int.parse('0x$clean'));
    } catch (_) {}
    return const Color(0xFF06B6D4);
  }

  Future<void> _deleteRoute(String id, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131D33),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: Text(
          'Delete Route',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'Are you sure you want to delete "$name"? Buses assigned to this route will become unassigned.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.delete('manager/routes/$id');
      _fetchRoutes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route "$name" deleted', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF131D33),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete route: $e', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAddRouteDialog() {
    final nameController = TextEditingController();
    final colorController = TextEditingController(text: '#06B6D4');
    
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF131D33),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF00F0FF), width: 1.2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00F0FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_road_rounded, color: Color(0xFF00F0FF), size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Add New Route',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Route Name',
                  hintText: 'e.g. Ashoka Garden Route 18',
                  hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12),
                  labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF00F0FF), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: colorController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Color Accent (Hex)',
                  hintText: '#06B6D4',
                  labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF00F0FF), width: 1.5),
                  ),
                  prefixIcon: const Icon(Icons.palette_rounded, color: Colors.white38, size: 20),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                try {
                  await _apiService.post('manager/routes', {
                    'name': nameController.text.trim(),
                    'color': colorController.text.trim(),
                    'stops': [],
                  });
                  if (dialogCtx.mounted) {
                    Navigator.of(dialogCtx).pop();
                  }
                  _fetchRoutes();
                } catch (_) {}
              }
            },
            child: Text('Create Route', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalStopsAcrossRoutes = 0;
    for (final r in _routes) {
      if (r['stops'] is List) totalStopsAcrossRoutes += (r['stops'] as List).length;
    }

    return Scaffold(
      backgroundColor: widget.nested ? Colors.transparent : const Color(0xFF090D16),
      appBar: widget.nested
          ? null
          : AppBar(
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
                    'Campus Bus Routes',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    '${_routes.length} Active Routes • $totalStopsAcrossRoutes Stops',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF00F0FF), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Add New Route',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F0FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.add_rounded, color: Color(0xFF00F0FF), size: 18),
                  ),
                  onPressed: _showAddRouteDialog,
                ),
                const SizedBox(width: 8),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRouteDialog,
        backgroundColor: const Color(0xFF00F0FF),
        foregroundColor: Colors.black,
        elevation: 6,
        icon: const Icon(Icons.add_road_rounded, size: 20),
        label: Text('New Route', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
        : _routes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.alt_route_rounded, color: Colors.white24, size: 50),
                  const SizedBox(height: 14),
                  Text('NO CAMPUS ROUTES FOUND', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Create First Route', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                    onPressed: _showAddRouteDialog,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF00F0FF),
              backgroundColor: const Color(0xFF131D33),
              onRefresh: _fetchRoutes,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _routes.length,
                itemBuilder: (context, index) {
                  final route = _routes[index];
                  final color = _parseColor(route['color']);
                  final List stops = route['stops'] is List ? (route['stops'] as List) : [];
                  final String name = route['name'] ?? 'Transit Route';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131D33),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => RouteEditScreen(route: route)),
                          );
                          if (result == true) _fetchRoutes();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              // Route Color Icon Badge
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: color.withOpacity(0.4)),
                                ),
                                child: Icon(Icons.directions_bus_filled_rounded, color: color, size: 24),
                              ),
                              const SizedBox(width: 14),
                              
                              // Route Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${stops.length} Waypoint Stops',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Edit Action
                              IconButton(
                                icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF00F0FF), size: 24),
                                tooltip: 'Edit Waypoints',
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => RouteEditScreen(route: route)),
                                  );
                                  if (result == true) _fetchRoutes();
                                },
                              ),

                              // Delete Action
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                tooltip: 'Delete Route',
                                onPressed: () => _deleteRoute(route['_id'], name),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: (index * 40).ms).slideX(begin: 0.04);
                },
              ),
            ),
    );
  }
}
