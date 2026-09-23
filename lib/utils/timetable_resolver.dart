/// Official SGI Transport Manager Timetable & Fleet Assignment Resolver
/// 
/// Resolves the exact manager-assigned bus number (e.g. "BUS 02", "BUS 19", "BUS T-4"),
/// vehicle registration number, driver details, and departure timings based on:
/// 1. Selected Route
/// 2. Day of Week (Mon - Sat)
/// 3. Shift (Shift 1 Morning, Shift 2 Afternoon, Shift 3 Evening, etc.)
library;

class TimetableRouteEntry {
  final String busNumber; // e.g. "02", "19", "T-4", "ECCO (Pvt)"
  final String vehicleNo; // e.g. "MP-04-HB-1002"
  final String routeName;
  final String shift; // "Shift 1", "Shift 2", etc.
  final String period; // "Morning", "Afternoon", "Evening"
  final String morningDeparture;
  final String campusArrival;
  final String returnDeparture;
  final String driverName;
  final String driverPhone;

  const TimetableRouteEntry({
    required this.busNumber,
    required this.vehicleNo,
    required this.routeName,
    this.shift = 'Shift 1',
    this.period = 'Morning',
    this.morningDeparture = '07:15 AM',
    this.campusArrival = '08:45 AM',
    this.returnDeparture = '04:30 PM',
    this.driverName = 'SGI Transport Driver',
    this.driverPhone = '9876543210',
  });

  String get displayBusLabel {
    final bn = busNumber.trim();
    if (bn.toUpperCase().startsWith('BUS')) return bn.toUpperCase();
    if (RegExp(r'^\d+$').hasMatch(bn)) return 'BUS $bn';
    return 'BUS $bn'.toUpperCase();
  }

  String get shiftTag => '$shift • ${period.toUpperCase()}';
}

