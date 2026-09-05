import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/club_route_service.dart';
import 'package:bitemates/core/services/club_run_service.dart';

/// Schedule a group run for a club: title, date/time, an optional saved route
/// (meetup + distance derived from it), and a pace note. Pops the created
/// [ClubRun] on success.
class ScheduleRunScreen extends StatefulWidget {
  final String groupId;

  const ScheduleRunScreen({super.key, required this.groupId});

  @override
  State<ScheduleRunScreen> createState() => _ScheduleRunScreenState();
}

class _ScheduleRunScreenState extends State<ScheduleRunScreen> {
  final _title = TextEditingController(text: 'Club Run');
  final _pace = TextEditingController();

  DateTime? _date;
  TimeOfDay? _time;

  List<ClubRoute> _routes = [];
  ClubRoute? _selectedRoute;
  bool _loadingRoutes = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _title.dispose();
    _pace.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final routes = await ClubRouteService().listRoutes(widget.groupId);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loadingRoutes = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 6, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  String _distanceLabel(double? m) {
    if (m == null || m <= 0) return '';
    final km = m / 1000;
    return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';
  }

  Future<void> _save() async {
    if (_date == null || _time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date and time')),
      );
      return;
    }
    final title = _title.text.trim().isEmpty ? 'Club Run' : _title.text.trim();
    final startAt = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );

    // Derive meetup + distance from the selected route (its start point).
    double? meetupLat, meetupLng;
    final coords = _selectedRoute?.path?['coordinates'];
    if (coords is List && coords.isNotEmpty && coords.first is List) {
      final first = coords.first as List;
      if (first.length >= 2) {
        meetupLng = (first[0] as num).toDouble();
        meetupLat = (first[1] as num).toDouble();
      }
    }

    setState(() => _saving = true);
    final run = await ClubRunService().createRun(
      groupId: widget.groupId,
      title: title,
      startAt: startAt,
      routeId: _selectedRoute?.id,
      distanceM: _selectedRoute?.distanceM,
      meetupLat: meetupLat,
      meetupLng: meetupLng,
      meetupLabel: _selectedRoute?.name,
      paceNote: _pace.text.trim().isEmpty ? null : _pace.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (run == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not schedule the run — try again')),
      );
      return;
    }
    Navigator.of(context).pop(run);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText =
        _date == null ? 'Select date' : DateFormat('EEE, MMM d').format(_date!);
    final timeText = _time == null ? 'Select time' : _time!.format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule a run')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Run name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _pickerTile(
                  icon: Icons.calendar_today,
                  label: dateText,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pickerTile(
                  icon: Icons.access_time,
                  label: timeText,
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Route', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_loadingRoutes)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else
            DropdownButtonFormField<ClubRoute?>(
              initialValue: _selectedRoute,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.map_outlined),
              ),
              hint: Text(
                _routes.isEmpty
                    ? 'No routes yet — optional'
                    : 'Pick a route (optional)',
              ),
              items: [
                const DropdownMenuItem<ClubRoute?>(
                  value: null,
                  child: Text('No route'),
                ),
                ..._routes.map(
                  (r) => DropdownMenuItem<ClubRoute?>(
                    value: r,
                    child: Text(
                      _distanceLabel(r.distanceM).isEmpty
                          ? r.name
                          : '${r.name} · ${_distanceLabel(r.distanceM)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedRoute = v),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _pace,
            decoration: const InputDecoration(
              labelText: 'Pace note (optional)',
              hintText: 'e.g. easy 6:00–7:00 /km, all levels welcome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Scheduling…' : 'Schedule run'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
