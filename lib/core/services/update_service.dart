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

enum UpdateCheckStatus {
  /// 当前已是最新版本
  upToDate,

  /// 有新版本且当前平台有可用安装包
  updateAvailable,

  /// 检查失败（网络/GitHub 接口错误）
  checkFailed,

  /// 有新版本，但 Release 中没有当前平台的安装包
  noPackageForPlatform,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? update;
  final String? errorMessage;

  const UpdateCheckResult._(this.status, {this.update, this.errorMessage});

  const UpdateCheckResult.upToDate() : this._(UpdateCheckStatus.upToDate);

  const UpdateCheckResult.available(UpdateInfo info)
      : this._(UpdateCheckStatus.updateAvailable, update: info);

  const UpdateCheckResult.failure(String message)
      : this._(UpdateCheckStatus.checkFailed, errorMessage: message);

  const UpdateCheckResult.noPackage(String version)
      : this._(
          UpdateCheckStatus.noPackageForPlatform,
          errorMessage: '已发布 v$version，但没有当前平台可用的安装包',
        );
}

class UpdateService {
  static const String _repoOwner = 'yuelangmanle';
  static const String _repoName = 'Apilot';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _releaseHistoryUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases?per_page=100';
  /// 国内网络兜底：github.com 的 Atom feed（api.github.com 常被墙，
  /// 但 github.com 主域通常可访问）。
  static const String _releasesAtomUrl =
      'https://github.com/$_repoOwner/$_repoName/releases.atom';

  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      http.Response response;
      try {
        response = await http.get(
          Uri.parse(_latestReleaseUrl),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        // api.github.com 不可达（国内常见）→ 尝试 Atom feed 兜底。
        final fallback = await _checkViaAtom(currentVersion);
        return fallback ??
            UpdateCheckResult.failure('无法连接 GitHub：$e');
      }

      if (response.statusCode != 200) {
        final fallback = await _checkViaAtom(currentVersion);
        return fallback ??
            UpdateCheckResult.failure('GitHub 返回 ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data is! Map) {
        return const UpdateCheckResult.failure('更新信息格式无效');
      }
      final latestVersion = _versionFromTag(data['tag_name']);
      if (latestVersion.isEmpty) {
        return const UpdateCheckResult.failure('更新信息缺少版本号');
      }

      final release = _parseRelease(data);

      if (!_isNewerVersion(latestVersion, currentVersion)) {
        return const UpdateCheckResult.upToDate();
      }

      final assets = data['assets'] as List? ?? [];
      final downloadUrl = selectReleaseAssetUrl(assets) ?? '';
      if (downloadUrl.isEmpty) {
        return UpdateCheckResult.noPackage(latestVersion);
      }

      return UpdateCheckResult.available(UpdateInfo(
        version: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: release.releaseNotes,
        publishedAt: release.publishedAt,
      ));
    } catch (e) {
      return UpdateCheckResult.failure('检查更新失败: $e');
    }
  }

  /// Atom feed 兜底检查：解析 github.com 的 releases.atom（国内可访问）。
  Future<UpdateCheckResult?> _checkViaAtom(String currentVersion) async {
    try {
      final response = await http
          .get(Uri.parse(_releasesAtomUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final releases = parseAtomFeed(response.body);
      if (releases.isEmpty) return null;
      final latest = releases.first;
      if (!_isNewerVersion(latest.version, currentVersion)) {
        return const UpdateCheckResult.upToDate();
      }
      // Atom 无资产列表：给出 Release 页面作为下载入口。
      return UpdateCheckResult.available(UpdateInfo(
        version: latest.version,
        downloadUrl:
            'https://github.com/$_repoOwner/$_repoName/releases',
        releaseNotes: latest.releaseNotes,
        publishedAt: latest.publishedAt,
      ));
    } catch (_) {
      return null;
    }
  }

  /// 解析 releases.atom（纯函数，便于单测）。
  static List<ReleaseInfo> parseAtomFeed(String xml) {
    final results = <ReleaseInfo>[];
    // <entry> ... <title>v2.3.0</title> ... <updated>2026-10-02T...</updated>
    //         ... <content type="html">escaped notes</content>
    final entryPattern = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    for (final match in entryPattern.allMatches(xml)) {
      final entry = match.group(1)!;
      final title = RegExp(r'<title>(.*?)</title>', dotAll: true)
          .firstMatch(entry)
          ?.group(1)
          ?.trim();
      if (title == null || title.isEmpty) continue;
      final version = _versionFromTag(title);
      if (version.isEmpty) continue;
      final updated = RegExp(r'<updated>(.*?)</updated>', dotAll: true)
          .firstMatch(entry)
          ?.group(1)
          ?.trim();
      final contentRaw = RegExp(r'<content[^>]*>(.*?)</content>', dotAll: true)
          .firstMatch(entry)
          ?.group(1) ??
          '';
      results.add(ReleaseInfo(
        version: version,
        releaseNotes: _unescapeXml(contentRaw),
        publishedAt: DateTime.tryParse(updated ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ));
    }
    return results;
  }

  static String _unescapeXml(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }

  Future<List<ReleaseInfo>> getReleaseHistory() async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse(_releaseHistoryUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      final fallback = await _historyViaAtom();
      if (fallback != null) return fallback;
      rethrow;
    }

    if (response.statusCode != 200) {
      final fallback = await _historyViaAtom();
      if (fallback != null) return fallback;
      throw Exception('无法读取更新日志，GitHub 返回 ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      final fallback = await _historyViaAtom();
      if (fallback != null) return fallback;
      throw Exception('更新日志格式无效');
    }
    return parseReleaseHistory(data);
  }

  Future<List<ReleaseInfo>?> _historyViaAtom() async {
    try {
      final response = await http
          .get(Uri.parse(_releasesAtomUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final releases = parseAtomFeed(response.body);
      return releases.isEmpty ? null : releases;
    } catch (_) {
      return null;
    }
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
