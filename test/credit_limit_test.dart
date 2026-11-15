import 'package:flutter_test/flutter_test.dart';
import 'package:deenbook/core/credit_limit.dart';

void main() {
  test('no ceiling: null or zero means unlimited', () {
    expect(creditLimitStatus(900, null).level, CreditLimitLevel.unlimited);
    expect(creditLimitStatus(900, 0).needsWarning, isFalse);
  });

  test('thresholds are 80 percent inclusive and 100 percent inclusive', () {
    expect(creditLimitStatus(399.99, 500).level, CreditLimitLevel.normal);
    expect(creditLimitStatus(400, 500).level, CreditLimitLevel.near);
    expect(creditLimitStatus(499.99, 500).level, CreditLimitLevel.near);
    expect(creditLimitStatus(500, 500).level, CreditLimitLevel.exceeded);
    expect(creditLimitStatus(510, 500).excess, 10);
  });

  test('customer credit is not debt', () {
    final status = creditLimitStatus(-150, 200);
    expect(status.level, CreditLimitLevel.normal);
    expect(status.used, 0);
    expect(status.remaining, 200);
  });

  test('projected debt reflects payment made with purchase', () {
    final current = 360.0;
    final purchase = 110.0;
    final payment = 20.0;
    expect(creditLimitStatus(current + purchase - payment, 500).level,
        CreditLimitLevel.near);
  });
}
