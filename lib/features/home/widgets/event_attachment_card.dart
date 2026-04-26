import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

// Placeholder for Event Details Logic - ideally this would navigate to a dedicated Event Details Screen
// For now, we'll just show a dialog or navigate to a placeholder
class EventAttachmentCard extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback? onTap;
  final VoidCallback? onImageTap;

  const EventAttachmentCard({
    super.key,
    required this.event,
    this.onTap,
    this.onImageTap,
  });

  @override
  State<EventAttachmentCard> createState() => _EventAttachmentCardState();
}

class _EventAttachmentCardState extends State<EventAttachmentCard> {
  @override
  Widget build(BuildContext context) {
    final title = widget.event['title'] ?? 'Untitled Event';
    final venue =
        widget.event['venue_name'] ?? widget.event['address'] ?? 'TBA';
    final startTime = widget.event['start_datetime'] != null
        ? DateTime.parse(widget.event['start_datetime'])
        : DateTime.now();
    final imageUrl = widget.event['cover_image_url'] as String?;
    final price = widget.event['ticket_price'];

    final month = DateFormat('MMM').format(startTime).toUpperCase();
    final day = DateFormat('d').format(startTime);
    final time = DateFormat('h:mm a').format(startTime);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              widget.onTap ??
              () {
                // Default action: Navigate to Event Details (Placeholder)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Navigate to Event Details Screen'),
                  ),
                );
              },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Cover Image
              if (imageUrl != null)
                GestureDetector(
                  onTap: widget.onImageTap,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    placeholder: (context, url) => Container(
                      height: 150,
                      color: Colors.grey[100],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 150,
                      color: Colors.grey[100],
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 100,
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  child: Center(
                    child: Icon(
                      Icons.event,
                      size: 40,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),

              // 2. Info Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Date Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            month,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          Text(
                            day,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Text Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  venue,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Description
              if (widget.event['description'] != null &&
                  widget.event['description'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    widget.event['description'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // 3. Footer / Button Area
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Price Tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        price != null && price > 0
                            ? (widget.event['is_external'] == true ? 'From ₱${price}' : '₱${price}')
                            : 'FREE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                          fontSize: 13,
                        ),
                      ),
                    ),

                    // CTA Button
                    Text(
                      widget.event['is_external'] == true
                          ? 'Get Tickets →'
                          : 'Get Tickets →',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
