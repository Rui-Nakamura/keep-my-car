import 'dart:convert';

import 'keep_my_car_data_dto.dart';
import 'keep_my_car_payload_codec.dart';
import 'storage_format.dart';

/// JSON syntax, required fields, types and version; never constructs domain
/// models. Strings can be transported as UTF-8 using dart:convert's utf8 codec.
/// Invalid storage input throws FormatException, without partial results.
class KeepMyCarJsonCodec {
  const KeepMyCarJsonCodec();

  static const _payload = KeepMyCarPayloadCodec();

  String encode(KeepMyCarDataDto data) {
    validateStorageFormat(data);
    return jsonEncode({
      'formatVersion': data.formatVersion,
      ..._payload.encode(data),
    });
  }

  KeepMyCarDataDto decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Expected object: root');
    }
    final version = root['formatVersion'];
    if (version is! int) {
      throw const FormatException('Expected int: formatVersion');
    }
    if (version != 1) {
      throw FormatException('Unsupported formatVersion: $version');
    }
    final data = _payload.decode(root);
    validateStorageFormat(data);
    return data;
  }
}
