import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../utils/map_math.dart';
import 'package:latlong2/latlong.dart';

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
    final routeColor = Color(int.parse(route.color.replaceAll('#', '0xFF')));
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1219),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: routeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: routeColor.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.directions_bus_filled_rounded, color: routeColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'BUS TERMINAL ID: #${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${bus.speed.toInt()}',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'KM/H',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          // Linear Progress Line
          LayoutBuilder(
            builder: (context, constraints) {
              const double minWidthPerStop = 100.0;
              final double itemsWidth = route.stops.length * minWidthPerStop;
              final bool needsScroll = itemsWidth > constraints.maxWidth;
              final double stopWidth = needsScroll ? minWidthPerStop : (constraints.maxWidth / route.stops.length);
              final double paddingX = stopWidth / 2;
              final List<LatLng> routePoints = route.coordinates.map((c) => LatLng(c['latitude']!, c['longitude']!)).toList();
              final double progress = MapMath.calculateRouteProgress(LatLng(bus.currentLat, bus.currentLng), routePoints);
              
              Widget content = Stack(
                clipBehavior: Clip.none,
                children: [
                  // Background Line
                  Positioned(
                    top: 24,
                    left: paddingX,
                    right: paddingX,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Active Progress Line
                  Positioned(
                    top: 24,
                    left: paddingX,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      width: stopWidth * (route.stops.length - 1) * progress,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [routeColor, routeColor.withValues(alpha: 0.5)]),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [BoxShadow(color: routeColor.withValues(alpha: 0.3), blurRadius: 10)],
                      ),
                    ),
                  ),
                  
                  // Stops
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: route.stops.asMap().entries.map((entry) {
                      final bool isVisited = (entry.key / (route.stops.length - 1)) <= progress;
                      return SizedBox(
                        width: stopWidth,
                        child: Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              margin: const EdgeInsets.only(top: 19),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isVisited ? routeColor : const Color(0xFF0F1219),
                                border: Border.all(
                                  color: isVisited ? routeColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1), 
                                  width: 3
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text(
                                entry.value['name'] ?? '',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: isVisited ? FontWeight.bold : FontWeight.normal,
                                  color: isVisited ? Colors.white : Colors.white38,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  
                  // Bus Position Marker
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 800),
                    left: paddingX + (stopWidth * (route.stops.length - 1) * progress) - 15,
                    top: 0,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F0FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: const Color(0xFF00F0FF).withValues(alpha: 0.5), blurRadius: 15)],
                          ),
                          child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.black, size: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              );


              if (needsScroll) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  child: SizedBox(
                    width: itemsWidth,
                    child: content,
                  ),
                );
              }

              return SizedBox(
                width: constraints.maxWidth,
                child: content,
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
