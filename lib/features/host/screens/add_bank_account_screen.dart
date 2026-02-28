import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class AddBankAccountScreen extends StatefulWidget {
  final String partnerId;

  const AddBankAccountScreen({super.key, required this.partnerId});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _hostService = HostService();
  final _formKey = GlobalKey<FormState>();

  final _accountNumberController = TextEditingController();
  final _accountHolderController = TextEditingController();

  String? _selectedBankCode;

  bool _isSaving = false;

  static const Map<String, String> _supportedBanks = {
    'PH_GCASH': 'GCash',
    'PH_PAYMAYA': 'Maya (PayMaya)',
    'PH_GRABPAY': 'GrabPay',
    'PH_COINS': 'Coins.PH',
    'PH_BPI': 'Bank of the Philippine Islands (BPI)',
    'PH_BDO': 'Banco De Oro Unibank, Inc. (BDO)',
    'PH_UBP': 'Union Bank of the Philippines (UBP)',
    'PH_RCBC': 'Rizal Commercial Banking Corporation (RCBC)',
    'PH_SEC': 'Security Bank Corporation',
    'PH_LBP': 'Land Bank of The Philippines',
    'PH_MET': 'Metropolitan Bank and Trust Company (Metrobank)',
    'PH_PNB': 'Philippine National Bank (PNB)',
    'PH_PSB': 'Philippine Savings Bank (PSBank)',
    'PH_EWB': 'East West Banking Corporation',
    'PH_CBC': 'China Banking Corporation',
    'PH_SB': 'Security Bank',
    'PH_AUB': 'Asia United Bank (AUB)',
    'PH_BOC': 'Bank of Commerce',
    'PH_CIMB': 'CIMB Bank Philippines',
    'PH_GOTYME': 'GoTyme Bank',
    'PH_SEA': 'Seabank Philippines Inc.',
  };

  @override
  void dispose() {
    _accountNumberController.dispose();
    _accountHolderController.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      await _hostService.addBankAccount(
        partnerId: widget.partnerId,
        bankCode: _selectedBankCode!,
        bankName: _supportedBanks[_selectedBankCode]!,
        accountNumber: _accountNumberController.text.trim(),
        accountHolderName: _accountHolderController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add bank account: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Add Payout Method',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where should we send your earnings?',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a local bank account or e-wallet (like GCash or Maya) to receive your payouts.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),

                // Bank Name
                Text(
                  'Bank Name / E-wallet',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedBankCode,
                  isExpanded: true,
                  hint: Text(
                    'Select Bank or E-wallet',
                    style: GoogleFonts.inter(color: Colors.grey[500]),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  items: _supportedBanks.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: GoogleFonts.inter(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBankCode = val;
                    });
                  },
                  validator: (val) => val == null || val.isEmpty
                      ? 'Please select a bank or e-wallet'
                      : null,
                ),
                const SizedBox(height: 24),

                // Account Number
                Text(
                  'Account Number',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _accountNumberController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g., 09123456789 or 10987654321',
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Please enter your account number'
                      : null,
                ),
                const SizedBox(height: 24),

                // Account Holder Name
                Text(
                  'Account Holder Name',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _accountHolderController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Juan Dela Cruz',
                    filled: true,
                    fillColor: Colors.white,
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
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Please enter the account holder name'
                      : null,
                ),
                const SizedBox(height: 48),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save Payout Method',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
