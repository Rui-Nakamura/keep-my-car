/// A calendar month, independent of days and time zones.
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month) : assert(month >= 1 && month <= 12);

  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YearMonth && year == other.year && month == other.month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  int compareTo(YearMonth other) {
    final yearComparison = year.compareTo(other.year);
    return yearComparison != 0 ? yearComparison : month.compareTo(other.month);
  }

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}