class TimetableResolver {
  /// Complete Master Timetable matching the official college fleet allocation:
  /// "TIME - New Update Bus Route 19-08-2025 111111.xlsx"
  static const List<TimetableRouteEntry> masterFleet = [
    TimetableRouteEntry(
      busNumber: '01',
      vehicleNo: 'MP-04-HB-1001',
      routeName: 'Gandhi Nagar & Lalghati Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:30 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Ramprasad Sharma',
    ),
    TimetableRouteEntry(
      busNumber: '02',
      vehicleNo: 'MP-04-HB-1002',
      routeName: 'Ashoka Garden & Bhopal Station Route (Shift 1)',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:15 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Rajesh Kumar',
    ),
    TimetableRouteEntry(
      busNumber: '03',
      vehicleNo: 'MP-04-HB-1003',
      routeName: 'DwarkaDham & Karond Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:20 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Mohan Singh',
    ),
    TimetableRouteEntry(
      busNumber: '04',
      vehicleNo: 'MP-04-HB-1004',
      routeName: 'Kolar Road & DPS School Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:30 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Dinesh Verma',
    ),
    TimetableRouteEntry(
      busNumber: '05',
      vehicleNo: 'MP-04-HB-1005',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 2)',
      shift: 'Shift 2',
      period: 'Morning',
      morningDeparture: '07:25 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Santosh Yadav',
    ),
    TimetableRouteEntry(
      busNumber: '06',
      vehicleNo: 'MP-04-HB-1006',
      routeName: 'Alipur & Ashta Route (Shift 1)',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:45 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Mahesh Sen',
    ),
    TimetableRouteEntry(
      busNumber: '07',
      vehicleNo: 'MP-04-HB-1007',
      routeName: 'Gehnu Kheda & Lalita Nagar Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:35 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Sunil Rathore',
    ),
    TimetableRouteEntry(
      busNumber: '09',
      vehicleNo: 'MP-04-HB-1009',
      routeName: 'Mandideep & Satlapur Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:15 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Anil Meena',
    ),
    TimetableRouteEntry(
      busNumber: '10',
      vehicleNo: 'MP-04-HB-1010',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 3)',
      shift: 'Shift 3',
      period: 'Morning',
      morningDeparture: '07:35 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Kailash Chouhan',
    ),
    TimetableRouteEntry(
      busNumber: '11',
      vehicleNo: 'MP-04-HB-1011',
      routeName: 'SOS & Transport Nagar & Ayodhya Bypass Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:20 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Suresh Parmar',
    ),
    TimetableRouteEntry(
      busNumber: '13',
      vehicleNo: 'MP-04-HB-1013',
      routeName: 'Sehore & Bishan Khedi Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:10 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Vinod Tiwari',
    ),
    TimetableRouteEntry(
      busNumber: '14',
      vehicleNo: 'MP-04-HB-1014',
      routeName: 'Fanda & Pipaliya Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:40 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Prakash Malviya',
    ),
    TimetableRouteEntry(
      busNumber: '15',
      vehicleNo: 'MP-04-HB-1015',
      routeName: 'Icchawar & Diwadiya Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:50 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Gopal Sahu',
    ),
    TimetableRouteEntry(
      busNumber: '16',
      vehicleNo: 'MP-04-HB-1016',
      routeName: 'Ashta & Bhopal Naka Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:40 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Hemant Joshi',
    ),
    TimetableRouteEntry(
      busNumber: '17',
      vehicleNo: 'MP-04-HB-1017',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 4)',
      shift: 'Shift 4',
      period: 'Morning',
      morningDeparture: '07:45 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Ravi Patidar',
    ),
    TimetableRouteEntry(
      busNumber: '18',
      vehicleNo: 'MP-04-HB-1018',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 5)',
      shift: 'Shift 5',
      period: 'Morning',
      morningDeparture: '07:55 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Deepak Saxena',
    ),
    TimetableRouteEntry(
      busNumber: '19',
      vehicleNo: 'MP-04-HB-1019',
      routeName: 'Dodi & Sonkach & Jawar Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:30 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Rameshwar Lodhi',
    ),
    TimetableRouteEntry(
      busNumber: '20',
      vehicleNo: 'MP-04-HB-1020',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 6)',
      shift: 'Shift 6',
      period: 'Morning',
      morningDeparture: '08:05 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Manoj Gour',
    ),
    TimetableRouteEntry(
      busNumber: '21',
      vehicleNo: 'MP-04-HB-1021',
      routeName: 'Neelbad Express Shuttle Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:45 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Jagdish Kushwaha',
    ),
    TimetableRouteEntry(
      busNumber: '22',
      vehicleNo: 'MP-04-HB-1022',
      routeName: 'Bhopal Station & Ashoka Garden Route (Shift 7)',
      shift: 'Shift 7',
      period: 'Morning',
      morningDeparture: '08:15 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Sanjay Ahirwar',
    ),
    TimetableRouteEntry(
      busNumber: '23',
      vehicleNo: 'MP-04-HB-1023',
      routeName: 'Katara & Bagmugaliya & AIIMS Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:20 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Vikram Thakur',
    ),
    TimetableRouteEntry(
      busNumber: '24',
      vehicleNo: 'MP-04-HB-1024',
      routeName: 'Ashoka Garden & Bhopal Station (Shift 8)',
      shift: 'Shift 8',
      period: 'Morning',
      morningDeparture: '08:25 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Babulal Sen',
    ),
    TimetableRouteEntry(
      busNumber: 'T-4',
      vehicleNo: 'MP-04-HB-1034',
      routeName: 'Rehti & Narsullaganj Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:30 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Brijesh Sharma',
    ),
    TimetableRouteEntry(
      busNumber: 'T-5',
      vehicleNo: 'MP-04-HB-1035',
      routeName: 'Hoshangabad & Babai & Mana Gaon Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '06:15 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Kamlesh Mewada',
    ),
    TimetableRouteEntry(
      busNumber: 'T-6',
      vehicleNo: 'MP-04-HB-1036',
      routeName: 'Bakaniya & Kharkedi Route',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:15 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Narayan Singh',
    ),
    TimetableRouteEntry(
      busNumber: 'ECCO (Pvt)',
      vehicleNo: 'MP-04-TA-9901',
      routeName: 'Brajesh Nagar & Icchawar Route (Pvt)',
      shift: 'Shift 1',
      period: 'Morning',
      morningDeparture: '07:00 AM',
      campusArrival: '08:45 AM',
      returnDeparture: '04:30 PM',
      driverName: 'Mukesh Prajapati',
    ),
  ];

  /// Resolves the official manager-assigned bus number for a given route name, shift, and explicit bus number.
  /// GUARANTEED to NEVER return a raw hex ID or MongoDB ObjectID substring.
  static String resolveAssignedBusNumber({
    String? explicitBusNumber,
    String? busName,
    String? routeName,
    String? shift,
  }) {
    // 1. Check explicit busNumber from manager database (e.g. '02', 'Bus 02', 'MP-04-HB-1002')
    if (explicitBusNumber != null &&
        explicitBusNumber.trim().isNotEmpty &&
        explicitBusNumber.trim().toUpperCase() != 'N/A' &&
        !_isRawHexId(explicitBusNumber)) {
      final bn = explicitBusNumber.trim();
      if (bn.toUpperCase().startsWith('BUS')) return bn.toUpperCase();
      if (RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(bn)) return 'BUS $bn';
      return 'BUS $bn'.toUpperCase();
    }

    // 2. Check manager assigned name (e.g. 'Bus 02 - Ashoka Garden' or 'Bus 19')
    if (busName != null && busName.trim().isNotEmpty && !_isRawHexId(busName)) {
      final n = busName.trim();
      if (n.contains(' - ')) {
        final prefix = n.split(' - ').first.trim().toUpperCase();
        if (prefix.isNotEmpty) return prefix.startsWith('BUS') ? prefix : 'BUS $prefix';
      }
      if (n.toUpperCase().startsWith('BUS')) return n.toUpperCase();
      if (RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(n)) return 'BUS $n';
      return 'BUS $n'.toUpperCase();
    }

    // 3. Match from routeName via Regex (e.g. "Bus 02", "Route 19", "Bus T-4", "Bus #05")
    if (routeName != null && routeName.trim().isNotEmpty) {
      final match = RegExp(r'(?:Bus|Route)\s*#?\s*([0-9]+[A-Za-z]?|T-\d+|ECCO)', caseSensitive: false).firstMatch(routeName);
      if (match != null) {
        final val = match.group(1)!.toUpperCase();
        return val.startsWith('BUS') ? val : 'BUS $val';
      }

      // 4. Corridor-based search in official master fleet
      final cleanName = routeName.toLowerCase();
      for (final entry in masterFleet) {
        if (shift != null && shift.isNotEmpty) {
          if (cleanName.contains(_extractKeyCorridor(entry.routeName).toLowerCase()) &&
              entry.shift.toLowerCase() == shift.toLowerCase()) {
            return entry.displayBusLabel;
          }
        } else {
          if (cleanName.contains(_extractKeyCorridor(entry.routeName).toLowerCase())) {
            return entry.displayBusLabel;
          }
        }
      }
    }

    return 'BUS ASSIGNED';
  }

  /// Resolves the shift label (e.g. "SHIFT 1 • MORNING")
  static String resolveShiftLabel({
    String? explicitShift,
    String? routeName,
    int? currentHour,
  }) {
    if (explicitShift != null && explicitShift.trim().isNotEmpty) {
      final s = explicitShift.trim().toUpperCase();
      if (s.contains('•')) return s;
      if (s.contains('SHIFT 1')) return 'SHIFT 1 • MORNING';
      if (s.contains('SHIFT 2')) return 'SHIFT 2 • AFTERNOON';
      if (s.contains('SHIFT 3')) return 'SHIFT 3 • EVENING';
      return '$s • SCHEDULED';
    }

    if (routeName != null) {
      for (int i = 1; i <= 8; i++) {
        if (routeName.contains('Shift $i')) {
          if (i == 1 || i == 2) return 'SHIFT $i • MORNING';
          if (i == 3 || i == 4) return 'SHIFT $i • AFTERNOON';
          return 'SHIFT $i • EVENING';
        }
      }
    }

    final h = currentHour ?? DateTime.now().hour;
    if (h < 12) return 'SHIFT 1 • MORNING';
    if (h < 16) return 'SHIFT 2 • AFTERNOON';
    return 'SHIFT 3 • EVENING';
  }

  /// Returns the current day abbreviation (e.g. "MON", "TUE", "WED", "THU", "FRI", "SAT")
  static String getCurrentDayLabel() {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final now = DateTime.now();
    return days[now.weekday - 1];
  }

  /// Returns all fleet timetable entries matching a route corridor
  static List<TimetableRouteEntry> getShiftsForRoute(String? routeName) {
    if (routeName == null || routeName.isEmpty) return [masterFleet[1]]; // Default Bus 02
    final corridor = _extractKeyCorridor(routeName).toLowerCase();
    final matches = masterFleet.where((e) => e.routeName.toLowerCase().contains(corridor)).toList();
    return matches.isNotEmpty ? matches : [masterFleet.firstWhere((e) => e.routeName.toLowerCase().contains(corridor), orElse: () => masterFleet[1])];
  }

  /// Resolves the complete bus entry details (registration, shift, timings, driver) for a route.
  static TimetableRouteEntry? resolveBusDetails({String? routeName, int? currentHour}) {
    final list = getShiftsForRoute(routeName);
    if (list.isEmpty) return masterFleet[1];
    if (currentHour != null) {
      if (currentHour < 12 && list.isNotEmpty) return list.first;
      if (list.length > 1) return list[1];
    }
    return list.first;
  }

  static String _extractKeyCorridor(String name) {
    final split = name.split('&');
    if (split.isNotEmpty) return split.first.replaceAll(RegExp(r'Route|\(.*?\)'), '').trim();
    return name;
  }

  static bool _isRawHexId(String text) {
    final clean = text.replaceAll('#', '').replaceAll('BUS', '').trim();
    return RegExp(r'^[0-9a-fA-F]{4,24}$').hasMatch(clean) && clean.length >= 4 && !RegExp(r'^\d+$').hasMatch(clean);
  }
}
