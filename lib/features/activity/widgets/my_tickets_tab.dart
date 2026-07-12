import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';
import 'package:bitemates/features/activity/widgets/my_experiences_list.dart';

/// "My Tickets" tab in Explore — merges event tickets and experience bookings
/// under one tab with a segmented toggle. Both lists are kept alive via
/// [IndexedStack] so switching doesn't reload or lose scroll position.
class MyTicketsTab extends StatefulWidget {
  const MyTicketsTab({super.key});

  @override
  State<MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<MyTicketsTab> {
  int _segment = 0; // 0 = Tickets, 1 = Experiences

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SegmentedToggle(
            selected: _segment,
            onChanged: (i) => setState(() => _segment = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: const [
              MyTicketsScreen(embedded: true),
              MyExperiencesList(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _SegmentedToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segButton(context, 'Tickets', Icons.confirmation_number_outlined, 0),
          _segButton(context, 'Experiences', Icons.explore_outlined, 1),
        ],
      ),
    );
  }

  Widget _segButton(BuildContext context, String label, IconData icon, int i) {
    final isSelected = selected == i;
    final primary = Theme.of(context).primaryColor;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
