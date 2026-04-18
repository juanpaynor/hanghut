import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'create_hangout_flow.dart';

/// Step 4: Review all selections before creating.
class StepReview extends StatefulWidget {
  final CreateHangoutFlowState flow;

  const StepReview({super.key, required this.flow});

  @override
  State<StepReview> createState() => _StepReviewState();
}

class _StepReviewState extends State<StepReview> with TickerProviderStateMixin {
  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Play entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  CreateHangoutFlowState get flow => widget.flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Looks good? 🎉',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review your hangout before posting',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),

          // ── GIF Preview (if any) ────────────────
          if (flow.selectedGifUrl != null) ...[
            _buildStaggeredCard(
              index: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  flow.selectedGifUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Activity & Venue Card ───────────────
          _buildStaggeredCard(
            index: 1,
            child: _ReviewCard(
              isDark: isDark,
              children: [
                _ReviewRow(
                  icon: Icons.local_activity_outlined,
                  label: 'Activity',
                  value: flow.activityController.text.trim().isNotEmpty
                      ? flow.activityController.text.trim()
                      : 'Not set',
                  isDark: isDark,
                ),
                if (flow.venueName != null)
                  _ReviewRow(
                    icon: Icons.location_on_outlined,
                    label: 'Venue',
                    value: flow.venueName!,
                    isDark: isDark,
                  ),
                if (flow.descriptionController.text.trim().isNotEmpty)
                  _ReviewRow(
                    icon: Icons.notes,
                    label: 'Details',
                    value: flow.descriptionController.text.trim(),
                    isDark: isDark,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── When Card ───────────────────────────
          _buildStaggeredCard(
            index: 2,
            child: _ReviewCard(
              isDark: isDark,
              children: [
                _ReviewRow(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value: DateFormat(
                    'EEEE, MMMM d, yyyy',
                  ).format(flow.selectedDateTime),
                  isDark: isDark,
                ),
                _ReviewRow(
                  icon: Icons.access_time,
                  label: 'Time',
                  value: DateFormat('h:mm a').format(flow.selectedDateTime),
                  isDark: isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Who Card ────────────────────────────
          _buildStaggeredCard(
            index: 3,
            child: _ReviewCard(
              isDark: isDark,
              children: [
                _ReviewRow(
                  icon: Icons.people_outline,
                  label: 'Max Guests',
                  value: flow.maxCapacity.round().toString(),
                  isDark: isDark,
                ),
                _ReviewRow(
                  icon: Icons.visibility_outlined,
                  label: 'Visibility',
                  value: _visibilityLabel(flow.visibility),
                  isDark: isDark,
                ),
                if (flow.requiresApproval)
                  _ReviewRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Approval',
                    value: 'Required',
                    isDark: isDark,
                  ),
                if (flow.invitedUsers.isNotEmpty)
                  _ReviewRow(
                    icon: Icons.person_add_outlined,
                    label: 'Invitations',
                    value: '${flow.invitedUsers.length} people',
                    isDark: isDark,
                  ),
                if (flow.genderFilter != 'everyone')
                  _ReviewRow(
                    icon: Icons.tune,
                    label: 'Gender',
                    value: _genderLabel(flow.genderFilter),
                    isDark: isDark,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Marker Preview ──────────────────────
          _buildStaggeredCard(
            index: 4,
            child: _ReviewCard(
              isDark: isDark,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.place,
                      size: 18,
                      color: AppTheme.primaryColor.withOpacity(0.7),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Map Marker',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                    const Spacer(),
                    if (flow.markerImage != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          flow.markerImage!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          flow.selectedEmoji ?? '📍',
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaggeredCard({required int index, required Widget child}) {
    final delay = (index * 0.12).clamp(0.0, 0.6);
    final end = (delay + 0.4).clamp(0.0, 1.0);

    final slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: Interval(delay, end, curve: Curves.easeOutCubic),
          ),
        );

    final fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: Interval(delay, end, curve: Curves.easeOut),
      ),
    );

    return SlideTransition(
      position: slideAnim,
      child: FadeTransition(opacity: fadeAnim, child: child),
    );
  }

  String _visibilityLabel(String v) {
    switch (v) {
      case 'public':
        return 'Public 🌍';
      case 'followers_only':
        return 'Followers Only 👥';
      case 'mystery':
        return 'Mystery 🔮';
      case 'group_only':
        return 'Group Members 🔒';
      default:
        return v;
    }
  }

  String _genderLabel(String g) {
    switch (g) {
      case 'women_only':
        return 'Women Only 👩';
      case 'men_only':
        return 'Men Only 👨';
      case 'nonbinary_only':
        return 'Non-binary Only 🏳️‍🌈';
      default:
        return 'Everyone 🌈';
    }
  }
}

// ── Review card container ────────────────────────────

class _ReviewCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _ReviewCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200]!,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.grey[100],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Review row ───────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor.withOpacity(0.7)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
