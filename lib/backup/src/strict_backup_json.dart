import 'dart:convert';

/// Restricted to the ZIP contracts (maximum container depth three).
/// This is a lexical duplicate-key guard, not a second JSON parser: jsonDecode
/// remains responsible for grammar, string escapes, values and number syntax.
Map<String, dynamic> strictBackupJson(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    throw const FormatException('BOM is not allowed');
  }
  final source = utf8.decode(bytes, allowMalformed: false);
  final scopes = <Set<String>?>[];
  for (var i = 0; i < source.length; i++) {
    final ch = source.codeUnitAt(i);
    if (ch == 0x7b || ch == 0x5b) {
      if (scopes.length == 3) throw const FormatException('Excess JSON depth');
      scopes.add(ch == 0x7b ? <String>{} : null);
    } else if (ch == 0x7d || ch == 0x5d) {
      if (scopes.isEmpty) throw const FormatException('Unbalanced JSON');
      scopes.removeLast();
    } else if (ch == 0x22) {
      final start = i;
      var ended = false;
      while (++i < source.length) {
        if (source.codeUnitAt(i) == 0x5c) {
          i++; // Skip the escaped code unit, including an escaped quote.
        } else if (source.codeUnitAt(i) == 0x22) {
          ended = true;
          break;
        }
      }
      if (!ended) throw const FormatException('Unterminated JSON string');
      var next = i + 1;
      while (next < source.length &&
          const [0x20, 0x09, 0x0a, 0x0d].contains(source.codeUnitAt(next))) {
        next++;
      }
      if (next < source.length && source.codeUnitAt(next) == 0x3a) {
        if (scopes.isEmpty || scopes.last == null) {
          throw const FormatException('Key outside object');
        }
        final key = jsonDecode(source.substring(start, i + 1)) as String;
        if (!scopes.last!.add(key)) {
          throw const FormatException('Duplicate JSON key');
        }
      }
    }
  }
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object');
  }
  return decoded;
}

Map<String, dynamic> exactBackupObject(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Unexpected object fields');
  }
  return value;
}
