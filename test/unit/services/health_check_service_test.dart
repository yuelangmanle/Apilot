import 'package:api_manager/core/models/request_history.dart';
import 'package:api_manager/core/services/health_check_service.dart';
import 'package:api_manager/core/services/usage_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BalanceParsers', () {
    test('deepseek extracts currency and balance', () {
      final text = BalanceParsers.deepseek({
        'is_available': true,
        'balance_infos': [
          {'currency': 'CNY', 'total_balance': '110.50'}
        ],
      });
      expect(text, 'CNY 110.50');
    });

    test('siliconflow extracts balance', () {
      final text = BalanceParsers.siliconflow({
        'data': {'balance': '8.25', 'chargeBalance': '100.00'}
      });
      expect(text, 'CNY 8.25');
    });

    test('openrouter computes remaining from limit and usage', () {
      final text = BalanceParsers.openrouter({
        'data': {'usage': 1.5, 'limit': 10.0}
      });
      expect(text, 'USD 8.50');
    });

    test('openrouter reports free tier without limit', () {
      expect(
        BalanceParsers.openrouter({
          'data': {'usage': 0.2, 'is_free_tier': true}
        }),
        '免费额度',
      );
    });

    test('malformed payloads return null instead of throwing', () {
      expect(BalanceParsers.deepseek({}), isNull);
      expect(BalanceParsers.siliconflow({'data': 'oops'}), isNull);
      expect(BalanceParsers.openrouter({'data': null}), isNull);
    });
  });

  group('UsageAggregator', () {
    RequestHistory history(
      String configId, {
      int? statusCode,
      int? total,
      int? prompt,
      int? completion,
    }) {
      return RequestHistory(
        id: 'h-$configId-$total-$statusCode',
        apiConfigId: configId,
        model: 'm',
        endpoint: '/chat/completions',
        requestBody: {},
        statusCode: statusCode,
        promptTokens: prompt,
        completionTokens: completion,
        totalTokens: total,
        createdAt: DateTime(2026, 9, 29, 12),
      );
    }

    test('aggregates tokens and success rate per config', () {
      final usages = UsageAggregator.byConfig([
        history('a', statusCode: 200, total: 100, prompt: 70, completion: 30),
        history('a', statusCode: 401, total: 5, prompt: 5, completion: 0),
        history('b', statusCode: 200, total: 1000, prompt: 800, completion: 200),
      ], names: {
        'a': 'DeepSeek',
        'b': 'OpenRouter'
      });

      expect(usages, hasLength(2));
      // 按 total tokens 降序
      expect(usages.first.configId, 'b');
      expect(usages.first.totalTokens, 1000);
      expect(usages.last.configId, 'a');
      expect(usages.last.totalTokens, 105);
      expect(usages.last.requestCount, 2);
      expect(usages.last.successCount, 1);
    });

    test('unknown config id falls back to the id as name', () {
      final usages = UsageAggregator.byConfig([
        history('ghost', statusCode: 200, total: 1),
      ]);
      expect(usages.single.configName, 'ghost');
    });
  });

  group('healthBadgeText', () {
    test('describes each status without throwing', () {
      expect(healthBadgeText(null), '未体检');
      expect(
        healthBadgeText(HealthCheckResult(
          status: KeyHealthStatus.authFailed,
          checkedAt: DateTime.now(),
        )),
        'Key 无效或已欠费',
      );
      final ok = healthBadgeText(HealthCheckResult(
        status: KeyHealthStatus.ok,
        checkedAt: DateTime.now(),
        balanceText: 'CNY 9.9',
      ));
      expect(ok, contains('CNY 9.9'));
    });
  });
}
