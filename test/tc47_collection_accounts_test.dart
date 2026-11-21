import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/collection_accounts.dart';
import 'package:deenbook/core/report_share_summary.dart';
import 'package:deenbook/services/export.dart';

void main() {
  const bank = ShopCollectionAccount(
    method: 'Bank', accountHolder: 'أحمد', accountNumber: 'PS12 0001', bankName: 'بنك فلسطين');
  const palPay = ShopCollectionAccount(
    method: 'PalPayBusiness', accountHolder: 'شركة السعادة', accountNumber: '0591112222');
  const jawwal = ShopCollectionAccount(
    method: 'JawwalPayBusiness', accountHolder: 'لؤي', accountNumber: '0593334444');
  final accounts = [bank, palPay, jawwal];

  test('TC-47: several collection accounts retain different owners and destinations', () {
    final settings = <String, dynamic>{
      'collectionAccounts': accounts.map((a) => a.toJson()).toList(),
    };
    final restored = collectionAccountsFromSettings(settings);
    expect(restored, hasLength(3));
    expect(restored[0].destination, contains('بنك فلسطين'));
    expect(restored[1].destination, contains('تجاري'));
    expect(restored[2].accountHolder, 'لؤي');
    expect(restored.map((a) => a.accountNumber).toSet(), hasLength(3));
  });

  test('TC-47: old settings work safely with no collection accounts', () {
    expect(collectionAccountsFromSettings({'name': 'اختبار'}), isEmpty);
    expect(collectionAccountLines([]), isEmpty);
  });

  test('TC-47: customer summary includes all accounts', () {
    final draft = buildReportShareSummary(
      shopName: 'محل السعادة', partyKind: 'Customer', periodLabel: 'هذا الشهر',
      overview: {'invoices': 100, 'received': 20, 'returns': 0},
      partyName: 'محمد', currentBalance: 80, collectionAccounts: accounts,
    );
    expect(draft, contains('المشتريات'));
    expect(draft, contains('معلومات التحويل إلى المحل'));
    expect(draft, contains('PS12 0001'));
    expect(draft, contains('0591112222'));
    expect(draft, contains('0593334444'));
    expect(draft, contains('اسم صاحب الحساب: شركة السعادة'));
  });

  test('TC-47: supplier summary never includes customer collection accounts', () {
    final draft = buildReportShareSummary(
      shopName: 'محل السعادة', partyKind: 'Supplier', periodLabel: 'هذا الشهر',
      overview: {'invoices': 100, 'paid': 30, 'returns': 0},
      partyName: 'مورد', currentBalance: 70, collectionAccounts: accounts,
    );
    expect(draft, isNot(contains('معلومات التحويل')));
    expect(draft, isNot(contains('PS12 0001')));
  });

  test('TC-47: CSV includes collection accounts only for customer reports', () {
    final customers = Exports.historyCsvText([], {},
      collectionAccounts: accounts, customerReport: true);
    final suppliers = Exports.historyCsvText([], {},
      collectionAccounts: accounts, customerReport: false);
    expect(customers, contains('PS12 0001'));
    expect(customers, contains('0591112222'));
    expect(suppliers, isNot(contains('PS12 0001')));
    expect(customers.split('\r\n').skip(1).every(
      (line) => line.split(',').length == 6), isTrue);
  });
}
