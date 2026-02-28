import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';

class HostBookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> booking;

  const HostBookingDetailScreen({super.key, required this.booking});

  @override
  State<HostBookingDetailScreen> createState() =>
      _HostBookingDetailScreenState();
}

class _HostBookingDetailScreenState extends State<HostBookingDetailScreen> {
  final HostService _hostService = HostService();
  bool _isLoading = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.booking['check_in_status'] ?? 'pending';
  }

  Future<void> _issueRefund() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue Refund'),
        content: const Text(
          'Are you sure you want to refund this guest? This action cannot be undone and will void their ticket.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Refund', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'request-refund',
        body: {
          'intent_id': widget.booking['id'],
          'reason': 'REQUESTED_BY_CUSTOMER',
          'intent_type': 'experience',
        },
      );

      if (response.status == 200) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            widget.booking['status'] = 'refunded';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Refund completed successfully.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Refund failed: ${response.status}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request refund: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isLoading = true);
    try {
      if (newStatus == 'checked_in') {
        await _hostService.checkInGuest(widget.booking['id']);
      } else if (newStatus == 'no_show') {
        await _hostService.markGuestNoShow(widget.booking['id']);
      }

      if (mounted) {
        setState(() {
          _currentStatus = newStatus;
          _isLoading = false;
        });
        widget.booking['check_in_status'] = newStatus; // Update local ref
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guest marked as $newStatus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  bool _isCreatingChat = false;

  Future<void> _messageGuest(
    String guestId,
    String guestName,
    String experienceName,
  ) async {
    if (_isCreatingChat) return;
    setState(() => _isCreatingChat = true);

    try {
      final chatId = await DirectChatService().startConversation(guestId);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              tableId: chatId,
              tableTitle: guestName,
              channelId: 'dm:$chatId',
              chatType: 'dm',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guestName = widget.booking['guest_name'] ?? 'Guest';
    final guestEmail = widget.booking['guest_email'] ?? 'No email provided';
    final guestPhone = widget.booking['guest_phone'] ?? 'No phone provided';
    final quantity = widget.booking['quantity'] as int? ?? 1;
    final total = widget.booking['total_amount'] as num? ?? 0;

    final schedule = widget.booking['schedule'] as Map<String, dynamic>?;
    final experienceName =
        (widget.booking['experience'] as Map<String, dynamic>?)?['title'] ??
        'Experience';
    final start = schedule != null
        ? DateTime.tryParse(schedule['start_time'] ?? '')
        : null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Booking Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirmed Booking',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[800],
                        ),
                      ),
                      if (_currentStatus == 'checked_in')
                        Text(
                          'Guest Checked In',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.green[700],
                          ),
                        )
                      else if (_currentStatus == 'no_show')
                        Text(
                          'Marked as No Show',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.red[700],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Experience Info
            Text('EXPERIENCE', style: _labelStyle()),
            const SizedBox(height: 8),
            _infoCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.explore, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          experienceName,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (start != null)
                          Text(
                            DateFormat(
                              'EEEE, MMM d, yyyy • h:mm a',
                            ).format(start),
                            style: GoogleFonts.inter(color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Guest Info
            Text('GUEST INFORMATION', style: _labelStyle()),
            const SizedBox(height: 8),
            _infoCard(
              child: Column(
                children: [
                  _detailRow(Icons.person, 'Name', guestName),
                  const Divider(),
                  _detailRow(Icons.people, 'Party Size', '$quantity Guests'),
                  const Divider(),
                  _detailRow(Icons.email, 'Email', guestEmail),
                  const Divider(),
                  _detailRow(Icons.phone, 'Phone', guestPhone),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Summary
            Text('PAYMENT', style: _labelStyle()),
            const SizedBox(height: 8),
            _infoCard(
              child: Column(
                children: [
                  _detailRow(
                    Icons.receipt_long,
                    'Total Paid',
                    '₱${total.toStringAsFixed(2)}',
                  ),
                  const Divider(),
                  _detailRow(
                    Icons.credit_card,
                    'Payment Method',
                    (widget.booking['payment_method'] ?? 'XENDIT')
                        .toString()
                        .toUpperCase(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Actions
            Text('ACTIONS', style: _labelStyle()),
            const SizedBox(height: 8),

            if (widget.booking['user_id'] != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCreatingChat
                      ? null
                      : () => _messageGuest(
                          widget.booking['user_id'],
                          guestName,
                          experienceName,
                        ),
                  icon: _isCreatingChat
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message Guest'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_currentStatus == 'pending') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _updateStatus('checked_in'),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Check In Guest'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _updateStatus('no_show'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Mark as No Show'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.red[600],
                    side: BorderSide(color: Colors.red[200]!),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (widget.booking['status'] == 'completed') ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _issueRefund,
                  icon: const Icon(Icons.money_off),
                  label: const Text('Issue Refund'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.red[600],
                    side: BorderSide(color: Colors.red[200]!),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle() {
    return GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Colors.grey[500],
      letterSpacing: 1.2,
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: child,
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
