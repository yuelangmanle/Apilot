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

      // 根据平台选择下载链接
      String downloadUrl = '';
      final assets = data['assets'] as List? ?? [];
      final isMacOS = Platform.isMacOS;
      final targetExt = isMacOS ? '.dmg' : '.apk';

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith(targetExt)) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }
      // 降级：如果没有对应格式，取第一个
      if (downloadUrl.isEmpty && assets.isNotEmpty) {
        downloadUrl = assets.first['browser_download_url'] as String? ?? '';
      }

      final publishedAt = DateTime.tryParse(data['published_at'] as String? ?? '') ?? DateTime.now();
      final body = data['body'] as String? ?? '';

      if (_isNewerVersion(latestVersion, currentVersion)) {
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
