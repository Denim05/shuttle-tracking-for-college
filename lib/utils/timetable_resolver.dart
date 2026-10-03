/// Official SGI Transport Manager Timetable & Fleet Assignment Resolver
/// 
/// Extracted and synchronized with the official college schedule:
/// "SISTec Ratibad time 9_00 am.xlsx - sistec123 900.pdf"
///
/// Features:
/// 1. Complete fleet matrix (Bus 01 to 37+ buses, official registrations, drivers & mobile numbers).
/// 2. Official Transport Incharge hotlines (Vaibhav Pathak: 7024256904, Ramswroop: 9669660990).
/// 3. Authentic scheduled stop arrival timings directly from the institutional roster.
/// 4. Intelligent resilient matching across corridors, bus numbers, and stop names.
library;

class TimetableStop {
  final String stopName;
  final String time;

  const TimetableStop(this.stopName, this.time);
}

class TransportOfficial {
  final String name;
  final String phone;
  final String designation;

  const TransportOfficial({
    required this.name,
    required this.phone,
    required this.designation,
  });
}

class TimetableRouteEntry {
  final String busNumber;
  final String vehicleNo;
  final String routeName;
  final String shift;
  final String period;
  final String morningDeparture;
  final String campusArrival;
  final String returnDeparture;
  final String driverName;
  final String driverPhone;
  final List<TimetableStop> scheduledStops;

  const TimetableRouteEntry({
    required this.busNumber,
    required this.vehicleNo,
    required this.routeName,
    this.shift = 'Shift 1 (9:00 AM)',
    this.period = 'Morning',
    required this.morningDeparture,
    this.campusArrival = '09:00 AM',
    this.returnDeparture = '04:30 PM',
    required this.driverName,
    required this.driverPhone,
    this.scheduledStops = const [],
  });

  String get displayBusLabel {
    final bn = busNumber.trim();
    if (bn.toUpperCase().startsWith('BUS')) return bn.toUpperCase();
    if (RegExp(r'^\d+$').hasMatch(bn)) return 'BUS $bn';
    if (bn.startsWith('MP')) return bn;
    return 'BUS $bn'.toUpperCase();
  }

  String get shiftTag => '$shift • ${period.toUpperCase()}';

