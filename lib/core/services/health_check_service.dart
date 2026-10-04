import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_config.dart';
import 'api_service.dart';

/// Key 健康状态。
enum KeyHealthStatus {
  ok, // 模型列表可达
  authFailed, // 401/403：Key 无效或欠费
  unreachable, // 网络/域名不可达
  emptyOk, // 可达但没有模型列表
  unknown, // 尚未体检
}

class HealthCheckResult {
  final KeyHealthStatus status;
  final DateTime checkedAt;
  final int modelCount;
  final String? detail;
  final String? balanceText;

  const HealthCheckResult({
    required this.status,
    required this.checkedAt,
    this.modelCount = 0,
    this.detail,
    this.balanceText,
  });

  bool get isOk => status == KeyHealthStatus.ok;

  Map<String, dynamic> toPrefsJson() => {
        'status': status.name,
        'checkedAt': checkedAt.toIso8601String(),
        'modelCount': modelCount,
        if (detail != null) 'detail': detail,
        if (balanceText != null) 'balanceText': balanceText,
      };

  static HealthCheckResult fromPrefsJson(Map<String, dynamic> json) {
    return HealthCheckResult(
      status: KeyHealthStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => KeyHealthStatus.unknown,
      ),
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      modelCount: (json['modelCount'] as num?)?.toInt() ?? 0,
      detail: json['detail'] as String?,
      balanceText: json['balanceText'] as String?,
    );
  }
}

class BalanceSnapshot {
  final DateTime checkedAt;
  final String balanceText;

  const BalanceSnapshot({required this.checkedAt, required this.balanceText});

  Map<String, String> toJson() => {
        'checkedAt': checkedAt.toIso8601String(),
        'balanceText': balanceText,
      };

  static BalanceSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final checkedAt = DateTime.tryParse(value['checkedAt']?.toString() ?? '');
    final balanceText = value['balanceText']?.toString();
    if (checkedAt == null || balanceText == null || balanceText.isEmpty) {
      return null;
    }
    return BalanceSnapshot(checkedAt: checkedAt, balanceText: balanceText);
  }
}

/// 余额端点的静态解析（纯函数，便于单测）。
class BalanceParsers {
  const BalanceParsers._();

  /// DeepSeek GET /user/balance
  static String? deepseek(Map<String, dynamic> json) {
    final infos = json['balance_infos'];
    if (infos is! List || infos.isEmpty) return null;
    final first = infos.first;
    if (first is! Map) return null;
    final balance = first['total_balance'];
    if (balance == null) return null;
    final currency = first['currency']?.toString() ?? '';
    return '$currency $balance';
  }

  /// SiliconFlow GET /v1/user/info
  static String? siliconflow(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) return null;
    final balance = data['balance'];
    if (balance == null) return null;
    return 'CNY ${data['chargeBalance'] == null ? balance : '$balance'}';
  }

  /// OpenRouter GET /api/v1/key（limit 非空时返回剩余额度）
  static String? openrouter(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) return null;
    final limit = data['limit'];
    final usage = data['usage'];
    if (limit is num && usage is num) {
      final remaining = limit - usage;
      return 'USD ${remaining.toStringAsFixed(2)}';
    }
    if (data['is_free_tier'] == true) return '免费额度';
    return null;
  }
}

/// Key 批量体检服务：结果持久化到 SharedPreferences（设备本地瞬态，
/// 不随配置同步/导出，避免陈旧状态污染其他设备）。
class HealthCheckService {
  static const _prefsKey = 'apilot_key_health_v1';
  static const _balanceHistoryKey = 'apilot_key_balance_history_v1';
  static const int _maxBalanceSnapshotsPerConfig = 100;

  final Map<String, HealthCheckResult> _results = {};
  final Map<String, List<BalanceSnapshot>> _balanceHistory = {};
  bool _loaded = false;
  Future<void>? _loadFuture;
  bool _cancelled = false;
  bool _running = false;

  bool get isRunning => _running;

  /// 请求中止当前批量体检（在两项之间生效，已完成的单项结果保留）。
  void cancel() {
    if (_running) _cancelled = true;
  }

