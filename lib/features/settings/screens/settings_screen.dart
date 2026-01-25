import 'package:flutter/material.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';
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
import 'package:bitemates/features/verification/screens/user_verification_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local State
  bool _hideDistance = false;

  // Notification Preferences
  bool _notifEventJoins = true;
  bool _notifChatMessages = true;
  bool _notifPostLikes = true;
  bool _notifPostComments = true;
  bool _isLoadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await SupabaseConfig.client
          .from('users')
          .select('notification_preferences')
          .eq('id', userId)
          .single();

      final prefs =
          response['notification_preferences'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _notifEventJoins = prefs['event_joins'] as bool? ?? true;
          _notifChatMessages = prefs['chat_messages'] as bool? ?? true;
          _notifPostLikes = prefs['post_likes'] as bool? ?? true;
          _notifPostComments = prefs['post_comments'] as bool? ?? true;
          _isLoadingPrefs = false;
        });
      }
    } catch (e) {
      print('Error loading notification preferences: $e');
      if (mounted) {
        setState(() => _isLoadingPrefs = false);
      }
    }
  }

  Future<void> _updateNotificationPreference(String key, bool value) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      await SupabaseConfig.client
          .from('users')
          .update({
            'notification_preferences': {
              'event_joins': key == 'event_joins' ? value : _notifEventJoins,
              'chat_messages': key == 'chat_messages'
                  ? value
                  : _notifChatMessages,
              'post_likes': key == 'post_likes' ? value : _notifPostLikes,
              'post_comments': key == 'post_comments'
                  ? value
                  : _notifPostComments,
            },
          })
          .eq('id', userId);
    } catch (e) {
      print('Error updating notification preference: $e');
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- Removed placeholder settings widgets (stepper, circle button) ---
  // These were for non-functional features: notification distance, age range

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
          // Account Section
          SettingsSection(
            title: 'ACCOUNT',
            children: [
              ListTile(
                leading: Icon(
                  Icons.verified_user,
                  color: Theme.of(context).primaryColor,
                ),
                title: const Text('Identity Verification'),
                subtitle: const Text('Get verified badge'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserVerificationScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const Divider(),

          // Notification Preferences Section
          SettingsSection(
            title: 'NOTIFICATIONS',
            children: [
              SettingsSwitchTile(
                icon: Icons.event,
                title: 'Event joins',
                subtitle: 'When someone joins your event',
                value: _notifEventJoins,
                onChanged: (val) async {
                  setState(() => _notifEventJoins = val);
                  await _updateNotificationPreference('event_joins', val);
                },
              ),
              SettingsSwitchTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chat messages',
                subtitle: 'New messages in your events',
                value: _notifChatMessages,
                onChanged: (val) async {
                  setState(() => _notifChatMessages = val);
                  await _updateNotificationPreference('chat_messages', val);
                },
              ),
              SettingsSwitchTile(
                icon: Icons.favorite_border,
                title: 'Post likes',
                subtitle: 'When someone likes your post',
                value: _notifPostLikes,
                onChanged: (val) async {
                  setState(() => _notifPostLikes = val);
                  await _updateNotificationPreference('post_likes', val);
                },
              ),
              SettingsSwitchTile(
                icon: Icons.comment_outlined,
                title: 'Comments',
                subtitle: 'When someone comments on your post',
                value: _notifPostComments,
                onChanged: (val) async {
                  setState(() => _notifPostComments = val);
                  await _updateNotificationPreference('post_comments', val);
                },
              ),
            ],
          ),

          const Divider(),
          SettingsSection(
            title: 'VISIBILITY',
            children: [
              SettingsSwitchTile(
                icon: Icons.visibility_off_outlined,
                title: 'Snooze mode (hide me from nearby list)',
                value: GeofenceEngine().isGhostMode,
                onChanged: (val) async {
                  await GeofenceEngine().setGhostMode(val);
                  setState(() {}); // Rebuild to show new state
                },
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
