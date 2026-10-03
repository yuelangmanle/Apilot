import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class HtmlProject {
  final String name;
  final String fileName;
  final DateTime updatedAt;
  final int sizeBytes;

  const HtmlProject({
    required this.name,
    required this.fileName,
    required this.updatedAt,
    required this.sizeBytes,
  });
}

/// 本地 HTML 项目存储。项目文件兼容旧版 snippets/*.html，覆盖保存前保留
/// 有限历史版本，聊天工具箱和内置编辑器可以共用同一份项目数据。
class HtmlProjectStore {
  HtmlProjectStore({Directory? root}) : _root = root;

  final Directory? _root;
  static const int _maxVersions = 20;

  Future<Directory> _directory() async {
    final configured = _root;
    final directory = configured ??
        Directory(p.join(
          (await getApplicationSupportDirectory()).path,
          'snippets',
        ));
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }

  static String safeName(String name) {
    final normalized = name
        .trim()
        .replaceAll(RegExp(r'\.html?$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5\-]+'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    if (normalized.isEmpty) return '未命名';
    return normalized.length > 80 ? normalized.substring(0, 80) : normalized;
  }

  Future<List<HtmlProject>> list() async {
    final directory = await _directory();
    final projects = <HtmlProject>[];
    for (final file in directory.listSync().whereType<File>()) {
      if (!file.path.toLowerCase().endsWith('.html')) continue;
      try {
        final stat = await file.stat();
        projects.add(HtmlProject(
          name: p.basenameWithoutExtension(file.path),
          fileName: p.basename(file.path),
          updatedAt: stat.modified,
          sizeBytes: stat.size,
        ));
      } catch (_) {}
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<String?> read(String name) async {
    final file = File(p.join(await _directoryPath(), '${safeName(name)}.html'));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  Future<File> save(String name, String html) async {
    final directory = await _directory();
    final file = File(p.join(directory.path, '${safeName(name)}.html'));
    if (file.existsSync()) await _archivePrevious(directory, file);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(html, flush: true);
    return temporary.rename(file.path);
  }

  Future<bool> delete(String name) async {
    final file = File(p.join(await _directoryPath(), '${safeName(name)}.html'));
    if (!file.existsSync()) return false;
    await file.delete();
    final history = Directory(p.join(file.parent.path, '.history'));
    if (history.existsSync()) {
      for (final archived in history.listSync().whereType<File>()) {
        if (p
            .basenameWithoutExtension(archived.path)
            .startsWith('${safeName(name)}__')) {
          await archived.delete();
        }
      }
    }
    return true;
  }

  Future<String?> readByFileName(String fileName) async {
    final safe = p.basename(fileName);
    if (!safe.toLowerCase().endsWith('.html')) return null;
    return read(p.basenameWithoutExtension(safe));
  }

  Future<String> _directoryPath() async => (await _directory()).path;

  Future<void> _archivePrevious(Directory directory, File file) async {
    final history = Directory(p.join(directory.path, '.history'));
    if (!history.existsSync()) history.createSync(recursive: true);
    final base = p.basenameWithoutExtension(file.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await file.copy(p.join(history.path, '${base}__$stamp.html'));
    final archived = history
        .listSync()
        .whereType<File>()
        .where((item) =>
            p.basenameWithoutExtension(item.path).startsWith('${base}__'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in archived.skip(_maxVersions)) {
      await old.delete();
    }
  }
}
