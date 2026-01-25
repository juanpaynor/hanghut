import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:bitemates/features/support/screens/support_appeal_screen.dart';

class AccountSuspendedScreen extends StatelessWidget {
  final String status; // 'suspended', 'banned', or 'deleted'
  final String? reason;

  const AccountSuspendedScreen({super.key, required this.status, this.reason});

  @override
  Widget build(BuildContext context) {
    final isBanned = status == 'banned';
    final isSuspended = status == 'suspended';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: isBanned ? Colors.red[100] : Colors.orange[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBanned ? Icons.block : Icons.pause_circle_outline,
                  size: 64,
                  color: isBanned ? Colors.red[700] : Colors.orange[700],
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                isBanned ? 'Account Banned' : 'Account Suspended',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Status message
              Text(
                isBanned
                    ? 'Your account has been permanently banned from HangHut.'
                    : 'Your account has been temporarily suspended.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),

              if (reason != null) ...[
                const SizedBox(height: 24),

                // Reason container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isBanned ? Colors.red[300]! : Colors.orange[300]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: isBanned
                                ? Colors.red[700]
                                : Colors.orange[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reason',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Support message
              if (!isBanned) ...[
                Text(
                  'If you believe this is a mistake, please submit an appeal to our support team.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Support button
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SupportAppealScreen(
                          accountStatus: status,
                          statusReason: reason,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Submit Appeal'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Logout button
              ElevatedButton(
                onPressed: () async {
                  await SupabaseConfig.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Log Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
