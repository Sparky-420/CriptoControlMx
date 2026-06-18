DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

const Duration days1 = Duration(days: 1);

String money(double value) => '\$${value.toStringAsFixed(2)} MXN';

String moneyShort(double value) => '\$${value.toStringAsFixed(0)}';

String crypto(double value) => value.toStringAsFixed(8);

String pct(double value) => '${value.toStringAsFixed(2)}%';

String fixed(double value, int decimals) => value.toStringAsFixed(decimals);

String compact(double value) {
  final String text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String longDate(DateTime date) {
  return '${shortDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String priceUpdatedLabel(DateTime? updatedAt) {
  if (updatedAt == null) return 'Sin actualización registrada';

  final Duration age = DateTime.now().difference(updatedAt);
  if (age.inMinutes < 1) return 'Actualizado hace menos de 1 min';
  if (age.inHours < 1) {
    return 'Actualizado hace ${age.inMinutes} min';
  }
  if (age.inDays < 1) {
    return 'Actualizado hace ${age.inHours} h';
  }

  return 'Actualizado ${longDate(updatedAt)}';
}

String isoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String csvEscape(Object? value) {
  final String text = value?.toString() ?? '';
  final bool needsEscape =
      text.contains(',') || text.contains('"') || text.contains('\n');
  final String escaped = text.replaceAll('"', '""');
  return needsEscape ? '"$escaped"' : escaped;
}
