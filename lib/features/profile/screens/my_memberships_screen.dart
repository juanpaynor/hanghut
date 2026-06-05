import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class MyMembershipsScreen extends StatefulWidget {
  const MyMembershipsScreen({super.key});

  @override
  State<MyMembershipsScreen> createState() => _MyMembershipsScreenState();
}

class _MyMembershipsScreenState extends State<MyMembershipsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _memberships = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await SupabaseConfig.client
          .from('fan_subscriptions')
          .select(
            'id, tier_id, partner_id, status, current_period_start, '
            'current_period_end, cancelled_at, '
            'subscription_tiers(id, name, price_monthly, perks), '
            'partners(business_name, profile_photo_url, slug)',
          )
          .eq('fan_id', userId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _memberships = List<Map<String, dynamic>>.from(rows as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error loading memberships: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelMembership(Map<String, dynamic> sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel membership?'),
        content: const Text(
          'You will lose access when your current period ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupabaseConfig.client
          .from('fan_subscriptions')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sub['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel — please try again')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Memberships',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memberships.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 52,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No memberships yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Follow organizers to discover membership tiers.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accentColor,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                itemCount: _memberships.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) =>
                    _MembershipCard(
                      sub: _memberships[i],
                      isDark: isDark,
                      onCancel: () => _cancelMembership(_memberships[i]),
                    ),
              ),
            ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  final Map<String, dynamic> sub;
  final bool isDark;
  final VoidCallback onCancel;

  const _MembershipCard({
    required this.sub,
    required this.isDark,
    required this.onCancel,
  });

  IconData _perkIcon(String type) {
    switch (type) {
      case 'digital_download':
        return Icons.download_rounded;
      case 'community_link':
        return Icons.group_rounded;
      case 'merch':
        return Icons.redeem_rounded;
      case 'shoutout':
        return Icons.campaign_rounded;
      case 'early_access':
        return Icons.bolt_rounded;
      case 'gated_posts':
        return Icons.lock_open_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = sub['partners'] as Map<String, dynamic>?;
    final tier = sub['subscription_tiers'] as Map<String, dynamic>?;
    final status = sub['status'] as String? ?? '';
    final slug = partner?['slug'] as String? ?? '';
    final tierId = tier?['id'] as String? ?? '';

    final name = partner?['business_name'] as String? ?? 'Organizer';
    final photoUrl = partner?['profile_photo_url'] as String?;
    final tierName = tier?['name'] as String? ?? '';
    final price = tier?['price_monthly'];
    final rawPerks = tier?['perks'] as List? ?? [];
    final perks = rawPerks.cast<Map<String, dynamic>>();

    final periodEnd = sub['current_period_end'] as String?;
    DateTime? renewDate;
    if (periodEnd != null) renewDate = DateTime.tryParse(periodEnd);

    final isActive = status == 'active';
    final isGrace = status == 'grace_period';
    final isCancelled = status == 'cancelled';

    final statusColor = isActive
        ? Colors.green
        : isGrace
        ? Colors.orange
        : Colors.grey;
    final statusLabel = isActive
        ? 'Active'
        : isGrace
        ? 'Grace period'
        : isCancelled
        ? 'Cancelled'
        : status;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? const Color(0xFFFFD700).withOpacity(0.3)
              : isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    border: Border.all(
                      color: const Color(0xFFFFD700).withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.storefront_rounded,
                            size: 22,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : const Icon(
                          Icons.storefront_rounded,
                          size: 22,
                          color: AppTheme.primaryColor,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            size: 13,
                            color: Color(0xFFFFD700),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            tierName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (price != null) ...[
                            Text(
                              ' · ₱$price/mo',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Renewal date
          if (renewDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                isCancelled
                    ? 'Access until ${DateFormat('MMM d, y').format(renewDate)}'
                    : 'Renews ${DateFormat('MMM d, y').format(renewDate)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),

          // Perks
          if (perks.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'YOUR PERKS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.grey,
                ),
              ),
            ),
            ...perks.map((perk) {
              final label = perk['label'] as String? ?? '';
              final type = perk['type'] as String? ?? 'custom';
              final isDownload = type == 'digital_download';
              final isCommunity = type == 'community_link';
              final isClaim = type == 'merch' || type == 'shoutout';
              final url = perk['url'] as String? ?? '';

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Icon(_perkIcon(type),
                        size: 15, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if ((isDownload || isCommunity) &&
                        url.isNotEmpty &&
                        isActive)
                      _PerkButton(
                        label: isDownload ? 'Download' : 'Join',
                        onTap: () async {
                          if (isDownload && slug.isNotEmpty &&
                              tierId.isNotEmpty) {
                            final uri = Uri.parse(
                              'https://hanghut.com/api/perks/download?tierId=$tierId',
                            );
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          } else {
                            final uri = Uri.parse(
                              url.startsWith('http') ? url : 'https://$url',
                            );
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      )
                    else if (isClaim && isActive)
                      _PerkButton(
                        label: type == 'merch' ? 'Claim' : 'Request',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Claim flow coming soon',
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            }),
          ],

          // Footer actions
          if (!isCancelled) ...[
            const Divider(height: 24, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  if (slug.isNotEmpty)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final uri = Uri.parse(
                            'https://hanghut.com/$slug/membership',
                          );
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: BorderSide(
                            color: AppTheme.primaryColor.withOpacity(0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text(
                          'View page',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  if (slug.isNotEmpty) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        side: BorderSide(
                          color: Colors.red.withOpacity(0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PerkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PerkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}
