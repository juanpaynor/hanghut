import 'package:flutter/material.dart';
import 'package:bitemates/core/services/club_route_service.dart';
import 'package:bitemates/features/run_clubs/screens/route_creator_screen.dart';
import 'package:bitemates/features/run_clubs/screens/route_viewer_screen.dart';

/// A run club's saved route library. Lists routes and launches the in-app
/// snap-to-roads creator. Tap-to-view (read-only map render) is the next slice.
class ClubRoutesScreen extends StatefulWidget {
  final String groupId;
  final String? clubName;
  final double? clubLat;
  final double? clubLng;

  const ClubRoutesScreen({
    super.key,
    required this.groupId,
    this.clubName,
    this.clubLat,
    this.clubLng,
  });

  @override
  State<ClubRoutesScreen> createState() => _ClubRoutesScreenState();
}

class _ClubRoutesScreenState extends State<ClubRoutesScreen> {
  final _service = ClubRouteService();
  List<ClubRoute> _routes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final routes = await _service.listRoutes(widget.groupId);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loading = false;
    });
  }

  Future<void> _createRoute() async {
    final saved = await Navigator.of(context).push<ClubRoute>(
      MaterialPageRoute(
        builder: (_) => RouteCreatorScreen(
          groupId: widget.groupId,
          initialLat: widget.clubLat,
          initialLng: widget.clubLng,
        ),
      ),
    );
    if (saved != null) _load();
  }

  Future<void> _confirmDelete(ClubRoute route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${route.name}"?'),
        content: const Text('This removes the route for the whole club.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _service.deleteRoute(route.id);
    if (!mounted) return;
    if (done) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete route')),
      );
    }
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
        title: Text(widget.clubName == null ? 'Routes' : '${widget.clubName} · Routes'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRoute,
        icon: const Icon(Icons.add),
        label: const Text('Create route'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _routes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _routes[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RouteViewerScreen(route: r),
                            ),
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.map_outlined),
                          ),
                          title: Text(
                            r.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(_distanceLabel(r.distanceM)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(r),
                          ),
                        ),
                      );
                    },
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
                  Icon(Icons.map_outlined, size: 52, color: Colors.grey[400]),
                  const SizedBox(height: 14),
                  const Text(
                    'No routes yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Map out your club\'s first run — tap Create route.',
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
