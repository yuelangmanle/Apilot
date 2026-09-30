import 'package:api_manager/features/api_management/services/template_catalog_service.dart';
import 'package:api_manager/features/security/app_lock_controller.dart';
import 'package:api_manager/shared/utils/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemplateCatalogService.parseCatalogJson', () {
    test('parses valid entries and prefixes community ids', () {
      final templates = TemplateCatalogService.parseCatalogJson('''
        {
          "templates": [
            {"id": "groq", "name": "Groq", "baseUrl": "https://api.groq.com/openai/v1",
             "models": ["llama-3.3-70b"], "tags": ["groq"]}
          ]
        }
      ''');
      expect(templates, hasLength(1));
      expect(templates!.single.id, 'community_groq');
      expect(templates.single.baseUrl, 'https://api.groq.com/openai/v1');
      expect(templates.single.tags, contains('community'));
    });

    test('rejects malformed or non-http entries', () {
      expect(TemplateCatalogService.parseCatalogJson('not json'), isNull);
      expect(TemplateCatalogService.parseCatalogJson('[]'), isNull);
      expect(
        TemplateCatalogService.parseCatalogJson('''
          {"templates": [{"id": "x", "name": "X", "baseUrl": "ftp://nope"}]}
        '''),
        isEmpty,
      );
    });
  });

  group('AppLockController.hashPin', () {
    test('is deterministic and salt-sensitive', () {
      expect(AppLockController.hashPin('1234', 'salt'),
          AppLockController.hashPin('1234', 'salt'));
      expect(AppLockController.hashPin('1234', 'salt'),
          isNot(AppLockController.hashPin('1234', 'other')));
      expect(AppLockController.hashPin('1234', 'salt'),
          isNot(AppLockController.hashPin('9999', 'salt')));
    });
  });

  group('friendlyError', () {
    test('translates common exceptions to human sentences', () {
      expect(
        friendlyError(Exception('SocketException: net down')),
        contains('无法连接'),
      );
      expect(
        friendlyError(Exception('TimeoutException after 60s')),
        contains('超时'),
      );
      expect(
        friendlyError(Exception('HandshakeException in SSL')),
        contains('SSL'),
      );
      expect(
        friendlyError(Exception('ApiException 401 unauthorized')),
        contains('API Key'),
      );
    });

    test('falls back to a trimmed single line', () {
      final text = friendlyError(Exception('something\nline2'));
      expect(text, contains('something'));
      expect(text.contains('line2'), isFalse);
    });
  });
}
