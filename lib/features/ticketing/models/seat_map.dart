import 'package:flutter/material.dart';

/// Models for the customer-facing seat picker. Mirrors the get_event_seat_map
/// RPC contract (team_comms #166). The RPC returns NULL when an event has no
/// map — callers fall back to normal quantity checkout in that case.

/// Canonical tier palette — MUST match web (components/seat-map/types.ts).
/// Color is assigned by tier POSITION in the tiers[] array (not sort_order),
/// since sort_order may have gaps: PALETTE[index % 12].
const List<Color> kSeatTierPalette = [
  Color(0xFFf59e0b),
  Color(0xFF6366f1),
  Color(0xFF22c55e),
  Color(0xFFec4899),
  Color(0xFF06b6d4),
  Color(0xFF8b5cf6),
  Color(0xFFf97316),
  Color(0xFF14b8a6),
  Color(0xFFf43f5e),
  Color(0xFF3b82f6),
  Color(0xFF84cc16),
  Color(0xFFd946ef),
];

// Status fill overrides (unselectable states) — from #150.
const Color kSeatHeldColor = Color(0xFF9ca3af);
const Color kSeatBookedColor = Color(0xFFef4444);
const Color kSeatDisabledColor = Color(0xFF374151);

class SeatTier {
  final String id;
  final String name;
  final num price;
  final int sortOrder;

  const SeatTier({
    required this.id,
    required this.name,
    required this.price,
    required this.sortOrder,
  });

  factory SeatTier.fromJson(Map<String, dynamic> j) => SeatTier(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        price: (j['price'] ?? 0) as num,
        sortOrder: (j['sort_order'] ?? 0) as int,
      );
}

class Seat {
  final String id;
  final String row;
  final int seat;
  final String label;
  final double x;
  final double y;
  final String? tierId; // already resolved server-side
  final String status; // available | held | booked | disabled

  const Seat({
    required this.id,
    required this.row,
    required this.seat,
    required this.label,
    required this.x,
    required this.y,
    required this.tierId,
    required this.status,
  });

  bool get isSelectable => status == 'available';

  factory Seat.fromJson(Map<String, dynamic> j) => Seat(
        id: j['id'] as String,
        row: (j['row'] ?? '').toString(),
        seat: (j['seat'] ?? 0) is int
            ? (j['seat'] ?? 0) as int
            : int.tryParse('${j['seat']}') ?? 0,
        label: (j['label'] ?? '').toString(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        tierId: j['tier_id'] as String?,
        status: (j['status'] ?? 'available').toString(),
      );

  Seat copyWith({String? status}) => Seat(
        id: id,
        row: row,
        seat: seat,
        label: label,
        x: x,
        y: y,
        tierId: tierId,
        status: status ?? this.status,
      );
}

class SeatSection {
  final String id;
  final String label;
  final String color; // hex, e.g. #ec4899 — fallback fill when tier_id null
  final String sectionType;
  final List<double> polygonPoints; // flat [x1,y1,x2,y2,...] in canvas space
  final String? tierId;
  final Map<String, String> rowTierOverrides;
  // 'ga' | 'seated' — from get_event_seat_map (team_comms #178). 'ga' means
  // a quantity-based zone (no individual seats): tap opens a stepper instead
  // of zooming to seat dots.
  final String salesMode;
  final int availableCount;
  final List<Seat> seats;

  const SeatSection({
    required this.id,
    required this.label,
    required this.color,
    required this.sectionType,
    required this.polygonPoints,
    required this.tierId,
    required this.rowTierOverrides,
    required this.salesMode,
    required this.availableCount,
    required this.seats,
  });

  bool get isGa => salesMode == 'ga';
  bool get isSoldOut => isGa && availableCount <= 0;

  factory SeatSection.fromJson(Map<String, dynamic> j) => SeatSection(
        id: j['id'] as String,
        label: (j['label'] ?? '').toString(),
        color: (j['color'] ?? '#6366f1').toString(),
        sectionType: (j['section_type'] ?? 'general').toString(),
        polygonPoints: ((j['polygon_points'] as List?) ?? [])
            .map((p) => (p as num).toDouble())
            .toList(),
        tierId: j['tier_id'] as String?,
        rowTierOverrides:
            ((j['row_tier_overrides'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        salesMode: (j['sales_mode'] ?? 'seated').toString(),
        availableCount: (j['available_count'] ?? 0) is int
            ? (j['available_count'] ?? 0) as int
            : int.tryParse('${j['available_count']}') ?? 0,
        seats: ((j['seats'] as List?) ?? [])
            .map((s) => Seat.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class SeatMap {
  final String eventId;
  final double canvasWidth;
  final double canvasHeight;
  // Organizer-chosen dot size/shape (world units, same space as seat x/y) —
  // from get_event_seat_map (team_comms #182). Null on legacy maps predating
  // this field; painter falls back to a fixed default in that case.
  final double? seatRadius;
  final String? seatShape; // 'circle' | 'square' | 'diamond' | null
  final List<Map<String, dynamic>> backgroundShapes; // raw; image type skipped
  final List<SeatTier> tiers;
  final List<SeatSection> sections;

  const SeatMap({
    required this.eventId,
    required this.canvasWidth,
    required this.canvasHeight,
    this.seatRadius,
    this.seatShape,
    required this.backgroundShapes,
    required this.tiers,
    required this.sections,
  });

  factory SeatMap.fromJson(Map<String, dynamic> j) => SeatMap(
        eventId: (j['event_id'] ?? '').toString(),
        canvasWidth: (j['canvas_width'] as num?)?.toDouble() ?? 1400,
        canvasHeight: (j['canvas_height'] as num?)?.toDouble() ?? 900,
        seatRadius: (j['seat_radius'] as num?)?.toDouble(),
        seatShape: j['seat_shape'] as String?,
        backgroundShapes: ((j['background_shapes'] as List?) ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList(),
        tiers: ((j['tiers'] as List?) ?? [])
            .map((t) => SeatTier.fromJson(t as Map<String, dynamic>))
            .toList(),
        sections: ((j['sections'] as List?) ?? [])
            .map((s) => SeatSection.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// tierId -> palette color, assigned by array index (web parity).
  Map<String, Color> get tierColors {
    final map = <String, Color>{};
    for (var i = 0; i < tiers.length; i++) {
      map[tiers[i].id] = kSeatTierPalette[i % kSeatTierPalette.length];
    }
    return map;
  }

  SeatTier? tierById(String? id) {
    if (id == null) return null;
    for (final t in tiers) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Fill color for a seat: status override first, else resolved tier color,
  /// else the section's own color.
  Color seatFill(Seat seat, SeatSection section) {
    switch (seat.status) {
      case 'held':
        return kSeatHeldColor;
      case 'booked':
        return kSeatBookedColor;
      case 'disabled':
        return kSeatDisabledColor;
    }
    final tc = tierColors[seat.tierId];
    if (tc != null) return tc;
    return hexColor(section.color);
  }

  /// Fill for a section polygon: resolved tier color else section.color.
  Color sectionFill(SeatSection section) {
    final tc = tierColors[section.tierId];
    if (tc != null) return tc;
    return hexColor(section.color);
  }

  static Color hexColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF6366f1) : Color(v);
  }
}
