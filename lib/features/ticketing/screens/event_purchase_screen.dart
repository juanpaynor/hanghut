import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/screens/ticket_success_screen.dart';
import 'dart:async';

class EventPurchaseScreen extends StatefulWidget {
  final Event event;

  const EventPurchaseScreen({super.key, required this.event});

  @override
  State<EventPurchaseScreen> createState() => _EventPurchaseScreenState();
}

class _EventPurchaseScreenState extends State<EventPurchaseScreen> {
  int _quantity = 1;
  bool _isLoading = false;
  Map<String, dynamic>? _cachedInvoice;
  String? _currentPurchaseIntentId;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _preloadInvoice();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Pre-load invoice in background for instant checkout
  Future<void> _preloadInvoice() async {
    try {
      final invoice = await _createInvoice(quantity: 1);
      if (mounted) {
        setState(() => _cachedInvoice = invoice);
      }
      print('✅ Invoice pre-loaded for instant checkout');
    } catch (e) {
      print('⚠️ Invoice pre-load failed: $e');
      // Silent fail - will create on-demand
    }
  }

  /// Create purchase intent via Edge Function
  Future<Map<String, dynamic>> _createInvoice({required int quantity}) async {
    final response = await SupabaseConfig.client.functions.invoke(
      'create-purchase-intent',
      body: {
        'event_id': widget.event.id,
        'quantity': quantity,
        'amount': widget.event.ticketPrice * quantity,
        // Use official HangHut web URLs for redirect
        'success_url': 'https://hanghut.com/checkout/success',
        'failure_url': 'https://hanghut.com/events/${widget.event.id}',
      },
    );

    if (response.status != 200) {
      throw Exception('Failed to create purchase intent');
    }

    return response.data as Map<String, dynamic>;
  }

  /// Main purchase flow
  Future<void> _proceedToPayment() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Use cached invoice if quantity matches, otherwise create new
      final invoice = (_cachedInvoice != null && _quantity == 1)
          ? _cachedInvoice!
          : await _createInvoice(quantity: _quantity);

      // Extract data from nested response structure
      final data = invoice['data'] as Map<String, dynamic>;
      final invoiceUrl = data['payment_url'] as String;
      _currentPurchaseIntentId = data['intent_id'] as String;

      // Validate URL
      if (!invoiceUrl.startsWith('https://')) {
        throw Exception('Invalid payment URL');
      }

      // Launch payment page in Custom Tabs / SFSafariViewController
      final launched = await launchUrl(
        Uri.parse(invoiceUrl),
        mode: LaunchMode.inAppBrowserView,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
        ),
      );

      if (!launched) {
        throw Exception('Could not open payment page');
      }

      // Start background polling for payment status
      if (mounted) {
        _startPaymentPolling();
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Poll for payment completion
  void _startPaymentPolling() {
    // Show processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProcessingDialog(
        onCancel: () {
          _pollingTimer?.cancel();
          Navigator.pop(context);
        },
      ),
    );

    int pollCount = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      pollCount++;

      try {
        final purchase = await SupabaseConfig.client
            .from('purchase_intents')
            .select('status')
            .eq('id', _currentPurchaseIntentId!)
            .single();

        final status = purchase['status'] as String;

        if (status == 'completed') {
          timer.cancel();
          if (mounted) {
            Navigator.pop(context); // Close processing dialog
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => TicketSuccessScreen(
                  purchaseIntentId: _currentPurchaseIntentId!,
                ),
              ),
            );
          }
        } else if (status == 'failed' || status == 'expired') {
          timer.cancel();
          if (mounted) {
            Navigator.pop(context);
            _showErrorDialog(
              'Payment Failed',
              'The payment was not completed.',
            );
          }
        }
      } catch (e) {
        print('⚠️ Polling error: $e');
      }

      // Timeout after 5 minutes
      if (pollCount > 100) {
        timer.cancel();
        if (mounted) {
          Navigator.pop(context);
          _showTimeoutDialog();
        }
      }
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Taking Longer Than Expected'),
        content: const Text(
          'The payment is taking longer than usual. '
          'You can check "My Tickets" in a few minutes or contact support.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/my-tickets');
            },
            child: const Text('Check My Tickets'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.event.ticketPrice * _quantity;

    return Scaffold(
      appBar: AppBar(title: const Text('Buy Tickets'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event summary card
                  _EventSummaryCard(event: widget.event),

                  const SizedBox(height: 32),

                  // Quantity selector
                  const Text(
                    'Number of Tickets',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _QuantitySelector(
                    quantity: _quantity,
                    max: widget.event.ticketsAvailable.clamp(1, 10),
                    onChanged: (qty) => setState(() => _quantity = qty),
                  ),

                  const SizedBox(height: 32),

                  // Price breakdown
                  _PriceBreakdown(
                    ticketPrice: widget.event.ticketPrice,
                    quantity: _quantity,
                    total: total,
                  ),
                ],
              ),
            ),
          ),

          // Bottom action
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _proceedToPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Proceed to Payment • ₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// SUPPORTING WIDGETS
// ============================================

class _EventSummaryCard extends StatelessWidget {
  final Event event;

  const _EventSummaryCard({required this.event});

  @override
  Widget build(BuildContext context) {
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
          // Event image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: event.coverImageUrl ?? '',
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey[300]),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.event, size: 48),
                ),
              ),
            ),
          ),

          // Event details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.location_on, text: event.venueName),
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.calendar_today,
                  text: DateFormat(
                    'MMM d, y • h:mm a',
                  ).format(event.startDatetime),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  const _QuantitySelector({
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          icon: const Icon(Icons.remove_circle),
          iconSize: 32,
          color: quantity > 1 ? Colors.deepPurple : Colors.grey,
        ),
        const SizedBox(width: 16),
        Text(
          '$quantity',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: quantity < max ? () => onChanged(quantity + 1) : null,
          icon: const Icon(Icons.add_circle),
          iconSize: 32,
          color: quantity < max ? Colors.deepPurple : Colors.grey,
        ),
        const Spacer(),
        if (max < 10)
          Text(
            'Only $max left',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange[700],
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _PriceBreakdown extends StatelessWidget {
  final double ticketPrice;
  final int quantity;
  final double total;

  const _PriceBreakdown({
    required this.ticketPrice,
    required this.quantity,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _PriceRow(
            label: 'Ticket Price',
            value: '₱${ticketPrice.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _PriceRow(label: 'Quantity', value: '× $quantity'),
          const Divider(height: 24),
          _PriceRow(
            label: 'Total',
            value: '₱${total.toStringAsFixed(2)}',
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _PriceRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _ProcessingDialog extends StatelessWidget {
  final VoidCallback onCancel;

  const _ProcessingDialog({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('Confirming payment...', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'This may take a few moments',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [TextButton(onPressed: onCancel, child: const Text('Cancel'))],
    );
  }
}
