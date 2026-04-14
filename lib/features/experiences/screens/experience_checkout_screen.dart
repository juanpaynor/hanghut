import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/experience_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';

class ExperienceCheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> experience;
  final Map<String, dynamic> schedule;
  final int quantity;
  final double unitPrice;

  const ExperienceCheckoutScreen({
    super.key,
    required this.experience,
    required this.schedule,
    required this.quantity,
    required this.unitPrice,
  });

  @override
  State<ExperienceCheckoutScreen> createState() =>
      _ExperienceCheckoutScreenState();
}

class _ExperienceCheckoutScreenState extends State<ExperienceCheckoutScreen> {
  final _experienceService = ExperienceService();
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _completePhoneNumber = '';

  bool _isProcessing = false;
  bool _subscribedToNewsletter = true;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      try {
        _emailController.text = user.email ?? '';

        final data = await SupabaseConfig.client
            .from('users')
            .select('display_name')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            _nameController.text = data['display_name'] ?? '';
          });
        }
      } catch (e) {
        print('⚠️ Failed to fetch profile: $e');
      }
    }
  }

  Future<void> _handleConfirmAndPay() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
      final guestDetails = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _completePhoneNumber.isNotEmpty
            ? _completePhoneNumber
            : _phoneController.text.trim(),
      };

      final result = await _experienceService.createPaymentIntent(
        tableId: widget.experience['id'],
        scheduleId: widget.schedule['id'],
        quantity: widget.quantity,
        guestDetails: guestDetails,
        subscribedToNewsletter: _subscribedToNewsletter,
      );

      final paymentUrl = result['payment_url'];
      if (paymentUrl != null) {
        final uri = Uri.parse(paymentUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            Navigator.of(context).pop(); // Pops the checkout
            Navigator.of(context).pop(); // Pops the Modal
          }
        } else {
          throw Exception('Could not launch payment URL');
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, error: e, fallbackMessage: 'Unable to process booking. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showFullScreenPreview(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: (widget.experience['images'] as List).length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(
                  widget.experience['images'][index],
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(widget.schedule['start_time']);
    final total = widget.unitPrice * widget.quantity;
    final currency = widget.experience['currency'] ?? '₱';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black87),
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Confirm Booking',
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              centerTitle: true,
              background:
                  widget.experience['images'] != null &&
                      (widget.experience['images'] as List).isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                          },
                          itemCount: (widget.experience['images'] as List).length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => _showFullScreenPreview(index),
                              child: Image.network(
                                widget.experience['images'][index],
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.9),
                              ],
                              stops: const [0.6, 1.0],
                            ),
                          ),
                        ),
                        if ((widget.experience['images'] as List).length > 1)
                          Positioned(
                            bottom: 24,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                (widget.experience['images'] as List).length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: _currentImageIndex == index ? 24 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: _currentImageIndex == index
                                        ? Colors.black87
                                        : Colors.black38,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.image,
                        color: Colors.grey,
                        size: 50,
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Summary
                  Text(
                    widget.experience['title'] ?? 'Experience',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM d').format(start),
                        style: GoogleFonts.inter(
                          color: Colors.grey[800], fontSize: 16, fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time_outlined, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('h:mm a').format(start),
                        style: GoogleFonts.inter(
                          color: Colors.grey[800], fontSize: 16, fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // 2. Guest Details
                  Text(
                    'GUEST DETAILS',
                    style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold,
                      color: Colors.grey[500], letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.quantity > 1)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue[700], size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You are booking for ${widget.quantity} guests. We just need the primary contact\'s details.',
                              style: GoogleFonts.inter(
                                color: Colors.blue[900], fontSize: 14, height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.deepPurple),
                              ),
                            ),
                            validator: (value) =>
                                value!.trim().isEmpty ? 'Name is required' : null,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.deepPurple),
                              ),
                            ),
                            validator: (value) => value == null
                                ? 'Required'
                                : (!value.contains('@') ? 'Invalid email' : null),
                          ),
                          const SizedBox(height: 20),
                          IntlPhoneField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.deepPurple),
                              ),
                            ),
                            initialCountryCode: 'PH',
                            dropdownIconPosition: IconPosition.trailing,
                            flagsButtonPadding: const EdgeInsets.only(left: 8),
                            dropdownTextStyle: const TextStyle(fontSize: 16),
                            pickerDialogStyle: PickerDialogStyle(
                              backgroundColor: Colors.white,
                              countryCodeStyle: const TextStyle(color: Colors.black54),
                              countryNameStyle: const TextStyle(
                                color: Colors.black87, fontSize: 16,
                              ),
                              searchFieldInputDecoration: InputDecoration(
                                hintText: 'Search country',
                                hintStyle: const TextStyle(color: Colors.black38),
                                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            onChanged: (phone) {
                              _completePhoneNumber = phone.completeNumber;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- NEWSLETTER OPT-IN ---
                  CheckboxListTile(
                    value: _subscribedToNewsletter,
                    onChanged: (val) => setState(() => _subscribedToNewsletter = val ?? true),
                    title: Text(
                      'Subscribe to updates from this organizer',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800]),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: Colors.deepPurple,
                  ),

                  const SizedBox(height: 40),

                  // 3. Price Breakdown
                  Text(
                    'PRICE BREAKDOWN',
                    style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold,
                      color: Colors.grey[500], letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$currency ${widget.unitPrice.toStringAsFixed(0)} x ${widget.quantity} guests',
                              style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 16),
                            ),
                            Text(
                              '$currency ${total.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                color: Colors.grey[800], fontWeight: FontWeight.w600, fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total (PHP)',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87,
                              ),
                            ),
                            Text(
                              '$currency ${total.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _handleConfirmAndPay,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'Confirm and Pay',
                    style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
