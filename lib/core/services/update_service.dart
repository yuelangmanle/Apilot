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

class UpdateService {
  static const String _repoOwner = 'yuelangmanle';
  static const String _repoName = 'Apilot';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');

      final assets = data['assets'] as List? ?? [];
      final downloadUrl = selectReleaseAssetUrl(assets) ?? '';

      final publishedAt =
          DateTime.tryParse(data['published_at'] as String? ?? '') ??
              DateTime.now();
      final body = data['body'] as String? ?? '';

      if (_isNewerVersion(latestVersion, currentVersion)) {
        if (downloadUrl.isEmpty) {
          throw Exception('GitHub Release 中没有当前平台可用的安装包');
        }
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: body,
          publishedAt: publishedAt,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
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
