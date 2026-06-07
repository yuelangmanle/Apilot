import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const String _apiUrl = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

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

      String downloadUrl = '';
      final assets = data['assets'] as List? ?? [];
      final targetExts = _targetAssetExtensions();

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (targetExts.any(name.endsWith)) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }

      final publishedAt = DateTime.tryParse(data['published_at'] as String? ?? '') ?? DateTime.now();
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

  List<String> _targetAssetExtensions() {
    if (Platform.isMacOS) return const ['.dmg'];
    if (Platform.isWindows) return const ['.exe', '.msix', '.zip'];
    if (Platform.isAndroid) return const ['.apk'];
    return const ['.apk', '.dmg', '.exe', '.msix', '.zip'];
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
