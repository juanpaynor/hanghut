import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitemates/providers/theme_provider.dart';
import 'package:bitemates/features/settings/widgets/settings_section.dart';
import 'package:bitemates/features/settings/widgets/settings_switch_tile.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/features/legal/screens/terms_of_service_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local State (Mocking backend preferences for now)
  bool _notifyNearby = true;
  int _notificationDistance = 20; // km
  int _minAge = 18;
  int _maxAge = 80; // "80+"
  bool _snoozeMode = false;
  bool _hideDistance = false;

  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _incrementDistance() {
    setState(
      () => _notificationDistance = (_notificationDistance + 5).clamp(5, 100),
    );
  }

  void _decrementDistance() {
    setState(
      () => _notificationDistance = (_notificationDistance - 5).clamp(5, 100),
    );
  }

  // --- Widgets ---

  Widget _buildStepper(
    String label,
    int value,
    VoidCallback onMinus,
    VoidCallback onPlus, {
    String suffix = '',
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircleButton(Icons.remove, onMinus),
            const SizedBox(width: 16),
            Text(
              '$value$suffix',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(width: 16),
            _buildCircleButton(Icons.add, onPlus),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!),
          color: isDark ? Colors.grey[800] : Colors.white,
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDark ? Colors.white : Colors.grey[600],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // 1. Notification Settings
          SettingsSwitchTile(
            icon: Icons.notifications_none,
            title: 'Notify me about activities nearby',
            value: _notifyNearby,
            onChanged: (val) => setState(() => _notifyNearby = val),
          ),

          if (_notifyNearby) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 56), // Align with text above
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.my_location,
                        size: 20,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      const SizedBox(width: 16),
                      // Flexible text to prevent overflow
                      const Expanded(
                        child: Text(
                          'Notification distance',
                          style: TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Custom mini stepper for distance
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red[50], // Light red bg
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.remove,
                            size: 16,
                            color: Colors.red,
                          ),
                        ),
                        onPressed: _decrementDistance,
                      ),
                      Text(
                        '$_notificationDistance km',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 16,
                            color: Colors.red,
                          ),
                        ),
                        onPressed: _incrementDistance,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),

            ListTile(
              leading: const SizedBox(width: 24), // Indent
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.category_outlined,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      const SizedBox(width: 16),
                      const Text('Activity types'),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'All types',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ],
                  ),
                ],
              ),
              onTap: () {}, // Future: Show multi-select dialog
            ),
          ],

          const Divider(),

          // 2. Creator Age Range
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Creator age range',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStepper(
                      'Min Age',
                      _minAge,
                      () => setState(() {
                        if (_minAge > 18) _minAge--;
                      }),
                      () => setState(() {
                        if (_minAge < _maxAge) _minAge++;
                      }),
                    ),
                    _buildStepper(
                      'Max Age',
                      _maxAge,
                      () => setState(() {
                        if (_maxAge > _minAge) _maxAge--;
                      }),
                      () => setState(() {
                        if (_maxAge < 100) _maxAge++;
                      }),
                      suffix: '+',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),
          SettingsSection(
            title: 'VISIBILITY',
            children: [
              SettingsSwitchTile(
                icon: Icons.visibility_off_outlined,
                title: 'Snooze mode (hide me from nearby list)',
                value: _snoozeMode,
                onChanged: (val) => setState(() => _snoozeMode = val),
              ),
              SettingsSwitchTile(
                icon: Icons.straighten,
                title: 'Hide my distance away from others',
                value: _hideDistance,
                // Nomadtable style has pink toggles for these
                onChanged: (val) => setState(() => _hideDistance = val),
              ),
              ListTile(
                leading: Icon(
                  Icons.block,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Blocked Users'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              // Moved Dark Mode here for consistency, or can keep seperate
              SwitchListTile(
                secondary: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Dark Mode'),
                activeColor: Theme.of(context).primaryColor,
                value: themeProvider.isDarkMode,
                onChanged: (value) => themeProvider.toggleTheme(value),
              ),
            ],
          ),

          const Divider(),

          SettingsSection(
            title: 'LEGAL',
            children: [
              ListTile(
                leading: Icon(
                  Icons.policy,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Terms of Service'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsOfServiceScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _launchUrl(AppConstants.privacyPolicyUrl),
              ),
            ],
          ),

          const Divider(),
          SettingsSection(
            title: 'SUPPORT',
            children: [
              ListTile(
                leading: Icon(
                  Icons.support_agent,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Contact Support'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Support chat placeholder')),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.bug_report_outlined,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: const Text('Report an Issue'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report issue placeholder')),
                  );
                },
              ),
            ],
          ),

          const Divider(),
          // LOGOUT functionality added here
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log Out'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );

              if (shouldLogout == true && context.mounted) {
                Navigator.of(
                  context,
                ).popUntil((route) => route.isFirst); // Clear stack
                await SupabaseConfig.client.auth.signOut();
                if (context.mounted) {
                  context.read<AuthProvider>().signOut();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                }
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor:
                      Colors.red, // Explicit color avoids Theme lerping issues
                  textStyle: const TextStyle(
                    inherit: true,
                  ), // Ensure inherit consistency
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Account'),
                      content: const Text(
                        'Are you sure? This action cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx); // Close dialog

                            // Mock Deletion Logic
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Account scheduled for deletion. Signing out...',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );

                            // Wait for snackbar
                            await Future.delayed(const Duration(seconds: 2));

                            if (context.mounted) {
                              // Perform Sign Out
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                              await SupabaseConfig.client.auth.signOut();
                              if (context.mounted) {
                                context.read<AuthProvider>().signOut();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                  (route) => false,
                                );
                              }
                            }
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Colors.red[400],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
