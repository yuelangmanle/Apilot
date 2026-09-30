
import 'package:api_manager/core/models/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：copyWith 曾缺 4 个字段，收藏切换会静默抹掉 Key 生命周期数据。
void main() {
  test('copyWith preserves lifecycle fields it does not touch', () {
    final config = ApiConfig(
      id: 'a',
      name: 'A',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-a',
      models: const ['m'],
      environment: 'development',
      isFavorite: false,
      expiresAt: DateTime(2027, 1, 1),
      lowBalanceThreshold: '10',
      monthlyBudget: 5.0,
      deletedAt: DateTime(2026, 9, 1),
    );

    final toggled = config.copyWith(isFavorite: true);
    expect(toggled.expiresAt, config.expiresAt);
    expect(toggled.lowBalanceThreshold, '10');
    expect(toggled.monthlyBudget, 5.0);
    expect(toggled.deletedAt, config.deletedAt);
  });

  test('copyWith can explicitly clear nullable lifecycle fields', () {
    final config = ApiConfig(
      id: 'a',
      name: 'A',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-a',
      models: const ['m'],
      environment: 'development',
      lowBalanceThreshold: '10',
    );

    final cleared = config.copyWith(lowBalanceThreshold: null);
    expect(cleared.lowBalanceThreshold, isNull);
  });

  test('replaceApiModels-style update preserves lifecycle fields', () {
    final config = ApiConfig(
      id: 'a',
      name: 'A',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-a',
      models: const ['old'],
      environment: 'development',
      monthlyBudget: 3.5,
      expiresAt: DateTime(2027),
    );

    final refreshed = config.copyWith(
      models: const ['new'],
      updatedAt: DateTime.now(),
    );
    expect(refreshed.monthlyBudget, 3.5);
    expect(refreshed.expiresAt, config.expiresAt);
  });
}
