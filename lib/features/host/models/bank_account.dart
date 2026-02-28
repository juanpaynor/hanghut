class BankAccount {
  final String id;
  final String partnerId;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final bool isPrimary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BankAccount({
    required this.id,
    required this.partnerId,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    this.isPrimary = false,
    this.createdAt,
    this.updatedAt,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      bankCode: json['bank_code'] as String,
      bankName: json['bank_name'] as String,
      accountNumber: json['account_number'] as String,
      accountHolderName: json['account_holder_name'] as String,
      isPrimary: json['is_primary'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'partner_id': partnerId,
      'bank_code': bankCode,
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_holder_name': accountHolderName,
      'is_primary': isPrimary,
    };
  }
}
