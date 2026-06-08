import 'package:api_manager/core/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService release asset selection', () {
    const assets = [
      {
        'name': 'Apilot-1.18.0-android.apk',
        'browser_download_url': 'https://example.com/android.apk',
      },
      {
        'name': 'Apilot-1.18.0-macos.dmg.sha256',
        'browser_download_url': 'https://example.com/macos.dmg.sha256',
      },
      {
        'name': 'Apilot-1.18.0-macos.dmg',
        'browser_download_url': 'https://example.com/macos.dmg',
      },
      {
        'name': 'Apilot-1.18.0-windows-setup.exe',
        'browser_download_url': 'https://example.com/windows.exe',
      },
    ];

    test('macOS only selects the dmg installer and never an Android APK', () {
      final url = UpdateService.selectReleaseAssetUrl(
        assets,
        platform: ReleasePlatform.macOS,
      );

      expect(url, 'https://example.com/macos.dmg');
    });

    test('Android only selects the APK installer', () {
      final url = UpdateService.selectReleaseAssetUrl(
        assets,
        platform: ReleasePlatform.android,
      );

      expect(url, 'https://example.com/android.apk');
    });

    test('Windows prefers the setup executable over generic archives', () {
      final url = UpdateService.selectReleaseAssetUrl(
        [
          {
            'name': 'Apilot-1.18.0-windows.zip',
            'browser_download_url': 'https://example.com/windows.zip',
          },
          ...assets,
        ],
        platform: ReleasePlatform.windows,
      );

      expect(url, 'https://example.com/windows.exe');
    });
  });
}
