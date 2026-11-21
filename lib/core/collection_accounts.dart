/// A shop can publish multiple collection destinations to its customers.
/// These are merchant-provided details, never automatic payment instructions.
const collectionMethodLabels = <String, String>{
  'Bank': 'تحويل بنكي',
  'PalPay': 'محفظة PalPay',
  'PalPayBusiness': 'PalPay تجاري',
  'JawwalPay': 'محفظة جوال بي',
  'JawwalPayBusiness': 'جوال بي تجاري',
};

class ShopCollectionAccount {
  const ShopCollectionAccount({
    required this.method,
    required this.accountHolder,
    required this.accountNumber,
    this.bankName = '',
  });
  final String method, accountHolder, accountNumber, bankName;

  factory ShopCollectionAccount.fromJson(Map<String, dynamic> json) =>
      ShopCollectionAccount(
        method: '${json['method'] ?? ''}',
        accountHolder: '${json['accountHolder'] ?? ''}',
        accountNumber: '${json['accountNumber'] ?? ''}',
        bankName: '${json['bankName'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
    'method': method,
    'accountHolder': accountHolder,
    'accountNumber': accountNumber,
    'bankName': bankName,
  };

  String get destination => method == 'Bank' && bankName.trim().isNotEmpty
      ? 'تحويل بنكي - ${bankName.trim()}'
      : collectionMethodLabels[method] ?? method;

  String get description => '$destination | $accountHolder | $accountNumber';
}

List<ShopCollectionAccount> collectionAccountsFromSettings(
  Map<String, dynamic>? settings,
) {
  final raw = settings?['collectionAccounts'];
  if (raw is! List) return [];
  return raw.whereType<Map>().map((e) =>
      ShopCollectionAccount.fromJson(Map<String, dynamic>.from(e))).toList();
}

List<String> collectionAccountLines(List<ShopCollectionAccount> accounts) => [
  if (accounts.isNotEmpty) 'معلومات التحويل إلى المحل:',
  for (final account in accounts)
    '- ${account.destination}: ${account.accountNumber} | اسم صاحب الحساب: ${account.accountHolder}',
];