  HealthCheckService() {
    // 构造即异步加载缓存：应用重启后徽标能立即回显，
    // 而不是等到下一次 checkAll 才出现。
    unawaited(_ensureLoaded());
  }

  HealthCheckResult? resultFor(String configId) => _results[configId];

  List<BalanceSnapshot> balanceHistoryFor(String configId) =>
      List.unmodifiable(_balanceHistory[configId] ?? const []);

  /// 等待缓存加载完成（界面在 initState 里 await 它，再 setState 刷新）。
  /// 之前缓存是"构造即异步加载"且不通知界面，导致重启后详情页一直显示
  /// "未体检/无余额"，看起来像没有持久化。
  Future<void> ensureLoaded() => _ensureLoaded();

  /// 记录一次单体检结果并立即落盘。
  /// （详情页"立即体检"之前只更新界面、不写缓存，返回后又会显示旧值——
  /// 余额这类信息尤其明显。）
  Future<void> recordResult(String configId, HealthCheckResult result) async {
    await _ensureLoaded();
    _results[configId] = result;
    _lastCheckedAt[configId] = result.checkedAt;
    _appendBalanceSnapshot(configId, result);
    await _writeToPrefs();
  }

  /// 上次体检时间（界面显示"更新于 …"）。
  DateTime? lastCheckedAt(String configId) => _lastCheckedAt[configId];

