import 'dart:convert';

class ApiConnectionPasteResult {
  final String baseUrl;
  final String apiKey;
  final bool urlWasNormalized;

  const ApiConnectionPasteResult({
    required this.baseUrl,
    required this.apiKey,
    required this.urlWasNormalized,
  });
}

/// Extracts a connection URL and key from text copied from common API tools.
/// It intentionally requires both values so unrelated clipboard content cannot
/// overwrite a partially completed form.
class ApiConnectionPasteParser {
  static const _keyFields = {
    'key',
    'apikey',
    'apitoken',
    'token',
    'accesstoken',
    'accesskey',
    'authorization',
    'authorizationtoken',
    'bearertoken',
    'secret',
    'secretkey',
    'authkey',
    'xapikey',
    'xgoogapikey',
    'apikeyvalue',
    'clientsecret',
    'api密钥',
    '密钥',
    '访问令牌',
    '令牌',
  };
  static const _urlFields = {
    'url',
    'baseurl',
    'baseuri',
    'endpoint',
    'endpointurl',
    'apiurl',
    'apiendpoint',
    'apibaseurl',
    'apiaddress',
    'host',
    'server',
    'serverurl',
    'address',
    'uri',
    'apiuri',
    '服务地址',
    '请求地址',
    '网关地址',
    '接口地址',
    '接口url',
    'api地址',
    '地址',
    '端点',
  };
  static const _keyFieldPriority = [
    'apikey',
    'xapikey',
    'xgoogapikey',
    'secretkey',
    'authkey',
    'accesskey',
    'accesstoken',
    'apitoken',
    'bearertoken',
    'authorization',
    'authorizationtoken',
    '密钥',
    '访问令牌',
    '令牌',
    'token',
    'key',
    'secret',
  ];
  static const _urlFieldPriority = [
    'apibaseurl',
    'baseurl',
    'baseuri',
    'apiendpoint',
    'endpointurl',
    'endpoint',
    'apiurl',
    'serverurl',
    'apiaddress',
    '接口地址',
    '服务地址',
    '请求地址',
    '网关地址',
    '接口url',
    'api地址',
    'url',
    'host',
    'server',
    'address',
    '地址',
    '端点',
  ];

  static final RegExp _fieldAssignment = RegExp(
    r'''(?:^|[\{\[,;；|])\s*[`'\"]?([A-Za-z0-9_.\-\s\u4e00-\u9fff]+?)[`'\"]?\s*(?:=>|->|:|=|：)\s*''',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(
    r'''(?:https?\s*:\s*//|https?//|//)[^\s"'<>`|,;)\]}]+|(?:[A-Za-z0-9-]+\.)+[A-Za-z0-9-]+(?::\d+)?(?:/[^\s"'<>`|,;)\]}]*)?''',
    caseSensitive: false,
  );
  static final RegExp _bearerToken = RegExp(
    r'''authorization\s*[:=]\s*bearer\s+[`'"]?([^\s`'"]+)''',
    caseSensitive: false,
  );

  static ApiConnectionPasteResult? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    for (final source in _jsonSources(trimmed)) {
      for (final decoded in _decodeJsonObjects(source)) {
        final pairedValues = _findJsonConnection(decoded);
        if (pairedValues != null) {
          final result = _buildResult(
            pairedValues.baseUrl!,
            pairedValues.apiKey!,
          );
          if (result != null) return result;
        }
      }
    }

    return _findTextConnection(_extractTextCandidates(trimmed));
  }

  static List<String> _jsonSources(String text) {
    final sources = <String>[text];
    var unescaped = text;
    for (var attempt = 0; attempt < 2; attempt++) {
      final next = unescaped.replaceAll(r'\"', '"').replaceAll(r"\'", "'");
      if (next == unescaped) break;
      sources.add(next);
      unescaped = next;
    }
    return sources;
  }

  static ApiConnectionPasteResult? _buildResult(String rawUrl, String rawKey) {
    final normalizedUrl = _normalizeUrl(rawUrl);
    final normalizedKey = _normalizeKey(rawKey);
    if (normalizedUrl == null || normalizedKey.isEmpty) return null;

    return ApiConnectionPasteResult(
      baseUrl: normalizedUrl.url,
      apiKey: normalizedKey,
      urlWasNormalized: normalizedUrl.wasNormalized,
    );
  }

