import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  final ApiService _apiService = ApiService();
  
  List<dynamic> _allUsers = [];
  List<RouteModel> _routes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _roleFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userData = await _apiService.get('admin/users');
      final routeData = await _apiService.get('routes');
      
      setState(() {
        _allUsers = userData as List;
        _routes = (routeData as List).map((r) => RouteModel.fromJson(r)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading admin permissions data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin': return Colors.purpleAccent;
      case 'manager': return Colors.blueAccent;
      case 'driver': return Colors.tealAccent;
      default: return Colors.blue;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin': return Icons.admin_panel_settings_rounded;
      case 'manager': return Icons.manage_accounts_rounded;
      case 'driver': return Icons.directions_bus_rounded;
      default: return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allUsers.where((u) {
      final username = u['username']?.toString().toLowerCase() ?? '';
      final name = u['name']?.toString().toLowerCase() ?? '';
      final email = u['email']?.toString().toLowerCase() ?? '';
      final role = u['role']?.toString().toLowerCase() ?? '';
      
      final matchesSearch = username.contains(_searchQuery.toLowerCase()) ||
                            name.contains(_searchQuery.toLowerCase()) ||
                            email.contains(_searchQuery.toLowerCase());
                            
      final matchesRole = _roleFilter == 'All' || role == _roleFilter.toLowerCase();
      
      return matchesSearch && matchesRole;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ROLES & PERMISSIONS',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserDialog,
        backgroundColor: Colors.purpleAccent,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text('CREATE USER', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [Color(0xFF0F172A), Color(0xFF121212)],
          ),
        ),
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: TextField(
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by name, UID or email...',
                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
            
            // Filter chips
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: ['All', 'Admin', 'Manager', 'Driver', 'User'].map((role) {
                  final isSelected = _roleFilter == role;
                  final roleColor = role == 'All' ? Colors.blueAccent : _getRoleColor(role);
                  return GestureDetector(
                    onTap: () => setState(() => _roleFilter = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? roleColor.withValues(alpha: 0.15) 
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected 
                              ? roleColor.withValues(alpha: 0.4) 
                              : Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          role.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            color: isSelected ? roleColor : Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            
            // Users list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.group_off_rounded, color: Colors.white24, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No users match criteria',
                                style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final user = filtered[index];
                            final role = user['role']?.toString() ?? 'user';
                            final roleColor = _getRoleColor(role);
                            final roleIcon = _getRoleIcon(role);
                            final username = user['username'] ?? '';
                            final name = user['name'] ?? username;
                            final status = user['status']?.toString() ?? 'Active';
                            final isActive = status.toLowerCase() == 'active';
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E).withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: () => _showUserDetailsBottomSheet(user),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(color: isActive ? roleColor : Colors.orangeAccent, width: 4),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: roleColor.withValues(alpha: 0.1),
                                          child: Icon(roleIcon, color: roleColor, size: 20),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: roleColor.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: roleColor.withValues(alpha: 0.2)),
                                                    ),
                                                    child: Text(
                                                      role.toUpperCase(),
                                                      style: GoogleFonts.plusJakartaSans(color: roleColor, fontSize: 7.5, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'UID: $username',
                                                style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                              if (user['email'] != null && user['email'].toString().isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  user['email'],
                                                  style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ).animate().fadeIn().slideY(begin: 0.1);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetailsBottomSheet(dynamic user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _AdminUserDetailsBottomSheet(
          user: Map<String, dynamic>.from(user),
          apiService: _apiService,
          onDataChanged: _loadData,
          onDeleteUser: (userId, role) async {
            setState(() => _isLoading = true);
            try {
              await _apiService.delete('admin/users/$role/$userId');
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User deleted successfully.'), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
                );
              }
            }
          },
        );
      },
    );
  }

  Widget _buildFieldItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? 'N/A' : value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateUserDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String role = 'user';
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F1528),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.person_add_rounded, color: Colors.purpleAccent, size: 24),
                  const SizedBox(width: 12),
                  Text('Create New User', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameCtrl,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'USERNAME (UID / ENROLLMENT ID)',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'PASSWORD',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'FULL NAME',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'EMAIL ADDRESS',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ASSIGN ROLE:', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: role,
                          dropdownColor: const Color(0xFF0F1528),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => role = val);
                            }
                          },
                          items: ['admin', 'manager', 'driver', 'user'].map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: _getRoleColor(r))),
                          )).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    final username = usernameCtrl.text.trim();
                    final password = passwordCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();

                    if (username.isEmpty || password.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Username is required. Password must be at least 6 chars.'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      await _apiService.post('admin/users', {
                        'username': username,
                        'password': password,
                        'role': role,
                        'name': name.isEmpty ? username : name,
                        'email': email,
                      });
                      
                      if (mounted) {
                        Navigator.pop(dialogCtx);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User account created successfully!'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Creation failed: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('CREATE', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AdminUserDetailsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final ApiService apiService;
  final VoidCallback onDataChanged;
  final Function(String, String) onDeleteUser;

  const _AdminUserDetailsBottomSheet({
    required this.user,
    required this.apiService,
    required this.onDataChanged,
    required this.onDeleteUser,
  });

  @override
  State<_AdminUserDetailsBottomSheet> createState() => _AdminUserDetailsBottomSheetState();
}

