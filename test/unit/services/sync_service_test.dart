import 'package:flutter_test/flutter_test.dart';
import 'package:api_manager/features/sync/services/sync_service.dart';
import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/device_info.dart';

void main() {
  group('SyncService', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService();
    });

    tearDown(() async {
      await syncService.stop();
    });

    test('should create SyncService instance', () {
      expect(syncService, isNotNull);
    });

    test('should have empty device list initially', () {
      expect(syncService.discoveredDevices, isEmpty);
    });

    test('should generate device info', () async {
      final device = await syncService.getLocalDeviceInfo();
      expect(device, isNotNull);
      expect(device.name, isNotEmpty);
      expect(device.platform, isNotEmpty);
    });

    test('should serialize sync data correctly', () {
      final configs = [
        ApiConfig(
          id: '1',
          name: 'Test API',
          baseUrl: 'https://api.test.com',
          apiKey: 'sk-test',
          models: ['model-1'],
          environment: 'production',
        ),
      ];

      final syncData = SyncService.createSyncPayload(configs);
      expect(syncData, isNotEmpty);
      expect(syncData['version'], isNotNull);
      expect(syncData['configs'], isNotNull);
      expect((syncData['configs'] as List).length, 1);
    });

    test('should deserialize sync data correctly', () {
      final configs = [
        ApiConfig(
          id: '1',
          name: 'Test API',
          baseUrl: 'https://api.test.com',
          apiKey: 'sk-test',
          models: ['model-1'],
          environment: 'production',
        ),
      ];

      final syncData = SyncService.createSyncPayload(configs);
      final receivedConfigs = SyncService.parseSyncPayload(syncData);
      expect(receivedConfigs.length, 1);
      expect(receivedConfigs[0].name, 'Test API');
    });
  });
}
