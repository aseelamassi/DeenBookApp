/// Labels and accepted movement types for the two account report tabs.
/// Both use the same backend EntryKind values; only the display differs.
const customerReportKinds = <String, String>{
  'all': 'كل الحركات',
  'Debt': 'دين',
  'Payment': 'دفعة',
  'Return': 'مرتجع',
};

const supplierReportKinds = <String, String>{
  'all': 'كل الحركات',
  'Purchase': 'مشتريات',
  'Payment': 'دفعة لمورد',
  'Return': 'مرتجع',
};

Map<String, String> reportKindsFor(String? partyKind) =>
    partyKind == 'Supplier' ? supplierReportKinds : customerReportKinds;

String reportKindLabel(String? partyKind, String? kind) =>
    reportKindsFor(partyKind)[kind ?? 'all'] ?? 'حركة';
