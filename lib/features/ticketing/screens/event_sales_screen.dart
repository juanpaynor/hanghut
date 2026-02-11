import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:intl/intl.dart';

class EventSalesScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventSalesScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventSalesScreen> createState() => _EventSalesScreenState();
}

class _EventSalesScreenState extends State<EventSalesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sales = [];
  String _filter = 'all'; // all, completed, refunded

  @override
  void initState() {
    super.initState();
    _fetchSales();
  }

  Future<void> _fetchSales() async {
    try {
      var query = SupabaseConfig.client
          .from('purchase_intents')
          .select('*, user:users(full_name, email, avatar_url)')
          .eq('event_id', widget.eventId);

      if (_filter != 'all') {
        query = query.eq('status', _filter);
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _sales = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching sales: $e')));
      }
    }
  }

  Future<void> _processRefund(
    String intentId,
    double amount,
    String reason,
  ) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final response = await SupabaseConfig.client.functions.invoke(
        'request-refund',
        body: {'intent_id': intentId, 'amount': amount, 'reason': reason},
      );

      // Dismiss loading
      if (mounted) Navigator.pop(context);

      // invoke throws on error usually, or returns data
      final data = response.data;
      if (data != null && data['error'] != null) {
        throw Exception(data['error']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refund requested successfully')),
        );
        Navigator.pop(context); // Close details dialog
        _fetchSales(); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        // Dismiss loading if still open (tricky with async, better handling needed in prod)
        // But here we popped already.

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refund failed: $e')));
      }
    }
  }

  void _showSaleDetails(Map<String, dynamic> sale) {
    final amount = (sale['total_amount'] as num).toDouble();
    final status = sale['status'];
    final user = sale['user'];
    final date = DateTime.parse(sale['created_at']);
    final reasonController = TextEditingController(
      text: 'REQUESTED_BY_CUSTOMER',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Buyer', user?['full_name'] ?? 'Guest'),
              _buildDetailRow(
                'Email',
                user?['email'] ?? sale['guest_email'] ?? '-',
              ),
              _buildDetailRow('Date', DateFormat.yMMMd().add_jm().format(date)),
              _buildDetailRow('Status', status.toString().toUpperCase()),
              const Divider(),
              _buildDetailRow('Quantity', '${sale['quantity']} tix'),
              _buildDetailRow(
                'Total',
                NumberFormat.currency(symbol: '₱').format(amount),
              ),
              if (sale['xendit_external_id'] != null)
                _buildDetailRow('Ref ID', sale['xendit_external_id']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (status == 'completed')
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                // Confirm refund
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm Refund'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Are you sure you want to refund ${NumberFormat.currency(symbol: '₱').format(amount)}?',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: reasonController,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () {
                          Navigator.pop(context); // Close confirm
                          _processRefund(
                            sale['id'],
                            amount,
                            reasonController.text,
                          );
                        },
                        child: const Text('Issue Refund'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Refund Order'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventTitle),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _filter = value;
                _isLoading = true;
              });
              _fetchSales();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Orders')),
              const PopupMenuItem(
                value: 'completed',
                child: Text('Completed Only'),
              ),
              const PopupMenuItem(
                value: 'refunded',
                child: Text('Refunded Only'),
              ),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
          ? const Center(child: Text('No orders found.'))
          : ListView.separated(
              itemCount: _sales.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sale = _sales[index];
                final user = sale['user'];
                final amount = (sale['total_amount'] as num).toDouble();
                final status = sale['status'];
                final date = DateTime.parse(sale['created_at']);

                Color statusColor = Colors.grey;
                if (status == 'completed') statusColor = Colors.green;
                if (status == 'pending') statusColor = Colors.orange;
                if (status == 'refunded') statusColor = Colors.red;

                return ListTile(
                  onTap: () => _showSaleDetails(sale),
                  leading: CircleAvatar(
                    backgroundImage: user?['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    child: user?['avatar_url'] == null
                        ? Text((user?['full_name'] ?? 'G')[0].toUpperCase())
                        : null,
                  ),
                  title: Text(
                    user?['full_name'] ?? sale['guest_name'] ?? 'Guest',
                  ),
                  subtitle: Text(
                    '${sale['quantity']} tix • ${DateFormat.MMMd().format(date)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormat.currency(symbol: '₱').format(amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: statusColor.withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          status.toString().toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
