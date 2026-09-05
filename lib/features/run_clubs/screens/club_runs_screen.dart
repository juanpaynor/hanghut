import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/club_run_service.dart';
import 'package:bitemates/features/run_clubs/screens/schedule_run_screen.dart';

/// A run club's upcoming scheduled runs. Members can RSVP; any member can
/// schedule a run.
class ClubRunsScreen extends StatefulWidget {
  final String groupId;
  final String? clubName;

  const ClubRunsScreen({super.key, required this.groupId, this.clubName});

  @override
  State<ClubRunsScreen> createState() => _ClubRunsScreenState();
}

class _ClubRunsScreenState extends State<ClubRunsScreen> {
  final _service = ClubRunService();
  List<ClubRun> _runs = [];
  bool _loading = true;
  final Set<String> _busy = {}; // run ids mid-RSVP

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final runs = await _service.listUpcoming(widget.groupId);
    if (!mounted) return;
    setState(() {
      _runs = runs;
      _loading = false;
    });
  }

  Future<void> _schedule() async {
    final created = await Navigator.of(context).push<ClubRun>(
      MaterialPageRoute(
        builder: (_) => ScheduleRunScreen(groupId: widget.groupId),
      ),
    );
    if (created != null) _load();
  }

  Future<void> _toggleRsvp(ClubRun run) async {
    if (_busy.contains(run.id)) return;
    setState(() => _busy.add(run.id));
    final ok = await _service.setRsvp(run.id, !run.iAmGoing);
    if (!mounted) return;
    if (ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update RSVP')),
      );
    }
    if (mounted) setState(() => _busy.remove(run.id));
  }

  String _distanceLabel(double? m) {
    if (m == null || m <= 0) return '';
    final km = m / 1000;
    return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clubName == null ? 'Runs' : '${widget.clubName} · Runs'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _schedule,
        icon: const Icon(Icons.add),
        label: const Text('Schedule a run'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _runs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _runCard(_runs[i]),
                  ),
                ),
    );
  }

  Widget _runCard(ClubRun run) {
    final theme = Theme.of(context);
    final when = DateFormat('EEE, MMM d · h:mm a').format(run.startAt);
    final dist = _distanceLabel(run.distanceM);
    final busy = _busy.contains(run.id);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              run.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 15, color: theme.hintColor),
                const SizedBox(width: 6),
                Text(when, style: TextStyle(color: theme.hintColor, fontSize: 13)),
              ],
            ),
            if (run.meetupLabel != null || dist.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.map_outlined, size: 15, color: theme.hintColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [
                        if (run.meetupLabel != null) run.meetupLabel!,
                        if (dist.isNotEmpty) dist,
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
            if (run.paceNote != null && run.paceNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(run.paceNote!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  run.goingCount == 1
                      ? '1 going'
                      : '${run.goingCount} going',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.hintColor,
                  ),
                ),
                const Spacer(),
                run.iAmGoing
                    ? OutlinedButton.icon(
                        onPressed: busy ? null : () => _toggleRsvp(run),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Going'),
                      )
                    : ElevatedButton(
                        onPressed: busy ? null : () => _toggleRsvp(run),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Join'),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event, size: 52, color: Colors.grey[400]),
                  const SizedBox(height: 14),
                  const Text(
                    'No runs scheduled',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Post your club\'s next run — tap Schedule a run.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
