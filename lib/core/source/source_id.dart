import 'dart:convert';

import 'package:crypto/crypto.dart';

String normalizeSourceName(String value) => value.trim();

String normalizeApiUrl(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    throw FormatException('api_url 不是有效 URL: $value');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw FormatException('api_url 只支持 http/https: $value');
  }
  final withoutSlash = trimmed.replaceAll(RegExp(r'/+$'), '');
  if (withoutSlash.endsWith('/at/json')) {
    return withoutSlash;
  }
  return '$withoutSlash/at/json';
}

String buildSourceId(String normalizedName, String normalizedApiUrl) {
  final bytes = utf8.encode('$normalizedName|$normalizedApiUrl');
  return sha1.convert(bytes).toString().substring(0, 16);
}

String buildHash(String value) => sha256.convert(utf8.encode(value)).toString();
