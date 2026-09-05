import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:bitemates/core/services/seat_map_service.dart';
import 'package:bitemates/core/services/seat_realtime_service.dart';
import 'package:bitemates/features/ticketing/models/seat_map.dart';

/// Result returned to checkout when the user confirms a seat selection.
/// For GA (quantity-based) zones, [seatIds]/[seats] are empty and [quantity]
/// carries the chosen count instead (team_comms #178).
class SeatSelectionResult {
  final List<String> seatIds;
  final String? tierId;
  final List<Seat> seats;
  final int quantity;
  final bool isGa;

  /// The picker's seat-hold session. MUST be forwarded to checkout as
  /// `seat_session_id` for seated selections, or assign_seats_to_intent treats
  /// the buyer's own holds as competing and rejects them (#291 Trap 1). Null for
  /// GA (quantity zones create no holds).
  final String? sessionId;

  const SeatSelectionResult({
    required this.seatIds,
    required this.tierId,
    required this.seats,
    required this.quantity,
    this.isGa = false,
    this.sessionId,
  });
}

/// Customer-facing seat picker. Two-level UX (#150): section polygons →
/// tap → zoom to the section → seat dots. Never renders all seats at once.
class SeatMapPickerScreen extends StatefulWidget {
  final String eventId;
  final int maxSeats;

  const SeatMapPickerScreen({
    super.key,
    required this.eventId,
    this.maxSeats = 10,
  });

  @override
  State<SeatMapPickerScreen> createState() => _SeatMapPickerScreenState();
}

class _SeatMapPickerScreenState extends State<SeatMapPickerScreen> {
  final SeatMapService _service = SeatMapService();
  final TransformationController _transform = TransformationController();

  SeatMap? _map;
  bool _isLoading = true;

  // Level 2 focus
  SeatSection? _focused;

  // Selection (seated)
  final Set<String> _selectedSeatIds = {};
  String? _selectedTierId;
  bool _tierLocked = false;

  // Selection (GA / quantity-based). Mutually exclusive with seated selection
  // above — picking one clears the other.
  SeatSection? _gaSection;
  int _gaQuantity = 1;

  // Live updates: Ably per-section fast path (#284) + a reconciling status poll
  // as the floor. _lastVersion detects structural/tier edits → full refetch.
  SeatRealtimeService? _rt;
  Timer? _reconcileTimer;
  int? _lastVersion;
  Size? _viewport;

