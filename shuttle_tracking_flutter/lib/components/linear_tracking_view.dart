import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';

class LinearTrackingView extends StatelessWidget {
  final Bus bus;
  final RouteModel route;

  const LinearTrackingView({
    super.key,
    required this.bus,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(int.parse(route.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: Color(int.parse(route.color.replaceAll('#', '0xFF'))),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.name,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Bus #${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF38ef7d).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.3)),
                ),
                child: Text(
                  bus.status,
                  style: const TextStyle(color: Color(0xFF38ef7d), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Linear Progress Line
          Stack(
            children: [
              // Background Line
              Container(
                height: 4,
                width: double.infinity,
                margin: const EdgeInsets.only(top: 18),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Stops
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: route.stops.map((stop) {
                  return Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white24,
                          border: Border.all(color: Colors.white12, width: 2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 60,
                        child: Text(
                          stop['name'] ?? '',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              
              // Bus Position Marker (Animated would be better, but keeping it simple for now)
              // In a real app, you'd calculate the percentage along the route
              const Positioned(
                left: 0, // Should be calculated based on bus.currentLat/Lng vs stops
                top: 0,
                child: Column(
                  children: [
                    Icon(Icons.location_on, color: Color(0xFF38ef7d), size: 28),
                    SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
