import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/features/ticketing/models/event_registration.dart';

class PendingRegistrationCard extends StatelessWidget {
  final EventRegistration registration;
  final VoidCallback? onPayNow;

  const PendingRegistrationCard({
    super.key,
    required this.registration,
    this.onPayNow,
  });

  @override
  Widget build(BuildContext context) {
    final r = registration;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: r.eventCoverImage != null
                      ? CachedNetworkImage(
                          imageUrl: r.eventCoverImage!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: Colors.grey[300]),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.event, size: 48),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.event, size: 48),
                        ),
                ),
              ),
              Positioned(top: 12, right: 12, child: _buildStatusBadge()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.eventTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (r.eventStartDatetime != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('EEE, MMM d • h:mm a').format(r.eventStartDatetime!),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ],
                if (r.eventVenue != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.eventVenue!,
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _buildBody(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color bg;
    String text;
    if (registration.isPending) {
      bg = Colors.orange;
      text = 'PENDING';
    } else if (registration.isApproved) {
      bg = Colors.green;
      text = 'APPROVED';
    } else {
      bg = Colors.red;
      text = 'NOT APPROVED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (registration.isPending) {
      return _infoBox(
        icon: Icons.hourglass_top,
        color: Colors.orange,
        title: 'Awaiting organizer review',
        message: 'You\'ll be notified by email and in-app once they respond.',
      );
    }

    if (registration.isRejected) {
      final reason = registration.rejectionReason;
      return _infoBox(
        icon: Icons.cancel_outlined,
        color: Colors.red,
        title: 'Your request was not approved',
        message: (reason != null && reason.trim().isNotEmpty)
            ? reason
            : 'The organizer did not approve this registration.',
      );
    }

    // Approved
    if (registration.awaitingPayment) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBox(
            icon: Icons.check_circle_outline,
            color: Colors.green,
            title: 'You\'re approved!',
            message:
                'Complete your payment to secure your ticket — ₱${registration.eventTicketPrice.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPayNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Pay Now',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    // Approved + free → ticket should appear in upcoming tickets below
    return _infoBox(
      icon: Icons.check_circle_outline,
      color: Colors.green,
      title: 'You\'re approved!',
      message: 'Your ticket is now ready — check the Upcoming Events section.',
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: const TextStyle(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
