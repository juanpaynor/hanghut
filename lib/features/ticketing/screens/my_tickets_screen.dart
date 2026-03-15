import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/models/ticket.dart';
import 'package:bitemates/features/ticketing/widgets/ticket_card.dart';

/// Page size for paginated ticket loading from RPC
const int _kPageSize = 15;

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  final _ticketService = TicketService();
  List<Ticket> _tickets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _selectedFilter = 'All';
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 0;
        _tickets = [];
        _hasMore = true;
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final tickets = await _ticketService.getUserTickets(
        limit: _kPageSize,
        offset: 0,
        forceRefresh: refresh,
      );
      if (mounted) {
        _logTicketBreakdown(tickets);
        setState(() {
          _tickets = tickets;
          _currentPage = 1;
          _hasMore = tickets.length >= _kPageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final moreTickets = await _ticketService.getUserTickets(
        limit: _kPageSize,
        offset: _currentPage * _kPageSize,
      );
      if (mounted) {
        setState(() {
          _tickets.addAll(moreTickets);
          _currentPage++;
          _hasMore = moreTickets.length >= _kPageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _logTicketBreakdown(List<Ticket> tickets) {
    final upcoming = tickets.where((t) => t.isUpcoming).length;
    final used = tickets.where((t) => t.isUsed).length;
    final expired = tickets
        .where((t) => t.isExpired && !t.isUsed && !t.isCancelled && !t.isRefunded)
        .length;
    final cancelled = tickets.where((t) => t.isCancelled || t.isRefunded).length;
    final events = tickets.map((t) => t.eventTitle).toSet();
    print('🎟️ Tickets: $upcoming upcoming, $used used, $expired expired, $cancelled cancelled');
    print('🎟️ Events: $events');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Tickets'), centerTitle: true),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = ['All', 'Upcoming', 'Past', 'Cancelled'];
    final primaryColor = Theme.of(context).primaryColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to load tickets',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadTickets,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Tickets Yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your purchased tickets will appear here',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/map',
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Browse Events'),
              ),
            ],
          ),
        ),
      );
    }

    // Categorize tickets
    final filteredTickets = _getFilteredTickets();

    if (filteredTickets.isEmpty) {
      return Center(
        child: Text(
          'No ${_selectedFilter.toLowerCase()} tickets found',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    // Build a flat list of widgets for the ListView.builder
    final items = _buildListItems(filteredTickets);

    return RefreshIndicator(
      onRefresh: () => _loadTickets(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + (_hasMore || _isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              // Loading indicator at bottom
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return items[index];
          },
        ),
      ),
    );
  }

  List<Ticket> _getFilteredTickets() {
    switch (_selectedFilter) {
      case 'Upcoming':
        final list = _tickets.where((t) => t.isUpcoming).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      case 'Past':
        final used = _tickets.where((t) => t.isUsed).toList();
        final expired = _tickets.where(
          (t) => t.isExpired && !t.isUsed && !t.isCancelled && !t.isRefunded,
        ).toList();
        final combined = [...used, ...expired];
        combined.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));
        return combined;
      case 'Cancelled':
        final list = _tickets.where((t) => t.isCancelled || t.isRefunded).toList();
        list.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));
        return list;
      default: // All
        return _tickets;
    }
  }

  List<Widget> _buildListItems(List<Ticket> filteredTickets) {
    final items = <Widget>[];

    if (_selectedFilter == 'All') {
      // Group by section
      final upcoming = filteredTickets.where((t) => t.isUpcoming).toList();
      upcoming.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final used = filteredTickets.where((t) => t.isUsed).toList();
      used.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));

      final expired = filteredTickets.where(
        (t) => t.isExpired && !t.isUsed && !t.isCancelled && !t.isRefunded,
      ).toList();
      expired.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));

      final cancelled = filteredTickets.where((t) => t.isCancelled || t.isRefunded).toList();
      cancelled.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));

      if (upcoming.isNotEmpty) {
        items.add(_SectionHeader(title: 'Upcoming Events', count: upcoming.length));
        items.add(const SizedBox(height: 12));
        for (final ticket in upcoming) {
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TicketCard(ticket: ticket),
          ));
        }
        items.add(const SizedBox(height: 8));
      }
      if (used.isNotEmpty) {
        items.add(_SectionHeader(title: 'Used Tickets', count: used.length));
        items.add(const SizedBox(height: 12));
        for (final ticket in used) {
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TicketCard(ticket: ticket),
          ));
        }
        items.add(const SizedBox(height: 8));
      }
      if (expired.isNotEmpty) {
        items.add(_SectionHeader(title: 'Expired', count: expired.length));
        items.add(const SizedBox(height: 12));
        for (final ticket in expired) {
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TicketCard(ticket: ticket),
          ));
        }
        items.add(const SizedBox(height: 8));
      }
      if (cancelled.isNotEmpty) {
        items.add(_SectionHeader(title: 'Cancelled / Refunded', count: cancelled.length));
        items.add(const SizedBox(height: 12));
        for (final ticket in cancelled) {
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TicketCard(ticket: ticket),
          ));
        }
      }
    } else {
      // Single filtered list — no section headers needed
      for (final ticket in filteredTickets) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TicketCard(ticket: ticket),
        ));
      }
    }

    return items;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ),
      ],
    );
  }
}