  // Hold-on-tap (#289 option a / #291). One session per picker: used to hold via
  // web and reused as seat_session_id at checkout. _origin is a separate random
  // tag for echo discard (never the sessionId — that is a credential).
  final String _seatSessionId = const Uuid().v4();
  final String _origin = const Uuid().v4();
  // Server-time expiry per held seat + our clock offset (serverNow − local), so
  // the countdown is correct despite device-clock skew. Countdown targets the
  // earliest-expiring hold. seat_holds TTL is 12min (do not hardcode — drive off
  // expiresAt, #291 Q2).
  final Map<String, DateTime> _holdExpiry = {};
  Duration _clockSkew = Duration.zero;
  Timer? _holdTimer;
  Duration? _holdRemaining;
  // Seats with a hold request in flight — guards against double-taps re-entering.
  final Set<String> _pendingSeatIds = {};
  // True once we hand seats to checkout, so dispose does NOT release them
  // (checkout owns them via seat_session_id).
  bool _proceeding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = await _service.getEventSeatMap(widget.eventId);
    if (!mounted) return;
    setState(() {
      _map = map;
      _isLoading = false;
    });
    if (map != null) {
      // Fast path: per-section Ably subscribe (held/released/booked) — replaces
      // the old postgres_changes channel, which couldn't see others' holds.
      _rt = SeatRealtimeService(
        eventId: widget.eventId,
        sessionId: _seatSessionId,
        origin: _origin,
        onSeatUpdate: _onSeatUpdate,
      );
      // Authenticate now; subscribe to a single section's channel only when the
      // buyer focuses it (see _focusSection / _backToOverview) — web meters
      // deliveries, so per-section-on-focus is the required pattern (#289).
      _rt!.start();
      // Floor: a cheap status-only poll reconciles anything the fast path missed
      // (dropped/late messages, expired holds). Aligned to web's 3s floor (#285).
      _reconcileTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _reconcile(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToCanvas());
    }
  }

  /// Reconciling poll (the floor). Uses the lightweight get_event_seat_status;
  /// only falls back to a full map refetch when [version] shows a structural or
  /// tier edit (new sections/seats the light snapshot can't introduce).
  Future<void> _reconcile() async {
    final snap = await _service.getEventSeatStatus(widget.eventId);
    if (!mounted || snap == null) return;
    if (_lastVersion != null && snap.version != _lastVersion) {
      _lastVersion = snap.version;
      await _refetchFull();
      return;
    }
    _lastVersion = snap.version;
    _applyStatus(snap);
  }

  /// Applies a status snapshot onto the current map in place: any seat not in
  /// [SeatStatusSnapshot.taken] is available; section availability is refreshed.
  void _applyStatus(SeatStatusSnapshot snap) {
    final map = _map;
    if (map == null) return;
    for (final section in map.sections) {
      for (var i = 0; i < section.seats.length; i++) {
        final seat = section.seats[i];
        // Our own holds come back in taken[] as 'held' too — the RPC can't tell
        // our session from anyone else's. Skip them, or the poll would grey out
        // the buyer's own selection every 3s. Expiry of our holds is handled by
        // the countdown, not the poll.
        if (_selectedSeatIds.contains(seat.id)) continue;
        final status = snap.taken[seat.id] ?? 'available';
        if (seat.status != status) {
          section.seats[i] = seat.copyWith(status: status);
        }
      }
      final avail = snap.sectionAvailable[section.id];
      if (avail != null) section.availableCount = avail;
    }
    _pruneSelection(map);
    _reconcileGaSelection(map);
    if (mounted) setState(() {});
  }

  Future<void> _refetchFull() async {
    final map = await _service.getEventSeatMap(widget.eventId);
    if (!mounted || map == null) return;
    setState(() {
      _map = map;
      // Re-resolve focus + prune selection of seats no longer available.
      _focused = _focused == null
          ? null
          : map.sections.firstWhere(
              (s) => s.id == _focused!.id,
              orElse: () => _focused!,
            );
      _pruneSelection(map);
      _reconcileGaSelection(map);
    });
  }

  /// Re-resolves the selected GA section against a fresh map fetch, clamping
  /// or clearing the chosen quantity if availability dropped.
  void _reconcileGaSelection(SeatMap map) {
    if (_gaSection == null) return;
    final matches = map.sections.where((s) => s.id == _gaSection!.id);
    if (matches.isEmpty || matches.first.isSoldOut) {
      _gaSection = null;
      _gaQuantity = 1;
      _maybeSnack('That section is no longer available.');
      return;
    }
    _gaSection = matches.first;
    if (_gaQuantity > _gaSection!.availableCount) {
      _gaQuantity = _gaSection!.availableCount;
      _maybeSnack('Availability changed — quantity adjusted to $_gaQuantity.');
    }
  }

  void _onSeatUpdate(String seatId, String status) {
    final map = _map;
    if (map == null) return;
    // Patch the seat's status in place.
    for (final section in map.sections) {
      final idx = section.seats.indexWhere((s) => s.id == seatId);
      if (idx != -1) {
        section.seats[idx] = section.seats[idx].copyWith(status: status);
        if (status != 'available' && _selectedSeatIds.remove(seatId)) {
          if (_selectedSeatIds.isEmpty) _tierLocked = false;
          _maybeSnack('A selected seat was just taken — please pick another.');
        }
        if (mounted) setState(() {});
        return;
      }
    }
  }

  void _pruneSelection(SeatMap map) {
    final available = <String>{
      for (final s in map.sections)
        for (final seat in s.seats)
          if (seat.isSelectable) seat.id,
    };
    final removed = _selectedSeatIds.where((id) => !available.contains(id)).toList();
    if (removed.isNotEmpty) {
      _selectedSeatIds.removeAll(removed);
      if (_selectedSeatIds.isEmpty) _tierLocked = false;
      _maybeSnack('Some selected seats are no longer available.');
    }
  }

  void _maybeSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _reconcileTimer?.cancel();
    _holdTimer?.cancel();
    // Leaving WITHOUT proceeding to checkout: free our holds so others aren't
    // blocked for the full 12-min TTL. On proceed, checkout owns them via
    // seat_session_id, so we keep them.
    if (!_proceeding && _selectedSeatIds.isNotEmpty) {
      _rt?.release(_selectedSeatIds.toList());
    }
    _rt?.dispose(); // fire-and-forget: closes the Ably connection + channels
    _transform.dispose();
    super.dispose();
  }

  // ── Viewport / transform ─────────────────────────────────────────────────

  void _fitToCanvas() {
    final map = _map;
    final vp = _viewport;
    if (map == null || vp == null) return;
    _fitRect(0, 0, map.canvasWidth, map.canvasHeight, vp, padding: 24);
  }

  void _fitRect(double x, double y, double w, double h, Size vp,
      {double padding = 40}) {
    if (w <= 0 || h <= 0) return;
    final scale = ((vp.width - padding * 2) / w)
        .clamp(0.05, 8.0)
        .toDouble();
    final scaleY = ((vp.height - padding * 2) / h).clamp(0.05, 8.0).toDouble();
    final s = scale < scaleY ? scale : scaleY;
    final tx = (vp.width - w * s) / 2 - x * s;
    final ty = (vp.height - h * s) / 2 - y * s;
    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _focusSection(SeatSection section, Size vp) {
    // Fit to the SEATS' bounding box, not the section polygon — the polygon
    // outline is frequently much larger than the actual seated area, which
    // left seats clustered in a corner of the view (team_comms #181 Fix 2).
    if (section.seats.isEmpty) {
      // Defensive: seated sections always have seats per the RPC contract;
      // GA zones (which don't) never reach this method. Fall back to the
      // polygon bbox just in case.
      final pts = section.polygonPoints;
      if (pts.length < 4) return;
      double minX = pts[0], maxX = pts[0], minY = pts[1], maxY = pts[1];
      for (var i = 0; i < pts.length; i += 2) {
        minX = pts[i] < minX ? pts[i] : minX;
        maxX = pts[i] > maxX ? pts[i] : maxX;
        minY = pts[i + 1] < minY ? pts[i + 1] : minY;
        maxY = pts[i + 1] > maxY ? pts[i + 1] : maxY;
      }
      setState(() => _focused = section);
      _rt?.setSection(section.id);
      _fitRect(minX, minY, maxX - minX, maxY - minY, vp, padding: 48);
      return;
    }

    double minX = section.seats.first.x, maxX = section.seats.first.x;
    double minY = section.seats.first.y, maxY = section.seats.first.y;
    for (final seat in section.seats) {
      minX = seat.x < minX ? seat.x : minX;
      maxX = seat.x > maxX ? seat.x : maxX;
      minY = seat.y < minY ? seat.y : minY;
      maxY = seat.y > maxY ? seat.y : maxY;
    }
    // Pad by ~3x the seat radius (world units) so edge seats aren't clipped.
    final pad = (_map?.seatRadius ?? 9.0) * 3;
    minX -= pad;
    maxX += pad;
    minY -= pad;
    maxY += pad;

    setState(() => _focused = section);
    _rt?.setSection(section.id);
    _fitRect(minX, minY, maxX - minX, maxY - minY, vp, padding: 24);
  }

  void _backToOverview() {
    setState(() => _focused = null);
    _rt?.setSection(null); // level-1 overview: poll keeps availability fresh
    final vp = _viewport;
    if (vp != null) _fitToCanvas();
  }

  // ── Tap handling ─────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) {
    final map = _map;
    if (map == null) return;
    // Local → scene (canvas) coordinates.
    final scene = _transform.toScene(d.localPosition);
    final cx = scene.dx, cy = scene.dy;

    if (_focused == null) {
      // Level 1 — hit-test section polygons.
      for (final section in map.sections) {
        if (_pointInPolygon(cx, cy, section.polygonPoints)) {
          // Sold-out sections refuse the tap (#282) — no point letting a buyer
          // dig in and only hit SEATS_UNAVAILABLE at checkout.
          if (section.isSoldOut) {
            _maybeSnack('${section.label} is sold out.');
            return;
          }
          // GA zones have no seats to zoom into — open the quantity stepper
          // directly instead of the seated level-2 flow.
          if (section.isGa) {
            _selectGaSection(section);
          } else if (_viewport != null) {
            _focusSection(section, _viewport!);
          }
          return;
        }
      }
    } else {
      // Level 2 — hit-test seats (nearest within radius) first.
      const hitR = 22.0;
      Seat? best;
      double bestDist = hitR * hitR;
      for (final seat in _focused!.seats) {
        final dx = seat.x - cx, dy = seat.y - cy;
        final d2 = dx * dx + dy * dy;
        if (d2 <= bestDist) {
          bestDist = d2;
          best = seat;
        }
      }
      if (best != null) {
        _toggleSeat(best);
        return;
      }
      // No seat hit — let the user tap a DIFFERENT section to switch to it.
      for (final section in map.sections) {
        if (section.id != _focused!.id &&
            _pointInPolygon(cx, cy, section.polygonPoints)) {
          if (section.isSoldOut) {
            _maybeSnack('${section.label} is sold out.');
            return;
          }
          if (section.isGa) {
            setState(() => _focused = null);
            _selectGaSection(section);
          } else if (_viewport != null) {
            _focusSection(section, _viewport!);
          }
          return;
        }
      }
    }
  }

  Future<void> _toggleSeat(Seat seat) async {
    // A hold/release for this seat is already in flight — ignore the re-tap.
    if (_pendingSeatIds.contains(seat.id)) return;

    // Seated and GA selections are mutually exclusive. Clear immediately (own
    // setState) so the bottom bar updates even if the seat tap below turns
    // out to be a no-op (unavailable / max reached / tier mismatch).
    if (_gaSection != null) {
      setState(() {
        _gaSection = null;
        _gaQuantity = 1;
      });
      _maybeSnack('Cleared your General Admission selection.');
    }

    // DESELECT — drop locally and release the server hold (best-effort).
    if (_selectedSeatIds.contains(seat.id)) {
      setState(() {
        _selectedSeatIds.remove(seat.id);
        _holdExpiry.remove(seat.id);
        if (_selectedSeatIds.isEmpty) {
          _tierLocked = false;
          _selectedTierId = null;
        }
      });
      _recomputeCountdown();
      _rt?.release([seat.id]);
      HapticFeedback.selectionClick();
      return;
    }

    if (!seat.isSelectable) {
      _maybeSnack('That seat is not available.');
      return;
    }
    if (_selectedSeatIds.length >= widget.maxSeats) {
      _maybeSnack('You can select up to ${widget.maxSeats} seats.');
      return;
    }
    // One tier per order.
    if (_tierLocked && seat.tierId != _selectedTierId) {
      _maybeSnack('All seats must be from the same tier.');
      return;
    }

    // Optimistic select, then hold server-side; revert on failure (#289).
    setState(() {
      _pendingSeatIds.add(seat.id);
      _selectedSeatIds.add(seat.id);
      _selectedTierId = seat.tierId;
      _tierLocked = true;
    });
    HapticFeedback.selectionClick();

    final result = await (_rt?.hold(seat.id) ?? Future.value(SeatHoldResult.failed));
    if (!mounted) return;

    if (result.held) {
      setState(() {
        _pendingSeatIds.remove(seat.id);
        if (result.expiresAt != null) {
          _holdExpiry[seat.id] = result.expiresAt!;
          if (result.serverNow != null) {
            _clockSkew = result.serverNow!.difference(DateTime.now());
          }
        }
      });
      _recomputeCountdown();
    } else {
      // Revert the optimistic add — the hold did not take.
      setState(() {
        _pendingSeatIds.remove(seat.id);
        _selectedSeatIds.remove(seat.id);
        _holdExpiry.remove(seat.id);
        if (_selectedSeatIds.isEmpty) {
          _tierLocked = false;
          _selectedTierId = null;
        }
      });
      _recomputeCountdown();
      _maybeSnack(_holdFailMessage(result));
    }
  }

  /// held:false is ambiguous (#291): taken by another session, unavailable
  /// (booked/disabled), or this session hit its per-order limit. Web populates
  /// `reason` only when asked; until then absent → a neutral message.
  String _holdFailMessage(SeatHoldResult r) {
    switch (r.reason) {
      case 'taken':
        return 'Someone just grabbed that seat.';
      case 'unavailable':
        return 'That seat is no longer available.';
      case 'limit':
        return 'You\'ve reached the maximum seats for this order.';
      default:
        return 'That seat is no longer available.';
    }
  }

  // ── Hold countdown ─────────────────────────────────────────────────────────

  /// Starts/stops the 1s countdown ticker based on whether any hold is live.
  void _recomputeCountdown() {
    if (_holdExpiry.isEmpty) {
      _holdTimer?.cancel();
      _holdTimer = null;
      if (_holdRemaining != null && mounted) {
        setState(() => _holdRemaining = null);
      }
      return;
    }
    _holdTimer ??=
        Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();
  }

  void _tickCountdown() {
    if (_holdExpiry.isEmpty) {
      _recomputeCountdown();
      return;
    }
    // serverNow ≈ local + skew (from the hold response), so a wrong device clock
    // doesn't expire holds early or late (#291 Q2).
    final serverNow = DateTime.now().add(_clockSkew);
    final expired = _holdExpiry.entries
        .where((e) => !e.value.isAfter(serverNow))
        .map((e) => e.key)
        .toList();
    if (expired.isNotEmpty) {
      setState(() {
        for (final id in expired) {
          _selectedSeatIds.remove(id);
          _holdExpiry.remove(id);
        }
        if (_selectedSeatIds.isEmpty) {
          _tierLocked = false;
          _selectedTierId = null;
        }
      });
      // No release call: an expired hold is already swept server-side.
      _maybeSnack('A seat hold expired — please reselect.');
      _recomputeCountdown();
      return;
    }
    final earliest =
        _holdExpiry.values.reduce((a, b) => a.isBefore(b) ? a : b);
    final remaining = earliest.difference(serverNow);
    if (mounted) setState(() => _holdRemaining = remaining);
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// GA zones have no individual seats — tap opens a quantity stepper capped
  /// by both the section's remaining availability and [widget.maxSeats].
  Future<void> _selectGaSection(SeatSection section) async {
    if (section.isSoldOut) {
      _maybeSnack('This section is sold out.');
      return;
    }
    // Seated and GA selections are mutually exclusive.
    if (_selectedSeatIds.isNotEmpty) {
      setState(() {
        _selectedSeatIds.clear();
        _tierLocked = false;
        _selectedTierId = null;
      });
      _maybeSnack('Cleared your seat selection.');
    }

    final maxQty = section.availableCount < widget.maxSeats
        ? section.availableCount
        : widget.maxSeats;
    final startQty = (_gaSection?.id == section.id ? _gaQuantity : 1)
        .clamp(1, maxQty);

    final confirmed = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _GaQuantitySheet(
        section: section,
        initialQty: startQty,
        maxQty: maxQty,
      ),
    );

    if (confirmed == null || !mounted) return;
    setState(() {
      _gaSection = section;
      _gaQuantity = confirmed;
      _selectedTierId = section.tierId;
    });
    HapticFeedback.selectionClick();
  }

  bool _pointInPolygon(double px, double py, List<double> pts) {
    bool inside = false;
    final int n = pts.length ~/ 2;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = pts[i * 2], yi = pts[i * 2 + 1];
      final double xj = pts[j * 2], yj = pts[j * 2 + 1];
      final bool hit = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (hit) inside = !inside;
    }
    return inside;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  List<Seat> get _selectedSeats {
    final map = _map;
    if (map == null) return [];
    return [
      for (final s in map.sections)
        for (final seat in s.seats)
          if (_selectedSeatIds.contains(seat.id)) seat,
    ];
  }

  void _confirm() {
    if (_gaSection != null) {
      Navigator.pop(
        context,
        SeatSelectionResult(
          seatIds: const [],
          tierId: _gaSection!.tierId,
          seats: const [],
          quantity: _gaQuantity,
          isGa: true,
        ),
      );
      return;
    }
    // A hold is still resolving — its seat may yet be reverted, and checkout
    // requires seat_ids to EXACTLY match the held set (#291 Trap 2). Wait.
    if (_pendingSeatIds.isNotEmpty) {
      _maybeSnack('Finishing reserving your seats…');
      return;
    }
    _proceeding = true; // keep the holds — checkout claims them via sessionId
    Navigator.pop(
      context,
      SeatSelectionResult(
        seatIds: _selectedSeatIds.toList(),
        tierId: _selectedTierId,
        seats: _selectedSeats,
        quantity: _selectedSeatIds.length,
        sessionId: _seatSessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_focused == null ? 'Select Seats' : 'Section ${_focused!.label}'),
        leading: _focused != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Overview',
                onPressed: _backToOverview,
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _map == null
          ? _buildNoMap()
          : Column(
              children: [
                Expanded(child: _buildCanvas()),
                if (_map!.tiers.isNotEmpty) _buildLegend(),
                _buildSelectionBar(),
              ],
            ),
    );
  }

  Widget _buildNoMap() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This event doesn\'t have assigned seating.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final map = _map!;
        // GestureDetector must wrap the InteractiveViewer (not be its child) so
        // tap localPosition is in viewport space and toScene() maps it to canvas
        // space exactly once. (Inside the IV, localPosition is already child
        // space, and toScene would double-transform — taps drift when zoomed.)
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.05,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: CustomPaint(
                size: Size(map.canvasWidth, map.canvasHeight),
                painter: _SeatMapPainter(
                  map: map,
                  focused: _focused,
                  selectedSeatIds: _selectedSeatIds,
                  selectedGaSectionId: _gaSection?.id,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegend() {
    final map = _map!;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: map.tiers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final t = map.tiers[i];
          final c = map.tierColors[t.id] ?? Colors.grey;
          return Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                '${t.name}  ₱${t.price}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final isGa = _gaSection != null;
    final count = isGa ? _gaQuantity : _selectedSeatIds.length;
    final tier = _map?.tierById(isGa ? _gaSection!.tierId : _selectedTierId);
    // Block Continue while a hold is resolving so checkout gets the exact held
    // set (#291 Trap 2).
    final canContinue = count > 0 && _pendingSeatIds.isEmpty;
    final showTimer = !isGa && count > 0 && _holdRemaining != null;
    final selectedSeats = _selectedSeats;
    final labels = selectedSeats.map((s) => s.label).take(6).join(', ');

    String title;
    Widget? subtitle;
    if (isGa) {
      title = '$count · ${_gaSection!.label}';
      subtitle = Text(
        'General Admission${tier != null ? '  ·  ${tier.name}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    } else if (count == 0) {
      title = _focused == null ? 'Tap a section to view seats' : 'Tap seats to select';
    } else {
      title = '$count seat${count == 1 ? '' : 's'} selected';
      subtitle = Text(
        '$labels${selectedSeats.length > 6 ? '…' : ''}'
        '${tier != null ? '  ·  ${tier.name}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (subtitle != null) subtitle,
                ],
              ),
            ),
            if (showTimer) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_holdRemaining!.inSeconds <= 60
                          ? Colors.red
                          : Theme.of(context).primaryColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: _holdRemaining!.inSeconds <= 60
                          ? Colors.red
                          : Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatRemaining(_holdRemaining!),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: _holdRemaining!.inSeconds <= 60
                            ? Colors.red
                            : Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (!showTimer) const SizedBox(width: 12),
            ElevatedButton(
              onPressed: canContinue ? _confirm : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantity stepper sheet for GA (general admission) zone selection —
/// bounded by the section's remaining availability and the order max.
class _GaQuantitySheet extends StatefulWidget {
  final SeatSection section;
  final int initialQty;
  final int maxQty;

  const _GaQuantitySheet({
    required this.section,
    required this.initialQty,
    required this.maxQty,
  });

  @override
  State<_GaQuantitySheet> createState() => _GaQuantitySheetState();
}

class _GaQuantitySheetState extends State<_GaQuantitySheet> {
  late int _qty = widget.initialQty;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.section.label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.section.availableCount} available',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepperButton(
                  primary: primary,
                  icon: Icons.remove,
                  onTap: _qty > 1 ? () => setState(() => _qty--) : null,
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$_qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                _stepperButton(
                  primary: primary,
                  icon: Icons.add,
                  onTap: _qty < widget.maxQty ? () => setState(() => _qty++) : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _qty),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Select $_qty'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton({
    required Color primary,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? primary.withValues(alpha: 0.1) : Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: enabled ? primary : Colors.grey),
        ),
      ),
    );
  }
}

