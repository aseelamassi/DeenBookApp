import 'format.dart';
import 'weight_pricing.dart';

// Safety limits for a single weighted sale (not a shop-wide credit limit).
// Keep these as one source of truth for both amount- and weight-entry modes.
const int maxWeightedSaleGrams = 100000; // 100 kg
const int maxWeightedSaleCents = 1000000; // 10,000 NIS

class WeightEntryResult {
  const WeightEntryResult({
    this.grams = 0,
    this.totalCents = 0,
    this.requestedCents,
    this.error,
  });

  final int grams;
  final int totalCents;
  final int? requestedCents;
  final String? error;

  bool get canSubmit => error == null && grams > 0 && totalCents > 0;
}

/// Validates before any multiplication or conversion is shown or submitted.
/// Invalid entries have a safe zero preview and cannot reach the invoice.
WeightEntryResult validateWeightEntry({
  required int pricePerKgCents,
  required bool byAmount,
  required bool inKilos,
  required String weightText,
  required String amountText,
}) {
  if (pricePerKgCents <= 0) {
    return const WeightEntryResult(error: 'سعر الكيلو غير صالح');
  }

  int grams;
  int? requested;
  if (byAmount) {
    final normalized = digits(amountText.trim()).replaceAll('٫', '.');
    if (normalized.isEmpty) {
      return const WeightEntryResult(error: 'أدخل المبلغ المطلوب');
    }
    // Detect very large, otherwise well-formed numbers even if cents() rejects
    // them for exceeding its own integer guard.
    if (RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
      final whole = int.tryParse(normalized.split('.').first);
      if (whole == null || whole > maxWeightedSaleCents ~/ 100 ||
          (whole == maxWeightedSaleCents ~/ 100 &&
              (normalized.contains('.') &&
                  int.parse(normalized.split('.').last) > 0))) {
        return const WeightEntryResult(
          error: 'المبلغ كبير جدًا؛ الحد الأقصى 10,000 ₪ للعملية الواحدة',
        );
      }
    }
    requested = cents(amountText);
    if (requested == null) {
      return const WeightEntryResult(error: 'أدخل مبلغًا صحيحًا بالأرقام فقط');
    }
    if (requested <= 0) {
      return const WeightEntryResult(error: 'يجب أن يكون المبلغ أكبر من صفر');
    }
    if (requested > maxWeightedSaleCents) {
      return const WeightEntryResult(
        error: 'المبلغ كبير جدًا؛ الحد الأقصى 10,000 ₪ للعملية الواحدة',
      );
    }
    grams = gramsForAmount(pricePerKgCents, requested);
  } else {
    final normalized = digits(weightText.trim()).replaceAll('٫', '.');
    if (normalized.isEmpty) {
      return const WeightEntryResult(error: 'أدخل الوزن المطلوب');
    }
    if (inKilos) {
      if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(normalized)) {
        return const WeightEntryResult(error: 'أدخل وزنًا صحيحًا بالكيلو (حتى 3 منازل عشرية)');
      }
      final parts = normalized.split('.');
      final kg = int.tryParse(parts.first);
      if (kg == null || kg > maxWeightedSaleGrams ~/ 1000) {
        return const WeightEntryResult(
          error: 'الوزن كبير جدًا؛ الحد الأقصى 100 كغم للعملية الواحدة',
        );
      }
      final fraction = parts.length > 1 ? int.parse(parts.last.padRight(3, '0')) : 0;
      grams = kg * 1000 + fraction;
    } else {
      if (!RegExp(r'^\d+$').hasMatch(normalized)) {
        return const WeightEntryResult(error: 'أدخل وزنًا صحيحًا بالغرام، دون أحرف أو كسور');
      }
      final parsed = int.tryParse(normalized);
      if (parsed == null || parsed > maxWeightedSaleGrams) {
        return const WeightEntryResult(
          error: 'الوزن كبير جدًا؛ الحد الأقصى 100,000 غرام (100 كغم)',
        );
      }
      grams = parsed;
    }
  }

  if (grams <= 0) {
    return const WeightEntryResult(error: 'يجب أن يكون الوزن والمبلغ أكبر من صفر');
  }
  if (grams > maxWeightedSaleGrams) {
    return const WeightEntryResult(
      error: 'الوزن كبير جدًا؛ الحد الأقصى 100 كغم للعملية الواحدة',
    );
  }
  final total = totalForGrams(pricePerKgCents, grams);
  if (total <= 0) {
    return const WeightEntryResult(error: 'هذه الكمية لا ينتج عنها مبلغ صالح');
  }
  if (total > maxWeightedSaleCents) {
    return const WeightEntryResult(
      error: 'قيمة الصنف كبيرة جدًا؛ الحد الأقصى 10,000 ₪ للعملية الواحدة',
    );
  }
  return WeightEntryResult(
    grams: grams,
    requestedCents: requested,
    totalCents: total,
  );
}
