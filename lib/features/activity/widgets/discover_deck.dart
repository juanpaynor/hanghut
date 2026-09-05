import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:bitemates/features/ticketing/models/event.dart';

/// Swipe deck that headlines the Discover screen.
///
/// Interaction model (agreed 2026-09-05): a bare **swipe just advances** the
/// deck (a neutral "seen, next" — no taste signal). The three buttons carry the
/// real actions and are what train the user's taste:
///   ✕ Skip     → negative signal
///   ♥ Save     → positive signal
///   🎟 Tickets → strong positive + opens the event
///
/// The deck sits above the existing browse rails, so nobody is forced to swipe.
class DiscoverDeck extends StatefulWidget {
  final List<Event> events;

  /// Opens the event detail / ticket flow (tap the card, or the 🎟 button).
  final void Function(Event event) onOpen;

  const DiscoverDeck({
    super.key,
    required this.events,
    required this.onOpen,
  });

  @override
  State<DiscoverDeck> createState() => _DiscoverDeckState();
}

class _DiscoverDeckState extends State<DiscoverDeck> {
  static const _accent = Color(0xFF6C63FF);
  static const _like = Color(0xFFFF4D6D);

  late List<Event> _order;
  Offset _drag = Offset.zero;
  bool _dragging = false;

  // Lightweight, in-memory taste readout (categories the user leaned toward /
  // away from this session). The real DNA write to `user_taste` gets wired in a
  // follow-up — this just makes the learning visible for now.
  final Set<String> _liked = {};
  final Set<String> _disliked = {};

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.events);
  }

  @override
  void didUpdateWidget(covariant DiscoverDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the deck emptied and fresh events arrived (pagination), don't disturb
    // an in-progress deck; only reseed when we've run out.
    if (_order.isEmpty && widget.events.isNotEmpty) {
      _order = List.of(widget.events);
    }
  }

  Event? get _top => _order.isNotEmpty ? _order.first : null;

  void _record(String category, {required bool liked}) {
    final cat = category.trim();
    if (cat.isEmpty) return;
    setState(() {
      if (liked) {
        _liked.add(cat);
        _disliked.remove(cat);
      } else {
        _disliked.add(cat);
        _liked.remove(cat);
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        ),
      );
  }

  void _flyOut(int sign) {
    final w = MediaQuery.of(context).size.width;
    setState(() {
      _dragging = false;
      _drag = Offset(sign * w * 1.6, -60);
    });
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        if (_order.isNotEmpty) _order.removeAt(0);
        _drag = Offset.zero;
      });
    });
  }

  void _onPanEnd(DragEndDetails _) {
    final dx = _drag.dx;
    if (dx.abs() > 90) {
      // Bare swipe = neutral advance (no taste signal).
      _flyOut(dx < 0 ? -1 : 1);
    } else {
      setState(() {
        _dragging = false;
        _drag = Offset.zero;
      });
    }
  }

  void _skip() {
    final e = _top;
    if (e == null) return;
    _record(e.category, liked: false);
    _flyOut(-1);
  }

  void _save() {
    final e = _top;
    if (e == null) return;
    _record(e.category, liked: true);
    _flyOut(1);
    _toast('Saved · more like this coming');
  }

  void _tickets() {
    final e = _top;
    if (e == null) return;
    _record(e.category, liked: true);
    widget.onOpen(e);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 380,
              child: _order.isEmpty ? _buildEmpty() : _buildStack(),
            ),
          ),
          if (_order.isNotEmpty) _buildActions(),
          _buildDna(),
        ],
      ),
    );
  }

  Widget _buildStack() {
    final visible = _order.take(3).toList();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Render back-to-front so the top card paints last (on top).
        for (int i = visible.length - 1; i >= 0; i--)
          _buildCard(visible[i], i),
      ],
    );
  }

  Widget _buildCard(Event e, int depth) {
    final isTop = depth == 0;
    final Matrix4 matrix;
    if (isTop) {
      matrix = Matrix4.translationValues(_drag.dx, _drag.dy, 0)
        ..rotateZ(_drag.dx / 1400);
    } else {
      final scale = 1 - depth * 0.04;
      matrix = Matrix4.translationValues(0, depth * 12.0, 0)
        ..scaleByDouble(scale, scale, 1, 1);
    }

    Widget card = AnimatedContainer(
      duration: (_dragging && isTop)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      transform: matrix,
      transformAlignment: Alignment.center,
      child: _cardContent(e, dim: !isTop),
    );

    if (isTop) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(e),
        // Horizontal-only: lets the page scroll vertically and wins the swipe
        // over the (now disabled) tab pager.
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag = Offset(_drag.dx + d.delta.dx, 0)),
        onHorizontalDragEnd: _onPanEnd,
        child: card,
      );
    }

    return Positioned.fill(key: ValueKey(e.id), child: card);
  }

  Widget _cardContent(Event e, {required bool dim}) {
    final dateStr = e.isMultiDay
        ? e.dateRangeWithTimeLabel
        : DateFormat('EEE, MMM d · h:mm a').format(e.startLocal);
    final isFree = e.displayFromPrice <= 0;
    final kicker =
        e.category.trim().isNotEmpty ? e.category.toUpperCase() : 'FEATURED';
    final going = e.ticketsSold;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        fit: StackFit.expand,
        children: [
          e.coverImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: e.coverImageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 900,
                  placeholder: (_, __) => Container(color: Colors.grey[400]),
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[400]),
                )
              : Container(color: Colors.grey[400]),

          // Legibility scrim.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x73000000),
                  Color(0x00000000),
                  Color(0x80000000),
                  Color(0xF7000000),
                ],
                stops: [0.0, 0.28, 0.58, 1.0],
              ),
            ),
          ),

          // Category pill.
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_emoji(e.category)} $kicker',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          // Going count.
          if (going >= 10)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '🔥 $going going',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Bottom content.
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateStr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Color(0x99000000), blurRadius: 6)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    shadows: [Shadow(color: Color(0x99000000), blurRadius: 10)],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 14, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        e.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isFree ? const Color(0xFF22A06B) : Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    isFree ? 'FREE' : e.priceLabel(),
                    style: TextStyle(
                      color: isFree ? Colors.white : const Color(0xFF15131E),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Slightly darken the cards stacked behind so they read as "next up".
          if (dim)
            const IgnorePointer(
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: Color(0x22000000)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _actionButton(
            icon: Icons.close_rounded,
            size: 56,
            iconSize: 26,
            color: const Color(0xFF9A96A7),
            bg: Theme.of(context).cardColor,
            bordered: true,
            onTap: _skip,
          ),
          const SizedBox(width: 20),
          _actionButton(
            icon: Icons.favorite_rounded,
            size: 68,
            iconSize: 30,
            color: _like,
            bg: Theme.of(context).cardColor,
            bordered: true,
            onTap: _save,
          ),
          const SizedBox(width: 20),
          _actionButton(
            icon: Icons.local_activity_rounded,
            size: 56,
            iconSize: 24,
            color: Colors.white,
            bg: _accent,
            bordered: false,
            onTap: _tickets,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Color color,
    required Color bg,
    required bool bordered,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: bordered
              ? Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.07),
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }

  /// Slim, single-line taste readout (kept deliberately quiet to reduce clutter).
  Widget _buildDna() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pos = _liked.toList();
    final neg = _disliked.where((c) => !_liked.contains(c)).toList();
    final hasSignal = pos.isNotEmpty || neg.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
      child: Row(
        children: [
          const Text('✦', style: TextStyle(color: _accent, fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            hasSignal ? 'Learning your taste' : 'Swipe & tap to learn your taste',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
          if (hasSignal) ...[
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    ...pos.map((c) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _tasteTag(c, positive: true),
                        )),
                    ...neg.map((c) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _tasteTag(c, positive: false),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tasteTag(String label, {required bool positive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: positive
            ? const Color(0xFF17B26A).withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        positive ? '+ $label' : label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: positive ? const Color(0xFF17B26A) : Colors.grey[600],
          decoration: positive ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            Text(
              "You're all caught up",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF15131E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Fresh picks below, or reshuffle the deck',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _order = List.of(widget.events)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Reshuffle deck',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emoji(String category) {
    final c = category.toLowerCase();
    if (c.contains('night') || c.contains('club') || c.contains('party')) {
      return '🪩';
    }
    if (c.contains('sport') || c.contains('run') || c.contains('marathon')) {
      return '🏃';
    }
    if (c.contains('food') || c.contains('dine') || c.contains('eat')) {
      return '🍜';
    }
    if (c.contains('film') || c.contains('movie')) return '🍿';
    if (c.contains('well') || c.contains('yoga')) return '🧘';
    if (c.contains('music') || c.contains('concert')) return '🎵';
    if (c.contains('art') || c.contains('culture')) return '🎨';
    if (c.contains('social') || c.contains('meet')) return '☕';
    return '✦';
  }
}
