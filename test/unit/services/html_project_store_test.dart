import 'dart:io';

import 'package:api_manager/core/services/ai/html_project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late HtmlProjectStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('apilot_html_projects_');
    store = HtmlProjectStore(root: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('保存、读取、删除共享同一个持久项目', () async {
    await store.save('项目 A', '<!doctype html><html></html>');

    expect(await store.read('项目 A'), '<!doctype html><html></html>');
    expect((await store.list()).single.name, '项目_A');
    expect(await store.delete('项目 A'), isTrue);
    expect(await store.read('项目 A'), isNull);
  });

  test('覆盖保存保留有限历史且不会串到同名前缀项目', () async {
    await store.save('site', 'v1');
    await store.save('site_backup', 'backup');
    await store.save('site_backup', 'backup-v2');
    for (var version = 2; version <= 22; version++) {
      await store.save('site', 'v$version');
    }

    final history = Directory('${root.path}/.history')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
    final siteHistory = history.where((name) => name.startsWith('site__'));
    final backupHistory =
        history.where((name) => name.startsWith('site_backup__'));
    expect(siteHistory, hasLength(20));
    expect(backupHistory, hasLength(1));
    expect(await store.read('site_backup'), 'backup-v2');
    expect(await store.read('site'), 'v22');
  });

  test('项目名被净化且不允许路径穿越', () async {
    final file = await store.save('../../outside/..\u0000', 'safe');

    expect(file.parent.path, root.path);
    expect(file.path, isNot(contains('..')));
    expect(await file.readAsString(), 'safe');
  });
}
