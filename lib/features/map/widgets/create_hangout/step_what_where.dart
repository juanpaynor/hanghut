import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'create_hangout_flow.dart';

/// Step 1: Activity name, venue search, description.
class StepWhatWhere extends StatelessWidget {
  final CreateHangoutFlowState flow;

  const StepWhatWhere({super.key, required this.flow});

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
            // Group context banner
            if (flow.widget.groupId != null &&
                flow.widget.groupName != null) ...[
              _buildGroupBanner(context, flow.widget.groupName!),
              const SizedBox(height: 24),
            ],

            // ── I want to... ──────────────────────
            Text(
              'I want to...',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: flow.activityController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 22,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'grab coffee, play tennis, etc.',
                hintStyle: TextStyle(
                  color: theme.hintColor.withOpacity(0.5),
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => flow.rebuild(),
            ),

            // Divider
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200],
            ),

            const SizedBox(height: 24),

            // ── Where? ────────────────────────────
            _buildSectionLabel(context, 'Where?'),
            const SizedBox(height: 12),
            TextField(
              controller: flow.venueController,
              decoration: InputDecoration(
                hintText: 'Search for a place',
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.iconTheme.color?.withOpacity(0.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.map_outlined),
                  color: AppTheme.primaryColor,
                  tooltip: 'Pick on Map',
                  onPressed: flow.pickLocationOnMap,
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
              onChanged: (val) {
                if (flow.venueName != null && val != flow.venueName) {
                  flow.clearVenueSelection();
                }
              },
            ),

            // Venue selected indicator
            if (flow.venueName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      flow.venueAddress ?? flow.venueName!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[400],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Predictions
            if (flow.showPredictions && flow.venueController.text.isNotEmpty)
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
                  children: flow.placePredictions.map((p) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.primaryColor.withOpacity(0.7),
                        size: 20,
                      ),
                      title: Text(
                        p['main_text'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        p['secondary_text'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      onTap: () =>
                          flow.selectPlace(p['place_id'], p['description']),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),

            // ── Details ───────────────────────────
            _buildSectionLabel(context, 'Details'),
            const SizedBox(height: 12),
            TextField(
              controller: flow.descriptionController,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Add description, menu links, etc...',
                hintStyle: TextStyle(color: theme.hintColor.withOpacity(0.5)),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildSectionLabel(BuildContext context, String label) {
  return Text(
    label,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

Widget _buildGroupBanner(BuildContext context, String groupName) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.groups_outlined,
          size: 20,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Creating for $groupName',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    ),
  );
}