  static List<Object?> _decodeJsonObjects(String text) {
    final decodedValues = <Object?>[];
    try {
      decodedValues.add(jsonDecode(text));
      return decodedValues;
    } on FormatException {
      // A clipboard often contains explanatory prose around one JSON object.
    }

    var depth = 0;
    var inString = false;
    var escaped = false;
    int? start;

    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
        continue;
      }
      if (character == '{') {
        start ??= index;
        depth++;
        continue;
      }
      if (character != '}' || depth == 0) continue;

      depth--;
      if (depth != 0 || start == null) continue;
      try {
        decodedValues.add(jsonDecode(text.substring(start, index + 1)));
      } on FormatException {
        // This brace-delimited text was prose rather than JSON.
      }
      start = null;
    }
    return decodedValues;
  }

  static _ConnectionValues? _findJsonConnection(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return _findJsonConnection(jsonDecode(trimmed));
        } on FormatException {
          return null;
        }
      }
      return null;
    }
    if (value is Map) {
      final directValues = <String, String>{};
      for (final entry in value.entries) {
        if (entry.value is String) {
          directValues[_normalizeFieldName(entry.key.toString())] =
              (entry.value as String).trim();
        }
      }
      final apiKey = _findKeyValue(directValues);
      final baseUrl = _findUrlValue(directValues);
      if (apiKey != null && baseUrl != null) {
        return _ConnectionValues(baseUrl: baseUrl, apiKey: apiKey);
      }
      for (final item in value.values) {
        final nested = _findJsonConnection(item);
        if (nested != null) return nested;
      }
      return null;
    }
    if (value is List) {
      for (final item in value) {
        final nested = _findJsonConnection(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static List<_TextConnectionCandidate> _extractTextCandidates(String text) {
    final candidates = <_TextConnectionCandidate>[];
    final lines = text.split('\n');
    var offset = 0;

    void addFieldValue(
      String rawField,
      String rawValue,
      int valueOffset, {
      required int confidence,
    }) {
      final field = _normalizeFieldName(rawField);
      final value = _cleanTextValue(rawValue);
      if (value.isEmpty) return;
      if (_looksLikeUrlField(field)) {
        candidates.add(
          _TextConnectionCandidate.url(
            value: value,
            offset: valueOffset,
            confidence: confidence,
            fieldPriority: _fieldPriority(field, _urlFieldPriority),
          ),
        );
      }
      if (_looksLikeKeyField(field)) {
        candidates.add(
          _TextConnectionCandidate.key(
            value: value,
            offset: valueOffset,
            confidence: confidence,
            fieldPriority: _fieldPriority(field, _keyFieldPriority),
          ),
        );
      }
    }

    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      final line = _stripInlineComment(rawLine);
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        final cells = line
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .toList();
        for (var cellIndex = 0; cellIndex + 1 < cells.length; cellIndex++) {
          final field = cells[cellIndex];
          if (_looksLikeKeyField(_normalizeFieldName(field)) ||
              _looksLikeUrlField(_normalizeFieldName(field))) {
            final value = cells[cellIndex + 1];
            addFieldValue(
              field,
              value,
              offset + line.indexOf(value),
              confidence: 4,
            );
          }
        }

        final assignments = _fieldAssignment.allMatches(line).toList();
        for (var matchIndex = 0;
            matchIndex < assignments.length;
            matchIndex++) {
          final assignment = assignments[matchIndex];
          final valueEnd = matchIndex + 1 < assignments.length
              ? assignments[matchIndex + 1].start
              : line.length;
          addFieldValue(
            assignment.group(1)!,
            line.substring(assignment.end, valueEnd),
            offset + assignment.end,
            confidence: 4,
          );
        }

        final field = _normalizeFieldName(trimmedLine);
        final hasInlineValue = assignments.any(
          (assignment) =>
              _normalizeFieldName(assignment.group(1)!) == field &&
              _cleanTextValue(line.substring(assignment.end)).isNotEmpty,
        );
        if ((_looksLikeKeyField(field) || _looksLikeUrlField(field)) &&
            !hasInlineValue &&
            index + 1 < lines.length) {
          final nextValue = _stripInlineComment(lines[index + 1]).trim();
          if (nextValue.isNotEmpty) {
            addFieldValue(
              trimmedLine,
              nextValue,
              offset + rawLine.length + 1,
              confidence: 3,
            );
          }
        }
      }
      offset += rawLine.length + 1;
    }

    for (final match in _bearerToken.allMatches(text)) {
      final value = match.group(1);
      if (value == null) continue;
      candidates.add(
        _TextConnectionCandidate.key(
          value: _cleanTextValue(value),
          offset: match.start + match.group(0)!.indexOf(value),
          confidence: 3,
          fieldPriority: _fieldPriority('authorization', _keyFieldPriority),
        ),
      );
    }

    for (final match in _urlPattern.allMatches(text)) {
      final value = match.group(0);
      if (value == null) continue;
      candidates.add(
        _TextConnectionCandidate.url(
          value: value,
          offset: match.start,
          confidence: 1,
          fieldPriority: 0,
        ),
      );
    }
    return candidates;
  }

  static ApiConnectionPasteResult? _findTextConnection(
    List<_TextConnectionCandidate> candidates,
  ) {
    final urlCandidates = candidates
        .where((candidate) => candidate.isUrl)
        .where((candidate) => _normalizeUrl(candidate.value) != null)
        .toList();
    final keyCandidates = candidates
        .where((candidate) => !candidate.isUrl)
        .where((candidate) => _normalizeKey(candidate.value).isNotEmpty)
        .toList();

    ApiConnectionPasteResult? bestResult;
    var bestConfidence = -1;
    var bestFieldPriority = -1;
    var bestDistance = 0;

    for (final url in urlCandidates) {
      for (final key in keyCandidates) {
        final result = _buildResult(url.value, key.value);
        if (result == null) continue;

        final confidence = url.confidence + key.confidence;
        final fieldPriority = url.fieldPriority + key.fieldPriority;
        final distance = (url.offset - key.offset).abs();
        final isBetter = bestResult == null ||
            confidence > bestConfidence ||
            (confidence == bestConfidence &&
                fieldPriority > bestFieldPriority) ||
            (confidence == bestConfidence &&
                fieldPriority == bestFieldPriority &&
                distance < bestDistance);
        if (!isBetter) continue;

        bestResult = result;
        bestConfidence = confidence;
        bestFieldPriority = fieldPriority;
        bestDistance = distance;
      }
    }
    return bestResult;
  }

  static int _fieldPriority(String field, List<String> priority) {
    final index = priority.indexOf(field);
    return index < 0 ? 0 : priority.length - index;
  }

  static String _cleanTextValue(String value) {
    return _trimDecorators(_stripInlineComment(value));
  }

  static String _stripInlineComment(String value) {
    var quote = '';
    var escaped = false;
    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      if (quote.isNotEmpty) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          quote = '';
        }
        continue;
      }
      if (character == '\'' || character == '"' || character == '`') {
        quote = character;
      } else if (character == '#' &&
          (index == 0 || value[index - 1].trim().isEmpty)) {
        return value.substring(0, index);
      }
    }
    return value;
  }

  static String? _findKeyValue(Map<String, String> values) {
    return _findPreferredValue(
      values,
      priority: _keyFieldPriority,
      matches: _looksLikeKeyField,
    );
  }

  static String? _findUrlValue(Map<String, String> values) {
    return _findPreferredValue(
      values,
      priority: _urlFieldPriority,
      matches: _looksLikeUrlField,
    );
  }

  static String? _findPreferredValue(
    Map<String, String> values, {
    required List<String> priority,
    required bool Function(String field) matches,
  }) {
    for (final field in priority) {
      final value = values[field];
      if (value != null && value.isNotEmpty) return value;
    }
    for (final entry in values.entries) {
      if (matches(entry.key) && entry.value.isNotEmpty) return entry.value;
    }
    return null;
  }

  static bool _looksLikeKeyField(String field) {
    return _keyFields.contains(field) ||
        field.endsWith('apikey') ||
        field.endsWith('apitoken') ||
        field.endsWith('accesstoken') ||
        field.endsWith('accesskey') ||
        field.endsWith('authkey') ||
        field.endsWith('secretkey') ||
        field.endsWith('clientsecret');
  }

  static bool _looksLikeUrlField(String field) {
    return _urlFields.contains(field) ||
        field.endsWith('baseurl') ||
        field.endsWith('baseuri') ||
        field.endsWith('endpoint') ||
        field.endsWith('endpointurl') ||
        field.endsWith('apiurl') ||
        field.endsWith('apiuri') ||
        field.endsWith('apiaddress') ||
        field.endsWith('url') ||
        field.endsWith('uri') ||
        field.endsWith('address') ||
        field.endsWith('地址');
  }

  static String _normalizeFieldName(String field) {
    final stripped = field
        .trim()
        .replaceFirst(RegExp(r'^(?:[-*+>#]+\s*)+'), '')
        .replaceAll(RegExp(r'''[`'"*_\s]'''), '')
        .toLowerCase();
    return stripped.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }

  static String _normalizeKey(String value) {
    final trimmed = _trimDecorators(value);
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return _normalizeKey(trimmed.substring('bearer '.length));
    }
    final lowercase = trimmed.toLowerCase();
    if (RegExp(r'^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$').hasMatch(trimmed) ||
        RegExp(r'^<[^>]+>$').hasMatch(trimmed) ||
        lowercase == 'api_key' ||
        lowercase == 'your_api_key' ||
        lowercase == 'your-api-key' ||
        lowercase == 'replace_with_your_key' ||
        lowercase == 'replace-with-your-key' ||
        lowercase == 'null' ||
        lowercase == 'undefined') {
      return '';
    }
    return trimmed;
  }

  static _NormalizedUrl? _normalizeUrl(String value) {
    final trimmed = _trimDecorators(value);
    var fixedScheme = trimmed.replaceAll(r'\/', '/');
    fixedScheme = fixedScheme.replaceFirstMapped(
      RegExp(r'^(https?)\s*:\s*[/\\]*', caseSensitive: false),
      (match) => '${match.group(1)!.toLowerCase()}://',
    );
    fixedScheme = fixedScheme.replaceFirstMapped(
      RegExp(r'^(https?)\s*//', caseSensitive: false),
      (match) => '${match.group(1)!.toLowerCase()}://',
    );
    if (fixedScheme.startsWith('//')) fixedScheme = 'https:$fixedScheme';
    if (!fixedScheme.contains('://') && _looksLikeHost(fixedScheme)) {
      fixedScheme = 'https://$fixedScheme';
    }
    final uri = Uri.tryParse(fixedScheme);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return _NormalizedUrl(
      url: fixedScheme,
      wasNormalized: fixedScheme != trimmed,
    );
  }

  static bool _looksLikeHost(String value) {
    final host = value.split('/').first;
    return RegExp(r'^[A-Za-z0-9.-]+(?::\d+)?$').hasMatch(host) &&
        (host == 'localhost' || host.contains('.') || host.contains(':'));
  }

  static String _trimDecorators(String value) {
    const decorators = '`\'"|,;；)]}><[{';
    var result = value.trim();
    while (result.isNotEmpty) {
      final trimmedStart =
          decorators.contains(result[0]) ? result.substring(1).trim() : result;
      final trimmedEnd = trimmedStart.isNotEmpty &&
              decorators.contains(trimmedStart[trimmedStart.length - 1])
          ? trimmedStart.substring(0, trimmedStart.length - 1).trim()
          : trimmedStart;
      if (trimmedEnd == result) return result;
      result = trimmedEnd;
    }
    return result;
  }
}

class _TextConnectionCandidate {
  final bool isUrl;
  final String value;
  final int offset;
  final int confidence;
  final int fieldPriority;

  const _TextConnectionCandidate._({
    required this.isUrl,
    required this.value,
    required this.offset,
    required this.confidence,
    required this.fieldPriority,
  });

  const _TextConnectionCandidate.url({
    required String value,
    required int offset,
    required int confidence,
    required int fieldPriority,
  }) : this._(
          isUrl: true,
          value: value,
          offset: offset,
          confidence: confidence,
          fieldPriority: fieldPriority,
        );

  const _TextConnectionCandidate.key({
    required String value,
    required int offset,
    required int confidence,
    required int fieldPriority,
  }) : this._(
          isUrl: false,
          value: value,
          offset: offset,
          confidence: confidence,
          fieldPriority: fieldPriority,
        );
}

class _ConnectionValues {
  final String? baseUrl;
  final String? apiKey;

  const _ConnectionValues({this.baseUrl, this.apiKey});
}

class _NormalizedUrl {
  final String url;
  final bool wasNormalized;

  const _NormalizedUrl({required this.url, required this.wasNormalized});
}
