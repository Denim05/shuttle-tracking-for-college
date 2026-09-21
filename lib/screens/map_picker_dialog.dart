import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  @override
  void initState() {
    super.initState();
    final double validLat = (widget.initialLat != 0.0) ? widget.initialLat : 23.2599;
    final double validLng = (widget.initialLng != 0.0) ? widget.initialLng : 77.4126;
    _selectedLocation = LatLng(validLat, validLng);
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _selectedLocation = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: const Color(0xFF131D33),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: widget.themeColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30,
              spreadRadius: 5,
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Header Bar ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.pin_drop_rounded, color: widget.themeColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PIN STOP LOCATION',
                          style: GoogleFonts.plusJakartaSans(
                            color: widget.themeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          widget.stopName.isNotEmpty ? widget.stopName : 'Select Stop Position',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
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
                      zoom: 14.5,
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
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),

                  // Map Quick Location Shortcuts
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _quickLocationBtn('SISTec', const LatLng(23.180302, 77.302695)),
                        const SizedBox(height: 8),
                        _quickLocationBtn('Bhopal', const LatLng(23.2599, 77.4126)),
                      ],
                    ),
                  ),

                  // Helper Instruction Pill
                  Positioned(
                    bottom: 12,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_rounded, color: widget.themeColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap anywhere on the map or drag the cyan pin to adjust',
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _coordBadge('LATITUDE', _selectedLocation.latitude.toStringAsFixed(5)),
                      const SizedBox(width: 12),
                      _coordBadge('LONGITUDE', _selectedLocation.longitude.toStringAsFixed(5)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _quickLocationBtn(String title, LatLng pos) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedLocation = pos);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.themeColor.withOpacity(0.4)),
        ),
        child: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            color: widget.themeColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
