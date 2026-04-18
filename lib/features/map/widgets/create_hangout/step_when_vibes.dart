import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'create_hangout_flow.dart';

/// Step 2: Date, time, GIF vibe, map marker emoji/image.
class StepWhenVibes extends StatefulWidget {
  final CreateHangoutFlowState flow;

  const StepWhenVibes({super.key, required this.flow});

  @override
  State<StepWhenVibes> createState() => _StepWhenVibesState();
}

class _StepWhenVibesState extends State<StepWhenVibes> {
  bool _showGifPicker = false;

  static const List<String> _commonEmojis = [
    '📍',
    '☕️',
    '🍺',
    '🍔',
    '🍕',
    '🍣',
    '🏀',
    '🎾',
    '🎬',
    '🎮',
    '🎤',
    '🏋️',
    '📚',
    '💻',
    '🎉',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final flow = widget.flow;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── When? ─────────────────────────────
            Text(
              'When?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Date chip
                Expanded(
                  child: _DateTimeChip(
                    icon: Icons.calendar_today,
                    label: DateFormat(
                      'EEE, MMM d',
                    ).format(flow.selectedDateTime),
                    onTap: flow.pickDate,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                // Time chip
                Expanded(
                  child: _DateTimeChip(
                    icon: Icons.access_time,
                    label: DateFormat('h:mm a').format(flow.selectedDateTime),
                    onTap: flow.pickTime,
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Add a Vibe (GIF) ──────────────────
            GestureDetector(
              onTap: () => setState(() => _showGifPicker = !_showGifPicker),
              child: Row(
                children: [
                  Text(
                    'Add a Vibe',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'GIF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (flow.selectedGifUrl != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Added ✅',
                        style: TextStyle(
                          color: Colors.green[600],
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    Icon(
                      _showGifPicker
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[500],
                    ),
                ],
              ),
            ),

            if (_showGifPicker) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 400,
                child: TenorGifPicker(
                  isEmbedded: true,
                  onGifSelected: (url) {
                    flow.selectedGifUrl = url;
                    flow.rebuild();
                    setState(() => _showGifPicker = false);
                  },
                ),
              ),
            ],

            // GIF Preview
            if (flow.selectedGifUrl != null) ...[
              const SizedBox(height: 16),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      flow.selectedGifUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        flow.selectedGifUrl = null;
                        flow.rebuild();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // ── Map Marker ────────────────────────
            Text(
              'Map Marker',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),

            // Image upload option
            GestureDetector(
              onTap: flow.pickMarkerImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: flow.markerImage != null
                      ? Colors.green.withOpacity(0.08)
                      : (isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: flow.markerImage != null
                        ? Colors.green.withOpacity(0.4)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      flow.markerImage != null
                          ? Icons.check_circle
                          : Icons.camera_alt_outlined,
                      color: flow.markerImage != null
                          ? Colors.green
                          : theme.iconTheme.color?.withOpacity(0.5),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      flow.markerImage != null
                          ? 'Custom Image Selected'
                          : 'Upload Custom Image',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: flow.markerImage != null
                            ? Colors.green[600]
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (flow.markerImage == null) ...[
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'OR CHOOSE AN EMOJI',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // "More" button
                    GestureDetector(
                      onTap: flow.showFullEmojiPicker,
                      child: Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: AppTheme.primaryColor.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_reaction_outlined,
                              color: AppTheme.primaryColor,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'More',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Quick emojis
                    ..._commonEmojis.take(10).map((emoji) {
                      final isSelected = flow.selectedEmoji == emoji;
                      return GestureDetector(
                        onTap: () {
                          flow.selectEmoji(emoji);
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 10),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : (isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.white),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : (isDark
                                        ? Colors.grey[700]!
                                        : Colors.grey[300]!),
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : [],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // Custom emoji preview
              if (!_commonEmojis.take(10).contains(flow.selectedEmoji) &&
                  flow.selectedEmoji != '📍')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Selected: ',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          flow.selectedEmoji!,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Reusable date/time chip ──────────────────────────

class _DateTimeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _DateTimeChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).iconTheme.color?.withOpacity(0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
