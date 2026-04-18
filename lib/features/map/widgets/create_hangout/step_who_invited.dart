import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'create_hangout_flow.dart';

/// Step 3: Capacity, visibility, approval, invite by handle, advanced filters.
class StepWhoInvited extends StatefulWidget {
  final CreateHangoutFlowState flow;

  const StepWhoInvited({super.key, required this.flow});

  @override
  State<StepWhoInvited> createState() => _StepWhoInvitedState();
}

class _StepWhoInvitedState extends State<StepWhoInvited> {
  bool _showAdvancedFilters = false;

  CreateHangoutFlowState get flow => widget.flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Max Guests ────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Max Guests',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    flow.maxCapacity.round().toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey[200],
                thumbColor: AppTheme.primaryColor,
                overlayColor: AppTheme.primaryColor.withOpacity(0.1),
                valueIndicatorColor: AppTheme.primaryColor,
              ),
              child: Slider(
                value: flow.maxCapacity,
                min: 2,
                max: 30,
                divisions: 28,
                onChanged: (val) {
                  flow.maxCapacity = val;
                  flow.rebuild();
                  setState(() {});
                },
              ),
            ),

            const SizedBox(height: 24),

            // ── Require Approval ──────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: flow.requiresApproval
                        ? AppTheme.primaryColor
                        : Colors.grey[500],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Require Approval',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Review who joins before they enter',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: flow.requiresApproval,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      flow.requiresApproval = val;
                      flow.rebuild();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Visibility ────────────────────────
            Text(
              'Who can see this?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _VisibilityOption(
                  label: 'Public',
                  icon: Icons.public,
                  value: 'public',
                  selected: flow.visibility,
                  color: AppTheme.primaryColor,
                  isDark: isDark,
                  onTap: () {
                    flow.visibility = 'public';
                    flow.rebuild();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                _VisibilityOption(
                  label: 'Followers',
                  icon: Icons.people_outline,
                  value: 'followers_only',
                  selected: flow.visibility,
                  color: AppTheme.primaryColor,
                  isDark: isDark,
                  onTap: () {
                    flow.visibility = 'followers_only';
                    flow.rebuild();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                _VisibilityOption(
                  label: 'Mystery',
                  emoji: '🔮',
                  value: 'mystery',
                  selected: flow.visibility,
                  color: const Color(0xFF7C3AED),
                  isDark: isDark,
                  onTap: () {
                    flow.visibility = 'mystery';
                    flow.rebuild();
                    setState(() {});
                  },
                ),
                if (flow.widget.groupId != null) ...[
                  const SizedBox(width: 8),
                  _VisibilityOption(
                    label: 'Members',
                    icon: Icons.lock_outline,
                    value: 'group_only',
                    selected: flow.visibility,
                    color: const Color(0xFF059669),
                    isDark: isDark,
                    onTap: () {
                      flow.visibility = 'group_only';
                      flow.rebuild();
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),

            // Hint texts
            if (flow.visibility == 'mystery')
              _VisibilityHint(
                text:
                    'Only visible to people who scan this area with the walking pulse',
                color: const Color(0xFF7C3AED),
              ),
            if (flow.visibility == 'group_only')
              _VisibilityHint(
                text: 'Only group members can see this activity',
                color: const Color(0xFF059669),
              ),

            const SizedBox(height: 24),

            // ── Invite People ─────────────────────
            Text(
              'Invite People',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Search by @username to invite friends',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: flow.inviteController,
              onChanged: flow.onInviteSearchChanged,
              decoration: InputDecoration(
                hintText: '@username',
                prefixIcon: Icon(
                  Icons.alternate_email,
                  color: theme.iconTheme.color?.withOpacity(0.5),
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),

            // Search results
            if (flow.showInviteResults && flow.inviteSearchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: flow.inviteSearchResults.map((user) {
                    final displayName = user['display_name'] ?? 'User';
                    final username = user['username'] ?? '';
                    final avatarUrl = user['avatar_url'];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: username.isNotEmpty
                          ? Text(
                              '@$username',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            )
                          : null,
                      trailing: Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: AppTheme.primaryColor,
                      ),
                      onTap: () {
                        flow.addInvitedUser(user);
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),

            // Invited chips
            if (flow.invitedUsers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(flow.invitedUsers.length, (i) {
                  final user = flow.invitedUsers[i];
                  final name = user['display_name'] ?? 'User';
                  final username = user['username'] ?? '';
                  return Chip(
                    avatar: CircleAvatar(
                      radius: 12,
                      backgroundImage: user['avatar_url'] != null
                          ? NetworkImage(user['avatar_url'])
                          : null,
                      child: user['avatar_url'] == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 10),
                            )
                          : null,
                    ),
                    label: Text(
                      username.isNotEmpty ? '@$username' : name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      flow.removeInvitedUser(i);
                      setState(() {});
                    },
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(0.06)
                        : AppTheme.primaryColor.withOpacity(0.08),
                    side: BorderSide(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                    ),
                  );
                }),
              ),
            ],

            const SizedBox(height: 24),

            // ── Advanced Filters (Collapsible) ────
            GestureDetector(
              onTap: () =>
                  setState(() => _showAdvancedFilters = !_showAdvancedFilters),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 20,
                    color: _showAdvancedFilters
                        ? AppTheme.primaryColor
                        : Colors.grey[500],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Advanced Filters',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (flow.genderFilter != 'everyone' || flow.ageFilterEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _showAdvancedFilters
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),

            if (_showAdvancedFilters) ...[
              const SizedBox(height: 16),

              // Gender preference
              Text(
                'Gender Preference',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: flow.genderFilter,
                    isExpanded: true,
                    dropdownColor: isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.white,
                    items: const [
                      DropdownMenuItem(
                        value: 'everyone',
                        child: Text('Everyone Welcome 🌈'),
                      ),
                      DropdownMenuItem(
                        value: 'women_only',
                        child: Text('Women Only 👩'),
                      ),
                      DropdownMenuItem(
                        value: 'men_only',
                        child: Text('Men Only 👨'),
                      ),
                      DropdownMenuItem(
                        value: 'nonbinary_only',
                        child: Text('Non-binary Only 🏳️‍🌈'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        flow.genderFilter = val;
                        flow.rebuild();
                        setState(() {});
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Age range
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Age Range',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: flow.ageFilterEnabled,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      flow.ageFilterEnabled = val;
                      flow.rebuild();
                      setState(() {});
                    },
                  ),
                ],
              ),
              if (flow.ageFilterEnabled) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${flow.ageRange.start.round()} yrs',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${flow.ageRange.end.round()} yrs',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primaryColor,
                    inactiveTrackColor: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey[200],
                    thumbColor: AppTheme.primaryColor,
                    overlayColor: AppTheme.primaryColor.withOpacity(0.1),
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: RangeSlider(
                    values: flow.ageRange,
                    min: 18,
                    max: 65,
                    divisions: 47,
                    onChanged: (val) {
                      flow.ageRange = val;
                      flow.rebuild();
                      setState(() {});
                    },
                  ),
                ),
              ],

              // Enforcement mode
              if (flow.genderFilter != 'everyone' || flow.ageFilterEnabled) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.04)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enforcement',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _EnforcementOption(
                            label: 'Soft Label',
                            subtitle: 'Tag only',
                            icon: Icons.label_outline,
                            value: 'soft',
                            selected: flow.enforcement,
                            isDark: isDark,
                            color: Colors.amber,
                            onTap: () {
                              flow.enforcement = 'soft';
                              flow.rebuild();
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 12),
                          _EnforcementOption(
                            label: 'Enforced',
                            subtitle: 'Blocks join',
                            icon: Icons.lock_outline,
                            value: 'hard',
                            selected: flow.enforcement,
                            isDark: isDark,
                            color: Colors.red,
                            onTap: () {
                              flow.enforcement = 'hard';
                              flow.rebuild();
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Visibility option chip ───────────────────────────

class _VisibilityOption extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? emoji;
  final String value;
  final String selected;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _VisibilityOption({
    required this.label,
    this.icon,
    this.emoji,
    required this.value,
    required this.selected,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
          ),
          child: Column(
            children: [
              if (emoji != null)
                Text(
                  emoji!,
                  style: TextStyle(
                    fontSize: 16,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Visibility hint ──────────────────────────────────

class _VisibilityHint extends StatelessWidget {
  final String text;
  final Color color;

  const _VisibilityHint({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Enforcement option ───────────────────────────────

class _EnforcementOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final String value;
  final String selected;
  final bool isDark;
  final Color color;
  final VoidCallback onTap;

  const _EnforcementOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.12)
                : (isDark ? Colors.grey[700] : Colors.grey[100]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : Colors.transparent),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? color : Colors.grey[500],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? color : Colors.grey[500],
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
