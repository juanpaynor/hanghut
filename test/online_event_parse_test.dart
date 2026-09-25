import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/models/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

/// team_comms #327/#328: events.latitude/longitude went NULLABLE and an online
/// event writes NULL for venue_name/address/city too. Before this the parser
/// threw on the first online event and took the whole list down with it.
void main() {
  Map<String, dynamic> base() => {
        'id': 'e1',
        'title': 'Zoom workshop',
        'start_datetime': '2026-10-01T10:00:00Z',
        'ticket_price': 0,
        'capacity': 100,
        'created_at': '2026-09-21T00:00:00Z',
      };

  test('online event with NULL venue/coords parses', () {
    final e = Event.fromJson({
      ...base(),
      'is_online': true,
      'venue_name': null,
      'address': null,
      'latitude': null,
      'longitude': null,
    });
    expect(e.isOnline, isTrue);
    expect(e.hasLocation, isFalse);
    expect(e.latitude, isNull);
    expect(e.venueName, '');
    expect(e.placeLabel, 'Online event');
  });

  test('venue event unchanged: coords present, is_online absent → false', () {
    final e = Event.fromJson({
      ...base(),
      'venue_name': 'Saguijo',
      'latitude': 14.56,
      'longitude': 121.02,
    });
    expect(e.isOnline, isFalse);
    expect(e.hasLocation, isTrue);
    expect(e.placeLabel, 'Saguijo');
  });

  test('ticket for an online event carries the order token', () {
    final t = Ticket.fromJson({
      'id': 't1',
      'event_id': 'e1',
      'event_title': 'Zoom workshop',
      'event_venue': null,
      'event_start': '2099-10-01T10:00:00Z',
      'purchase_date': '2026-09-21T00:00:00Z',
      'status': 'valid',
      'event_is_online': true,
      'order_access_token': 'abc',
    });
    expect(t.isOnline, isTrue);
    expect(t.eventVenue, 'Online event');
    expect(t.canJoinOnline, isTrue);
  });

  test('refunded online ticket does not offer Join', () {
    final t = Ticket.fromJson({
      'id': 't1',
      'event_id': 'e1',
      'event_start': '2099-10-01T10:00:00Z',
      'purchase_date': '2026-09-21T00:00:00Z',
      'status': 'refunded',
      'event_is_online': true,
      'order_access_token': 'abc',
    });
    expect(t.canJoinOnline, isFalse);
  });
}
