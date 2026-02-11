import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/models/ticket.dart';
import 'package:bitemates/features/ticketing/widgets/ticket_card.dart';
import 'package:bitemates/core/config/supabase_config.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  final _ticketService = TicketService();
  List<Ticket>? _tickets;
  bool _isLoading = true;
  String? _error;
  String _selectedFilter = 'All'; // New filter state

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tickets = await _ticketService.getUserTickets();
      if (mounted) {
        setState(() {
          _tickets = tickets;
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
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter;
          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) setState(() => _selectedFilter = filter);
            },
            selectedColor: Colors.deepPurple,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.grey[200],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? Colors.deepPurple : Colors.transparent,
              ),
            ),
            showCheckmark: false,
          );
        },
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
              Text(
                'Failed to load tickets',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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

    if (_tickets == null || _tickets!.isEmpty) {
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

    // Group tickets by status
    var upcomingTickets = _tickets!.where((t) => t.isUpcoming).toList();
    // Sort Upcoming: Soonest First (ASC)
    upcomingTickets.sort((a, b) => a.eventDateTime.compareTo(b.eventDateTime));

    var usedTickets = _tickets!.where((t) => t.isUsed).toList();
    // Sort Past: Most Recent First (DESC)
    usedTickets.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));

    var cancelledRefundedTickets = _tickets!
        .where((t) => t.isCancelled || t.isRefunded)
        .toList();
    cancelledRefundedTickets.sort(
      (a, b) => b.eventDateTime.compareTo(a.eventDateTime),
    );

    var expiredTickets = _tickets!
        .where(
          (t) => t.isExpired && !t.isUsed && !t.isCancelled && !t.isRefunded,
        )
        .toList();
    expiredTickets.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));

    // Apply Filter logic
    if (_selectedFilter == 'Upcoming') {
      usedTickets = [];
      expiredTickets = [];
      cancelledRefundedTickets = [];
    } else if (_selectedFilter == 'Past') {
      upcomingTickets = [];
      cancelledRefundedTickets = [];
      // Show used & expired
    } else if (_selectedFilter == 'Cancelled') {
      upcomingTickets = [];
      usedTickets = [];
      expiredTickets = [];
    }

    // Check if empty after filter
    if (upcomingTickets.isEmpty &&
        usedTickets.isEmpty &&
        expiredTickets.isEmpty &&
        cancelledRefundedTickets.isEmpty) {
      return Center(
        child: Text(
          'No ${_selectedFilter.toLowerCase()} tickets found',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTickets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (upcomingTickets.isNotEmpty) ...[
            _SectionHeader(
              title: 'Upcoming Events',
              count: upcomingTickets.length,
            ),
            const SizedBox(height: 12),
            ...upcomingTickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TicketCard(ticket: ticket),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (usedTickets.isNotEmpty) ...[
            _SectionHeader(title: 'Used Tickets', count: usedTickets.length),
            const SizedBox(height: 12),
            ...usedTickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TicketCard(ticket: ticket),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (expiredTickets.isNotEmpty) ...[
            _SectionHeader(title: 'Expired', count: expiredTickets.length),
            const SizedBox(height: 12),
            ...expiredTickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TicketCard(ticket: ticket),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (cancelledRefundedTickets.isNotEmpty) ...[
            _SectionHeader(
              title: 'Cancelled / Refunded',
              count: cancelledRefundedTickets.length,
            ),
            const SizedBox(height: 12),
            ...cancelledRefundedTickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TicketCard(ticket: ticket),
              ),
            ),
          ],
        ],
      ),
    );
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