class _AdminUserDetailsBottomSheetState extends State<_AdminUserDetailsBottomSheet> {
  late bool isEditing;
  late bool isUpdating;
  late Map<String, dynamic> user;

  late TextEditingController nameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController departmentCtrl;
  late TextEditingController employeeIdCtrl;
  late TextEditingController assignedBusCtrl;
  late TextEditingController courseCtrl;
  late TextEditingController pickupCtrl;
  late TextEditingController passwordCtrl;

  late String selectedRole;
  late List<String> userRights;
  late List<String> canManage;

  final List<String> availableRoles = ['admin', 'manager', 'driver', 'user'];
  final List<String> standardRights = ['view_routes', 'track_bus', 'manage_fleet', 'manage_users', 'view_logs'];
  final List<String> managerOptions = ['students', 'drivers', 'buses', 'routes', 'alerts'];

  @override
  void initState() {
    super.initState();
    isEditing = false;
    isUpdating = false;
    user = Map<String, dynamic>.from(widget.user);

    nameCtrl = TextEditingController(text: user['name'] ?? user['username'] ?? '');
    emailCtrl = TextEditingController(text: user['email'] ?? '');
    phoneCtrl = TextEditingController(text: user['phone'] ?? user['contactNumber'] ?? '');
    departmentCtrl = TextEditingController(text: user['department'] ?? '');
    employeeIdCtrl = TextEditingController(text: user['employeeId'] ?? '');
    assignedBusCtrl = TextEditingController(text: user['assignedBus'] ?? '');
    courseCtrl = TextEditingController(text: user['courseName'] ?? '');
    pickupCtrl = TextEditingController(text: user['pickupPoint'] ?? '');
    passwordCtrl = TextEditingController();

    selectedRole = user['role']?.toString() ?? 'user';
    userRights = List<String>.from(user['accessRights'] ?? ['view_routes', 'track_bus']);
    canManage = List<String>.from(user['canManage'] ?? ['students', 'drivers', 'buses']);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    departmentCtrl.dispose();
    employeeIdCtrl.dispose();
    assignedBusCtrl.dispose();
    courseCtrl.dispose();
    pickupCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  Color _getRoleColor(String r) {
    switch (r.toLowerCase()) {
      case 'admin':
        return Colors.redAccent;
      case 'manager':
        return Colors.orangeAccent;
      case 'driver':
        return const Color(0xFF38EF7D);
      default:
        return Colors.purpleAccent;
    }
  }

  IconData _getRoleIcon(String r) {
    switch (r.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'manager':
        return Icons.manage_accounts_rounded;
      case 'driver':
        return Icons.directions_bus_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Widget _buildFieldItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? 'N/A' : value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEditableTextField(TextEditingController ctrl, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: ctrl,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentRole = user['role']?.toString() ?? 'user';
    final roleColor = _getRoleColor(selectedRole);
    final status = user['status']?.toString() ?? 'Active';
    final isActive = status.toLowerCase() == 'active';
    final statusColor = isActive ? const Color(0xFF38EF7D) : Colors.orangeAccent;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.15)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: roleColor.withValues(alpha: 0.1),
                        child: Icon(_getRoleIcon(selectedRole), color: roleColor, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            isEditing
                                ? buildEditableTextField(nameCtrl, 'Full Name')
                                : Text(
                                    user['name'] ?? user['username'] ?? 'Unknown',
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                                  ),
                            const SizedBox(height: 4),
                            Text(
                              'UID: ${user['username']}',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white10, height: 1),
                
                // Scrollable Contents
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Role Selection Row
                      Text('ROLE DEFINITION', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      if (isEditing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedRole,
                              dropdownColor: const Color(0xFF0D0B14),
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              iconEnabledColor: Colors.purpleAccent,
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => selectedRole = val);
                                }
                              },
                              items: availableRoles.map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(r.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: _getRoleColor(r))),
                              )).toList(),
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Icon(Icons.badge_rounded, color: roleColor, size: 18),
                            const SizedBox(width: 12),
                            Text(
                              selectedRole.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(color: roleColor, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      const SizedBox(height: 24),

                      // Edit Password field
                      if (isEditing) ...[
                        Text('SECURITY', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        buildEditableTextField(passwordCtrl, 'New Password (Leave blank to keep current)'),
                        const SizedBox(height: 24),
                      ],

                      // Fields based on role
                      Text('PROFILE ATTRIBUTES', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),

                      if (selectedRole == 'admin' || selectedRole == 'manager' || selectedRole == 'user') ...[
                        if (isEditing)
                          buildEditableTextField(emailCtrl, 'Email Address')
                        else
                          _buildFieldItem('Email Address', user['email'] ?? 'N/A', Icons.alternate_email_rounded),
                      ],

                      if (selectedRole == 'user' || selectedRole == 'driver') ...[
                        if (isEditing)
                          buildEditableTextField(phoneCtrl, 'Contact Phone')
                        else
                          _buildFieldItem('Contact Phone', (user['phone'] ?? user['contactNumber'] ?? 'N/A'), Icons.phone_android_rounded),
                      ],

                      // Manager specific fields
                      if (selectedRole == 'manager') ...[
                        if (isEditing) ...[
                          buildEditableTextField(employeeIdCtrl, 'Employee ID'),
                          buildEditableTextField(departmentCtrl, 'Department'),
                        ] else ...[
                          _buildFieldItem('Employee ID', user['employeeId'] ?? 'N/A', Icons.pin_rounded),
                          _buildFieldItem('Department', user['department'] ?? 'N/A', Icons.business_rounded),
                        ],
                        const SizedBox(height: 20),
                        Text('MANAGEMENT BREADTH', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        ...managerOptions.map((opt) {
                          final hasOpt = canManage.contains(opt);
                          return CheckboxListTile(
                            title: Text(opt.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            value: hasOpt,
                            activeColor: Colors.blueAccent,
                            checkColor: Colors.white,
                            onChanged: isEditing ? (val) {
                              setState(() {
                                if (val == true) {
                                  canManage.add(opt);
                                } else {
                                  canManage.remove(opt);
                                }
                              });
                            } : null,
                          );
                        }),
                      ],

                      // Driver specific fields
                      if (selectedRole == 'driver') ...[
                        if (isEditing)
                          buildEditableTextField(assignedBusCtrl, 'Assigned Bus Number')
                        else
                          _buildFieldItem('Assigned Bus', user['assignedBus'] ?? 'N/A', Icons.directions_bus_rounded),
                      ],

                      // User specific fields
                      if (selectedRole == 'user') ...[
                        if (isEditing) ...[
                          buildEditableTextField(courseCtrl, 'Course / Semester'),
                          buildEditableTextField(pickupCtrl, 'Pickup Stop'),
                        ] else ...[
                          _buildFieldItem('Course / Semester', user['courseName'] ?? 'N/A', Icons.school_rounded),
                          _buildFieldItem('Pickup Stop', user['pickupPoint'] ?? 'N/A', Icons.location_on_rounded),
                        ],
                        const SizedBox(height: 20),
                        Text('ACCESS RIGHTS / PERMISSIONS', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        ...standardRights.map((right) {
                          final hasRight = userRights.contains(right);
                          return CheckboxListTile(
                            title: Text(right.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            value: hasRight,
                            activeColor: Colors.purpleAccent,
                            checkColor: Colors.white,
                            onChanged: isEditing ? (val) {
                              setState(() {
                                if (val == true) {
                                  userRights.add(right);
                                } else {
                                  userRights.remove(right);
                                }
                              });
                            } : null,
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                
                const Divider(color: Colors.white10, height: 1),
                
                // Actions
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        // Toggle status button
                        if (selectedRole != 'admin')
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isUpdating ? null : () async {
                                setState(() => isUpdating = true);
                                try {
                                  final newStatus = isActive ? 'Suspended' : 'Active';
                                  await widget.apiService.put('admin/users/$currentRole/${user['_id']}', {'status': newStatus});
                                  setState(() {
                                    user['status'] = newStatus;
                                    isUpdating = false;
                                  });
                                  widget.onDataChanged();
                                } catch (e) {
                                  setState(() => isUpdating = false);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isActive ? Colors.orangeAccent.withValues(alpha: 0.1) : const Color(0xFF38EF7D).withValues(alpha: 0.1),
                                foregroundColor: isActive ? Colors.orangeAccent : const Color(0xFF38EF7D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: isUpdating
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(isActive ? 'SUSPEND' : 'ACTIVATE', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          
                        if (selectedRole != 'admin') const SizedBox(width: 10),

                        // Edit/Save Details Button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isUpdating ? null : () async {
                              if (isEditing) {
                                setState(() => isUpdating = true);
                                try {
                                  final body = <String, dynamic>{
                                    'role': selectedRole,
                                    'name': nameCtrl.text.trim(),
                                    'email': emailCtrl.text.trim(),
                                    'phone': phoneCtrl.text.trim(),
                                    'status': status,
                                  };
                                  
                                  if (passwordCtrl.text.isNotEmpty) {
                                    body['password'] = passwordCtrl.text.trim();
                                  }

                                  // Manager attributes
                                  if (selectedRole == 'manager') {
                                    body['employeeId'] = employeeIdCtrl.text.trim();
                                    body['department'] = departmentCtrl.text.trim();
                                    body['canManage'] = canManage;
                                  }
                                  // Driver attributes
                                  if (selectedRole == 'driver') {
                                    body['assignedBus'] = assignedBusCtrl.text.trim();
                                    body['contactNumber'] = phoneCtrl.text.trim();
                                  }
                                  // User attributes
                                  if (selectedRole == 'user') {
                                    body['courseName'] = courseCtrl.text.trim();
                                    body['pickupPoint'] = pickupCtrl.text.trim();
                                    body['accessRights'] = userRights;
                                  }

                                  await widget.apiService.put('admin/users/$currentRole/${user['_id']}', body);
                                  
                                  if (mounted) {
                                    Navigator.pop(context); // Close details sheet on role change to avoid layout mismatch
                                    widget.onDataChanged();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('User permissions updated successfully.'), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  setState(() => isUpdating = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              } else {
                                setState(() => isEditing = true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isEditing ? const Color(0xFF38EF7D) : Colors.white.withValues(alpha: 0.05),
                              foregroundColor: isEditing ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: isUpdating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(isEditing ? 'SAVE CHANGES' : 'EDIT DETAILS', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        
                        const SizedBox(width: 10),

                        // Delete Button
                        if (user['username'] != 'admin' && user['_id'] != user['id'])
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E1E),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                    title: Text('Delete Account?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                    content: Text('Are you sure you want to permanently delete this account? This action cannot be undone.', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx); // Close dialog
                                          Navigator.pop(context); // Close bottom sheet
                                          widget.onDeleteUser(user['_id'], currentRole);
                                        },
                                        child: Text('DELETE', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