/// Paints background decor, section polygons (level 1) and the focused
/// section's seats (level 2).
class _SeatMapPainter extends CustomPainter {
  final SeatMap map;
  final SeatSection? focused;
  final Set<String> selectedSeatIds;
  final String? selectedGaSectionId;

  _SeatMapPainter({
    required this.map,
    required this.focused,
    required this.selectedSeatIds,
    required this.selectedGaSectionId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas);

    for (final section in map.sections) {
      final dimmed = focused != null && section.id != focused!.id;
      _paintSection(canvas, section, dimmed);
    }

    // Level 2 — seats of the focused section only (never all at once).
    if (focused != null) {
      for (final seat in focused!.seats) {
        _paintSeat(canvas, seat, focused!);
      }
    }
  }

  void _paintBackground(Canvas canvas) {
    for (final shape in map.backgroundShapes) {
      final type = (shape['type'] ?? '').toString();
      if (type == 'image') continue; // organizer tracing aid — skip (#282 item 6)

      final x = (shape['x'] as num?)?.toDouble() ?? 0;
      final y = (shape['y'] as num?)?.toDouble() ?? 0;
      // #282 item 2: shapes can be rotated (degrees). Web rotates the group
      // around its origin (x,y); mirror that with a translate+rotate so a
      // rotated rect (e.g. a vertical BAR) lands correctly.
      final rotation = (shape['rotation'] as num?)?.toDouble() ?? 0;
      final rad = rotation * math.pi / 180.0;
      final label = (shape['label'] ?? '').toString();

      switch (type) {
        case 'rect':
          final w = (shape['width'] as num?)?.toDouble() ?? 0;
          final h = (shape['height'] as num?)?.toDouble() ?? 0;
          // #282 item 3: use the stored fill (full colour, not washed out).
          final fill = Paint()
            ..color = SeatMap.hexColor((shape['fill'] ?? '#e5e7eb').toString());
          canvas.save();
          canvas.translate(x, y);
          if (rad != 0) canvas.rotate(rad);
          canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fill);
          // #282 item 3: draw the shape's label centred, using its own font.
          if (label.isNotEmpty) {
            _paintTextCentered(
              canvas,
              label,
              Offset(w / 2, h / 2),
              (shape['fontSize'] as num?)?.toDouble() ?? 14,
              SeatMap.hexColor((shape['fontColor'] ?? '#ffffff').toString()),
            );
          }
          canvas.restore();
          break;
        case 'circle':
          final r = (shape['radius'] as num?)?.toDouble() ?? 0;
          final fill = Paint()
            ..color = SeatMap.hexColor((shape['fill'] ?? '#e5e7eb').toString());
          canvas.drawCircle(Offset(x, y), r, fill);
          if (label.isNotEmpty) {
            _paintTextCentered(
              canvas,
              label,
              Offset(x, y),
              (shape['fontSize'] as num?)?.toDouble() ?? 14,
              SeatMap.hexColor((shape['fontColor'] ?? '#ffffff').toString()),
            );
          }
          break;
        case 'line':
          final pts = (shape['points'] as List?) ?? [];
          if (pts.length >= 4) {
            final stroke = Paint()
              ..color = SeatMap.hexColor((shape['stroke'] ?? '#9ca3af').toString())
              ..strokeWidth = (shape['strokeWidth'] as num?)?.toDouble() ?? 2;
            for (var i = 0; i + 3 < pts.length; i += 2) {
              canvas.drawLine(
                Offset((pts[i] as num).toDouble(), (pts[i + 1] as num).toDouble()),
                Offset((pts[i + 2] as num).toDouble(), (pts[i + 3] as num).toDouble()),
                stroke,
              );
            }
          }
          break;
        case 'text':
          canvas.save();
          canvas.translate(x, y);
          if (rad != 0) canvas.rotate(rad);
          _paintText(
            canvas,
            label,
            Offset.zero,
            (shape['fontSize'] as num?)?.toDouble() ?? 14,
            SeatMap.hexColor((shape['fontColor'] ?? '#374151').toString()),
          );
          canvas.restore();
          break;
      }
    }
  }

  void _paintSection(Canvas canvas, SeatSection section, bool dimmed) {
    final pts = section.polygonPoints;
    if (pts.length < 6) return;
    final path = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i + 1 < pts.length; i += 2) {
      path.lineTo(pts[i], pts[i + 1]);
    }
    path.close();

    final isSelectedGa = section.id == selectedGaSectionId;
    final soldOut = section.isSoldOut;
    final base = map.sectionFill(section);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = soldOut
          ? Colors.grey.withValues(alpha: 0.15)
          : base.withValues(alpha: dimmed ? 0.12 : 0.30);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelectedGa ? 3.5 : 2
      ..color = isSelectedGa
          ? Colors.black
          : base.withValues(alpha: dimmed ? 0.3 : 0.9);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);

    // Section label at centroid (hidden in level 2 for non-focused). GA zones
    // show availability/sold-out inline since there's no seat-level detail.
    if (focused == null) {
      double cx = 0, cy = 0;
      final n = pts.length ~/ 2;
      for (var i = 0; i < pts.length; i += 2) {
        cx += pts[i];
        cy += pts[i + 1];
      }
      cx /= n;
      cy /= n;
      // Show availability on EVERY section now (seated + GA), per #282 — a
      // buyer should see "N left" / "Sold out" before tapping in.
      final label =
          '${section.label}\n${soldOut ? 'Sold out' : '${section.availableCount} left'}';
      _paintText(
        canvas,
        label,
        Offset(cx - 10, cy - 8),
        15,
        soldOut ? Colors.grey : Colors.black87,
        bold: true,
      );
    }
  }

  void _paintSeat(Canvas canvas, Seat seat, SeatSection section) {
    // Organizer-chosen dot size (team_comms #182) — prod values are 2-5 world
    // units. 9.0 is a legacy fallback for maps predating this field (none in
    // prod today); a fixed 9.0 for ALL maps is what caused dense sections to
    // render as overlapping blobs.
    final r = map.seatRadius ?? 9.0;
    final shape = map.seatShape ?? 'circle';
    final selected = selectedSeatIds.contains(seat.id);
    final center = Offset(seat.x, seat.y);
    final fill = Paint()..color = map.seatFill(seat, section);

    _drawSeatShape(canvas, shape, center, r, fill);

    if (selected) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black;
      final inner = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white;
      _drawSeatShape(canvas, shape, center, r + 2, ring);
      _drawSeatShape(canvas, shape, center, r + 2, inner);
    }
  }

  void _drawSeatShape(
    Canvas canvas,
    String shape,
    Offset center,
    double r,
    Paint paint,
  ) {
    switch (shape) {
      case 'square':
        canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 2, height: r * 2),
          paint,
        );
        break;
      case 'diamond':
        final path = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r, center.dy)
          ..lineTo(center.dx, center.dy + r)
          ..lineTo(center.dx - r, center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'circle':
      default:
        canvas.drawCircle(center, r, paint);
    }
  }

  /// Draws [text] centred on [center] (used for background-shape labels).
  void _paintTextCentered(
      Canvas canvas, String text, Offset center, double size, Color color) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _paintText(Canvas canvas, String text, Offset at, double size, Color color,
      {bool bold = false}) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _SeatMapPainter old) =>
      old.map != map ||
      old.selectedGaSectionId != selectedGaSectionId ||
      old.focused != focused ||
      old.selectedSeatIds != selectedSeatIds;
}