  String? getScheduledTime(String stopName) {
    if (scheduledStops.isEmpty) return null;
    final clean = _normalize(stopName);
    for (final s in scheduledStops) {
      final sNorm = _normalize(s.stopName);
      if (sNorm == clean || sNorm.contains(clean) || clean.contains(sNorm)) {
        return s.time;
      }
    }
    return null;
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

class TimetableResolver {
  /// Official Transport Incharge Helplines from College PDF
  static const List<TransportOfficial> transportIncharges = [
    TransportOfficial(
      name: 'Vaibhav Pathak',
      phone: '7024256904',
      designation: 'Transport Incharge',
    ),
    TransportOfficial(
      name: 'Ramswroop',
      phone: '9669660990',
      designation: 'Transport Incharge',
    ),
  ];

  /// Complete Master Fleet Timetable matching:
  /// "SISTec Ratibad time 9_00 am.xlsx - sistec123 900.pdf"
  static const List<TimetableRouteEntry> masterFleet = [
    TimetableRouteEntry(
      busNumber: '01',
      vehicleNo: 'MP04 PA 3496',
      routeName: 'Gandhi Nagar & Lalghati Route',
      morningDeparture: '07:20 AM',
      campusArrival: '09:00 AM',
      driverName: 'Ghanshyam Nagar',
      driverPhone: '9770534112',
      scheduledStops: [
        TimetableStop('Gandhi Nagar', '07:20 AM'),
        TimetableStop('Asharam Bapu Square', '07:25 AM'),
        TimetableStop('Bhaskar Colony', '07:30 AM'),
        TimetableStop('Data Colony', '07:35 AM'),
        TimetableStop('Panchwati', '07:40 AM'),
        TimetableStop('Halalpur (Bus Stand)', '07:45 AM'),
        TimetableStop('Bairagarh Police Station', '07:50 AM'),
        TimetableStop('Chirayu Hospital', '07:55 AM'),
        TimetableStop('Lalghati', '08:05 AM'),
        TimetableStop('Koh-E-Fiza', '08:10 AM'),
        TimetableStop('State Bank Square', '08:12 AM'),
        TimetableStop('Royal Market', '08:14 AM'),
        TimetableStop('Imami Gate', '08:16 AM'),
        TimetableStop('Peer Gate', '08:18 AM'),
        TimetableStop('Moti Masjid', '08:20 AM'),
        TimetableStop('Kamla Park', '08:22 AM'),
        TimetableStop('Polytechnic', '08:27 AM'),
        TimetableStop('Roshanpura', '08:30 AM'),
        TimetableStop('Jawahar Chowk', '08:35 AM'),
        TimetableStop('Bharat Mata Square', '08:37 AM'),
        TimetableStop('23 Bataliyan', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '02',
      vehicleNo: 'MP04 PA 3498',
      routeName: 'Kolar Road & DPS School Route',
      morningDeparture: '07:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rajesh',
      driverPhone: '9617648753',
      scheduledStops: [
        TimetableStop('DPS School', '07:40 AM'),
        TimetableStop('Beraghad', '07:45 AM'),
        TimetableStop('Priyanka Nagar', '07:50 AM'),
        TimetableStop('610 Colony', '07:55 AM'),
        TimetableStop('Mansarovar Dental Hospital', '08:00 AM'),
        TimetableStop('Bashkedi', '08:05 AM'),
        TimetableStop('Saliya', '08:10 AM'),
        TimetableStop('Akriti Eco City', '08:12 AM'),
        TimetableStop('Janki Hospital', '08:17 AM'),
        TimetableStop('Auro Mall', '08:20 AM'),
        TimetableStop('Shivay Complex', '08:22 AM'),
        TimetableStop('Ishwar Nagar', '08:25 AM'),
        TimetableStop('12 No Stop (Sai Board)', '08:27 AM'),
        TimetableStop('10 No Market', '08:30 AM'),
        TimetableStop('Bittan Market', '08:32 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '03',
      vehicleNo: 'MP04 PA 3501',
      routeName: 'DwarkaDham & Karond Route',
      morningDeparture: '07:20 AM',
      campusArrival: '09:00 AM',
      driverName: 'Sher Khan',
      driverPhone: '9039518048',
      scheduledStops: [
        TimetableStop('Asharam Chouraha', '07:20 AM'),
        TimetableStop('DwarkaDham SPS Campus', '07:25 AM'),
        TimetableStop('Lambakheda', '07:40 AM'),
        TimetableStop('Karond', '07:45 AM'),
        TimetableStop('Best Price', '07:50 AM'),
        TimetableStop('Karond (Sabzi Mandi)', '07:55 AM'),
        TimetableStop('DIG Bungla', '08:00 AM'),
        TimetableStop('Chola Mandir', '08:05 AM'),
        TimetableStop('Dharam Kata Chouraha', '08:10 AM'),
        TimetableStop('Shahjahanabad', '08:20 AM'),
        TimetableStop('Nadra Bus Stand', '08:02 AM'),
        TimetableStop('Bharat Talkies', '08:07 AM'),
        TimetableStop('Jahangirabad', '08:12 AM'),
        TimetableStop('PHQ', '08:14 AM'),
        TimetableStop('Roshanpura', '08:28 AM'),
        TimetableStop('Bharat Mata Square', '08:32 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '04',
      vehicleNo: 'MP04 PA 3504',
      routeName: 'Katara Hills & AIIMS Route',
      morningDeparture: '07:25 AM',
      campusArrival: '09:00 AM',
      driverName: 'Mukesh Shisodiya',
      driverPhone: '8251047765',
      scheduledStops: [
        TimetableStop('Katara Hospital', '07:25 AM'),
        TimetableStop('Katara Dastoor Hostel', '07:32 AM'),
        TimetableStop('Lahar Pur', '07:36 AM'),
        TimetableStop('Bagsewaniya Ojes Hospital', '07:40 AM'),
        TimetableStop('Saket Nagar', '07:45 AM'),
        TimetableStop('AIIMS', '07:47 AM'),
        TimetableStop('Alkapuri', '07:50 AM'),
        TimetableStop('Durga Mandir', '07:51 AM'),
        TimetableStop('Barkheda Pathani', '07:55 AM'),
        TimetableStop('Awadhpuri Thana', '08:00 AM'),
        TimetableStop('Aadharshila Chowk', '08:02 AM'),
        TimetableStop('Durga Chowk', '08:03 AM'),
        TimetableStop('Awadhpuri Tiraha', '08:05 AM'),
        TimetableStop('Mahatma Gandhi Chauraha', '08:08 AM'),
        TimetableStop('Red Cross', '08:25 AM'),
        TimetableStop('Panchsheel Nagar', '08:27 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '06',
      vehicleNo: 'MP04 PA 3511',
      routeName: 'Ashta & Kotri Route',
      morningDeparture: '07:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Ramesh Dangoliya',
      driverPhone: '9630411125',
      scheduledStops: [
        TimetableStop('Kachnariya', '07:00 AM'),
        TimetableStop('Kotri', '07:23 AM'),
        TimetableStop('Jat Khedi Jod', '07:25 AM'),
        TimetableStop('Amlaha', '07:35 AM'),
        TimetableStop('Bhadakhedi Jod', '07:45 AM'),
        TimetableStop('Goodwela', '08:00 AM'),
        TimetableStop('Jhagriya Bypass Sehore', '08:10 AM'),
        TimetableStop('Jhagriya', '08:35 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '07',
      vehicleNo: 'MP04 PA 3512',
      routeName: 'Gehnu Kheda & Kolar Route',
      morningDeparture: '07:25 AM',
      campusArrival: '09:00 AM',
      driverName: 'Virendra',
      driverPhone: '7770873503',
      scheduledStops: [
        TimetableStop('Gehnu Kheda', '07:25 AM'),
        TimetableStop('D-Mart', '07:28 AM'),
        TimetableStop('Lalita Nagar', '07:29 AM'),
        TimetableStop('Nayapura', '07:36 AM'),
        TimetableStop('Mandakini', '07:41 AM'),
        TimetableStop('J.K. Hospital', '07:48 AM'),
        TimetableStop('Bansal Hospital', '07:57 AM'),
        TimetableStop('10 Number', '08:10 AM'),
        TimetableStop('Arera Petrol Pump', '08:12 AM'),
        TimetableStop('Kolar Tiraha', '08:15 AM'),
        TimetableStop('Panchsheel Nagar', '08:18 AM'),
        TimetableStop('Vaishali Nagar', '08:21 AM'),
        TimetableStop('Nehru Nagar Chauraha', '08:25 AM'),
        TimetableStop('Nehru Nagar Naya Basera', '08:35 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '08',
      vehicleNo: 'MP04 YR 3428',
      routeName: 'Hoshangabad & Babai Route',
      morningDeparture: '06:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Harsh Giri',
      driverPhone: '8103661105',
      scheduledStops: [
        TimetableStop('Mana Gaon', '06:00 AM'),
        TimetableStop('Babai', '06:10 AM'),
        TimetableStop('Jaswapur', '06:40 AM'),
        TimetableStop('Gadariya Nala', '07:00 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '09',
      vehicleNo: 'MP04 PA 3513',
      routeName: 'Mandideep & Misrod Route',
      morningDeparture: '07:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rajesh',
      driverPhone: '9685648764',
      scheduledStops: [
        TimetableStop('Satlapur', '07:00 AM'),
        TimetableStop('Vardhman', '07:10 AM'),
        TimetableStop('Sarakiya', '07:20 AM'),
        TimetableStop('HEG / Mandideep', '07:35 AM'),
        TimetableStop('Samardha', '07:40 AM'),
        TimetableStop('Radhapuram', '07:41 AM'),
        TimetableStop('Pal Dhaba', '07:43 AM'),
        TimetableStop('Indus Town', '07:45 AM'),
        TimetableStop('11 Mile', '07:47 AM'),
        TimetableStop('Misrod', '07:50 AM'),
        TimetableStop('Ashima Mall', '07:55 AM'),
        TimetableStop('Danish Nagar', '07:57 AM'),
        TimetableStop('Bagsewaniya Thana', '08:00 AM'),
        TimetableStop('SP Office', '08:02 AM'),
        TimetableStop('Narayan Nagar', '08:05 AM'),
        TimetableStop('Ganesh Mandir', '08:06 AM'),
        TimetableStop('BJP Office', '08:07 AM'),
        TimetableStop('Nutan College', '08:10 AM'),
        TimetableStop('Durga Petrol Pump', '08:12 AM'),
        TimetableStop('Narmada Bhawan', '08:15 AM'),
        TimetableStop('Panchsheel Nagar', '08:17 AM'),
        TimetableStop('Mata Mandir', '08:18 AM'),
        TimetableStop('PNT Square', '08:20 AM'),
        TimetableStop('Nehru Nagar New Basti', '08:21 AM'),
        TimetableStop('Nehru Nagar Square', '08:25 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '11',
      vehicleNo: 'MP04 PA 3522',
      routeName: 'Icchawar & Bhavkhedi Route (Bus 11)',
      morningDeparture: '05:45 AM',
      campusArrival: '09:00 AM',
      driverName: 'Mukesh Verma',
      driverPhone: '7049209613',
      scheduledStops: [
        TimetableStop('Bhavkhedi', '05:45 AM'),
        TimetableStop('Narshing Kheda', '06:10 AM'),
        TimetableStop('Pratap Pura (Nagli Jod)', '06:15 AM'),
        TimetableStop('Torniya', '06:25 AM'),
        TimetableStop('Ram Nagar', '06:35 AM'),
        TimetableStop('Satpipliya', '06:40 AM'),
        TimetableStop('Vishankhedi', '06:50 AM'),
        TimetableStop('Molakhedi', '06:55 AM'),
        TimetableStop('Amla', '07:05 AM'),
        TimetableStop('Khudi', '07:25 AM'),
        TimetableStop('Khakarkheda', '07:35 AM'),
        TimetableStop('Hasnabad', '07:40 AM'),
        TimetableStop('Dait Colony', '07:45 AM'),
        TimetableStop('Indra Nagar', '07:50 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '12',
      vehicleNo: 'MP04 PA 3521',
      routeName: 'Rehti & Soyat Route',
      morningDeparture: '05:45 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rahul',
      driverPhone: '8305973987',
      scheduledStops: [
        TimetableStop('Agra', '05:45 AM'),
        TimetableStop('Majarkui', '06:30 AM'),
        TimetableStop('Naya Gaon', '06:35 AM'),
        TimetableStop('Karri', '06:40 AM'),
        TimetableStop('Khakarda', '06:41 AM'),
        TimetableStop('Soyat', '07:00 AM'),
        TimetableStop('Jamuniya', '07:05 AM'),
        TimetableStop('Nadhiyakheda', '07:07 AM'),
        TimetableStop('Kotra', '07:10 AM'),
        TimetableStop('Chakaldi', '07:25 AM'),
        TimetableStop('Dhaba Gaon', '07:30 AM'),
        TimetableStop('Amdo', '07:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '13',
      vehicleNo: 'MP04 PA 2288',
      routeName: 'Sehore & Ganga Ashram Route',
      morningDeparture: '06:55 AM',
      campusArrival: '09:00 AM',
      driverName: 'Abrar Khan',
      driverPhone: '8225932275',
      scheduledStops: [
        TimetableStop('Kodiya', '06:55 AM'),
        TimetableStop('Ganesh Mandir', '07:00 AM'),
        TimetableStop('Moti Baba Mandir', '07:03 AM'),
        TimetableStop('Bijori Jod', '07:15 AM'),
        TimetableStop('Police Line', '07:18 AM'),
        TimetableStop('Luniya Chouraha', '07:20 AM'),
        TimetableStop('Reliance Petrol Pump', '07:22 AM'),
        TimetableStop('Indore Naka', '07:25 AM'),
        TimetableStop('Kohli Pura', '07:27 AM'),
        TimetableStop('Ganga Ashram', '07:32 AM'),
        TimetableStop('Bhopal Naka', '07:40 AM'),
        TimetableStop('Chanakyapuri', '07:42 AM'),
        TimetableStop('Chanakyapuri (Vishal Mega Mart)', '07:45 AM'),
        TimetableStop('Khurchani', '08:35 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '14',
      vehicleNo: 'MP04 PA 2290',
      routeName: 'Bakaniya & Khajuri Route',
      morningDeparture: '06:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Jitendra Prajapati',
      driverPhone: '918965815880',
      scheduledStops: [
        TimetableStop('Ratikheda', '06:50 AM'),
        TimetableStop('Dodi', '06:55 AM'),
        TimetableStop('Sonkach', '07:25 AM'),
        TimetableStop('Kharkheda', '07:30 AM'),
        TimetableStop('Toomda', '07:45 AM'),
        TimetableStop('Bakaniya', '08:00 AM'),
        TimetableStop('Barkheda', '08:10 AM'),
        TimetableStop('Kolukhedi', '08:25 AM'),
        TimetableStop('Khajuri', '08:30 AM'),
        TimetableStop('Lakhapur', '08:40 AM'),
        TimetableStop('Kajlash', '08:45 AM'),
        TimetableStop('Kodiya', '08:50 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '15',
      vehicleNo: 'MP04 PA 2289',
      routeName: 'Icchawar & Bhavkhedi Route (Bus 15)',
      morningDeparture: '05:45 AM',
      campusArrival: '09:00 AM',
      driverName: 'Manohar Verma',
      driverPhone: '7509826700',
      scheduledStops: [
        TimetableStop('Bhavkhedi', '05:45 AM'),
        TimetableStop('Narshing Kheda', '06:10 AM'),
        TimetableStop('Pratap Pura (Nagli Jod)', '06:15 AM'),
        TimetableStop('Torniya', '06:25 AM'),
        TimetableStop('Ram Nagar', '06:35 AM'),
        TimetableStop('Satpipliya', '06:40 AM'),
        TimetableStop('Vishankhedi', '06:50 AM'),
        TimetableStop('Molakhedi', '06:55 AM'),
        TimetableStop('Amla', '07:05 AM'),
        TimetableStop('Khudi', '07:25 AM'),
        TimetableStop('Khakarkheda', '07:35 AM'),
        TimetableStop('Hasnabad', '07:40 AM'),
        TimetableStop('Dait Colony', '07:45 AM'),
        TimetableStop('Indra Nagar', '07:50 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '16',
      vehicleNo: 'MP04 PA 2515',
      routeName: 'Phanda & Nandni Route',
      morningDeparture: '07:10 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rahul Verma',
      driverPhone: '7987924702',
      scheduledStops: [
        TimetableStop('Amrod', '07:10 AM'),
        TimetableStop('Phanda', '07:20 AM'),
        TimetableStop('Padli Jod', '07:25 AM'),
        TimetableStop('Kulas', '07:40 AM'),
        TimetableStop('Choti Kulas', '07:45 AM'),
        TimetableStop('Sastakhedi', '07:55 AM'),
        TimetableStop('Dubdi', '08:00 AM'),
        TimetableStop('Borkhedi', '08:10 AM'),
        TimetableStop('Khokhariya', '08:15 AM'),
        TimetableStop('Deriya', '08:30 AM'),
        TimetableStop('Mudla', '08:35 AM'),
        TimetableStop('Narela', '08:40 AM'),
        TimetableStop('Telakhedi', '08:45 AM'),
        TimetableStop('Nandni', '08:50 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '19',
      vehicleNo: 'MP04 PA 1543',
      routeName: 'Piplani & Kokta Bypass Route',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Dinesh Jatav',
      driverPhone: '8827729942',
      scheduledStops: [
        TimetableStop('Kokta Bypass', '07:50 AM'),
        TimetableStop('SOS Piplani', '08:10 AM'),
        TimetableStop('Apsara Talkies', '08:15 AM'),
        TimetableStop('Vallabh Bhavan', '08:25 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '21',
      vehicleNo: 'MP04 ZL 9712',
      routeName: 'SLV & Ayodhya Bypass Route',
      morningDeparture: '07:30 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rakesh Shisodiya',
      driverPhone: '8770275181',
      scheduledStops: [
        TimetableStop('Minal Gate No - 02', '07:30 AM'),
        TimetableStop('Ayodhya Chouraha', '07:31 AM'),
        TimetableStop('Narela Tiraha', '07:32 AM'),
        TimetableStop('Tana Tan Dhaba', '07:33 AM'),
        TimetableStop('Ayodhya Extension', '07:34 AM'),
        TimetableStop('Vrindavan Chouraha', '07:35 AM'),
        TimetableStop('Ratnagiri (Azad Nagar)', '07:37 AM'),
        TimetableStop('Anand Nagar', '07:40 AM'),
        TimetableStop('Ishan Park', '07:42 AM'),
        TimetableStop('Oriental College', '07:45 AM'),
        TimetableStop('Piplani', '08:05 AM'),
        TimetableStop('Bima Hospital', '08:06 AM'),
        TimetableStop('Indrapuri', '08:07 AM'),
        TimetableStop('J.K. Road', '08:09 AM'),
        TimetableStop('ITI Chouraha', '08:10 AM'),
        TimetableStop('Shanti Niketan', '08:25 AM'),
        TimetableStop('Bharti Niketan', '08:26 AM'),
        TimetableStop('Sangam Talkies (MP Nagar)', '08:32 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '23',
      vehicleNo: 'MP04 ZN 1503',
      routeName: 'Ashta & Alipur Route (Bus 23)',
      morningDeparture: '06:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Banti Parmar',
      driverPhone: '9074915343',
      scheduledStops: [
        TimetableStop('Alipur', '06:50 AM'),
        TimetableStop('Old Bus Stand', '06:51 AM'),
        TimetableStop('Bhopal Naka', '06:52 AM'),
        TimetableStop('Bajrang Colony', '06:53 AM'),
        TimetableStop('Colony Square', '06:54 AM'),
        TimetableStop('Banjari Mata', '06:55 AM'),
        TimetableStop('Kachnariya Jod', '07:20 AM'),
        TimetableStop('Kotri', '07:23 AM'),
        TimetableStop('Jat Khedi Jod', '07:25 AM'),
        TimetableStop('Amlaha', '07:35 AM'),
        TimetableStop('Bhadakhedi Jod', '07:45 AM'),
        TimetableStop('Goodwela', '08:00 AM'),
        TimetableStop('Jhagriya Bypass Sehore', '08:10 AM'),
        TimetableStop('Jhagriya', '08:35 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '26',
      vehicleNo: 'MP04 YR 4318',
      routeName: 'Ashta & Alipur Route (Bus 26)',
      morningDeparture: '06:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Raj Kumar',
      driverPhone: '8989878725',
      scheduledStops: [
        TimetableStop('Alipur', '06:50 AM'),
        TimetableStop('Old Bus Stand', '06:51 AM'),
        TimetableStop('Bhopal Naka', '06:52 AM'),
        TimetableStop('Bajrang Colony', '06:53 AM'),
        TimetableStop('Colony Square', '06:54 AM'),
        TimetableStop('Banjari Mata', '06:55 AM'),
        TimetableStop('Kachnariya Jod', '07:20 AM'),
        TimetableStop('Kotri', '07:23 AM'),
        TimetableStop('Jat Khedi Jod', '07:25 AM'),
        TimetableStop('Amlaha', '07:35 AM'),
        TimetableStop('Bhadakhedi Jod', '07:45 AM'),
        TimetableStop('Goodwela', '08:00 AM'),
        TimetableStop('Jhagriya Bypass Sehore', '08:10 AM'),
        TimetableStop('Jhagriya', '08:35 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '27',
      vehicleNo: 'MP04 YR 3427',
      routeName: 'Narsullaganj & Bilkisganj Route',
      morningDeparture: '06:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Anand Gour',
      driverPhone: '7697227699',
      scheduledStops: [
        TimetableStop('Narsullaganj', '06:00 AM'),
        TimetableStop('Rala', '06:05 AM'),
        TimetableStop('Satrana', '06:20 AM'),
        TimetableStop('Nipaniya', '06:30 AM'),
        TimetableStop('Ramgada', '06:35 AM'),
        TimetableStop('Kakvana', '06:40 AM'),
        TimetableStop('Bor Ghati', '06:50 AM'),
        TimetableStop('Rehti', '07:00 AM'),
        TimetableStop('Malimaya', '07:10 AM'),
        TimetableStop('Bordi', '07:25 AM'),
        TimetableStop('Amdo', '07:40 AM'),
        TimetableStop('Bilkisganj', '08:55 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: '28',
      vehicleNo: 'MP04 YR 4386',
      routeName: 'Diwadiya & Icchawar Route',
      morningDeparture: '06:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Krishna Verma',
      driverPhone: '9977606876',
      scheduledStops: [
        TimetableStop('Diwadiya', '06:40 AM'),
        TimetableStop('Jhalki', '06:50 AM'),
        TimetableStop('Kushal Pura', '07:00 AM'),
        TimetableStop('Amla', '07:10 AM'),
        TimetableStop('Nayapura', '07:15 AM'),
        TimetableStop('Siradi', '07:25 AM'),
        TimetableStop('Icchawar (Mandi)', '07:28 AM'),
        TimetableStop('Icchawar (Bus Stand)', '07:30 AM'),
        TimetableStop('Icchawar (Thana)', '07:32 AM'),
        TimetableStop('Uljhawan', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'T-4',
      vehicleNo: 'MP04 PA 4443',
      routeName: 'Itarsi & Budhni Route',
      morningDeparture: '06:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rahul Vishvkarma',
      driverPhone: '8928566577',
      scheduledStops: [
        TimetableStop('Itarsi (Bus Stop)', '06:00 AM'),
        TimetableStop('Church', '06:10 AM'),
        TimetableStop('Rasuliya', '06:15 AM'),
        TimetableStop('Biora', '06:20 AM'),
        TimetableStop('Aandhyari', '06:25 AM'),
        TimetableStop('Rohna Gaon', '06:30 AM'),
        TimetableStop('Bhopal Chouraha', '06:40 AM'),
        TimetableStop('Budhni Town', '06:45 AM'),
        TimetableStop('Gadriya Nala', '07:00 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'T-6',
      vehicleNo: 'MP04 PA 4446',
      routeName: 'Narsullaganj & Chakaldi Route',
      morningDeparture: '05:45 AM',
      campusArrival: '09:00 AM',
      driverName: 'Deepak',
      driverPhone: '9617093329',
      scheduledStops: [
        TimetableStop('Agra', '05:45 AM'),
        TimetableStop('Majarkui', '06:30 AM'),
        TimetableStop('Naya Gaon', '06:35 AM'),
        TimetableStop('Karri', '06:40 AM'),
        TimetableStop('Khakarda', '06:41 AM'),
        TimetableStop('Soyat', '07:00 AM'),
        TimetableStop('Jamuniya', '07:05 AM'),
        TimetableStop('Nadhiyakheda', '07:07 AM'),
        TimetableStop('Kotra', '07:10 AM'),
        TimetableStop('Chakaldi', '07:25 AM'),
        TimetableStop('Dhaba Gaon', '07:30 AM'),
        TimetableStop('Amdo', '07:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 PA 1886',
      vehicleNo: 'MP04 PA 1886',
      routeName: 'Gautam Nagar & Panchsheel Nagar Route',
      morningDeparture: '08:00 AM',
      campusArrival: '09:00 AM',
      driverName: 'Deepak',
      driverPhone: '7017963219',
      scheduledStops: [
        TimetableStop('Gautam Nagar', '08:00 AM'),
        TimetableStop('Chetak Bridge', '08:05 AM'),
        TimetableStop('Panchsheel Nagar', '08:15 AM'),
        TimetableStop('Nehru Nagar Chauraha', '08:25 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 PA 2127',
      vehicleNo: 'MP04 PA 2127',
      routeName: 'Dwarka Dham & Ashoka Garden Express',
      morningDeparture: '07:30 AM',
      campusArrival: '09:00 AM',
      driverName: 'Mobin Bhai',
      driverPhone: '9329540295',
      scheduledStops: [
        TimetableStop('Dwarka Nagar', '07:30 AM'),
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:35 AM'),
        TimetableStop('Pushpa Nagar', '07:45 AM'),
        TimetableStop('Sangam Tent House', '07:55 AM'),
        TimetableStop('80 Feet Road', '08:10 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:30 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Jinsi Square', '08:10 AM'),
        TimetableStop('Depot', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 PA 3631',
      vehicleNo: 'MP04 PA 3631',
      routeName: 'Ashoka Garden & Depot Chouraha Route 1',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Ravi Singh',
      driverPhone: '7697868157',
      scheduledStops: [
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:50 AM'),
        TimetableStop('Pushpa Nagar', '07:52 AM'),
        TimetableStop('Sangam Tent House', '07:53 AM'),
        TimetableStop('80 Feet Road', '07:55 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:00 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Depot Chouraha', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 ZY 6121',
      vehicleNo: 'MP04 ZY 6121',
      routeName: 'Ashoka Garden & Depot Chouraha Route 2',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Deepak Rathore',
      driverPhone: '9201611685',
      scheduledStops: [
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:50 AM'),
        TimetableStop('Pushpa Nagar', '07:52 AM'),
        TimetableStop('Sangam Tent House', '07:53 AM'),
        TimetableStop('80 Feet Road', '07:55 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:00 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Depot Chouraha', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 ZF 0182',
      vehicleNo: 'MP04 ZF 0182',
      routeName: 'Ashoka Garden & Depot Chouraha Route 3',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Shadab',
      driverPhone: '9589605433',
      scheduledStops: [
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:50 AM'),
        TimetableStop('Pushpa Nagar', '07:52 AM'),
        TimetableStop('Sangam Tent House', '07:53 AM'),
        TimetableStop('80 Feet Road', '07:55 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:00 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Depot Chouraha', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YA 6769',
      vehicleNo: 'MP04 YA 6769',
      routeName: 'Ashoka Garden & Nehru Nagar Route 1',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Usman',
      driverPhone: '7697067400',
      scheduledStops: [
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:50 AM'),
        TimetableStop('Pushpa Nagar', '07:52 AM'),
        TimetableStop('Sangam Tent House', '07:53 AM'),
        TimetableStop('80 Feet Road', '07:55 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:00 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Panchsheel Nagar', '08:15 AM'),
        TimetableStop('MANIT Chouraha', '08:20 AM'),
        TimetableStop('Nehru Nagar Chauraha', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YP 7290',
      vehicleNo: 'MP04 YP 7290',
      routeName: 'Ashoka Garden & Nehru Nagar Route 2',
      morningDeparture: '07:50 AM',
      campusArrival: '09:00 AM',
      driverName: 'Irshad',
      driverPhone: '7049313640',
      scheduledStops: [
        TimetableStop('Bhopal Railway Station (Platform-1)', '07:50 AM'),
        TimetableStop('Pushpa Nagar', '07:52 AM'),
        TimetableStop('Sangam Tent House', '07:53 AM'),
        TimetableStop('80 Feet Road', '07:55 AM'),
        TimetableStop('Ashoka Garden Pani Ki Tanki', '08:00 AM'),
        TimetableStop('Prabhat Square', '08:02 AM'),
        TimetableStop('Panchsheel Nagar', '08:15 AM'),
        TimetableStop('MANIT Chouraha', '08:20 AM'),
        TimetableStop('Nehru Nagar Chauraha', '08:25 AM'),
        TimetableStop('Neelbad', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YP 7236',
      vehicleNo: 'MP04 YP 7236',
      routeName: 'Rani Kamlapati & Naya Basera Route',
      morningDeparture: '08:06 AM',
      campusArrival: '09:00 AM',
      driverName: 'Brijmohan',
      driverPhone: '9201611685',
      scheduledStops: [
        TimetableStop('Ganesh Mandir', '08:06 AM'),
        TimetableStop('BJP Office', '08:07 AM'),
        TimetableStop('Nutan College', '08:10 AM'),
        TimetableStop('Durga Petrol Pump', '08:12 AM'),
        TimetableStop('Narmada Bhawan', '08:15 AM'),
        TimetableStop('Panchsheel Nagar', '08:17 AM'),
        TimetableStop('Mata Mandir', '08:18 AM'),
        TimetableStop('PNT Square', '08:20 AM'),
        TimetableStop('Nehru Nagar New Basti', '08:21 AM'),
        TimetableStop('Nehru Nagar Square', '08:25 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YP 7287',
      vehicleNo: 'MP04 YP 7287',
      routeName: 'Nadra Bus Stand & Depot Route',
      morningDeparture: '08:20 AM',
      campusArrival: '09:00 AM',
      driverName: 'Ram',
      driverPhone: '9131840531',
      scheduledStops: [
        TimetableStop('Nadra Bus Stand', '08:20 AM'),
        TimetableStop('Jahangirabad', '08:30 AM'),
        TimetableStop('Depot', '08:40 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 ZY 7230',
      vehicleNo: 'MP04 ZY 7230',
      routeName: 'Kalkheda & Neelbad Route',
      morningDeparture: '08:30 AM',
      campusArrival: '09:00 AM',
      driverName: 'Shriram',
      driverPhone: '8435525087',
      scheduledStops: [
        TimetableStop('Kalkheda', '08:30 AM'),
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YA 6721',
      vehicleNo: 'MP04 YA 6721',
      routeName: 'Neelbad Express Shuttle 1',
      morningDeparture: '08:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Ajay',
      driverPhone: '7024876498',
      scheduledStops: [
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 ZY 6164',
      vehicleNo: 'MP04 ZY 6164',
      routeName: 'Neelbad Express Shuttle 2',
      morningDeparture: '08:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Rohit',
      driverPhone: '8463041621',
      scheduledStops: [
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YG 7781',
      vehicleNo: 'MP04 YG 7781',
      routeName: 'Neelbad Express Shuttle 3',
      morningDeparture: '08:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Narendra',
      driverPhone: '6261692120',
      scheduledStops: [
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 YN 9981',
      vehicleNo: 'MP04 YN 9981',
      routeName: 'Neelbad Express Shuttle 4',
      morningDeparture: '08:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Shafeeq',
      driverPhone: '9754992746',
      scheduledStops: [
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
    ),
    TimetableRouteEntry(
      busNumber: 'MP04 PA 3629',
      vehicleNo: 'MP04 PA 3629',
      routeName: 'Neelbad Express Shuttle 5',
      morningDeparture: '08:40 AM',
      campusArrival: '09:00 AM',
      driverName: 'Aadil',
      driverPhone: '9826562362',
      scheduledStops: [
        TimetableStop('Neelbad (Durga Mandir Chouraha)', '08:40 AM'),
        TimetableStop('Neelbad (Government School Chouraha)', '08:42 AM'),
        TimetableStop('Neelbad (Kanak Sweets Chouraha)', '08:44 AM'),
        TimetableStop('Ratibad Campus', '09:00 AM'),
      ],
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

  /// Resolves an authentic, real-world schedule label formatted according to:
  /// 1. Current Day of Week (e.g. "MON", "TUE", "WED")
  /// 2. Active Operation Period (Morning Pickup vs Afternoon / Evening Return)
  /// 3. Official Timetable Departure Timings (e.g. "7:20 AM" or "4:30 PM")
  static String resolveRealtimeShiftLabel({
    String? routeName,
    String? direction, // 'pickup' or 'dropoff'
    bool isLive = false,
    int? currentHour,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final day = getCurrentDayLabel();
    final isSunday = now.weekday == DateTime.sunday;

    if (isLive) {
      return '$day • LIVE ON ROUTE';
    }

    if (isSunday) {
      return 'SUN • WEEKEND STANDBY';
    }

    final shifts = getShiftsForRoute(routeName);
    final entry = shifts.isNotEmpty ? shifts.first : masterFleet[1];
    final rawMorning = entry.morningDeparture; // e.g. "07:20 AM"
    final rawReturn = entry.returnDeparture;   // e.g. "04:30 PM"
    final morningDep = rawMorning.startsWith('0') ? rawMorning.substring(1) : rawMorning;
    final returnDep = rawReturn.startsWith('0') ? rawReturn.substring(1) : rawReturn;

    final hour = currentHour ?? now.hour;

    // If explicit direction is provided from user toggle ('pickup' or 'dropoff')
    if (direction == 'pickup') {
      return '$day • MORNING SHIFT ($morningDep)';
    } else if (direction == 'dropoff') {
      return '$day • RETURN SHIFT ($returnDep)';
    }

    // Dynamic resolution based on real time of day:
    if (hour < 5) {
      return '$day • STANDBY (Next: $morningDep)';
    } else if (hour < 12) {
      return '$day • MORNING SHIFT ($morningDep)';
    } else if (hour < 19) {
      return '$day • RETURN SHIFT ($returnDep)';
    } else {
      return '$day • SERVICE CONCLUDED (Next: $morningDep)';
    }
  }

  /// Resolves the shift label (e.g. "MON • RETURN SHIFT (4:30 PM)")
  static String resolveShiftLabel({
    String? explicitShift,
    String? routeName,
    int? currentHour,
    String? direction,
  }) {
    if (explicitShift != null && explicitShift.trim().isNotEmpty) {
      final s = explicitShift.trim().toUpperCase();
      if (s.contains('•')) return s;
      final day = getCurrentDayLabel();
      if (s.contains('SHIFT 1')) return '$day • MORNING SHIFT';
      if (s.contains('SHIFT 2')) return '$day • RETURN SHIFT';
      if (s.contains('SHIFT 3')) return '$day • EVENING SHIFT';
      return '$day • $s';
    }

    return resolveRealtimeShiftLabel(
      routeName: routeName,
      direction: direction,
      currentHour: currentHour,
    );
  }

  /// Returns the current day abbreviation (e.g. "MON", "TUE", "WED", "THU", "FRI", "SAT")
  static String getCurrentDayLabel() {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final now = DateTime.now();
    return days[now.weekday - 1];
  }

  /// Extracts bus number token if present (e.g. "Bus 01", "Bus 12", "Bus T-4", "Bus MP04 PA 1886")
  static String? _extractBusNoFromText(String? text) {
    if (text == null) return null;
    final match = RegExp(r'\bBus\s*([A-Za-z0-9\-\s]+?)(?:\s*[\-\:]|\s{2,}|$)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      return match.group(1)?.trim();
    }
    final rawNoMatch = RegExp(r'^(\d{1,2})\b').firstMatch(text.trim());
    if (rawNoMatch != null) {
      return rawNoMatch.group(1);
    }
    return null;
  }

  /// Returns all fleet timetable entries matching a route corridor or bus number
  static List<TimetableRouteEntry> getShiftsForRoute(String? routeName) {
    if (routeName == null || routeName.isEmpty) return [masterFleet[1]]; // Default Bus 02

    // 1. Direct Bus Number matching
    final busNo = _extractBusNoFromText(routeName);
    if (busNo != null && busNo.isNotEmpty) {
      final clean = busNo.toUpperCase().replaceAll('BUS', '').trim();
      final match = masterFleet.where((e) =>
        e.busNumber.toUpperCase() == clean ||
        e.busNumber.toUpperCase() == clean.padLeft(2, '0') ||
        clean == e.busNumber.toUpperCase().padLeft(2, '0') ||
        e.vehicleNo.toUpperCase().replaceAll(' ', '') == clean.replaceAll(' ', '')
      ).toList();
      if (match.isNotEmpty) return match;
    }

    // 2. Direct Corridor string matching
    final corridor = _extractKeyCorridor(routeName).toLowerCase();
    final matches = masterFleet.where((e) => e.routeName.toLowerCase().contains(corridor)).toList();
    if (matches.isNotEmpty) return matches;

    // 3. Check individual corridor keywords (e.g. 'kolar', 'karond', 'katara', 'ashta', 'sehore')
    final keywords = corridor.split(RegExp(r'[\s,/&\-]+')).where((w) => w.length > 2 && !w.startsWith('bus'));
    for (final kw in keywords) {
      final subMatches = masterFleet.where((e) => e.routeName.toLowerCase().contains(kw)).toList();
      if (subMatches.isNotEmpty) return subMatches;
    }

    return [masterFleet.firstWhere((e) => e.routeName.toLowerCase().contains(corridor), orElse: () => masterFleet[1])];
  }

  /// Resolves the complete bus entry details (registration, shift, timings, driver) for a route.
  static TimetableRouteEntry? resolveBusDetails({String? routeName, int? currentHour, String? busNo}) {
    if (busNo != null && busNo.isNotEmpty) {
      final clean = busNo.trim().toUpperCase().replaceAll('BUS', '').trim();
      final match = masterFleet.cast<TimetableRouteEntry?>().firstWhere(
        (e) => e != null && (
          e.busNumber.toUpperCase() == clean ||
          e.busNumber.toUpperCase() == clean.padLeft(2, '0') ||
          clean == e.busNumber.toUpperCase().padLeft(2, '0') ||
          e.vehicleNo.toUpperCase().replaceAll(' ', '') == clean.replaceAll(' ', '')
        ),
        orElse: () => null,
      );
      if (match != null) return match;
    }

    final list = getShiftsForRoute(routeName);
    if (list.isEmpty) return masterFleet[1];
    if (currentHour != null) {
      if (currentHour < 12 && list.isNotEmpty) return list.first;
      if (list.length > 1) return list[1];
    }
    return list.first;
  }

  /// Convenience lookup by busNumber, busName, or routeName
  static TimetableRouteEntry? lookupEntry({String? busNumber, String? busName, String? routeName}) {
    if (busNumber != null && busNumber.trim().isNotEmpty && !_isRawHexId(busNumber)) {
      final byNo = resolveBusDetails(busNo: busNumber);
      if (byNo != null) return byNo;
    }
    if (busName != null && busName.trim().isNotEmpty && !_isRawHexId(busName)) {
      final byName = resolveBusDetails(busNo: busName);
      if (byName != null) return byName;
    }
    return resolveBusDetails(routeName: routeName);
  }

  /// Resolves scheduled time for a given stop on a route
  static String? getScheduledTimeForStop(String? routeName, String stopName) {
    final entry = resolveBusDetails(routeName: routeName);
    if (entry != null) {
      final time = entry.getScheduledTime(stopName);
      if (time != null) return time;
    }
    // Fallback: search across all fleet entries for this stop
    final clean = TimetableRouteEntry._normalize(stopName);
    for (final e in masterFleet) {
      for (final s in e.scheduledStops) {
        final sNorm = TimetableRouteEntry._normalize(s.stopName);
        if (sNorm == clean || sNorm.contains(clean) || clean.contains(sNorm)) {
          return s.time;
        }
      }
    }
    return null;
  }

  /// Returns scheduled stops for a route
  static List<TimetableStop> getScheduledStopsForRoute(String? routeName) {
    final entry = resolveBusDetails(routeName: routeName);
    if (entry != null && entry.scheduledStops.isNotEmpty) {
      return entry.scheduledStops;
    }
    return const [];
  }

  static const List<String> routeColors = [
    '#2563EB', '#38EF7D', '#6366F1', '#EC4899', '#F59E0B',
    '#8B5CF6', '#10B981', '#3B82F6', '#14B8A6', '#F97316',
    '#06B6D4', '#84CC16', '#E11D48', '#A855F7', '#0EA5E9',
    '#EAB308', '#22C55E', '#D946EF', '#64748B', '#FB7185',
    '#38BDF8', '#4ADE80', '#C084FC', '#F43F5E', '#2DD4BF',
    '#34D399', '#F472B6', '#FBBF24', '#60A5FA', '#A78BFA',
    '#F87171', '#4FD1C5', '#818CF8', '#FB923C', '#22D3EE',
    '#A3E635', '#E879F9'
  ];

  /// Generates the complete JSON preview list for [TimetablePreviewScreen].
  /// Preserves ANY GPS coordinates already configured in [existingRoutes].
  static List<Map<String, dynamic>> toPreviewJsonList({List<dynamic>? existingRoutes}) {
    // 1. Build map of existing stop coordinates: normalized stop name -> {lat, lng}
    final existingCoords = <String, Map<String, double>>{};
    final existingRouteByBus = <String, Map<String, dynamic>>{};

    if (existingRoutes != null) {
      for (final r in existingRoutes) {
        if (r is Map) {
          final rName = (r['name'] ?? r['routeName'] ?? '').toString();
          final bNo = _extractBusDigits(rName);
          if (bNo.isNotEmpty) {
            existingRouteByBus[bNo] = Map<String, dynamic>.from(r);
          }
          final stops = r['stops'] is List ? (r['stops'] as List) : [];
          for (final s in stops) {
            if (s is Map && s['name'] != null && s['lat'] != null && s['lng'] != null) {
              final lat = double.tryParse(s['lat'].toString());
              final lng = double.tryParse(s['lng'].toString());
              if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
                final k = TimetableRouteEntry._normalize(s['name'].toString());
                existingCoords[k] = {'lat': lat, 'lng': lng};
              }
            }
          }
        }
      }
    }

    const defaultCampusCoords = {'lat': 23.180302, 'lng': 77.302695};

    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < masterFleet.length; i++) {
      final entry = masterFleet[i];
      final color = routeColors[i % routeColors.length];
      final cleanBusNo = entry.busNumber.padLeft(2, '0');
      final busDigits = _extractBusDigits(entry.busNumber);

      // Check if we have an existing database route for this bus to preserve its _id & custom coordinates
      final existingRoute = existingRouteByBus[busDigits];
      final existingId = existingRoute?['_id']?.toString();

      final stopsList = <Map<String, dynamic>>[];
      for (final s in entry.scheduledStops) {
        final stopKey = TimetableRouteEntry._normalize(s.stopName);
        double lat = defaultCampusCoords['lat']!;
        double lng = defaultCampusCoords['lng']!;

        // Check if existing route has this specific stop
        if (existingRoute != null && existingRoute['stops'] is List) {
          for (final exS in (existingRoute['stops'] as List)) {
            if (exS is Map && TimetableRouteEntry._normalize(exS['name']?.toString() ?? '') == stopKey) {
              final exLat = double.tryParse(exS['lat']?.toString() ?? '');
              final exLng = double.tryParse(exS['lng']?.toString() ?? '');
              if (exLat != null && exLng != null && exLat != 0.0) {
                lat = exLat;
                lng = exLng;
                break;
              }
            }
          }
        }

        // Global coordinate lookup
        if (lat == defaultCampusCoords['lat'] && existingCoords.containsKey(stopKey)) {
          lat = existingCoords[stopKey]!['lat']!;
          lng = existingCoords[stopKey]!['lng']!;
        }

        stopsList.add({
          'name': s.stopName,
          'time': s.time,
          'lat': lat,
          'lng': lng,
        });
      }

      final routeMap = <String, dynamic>{
        if (existingId != null && existingId.isNotEmpty) '_id': existingId,
        'busNumber': 'Bus $cleanBusNo',
        'vehicleNo': entry.vehicleNo,
        'routeName': entry.routeName,
        'fullName': 'Bus $cleanBusNo - ${entry.routeName}',
        'routeColor': existingRoute?['routeColor'] ?? color,
        'driverName': entry.driverName,
        'driverPhone': entry.driverPhone,
        'shift': entry.shift,
        'period': entry.period,
        'morningDeparture': entry.morningDeparture,
        'campusArrival': entry.campusArrival,
        'returnDeparture': entry.returnDeparture,
        'stops': stopsList,
      };

      result.add(routeMap);
    }

    return result;
  }

  static String _extractBusDigits(String text) {
    final m = RegExp(r'(\d{1,2})').firstMatch(text);
    return m != null ? m.group(1)!.padLeft(2, '0') : '';
  }

  static String _extractKeyCorridor(String name) {
    var cleaned = name.replaceAll(RegExp(r'^Bus\s*[^-\:]+[\-\:]\s*', caseSensitive: false), '').trim();
    final split = cleaned.split('&');
    if (split.isNotEmpty) return split.first.replaceAll(RegExp(r'Route|\(.*?\)'), '').trim();
    return cleaned;
  }

  static bool _isRawHexId(String text) {
    final clean = text.replaceAll('#', '').replaceAll('BUS', '').trim();
    return RegExp(r'^[0-9a-fA-F]{4,24}$').hasMatch(clean) && clean.length >= 4 && !RegExp(r'^\d+$').hasMatch(clean);
  }
}
