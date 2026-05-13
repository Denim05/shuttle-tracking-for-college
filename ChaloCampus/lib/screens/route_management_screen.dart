import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

class RouteManagementScreen extends StatefulWidget {
  const RouteManagementScreen({super.key});

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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _routes = [];
        });
      }
    }
  }

  Future<void> _deleteRoute(String id) async {
    try {
      await _apiService.delete('manager/routes/$id');
      _fetchRoutes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Route deleted', style: GoogleFonts.plusJakartaSans())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete route', style: GoogleFonts.plusJakartaSans())),
        );
      }
    }
  }

  void _showAddRouteDialog() {
    final nameController = TextEditingController();
    final colorController = TextEditingController(text: '#2D5BFF');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Add New Route', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Route Name',
                labelStyle: const TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: colorController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Color (Hex)',
                labelStyle: const TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  await _apiService.post('manager/routes', {
                    'name': nameController.text,
                    'color': colorController.text,
                    'stops': [],
                  });
                  Navigator.pop(context);
                  _fetchRoutes();
                } catch (e) {
                  // error
                }
              }
            },
            child: Text('Add', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Route Management', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blueAccent),
            onPressed: _showAddRouteDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : _routes.isEmpty
          ? Center(child: Text('No routes found', style: GoogleFonts.plusJakartaSans(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _routes.length,
              itemBuilder: (context, index) {
                final route = _routes[index];
                final color = Color(int.parse(route['color'].replaceAll('#', '0xFF')));
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: color.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.route_rounded, color: color, size: 28),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route['name'] ?? 'Unknown Route',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            Text(
                              '${(route['stops'] as List).length} Stops',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        onPressed: () => _deleteRoute(route['_id']),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
              },
            ),
    );
  }
}
