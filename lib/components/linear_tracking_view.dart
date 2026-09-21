import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.alt_route_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROUTE PROGRESS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TERMINAL BUS #${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${bus.speed.toInt()}',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'KM/H',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
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
                        color: const Color(0xFF1E293B),
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
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
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
                                color: isVisited ? AppColors.primary : AppColors.surface,
                                border: Border.all(
                                  color: isVisited ? AppColors.primary : const Color(0xFF334155), 
                                  width: 2.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: Text(
                                entry.value['name'] ?? '',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: isVisited ? FontWeight.w700 : FontWeight.w500,
                                  color: isVisited ? Colors.white : AppColors.textMuted,
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
                    left: paddingX + (stopWidth * (route.stops.length - 1) * progress) - 14,
                    top: 2,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 12),
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

