import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum ReleasePlatform {
  macOS,
  windows,
  android,
  ios,
  linux,
  unknown,
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });
}

class ReleaseInfo {
  final String version;
  final String releaseNotes;
  final DateTime publishedAt;

  const ReleaseInfo({
    required this.version,
    required this.releaseNotes,
    required this.publishedAt,
  });
}

class UpdateService {
  static const String _repoOwner = 'yuelangmanle';
  static const String _repoName = 'Apilot';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _releaseHistoryUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases?per_page=100';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      final latestVersion = _versionFromTag(data['tag_name']);
      if (latestVersion.isEmpty) return null;

      final assets = data['assets'] as List? ?? [];
      final downloadUrl = selectReleaseAssetUrl(assets) ?? '';

      final release = _parseRelease(data);

      if (_isNewerVersion(latestVersion, currentVersion)) {
        if (downloadUrl.isEmpty) {
          throw Exception('GitHub Release 中没有当前平台可用的安装包');
        }
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: release.releaseNotes,
          publishedAt: release.publishedAt,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<ReleaseInfo>> getReleaseHistory() async {
    final response = await http.get(
      Uri.parse(_releaseHistoryUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('无法读取更新日志，GitHub 返回 ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      throw Exception('更新日志格式无效');
    }
    return parseReleaseHistory(data);
  }

  static List<ReleaseInfo> parseReleaseHistory(List<dynamic> releases) {
    return releases
        .whereType<Map>()
        .where((release) => release['draft'] != true)
        .map(_parseRelease)
        .where((release) => release.version.isNotEmpty)
        .toList(growable: false);
  }

  static ReleaseInfo _parseRelease(Map<dynamic, dynamic> release) {
    return ReleaseInfo(
      version: _versionFromTag(release['tag_name']),
      releaseNotes: release['body'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(release['published_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String _versionFromTag(Object? tagName) {
    return (tagName as String? ?? '').replaceFirst(RegExp(r'^v'), '');
  }

  static String? selectReleaseAssetUrl(
    List<dynamic> assets, {
    ReleasePlatform? platform,
  }) {
    final targetPlatform = platform ?? currentReleasePlatform();
    final extensions = _targetAssetExtensions(targetPlatform);

    for (final extension in extensions) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (!name.endsWith(extension)) continue;

        final url = asset['browser_download_url'] as String? ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static ReleasePlatform currentReleasePlatform() {
    if (Platform.isMacOS) return ReleasePlatform.macOS;
    if (Platform.isWindows) return ReleasePlatform.windows;
    if (Platform.isAndroid) return ReleasePlatform.android;
    if (Platform.isIOS) return ReleasePlatform.ios;
    if (Platform.isLinux) return ReleasePlatform.linux;
    return ReleasePlatform.unknown;
  }

  static List<String> _targetAssetExtensions(ReleasePlatform platform) {
    switch (platform) {
      case ReleasePlatform.macOS:
        return const ['.dmg'];
      case ReleasePlatform.windows:
        return const ['.exe', '.msix', '.zip'];
      case ReleasePlatform.android:
        return const ['.apk'];
      case ReleasePlatform.ios:
      case ReleasePlatform.linux:
      case ReleasePlatform.unknown:
        return const ['.dmg', '.exe', '.msix', '.zip', '.apk'];
    }
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> downloadUpdate(String downloadUrl) async {
    final uri = Uri.parse(downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('无法打开下载链接');
    }
  }

  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
}
