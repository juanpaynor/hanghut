import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/scanner_service.dart';
import 'package:bitemates/features/ticketing/screens/ticket_scanner_screen.dart';

/// Lets scan-eligible organizers/staff pick which of their events to scan
/// tickets for, then opens the camera scanner for that event.
class ScanEntryScreen extends StatefulWidget {
  const ScanEntryScreen({super.key});

  @override
  State<ScanEntryScreen> createState() => _ScanEntryScreenState();
}

class _ScanEntryScreenState extends State<ScanEntryScreen> {
  final ScannerService _service = ScannerService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = true;
  List<Map<String, dynamic>> _events = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _load() async {
    final partnerIds = await _service.getScannablePartnerIds();
    final events = await _service.getScannableEvents(partnerIds);
    if (mounted) {
      setState(() {
        _events = events;
        _isLoading = false;
      });
    }
  }

  /// Events filtered by the search query (matches title or venue).
  List<Map<String, dynamic>> get _filteredEvents {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _events;
    return _events.where((e) {
      final title = (e['title'] ?? '').toString().toLowerCase();
      final venue = (e['venue_name'] ?? '').toString().toLowerCase();
      return title.contains(q) || venue.contains(q);
    }).toList();
  }

  void _openScanner(Map<String, dynamic> event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TicketScannerScreen(
          eventId: event['id'] as String,
          eventTitle: (event['title'] ?? 'Event') as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Tickets')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(child: _buildEventList()),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search events by name or venue',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildEventList() {
    final events = _filteredEvents;
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No events match "${_query.trim()}"',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: events.length,
        itemBuilder: (context, index) => _buildEventTile(events[index]),
      ),
    );
  }


  Widget _buildEmpty() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No events to scan',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Upcoming events you can scan for will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final date = DateTime.tryParse(event['start_datetime']?.toString() ?? '');
    final cover = event['cover_image_url'] as String?;
    final sold = event['tickets_sold'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openScanner(event),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: cover != null
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _coverFallback(),
                      )
                    : _coverFallback(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (event['title'] ?? 'Event').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (date != null)
                      Text(
                        DateFormat.yMMMEd().add_jm().format(date),
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '$sold sold',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback() {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey[300],
      child: Icon(Icons.event, color: Colors.grey[500]),
    );
  }
}
