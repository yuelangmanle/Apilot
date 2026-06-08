import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS bundle id stays stable so sandboxed data survives updates', () {
    final appInfo =
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();

    expect(appInfo,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.apiManager'));
  });
}