  final Map<String, DateTime> _lastCheckedAt = {};
  static const _checkedAtKey = 'apilot_health_checked_at';

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            _results[key] = HealthCheckResult.fromPrefsJson(value);
          }
        });
      }
      final atRaw = prefs.getString(_checkedAtKey);
      if (atRaw != null && atRaw.isNotEmpty) {
        final decodedAt = jsonDecode(atRaw) as Map<String, dynamic>;
        decodedAt.forEach((key, value) {
          final parsed = DateTime.tryParse(value.toString());
          if (parsed != null) _lastCheckedAt[key] = parsed;
        });
      }
      final historyRaw = prefs.getString(_balanceHistoryKey);
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decodedHistory = jsonDecode(historyRaw) as Map<String, dynamic>;
        decodedHistory.forEach((key, value) {
          if (value is List) {
            _balanceHistory[key] = value
                .map(BalanceSnapshot.fromJson)
                .whereType<BalanceSnapshot>()
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('[Health] 读取体检缓存失败: $e');
    }
    _loaded = true;
  }

  Future<void> _persist(Map<String, ApiConfig> validIds) async {
    _results.removeWhere((id, _) => !validIds.containsKey(id));
    _lastCheckedAt.removeWhere((id, _) => !validIds.containsKey(id));
    _balanceHistory.removeWhere((id, _) => !validIds.containsKey(id));
    await _writeToPrefs();
  }

  void _appendBalanceSnapshot(String configId, HealthCheckResult result) {
    final balance = result.balanceText?.trim();
    if (balance == null || balance.isEmpty) return;
    final snapshots = _balanceHistory.putIfAbsent(configId, () => []);
    snapshots.add(BalanceSnapshot(
      checkedAt: result.checkedAt,
      balanceText: balance,
    ));
    if (snapshots.length > _maxBalanceSnapshotsPerConfig) {
      snapshots.removeRange(
          0, snapshots.length - _maxBalanceSnapshotsPerConfig);
    }
  }

  Future<void> _writeToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final entry in _results.entries)
            entry.key: entry.value.toPrefsJson(),
        }),
      );
      await prefs.setString(
        _checkedAtKey,
        jsonEncode({
          for (final entry in _lastCheckedAt.entries)
            entry.key: entry.value.toIso8601String(),
        }),
      );
      await prefs.setString(
        _balanceHistoryKey,
        jsonEncode({
          for (final entry in _balanceHistory.entries)
            entry.key:
                entry.value.map((snapshot) => snapshot.toJson()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('[Health] 保存体检结果失败: $e');
    }
  }

  /// 批量体检。逐个串行执行，避免对同一服务商并发轰炸。
  /// [onProgress] 在每完成一项时回调 (已完成数, 总数)，供界面刷新角标。
  Future<Map<String, HealthCheckResult>> checkAll(
    List<ApiConfig> configs, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (_running) return Map.unmodifiable(_results);
    await _ensureLoaded();
    _running = true;
    _cancelled = false;
    var done = 0;
    try {
      for (final config in configs) {
        if (_cancelled) break;
        final result = await checkOne(config);
        _results[config.id] = result;
        _lastCheckedAt[config.id] = result.checkedAt;
        _appendBalanceSnapshot(config.id, result);
        done++;
        await _persist({for (final c in configs) c.id: c});
        onProgress?.call(done, configs.length);
      }
    } finally {
      _running = false;
    }
    return Map.unmodifiable(_results);
  }

  Future<HealthCheckResult> checkOne(ApiConfig config) async {
    final models = await ApiService().fetchAvailableModels(config);
    final balanceText = await _fetchBalance(config);
    if (models.isSuccess) {
      return HealthCheckResult(
        status: KeyHealthStatus.ok,
        checkedAt: DateTime.now(),
        modelCount: models.models.length,
        balanceText: balanceText,
      );
    }

    final error = models.errorMessage ?? '';
    return HealthCheckResult(
      status: _statusFromError(error),
      checkedAt: DateTime.now(),
      detail: error,
      balanceText: balanceText,
    );
  }

  KeyHealthStatus _statusFromError(String error) {
    if (error.contains('401') || error.contains('403')) {
      return KeyHealthStatus.authFailed;
    }
    if (error.contains('Failed host lookup') ||
        error.contains('SocketException') ||
        error.contains('Connection refused') ||
        error.contains('Connection timed out')) {
      return KeyHealthStatus.unreachable;
    }
    if (error.contains('未返回可识别的模型列表')) {
      return KeyHealthStatus.emptyOk;
    }
    return KeyHealthStatus.unknown;
  }

  Future<String?> _fetchBalance(ApiConfig config) async {
    try {
      final host = Uri.tryParse(config.baseUrl)?.host ?? '';
      final endpoint = _balanceEndpointFor(host);
      if (endpoint == null) return null;

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          if (host == 'api.anthropic.com') ..._anthropicHeaders(config.apiKey),
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return _balanceParserFor(host)(decoded);
    } catch (e) {
      debugPrint('[Health] 余额查询失败: $e');
      return null;
    }
  }

  /// 仅当 base URL 的 host 与官方裸域**完全一致**时才查询余额：
  /// 中转/代理域名（如 xxx.openrouter.ai.proxy.example.com）的 Key
  /// 绝不能被发往官方域。
  String? _balanceEndpointFor(String host) {
    if (host == 'api.deepseek.com') {
      return 'https://api.deepseek.com/user/balance';
    }
    if (host == 'api.siliconflow.cn') {
      return 'https://api.siliconflow.cn/v1/user/info';
    }
    if (host == 'openrouter.ai') {
      return 'https://openrouter.ai/api/v1/key';
    }
    return null;
  }

  String? Function(Map<String, dynamic>) _balanceParserFor(String host) {
    if (host == 'api.deepseek.com') return BalanceParsers.deepseek;
    if (host == 'api.siliconflow.cn') return BalanceParsers.siliconflow;
    if (host == 'openrouter.ai') return BalanceParsers.openrouter;
    return (_) => null;
  }

  Map<String, String> _anthropicHeaders(String apiKey) => {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      };
}

/// 体检状态的一句话摘要（纯函数，供列表/详情复用）。
String healthBadgeText(HealthCheckResult? result) {
  if (result == null) return '未体检';
  switch (result.status) {
    case KeyHealthStatus.ok:
      final age = DateTime.now().difference(result.checkedAt);
      final ago =
          age.inHours >= 1 ? '${age.inHours}小时前' : '${age.inMinutes}分钟前';
      return result.balanceText == null
          ? '正常 · $ago'
          : '${result.balanceText} · $ago';
    case KeyHealthStatus.authFailed:
      return 'Key 无效或已欠费';
    case KeyHealthStatus.unreachable:
      return '无法连接';
    case KeyHealthStatus.emptyOk:
      return '可达（无模型列表）';
    case KeyHealthStatus.unknown:
      return '状态未知';
  }
}
