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
  final String? shiftDirection; // 'pickup' or 'dropoff'

  const LinearTrackingView({
    super.key,
    required this.bus,
    required this.route,
    this.shiftDirection,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDropoff = (shiftDirection == 'dropoff') || (shiftDirection == null && bus.isDropoff);
    final List<Map<String, dynamic>> displayedStops = isDropoff 
        ? route.stops.reversed.toList() 
        : route.stops;

    Color routeColor = AppColors.primary;
    try {
      if (route.color.isNotEmpty) {
        routeColor = Color(int.parse(route.color.replaceAll('#', '0xFF')));
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  color: isDropoff 
                      ? AppColors.accent.withValues(alpha: 0.15) 
                      : AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDropoff 
                        ? AppColors.accent.withValues(alpha: 0.3) 
                        : AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  isDropoff ? Icons.departure_board_rounded : Icons.alt_route_rounded,
                  color: isDropoff ? AppColors.accent : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'ROUTE PROGRESS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDropoff 
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDropoff 
                                  ? AppColors.accent.withValues(alpha: 0.3)
                                  : AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            isDropoff ? 'CAMPUS ➔ STOPS' : 'STOPS ➔ CAMPUS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isDropoff ? AppColors.accent : AppColors.primaryLight,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bus.displayBusNumber} • ${isDropoff ? "2nd Shift Return" : "Morning Shift"}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isDropoff ? AppColors.accent : AppColors.primaryLight,
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
          const SizedBox(height: 28),
          
          // Linear Progress Line
          LayoutBuilder(
            builder: (context, constraints) {
              const double minWidthPerStop = 100.0;
              final double itemsWidth = displayedStops.length * minWidthPerStop;
              final bool needsScroll = itemsWidth > constraints.maxWidth;
              final double stopWidth = needsScroll ? minWidthPerStop : (constraints.maxWidth / (displayedStops.isEmpty ? 1 : displayedStops.length));
              final double paddingX = stopWidth / 2;

              final rawPoints = route.coordinates.map((c) => LatLng(c['latitude']!, c['longitude']!)).toList();
              final List<LatLng> routePoints = isDropoff ? rawPoints.reversed.toList() : rawPoints;
              final double progress = MapMath.calculateRouteProgress(LatLng(bus.currentLat, bus.currentLng), routePoints);
              
              final int stopCount = displayedStops.length;
              final double trackWidth = stopCount > 1 ? stopWidth * (stopCount - 1) : stopWidth;

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
                      width: trackWidth * progress.clamp(0.0, 1.0),
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDropoff ? AppColors.accent : routeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Stops
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: displayedStops.asMap().entries.map((entry) {
                      final int idx = entry.key;
                      final stopName = entry.value['name']?.toString().trim() ?? '';
                      final bool isReached = bus.reachedStops.contains(stopName);
                      final bool isVisited = isReached || (stopCount > 1 ? ((idx / (stopCount - 1)) <= progress) : true);
                      final bool isFirstStop = idx == 0;
                      final bool isLastStop = idx == stopCount - 1;

                      Color nodeColor = isVisited 
                          ? (isDropoff ? AppColors.accent : routeColor) 
                          : const Color(0xFF334155);

                      return SizedBox(
                        width: stopWidth,
                        child: Column(
                          children: [
                            Container(
                              width: (isFirstStop || isLastStop) ? 16 : 14,
                              height: (isFirstStop || isLastStop) ? 16 : 14,
                              margin: EdgeInsets.only(top: (isFirstStop || isLastStop) ? 18 : 19),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isVisited 
                                    ? (isDropoff ? AppColors.accent : routeColor) 
                                    : AppColors.surface,
                                border: Border.all(
                                  color: nodeColor,
                                  width: 2.5,
                                ),
                              ),
                              child: (isFirstStop || isLastStop)
                                  ? Center(
                                      child: Icon(
                                        isFirstStop 
                                            ? (isDropoff ? Icons.school_rounded : Icons.play_arrow_rounded)
                                            : (isDropoff ? Icons.flag_rounded : Icons.school_rounded),
                                        size: 8,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: Column(
                                children: [
                                  Text(
                                    entry.value['name'] ?? '',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10.5,
                                      fontWeight: isVisited ? FontWeight.w800 : FontWeight.w500,
                                      color: isVisited ? Colors.white : AppColors.textMuted,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isFirstStop 
                                        ? (isDropoff ? 'CAMPUS' : 'ORIGIN')
                                        : (isLastStop 
                                            ? (isDropoff ? 'TERMINAL' : 'CAMPUS')
                                            : 'STOP ${idx + 1}'),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w800,
                                      color: isVisited 
                                          ? (isDropoff ? AppColors.accent : AppColors.primaryLight) 
                                          : AppColors.textDisabled,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
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
                    left: paddingX + (trackWidth * progress.clamp(0.0, 1.0)) - 14,
                    top: 2,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: isDropoff ? AppColors.accent : AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
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

