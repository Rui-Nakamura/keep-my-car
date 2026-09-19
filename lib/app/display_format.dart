import '../domain/models/year_month.dart';

String formatNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

String formatYen(int value) => '${formatNumber(value)}円';

String formatReserveYen(int value) =>
    value % 10000 == 0 ? '${formatNumber(value ~/ 10000)}万円' : formatYen(value);

String formatMonth(YearMonth value) => '${value.year}年${value.month}月';

String formatKm(int value) => '${formatNumber(value)}km';
