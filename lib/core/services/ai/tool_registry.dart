import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'html_project_store.dart';
import 'memory_store.dart';

/// 插件分类（界面上一类一个开关）。
class ToolCategory {
  final String id;
  final String label;
  final String description;
  final bool defaultEnabled;

  const ToolCategory({
    required this.id,
    required this.label,
    required this.description,
    this.defaultEnabled = true,
  });

  String get prefsKey => 'ai_tool_enabled_$id';
}

/// 一个可被 AI 调用的工具（插件）。
class AiTool {
  final String name;
  final String description;

  /// 参数说明（给模型看的人类可读描述）。
  final String parameters;

  /// 所属分类（开关粒度）。
  final String category;

  /// 执行；返回给模型的文本结果。
  final Future<String> Function(Map<String, dynamic> args) run;

  /// 可选的结构化执行器。结构化结果只供宿主使用，不会直接暴露给模型。
  final Future<ToolExecutionResult> Function(Map<String, dynamic> args)?
      runDetailed;

  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.category,
    required this.run,
    this.runDetailed,
  });
}

/// 工具执行结果。截图等工具可以把供下一轮推理使用的附件路径交给宿主，
/// 不再依赖一个容易被并发请求覆盖的全局“最近路径”。
class ToolExecutionResult {
  final String text;
  final String? attachmentPath;

  const ToolExecutionResult({required this.text, this.attachmentPath});

  ToolExecutionResult copyWith({String? text, String? attachmentPath}) =>
      ToolExecutionResult(
        text: text ?? this.text,
        attachmentPath: attachmentPath ?? this.attachmentPath,
      );
}

/// AI 工具注册表（内置插件）。
///
/// 调用协议与模型无关：模型需要工具时**只输出一行**
/// `@@TOOL {"name":"web_search","args":{"query":"..."}}`，宿主执行后回灌结果。
/// 本地小模型与云端模型共用同一套机制，不依赖各家 chat template。
///
/// 开关粒度：按 [categories] 分类，用户可在对话页逐个开关。
class ToolRegistry {
  ToolRegistry._();

  static final List<AiTool> _tools = [];
  static final Set<String> _disabled = {};
  static HtmlProjectStore _htmlProjects = HtmlProjectStore();

  static List<AiTool> get tools => List.unmodifiable(_tools);

  /// 全部分类（开关面板用）。
  static const List<ToolCategory> categories = [
    ToolCategory(
      id: 'search',
      label: '联网搜索',
      description: '内置多引擎（Bing / DuckDuckGo / 百度），无需配置 Key',
    ),
    ToolCategory(
      id: 'web',
      label: '抓取网页',
      description: '把指定网址转成纯文本阅读（只允许公网地址）',
    ),
    ToolCategory(
      id: 'calc',
      label: '计算器',
      description: '精确算术，避免模型心算出错',
    ),
    ToolCategory(
      id: 'html',
      label: 'HTML 编写与自检',
      description: '写页面、结构自检、反复修正后存成草稿',
    ),
    ToolCategory(
      id: 'todo',
      label: '待办清单',
      description: '多步任务自己列 to-do 并逐项推进',
    ),
    ToolCategory(
      id: 'screen',
      label: '截屏自查',
      description: '截取当前屏幕；多模态模型可直接"看"画面',
      defaultEnabled: false,
    ),
    ToolCategory(
      id: 'app',
      label: '查询 Apilot 数据',
      description: '列出 API 方案、用量摘要、打开页面（只读）',
    ),
    ToolCategory(
      id: 'memory',
      label: '长期记忆',
      description: '把用户说过的关键事实记下来，之后对话自动带上（可查看/删除）',
    ),
    ToolCategory(
      id: 'models',
      label: '找模型 / 入库下载',
      description: '联网搜索 HuggingFace / 魔搭 / GitHub 上的模型，'
          '写入「我的社区模型」并可立即下载',
    ),
    ToolCategory(
      id: 'news',
      label: '新闻与百科',
      description: '按关键词取最新新闻（RSS，带日期与来源）与维基百科摘要，'
          '比通用搜索更适合"今天有什么新闻"',
    ),
    ToolCategory(
      id: 'github',
      label: 'GitHub 搜索',
      description: '搜索开源仓库（找模型、找工具、看人气）',
    ),
    ToolCategory(
      id: 'downloads',
      label: '下载管理',
      description: '查询模型下载进度、列出已下载/未完成、继续或暂停下载',
    ),
    ToolCategory(
      id: 'time',
      label: '时间与日期',
      description: '告诉模型今天的日期时间（模型自己不知道"现在"）',
    ),
  ];

  /// 当前启用的工具（受开关控制）。
  static List<AiTool> get enabledTools =>
      _tools.where((t) => !_disabled.contains(t.category)).toList();

  static bool isCategoryEnabled(String category) =>
      !_disabled.contains(category);

  /// 工具总开关（对话页那个开关，跨重启保留）。
  static const _masterKey = 'ai_tools_master_enabled';
  static bool _masterEnabled = false;

  static bool get masterEnabled => _masterEnabled;

  static Future<void> loadMasterEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _masterEnabled = prefs.getBool(_masterKey) ?? false;
    } catch (_) {}
  }

  static Future<void> setMasterEnabled(bool value) async {
    _masterEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_masterKey, value);
    } catch (_) {}
  }

  /// 从本地偏好加载开关（App 启动时调用一次）。
  static Future<void> loadEnabledFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _disabled.clear();
      for (final category in categories) {
        final enabled =
            prefs.getBool(category.prefsKey) ?? category.defaultEnabled;
        if (!enabled) _disabled.add(category.id);
      }
    } catch (e) {
      debugPrint('[Tools] 读取插件开关失败: $e');
    }
  }

  /// 立即改内存态（界面乐观更新用；随后仍需 [setCategoryEnabled] 落盘）。
  static void enableCategoryInMemory(String category) =>
      _disabled.remove(category);

  static void disableCategoryInMemory(String category) =>
      _disabled.add(category);

  static Future<void> setCategoryEnabled(String category, bool enabled) async {
    if (enabled) {
      _disabled.remove(category);
    } else {
      _disabled.add(category);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ai_tool_enabled_$category', enabled);
    } catch (e) {
      debugPrint('[Tools] 保存插件开关失败: $e');
    }
  }

  static AiTool? byName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  static void register(AiTool tool) {
    _tools.removeWhere((t) => t.name == tool.name);
    _tools.add(tool);
  }

  @visibleForTesting
  static void resetForTest() {
    _tools.clear();
    _disabled.clear();
    _htmlProjects = HtmlProjectStore();
    lastScreenshotPath = null;
    ToolHost.screenshotLocation = null;
  }

  @visibleForTesting
  static void setHtmlProjectStoreForTesting(HtmlProjectStore store) {
    _htmlProjects = store;
  }

  /// 给模型的工具说明（只包含已启用的分类）。
  ///
  /// 本地模型默认使用紧凑、按任务筛选的清单，避免把十几个工具的说明
  /// 每轮塞进上下文；云端保持完整清单，兼容已有行为。
  static String describeForPrompt({String? task, bool compact = false}) {
    final enabled = _toolsForTask(task, compact);
    if (enabled.isEmpty) return '';
    // 精简版工具说明：只给"名字 + 一句话 + 参数键名"。
    // 之前把每个工具的完整参数说明都塞进系统提示词，预填充变长、工具模式明显变慢；
    // 参数细节模型大多能从键名推断，必要时再问它。
    final buffer = StringBuffer()
      ..writeln('需要工具时只输出一行：@@TOOL {"name":"工具名","args":{...}}')
      ..writeln('（@@工具名 {参数} 也可以）。不需要工具就正常回答。')
      ..writeln('多步任务先 todo_write 列计划；写网页先 html_check 自检再 save_html。')
      ..writeln('可用工具：');
    for (final tool in enabled) {
      final keys = RegExp(r'"([a-zA-Z_][a-zA-Z0-9_]*)":')
          .allMatches(tool.parameters)
          .map((m) => m.group(1))
          .where((k) => k != 'name' && k != 'args')
          .toList();
      buffer.writeln('- ${tool.name}：${tool.description}'
          '${keys.isEmpty ? '' : '（参数：${keys.join('/')}）'}');
    }
    return buffer.toString();
  }

  static List<AiTool> _toolsForTask(String? task, bool compact) {
    final all = enabledTools;
    if (!compact || task == null || task.trim().isEmpty) return all;
    final lower = task.toLowerCase();
    final categories = <String>{'calc', 'time', 'memory'};
    if (RegExp(r'html|网页|页面|前端|css|javascript|脚本|代码').hasMatch(lower)) {
      categories.addAll(['html', 'todo']);
    }
    if (RegExp(r'搜索|查一下|查找|网址|网页内容|联网|新闻|百科|github|仓库').hasMatch(lower)) {
      categories.addAll(['search', 'web', 'news', 'github']);
    }
    if (RegExp(r'模型|量化|下载|gguf|投影|mmproj').hasMatch(lower)) {
      categories.addAll(['models', 'downloads']);
    }
    if (RegExp(r'apilot|配置|api|接口|用量|请求').hasMatch(lower)) {
      categories.add('app');
    }
    if (RegExp(r'待办|计划|步骤|任务').hasMatch(lower)) {
      categories.add('todo');
    }
    if (RegExp(r'截屏|截图|屏幕|看一下界面').hasMatch(lower)) {
      categories.add('screen');
    }
    return all.where((tool) => categories.contains(tool.category)).toList();
  }

  /// 解析模型输出里的工具调用（只取第一条）。
  ///
  /// 花括号配对扫描而非正则：参数常含嵌套对象（`{"args":{...}}`）。
  static ({String name, Map<String, dynamic> args})? parseCall(String text) {
    // ① 规范写法：@@TOOL {"name":"...","args":{...}}
    final json = _extractToolJson(text);
    if (json != null) {
      // 规范写法：只要 JSON 里有 name 就认（未知工具交给 execute 报错）。
      final parsed = _fromJson(json, requireKnown: false);
      if (parsed != null) return parsed;
    }
    // ② 模型很自然会写成 @@工具名 {参数}（真机实测 Spark 就是这样），
    //    协议必须认——否则模型明明调对了工具，我们却不执行，只把原文糊到聊天里。
    final inline =
        RegExp(r'@@([a-zA-Z_][a-zA-Z0-9_]*)\s*(\{)').firstMatch(text);
    if (inline != null) {
      final name = inline.group(1)!;
      if (byName(name) != null) {
        final argsJson = _extractBalancedJson(
            text, inline.start + inline.group(0)!.length - 1);
        if (argsJson != null) {
          final parsed = _fromJson(argsJson, fallbackName: name);
          if (parsed != null) return parsed;
        }
        return (name: name, args: const <String, dynamic>{});
      }
    }
    // ③ 回复"恰好就是工具名"（云端模型常见）：当作无参调用执行，
    //    否则用户会收到一条内容只有 "current_time" 的回复。
    final nameOnly = text.trim().replaceAll(RegExp(r'[`。.!！?？\s]+$'), '');
    if (nameOnly.isNotEmpty && byName(nameOnly) != null) {
      return (name: nameOnly, args: const <String, dynamic>{});
    }
    // ④ 裸 JSON（含 name/tool/tool_name 字段且是我们认识的工具）。
    final bareJson = _extractBalancedJson(text, text.indexOf('{'));
    if (bareJson != null) {
      final parsed = _fromJson(bareJson);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static ({String name, Map<String, dynamic> args})? _fromJson(
    String json, {
    String? fallbackName,
    bool requireKnown = true,
  }) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final name = (decoded['name'] ??
              decoded['tool'] ??
              decoded['tool_name'] ??
              fallbackName ??
              '')
          .toString();
      if (name.isEmpty) return null;
      // 宽松写法（@@工具名 / 裸 JSON）要求名字确实是我们注册过的工具，
      // 否则普通的 JSON 文本会被误判成工具调用。
      if (requireKnown && byName(name) == null) return null;
      // 参数可能在 args / arguments / parameters 里，也可能直接平铺在顶层。
      final argsRaw =
          decoded['args'] ?? decoded['arguments'] ?? decoded['parameters'];
      Map<String, dynamic> args;
      if (argsRaw is Map) {
        args = Map<String, dynamic>.from(argsRaw);
      } else {
        args = Map<String, dynamic>.from(decoded)
          ..remove('name')
          ..remove('tool')
          ..remove('tool_name');
      }
      return (name: name, args: args);
    } catch (e) {
      debugPrint('[Tools] 解析工具调用失败: $e');
      return null;
    }
  }

  /// 从 [start] 位置的 `{` 开始做花括号配对，取出完整 JSON 对象。
  static String? _extractBalancedJson(String text, int start) {
    if (start < 0 || start >= text.length || text[start] != '{') return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  static String? _extractToolJson(String text) {
    final marker = text.indexOf('@@TOOL');
    if (marker < 0) return null;
    final start = text.indexOf('{', marker);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  static String stripCall(String text) {
    var result = text;
    // 反复剥掉：@@TOOL {...} 与 @@工具名 {...} 两种写法。
    final pattern = RegExp(r'@@(?:TOOL\s*)?([a-zA-Z_][a-zA-Z0-9_]*)?\s*\{');
    while (true) {
      final match = pattern.firstMatch(result);
      if (match == null) {
        if (result.contains('@@')) {
          result = result.replaceAll('@@TOOL', '');
        }
        break;
      }
      final json =
          _extractBalancedJson(result, result.indexOf('{', match.start));
      if (json == null) break;
      final end = result.indexOf(json, match.start) + json.length;
      result = result.substring(0, match.start) + result.substring(end);
    }
    return result.trim();
  }

  /// 执行工具（尊重开关：被关掉的分类一律拒绝执行）。
  static Future<String> execute(String name, Map<String, dynamic> args) async {
    final result = await executeDetailed(name, args);
    return result.text;
  }

  /// 执行工具并保留宿主侧元数据（例如截图附件路径）。
  static Future<ToolExecutionResult> executeDetailed(
    String name,
    Map<String, dynamic> args,
  ) async {
    final tool = byName(name);
    if (tool == null) {
      return ToolExecutionResult(text: '错误：没有名为 $name 的工具');
    }
    if (!isCategoryEnabled(tool.category)) {
      return ToolExecutionResult(
        text: '错误：插件「${tool.category}」已被用户关闭，请在对话页插件面板里开启',
      );
    }
    try {
      final result = await (tool.runDetailed?.call(args) ??
              tool.run(args).then((text) => ToolExecutionResult(text: text)))
          .timeout(const Duration(seconds: 45));
      if (result.text.length <= 6000) return result;
      return result.copyWith(
        text: '${result.text.substring(0, 6000)}…（已截断）',
      );
    } catch (e) {
      return ToolExecutionResult(text: '工具 $name 执行失败：$e');
    }
  }

  /// 注册全部内置工具（App 启动时调用一次）。
  static void registerBuiltins() {
    register(_webSearchTool);
    register(_webFetchTool);
    register(_calculatorTool);
    register(_htmlCheckTool);
    register(_saveHtmlTool);
    register(_listHtmlProjectsTool);
    register(_readHtmlProjectTool);
    register(_deleteHtmlProjectTool);
    register(_todoWriteTool);
    register(_todoReadTool);
    register(_screenshotTool);
    register(_currentTimeTool);
    register(_newsSearchTool);
    register(_wikipediaTool);
    register(_githubSearchTool);
    register(_downloadStatusTool);
    register(_listDownloadedTool);
    register(_memorySaveTool);
    register(_memorySearchTool);
    register(_modelSearchTool);
    register(_modelSaveTool);
  }

  // ── 联网搜索：内置多引擎（国内可用，无需 Key） ──────────────────

  static final AiTool _webSearchTool = AiTool(
    name: 'web_search',
    category: 'search',
    description: '联网搜索，返回若干条标题+链接+摘要。',
    parameters: '{"query":"搜索词"}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return '错误：query 不能为空';
      final attempts = <(String, Future<String?> Function())>[
        ('Bing', () => _bingSearch(query)),
        ('DuckDuckGo', () => _ddgSearch(query)),
        ('百度', () => _baiduSearch(query)),
      ];
      for (final (name, fetcher) in attempts) {
        try {
          final text = await fetcher();
          if (text != null && text.trim().isNotEmpty) return text;
        } catch (e) {
          debugPrint('[Tools] $name 搜索失败: $e');
        }
      }
      return '搜索失败：网络不可达或被限制（已尝试 Bing / DuckDuckGo / 百度）';
    },
  );

  /// Bing 中国站（国内可直连）。
  static Future<String?> _bingSearch(String query) async {
    final html = await _httpGet(Uri.parse(
        'https://cn.bing.com/search?q=${Uri.encodeQueryComponent(query)}'));
    if (html == null) return null;
    final blocks = RegExp(r'<li class="b_algo".*?</li>',
            dotAll: true, caseSensitive: false)
        .allMatches(html)
        .toList();
    final buffer = StringBuffer('搜索「$query」（Bing）：\n');
    var count = 0;
    for (final block in blocks.take(6)) {
      final chunk = block.group(0)!;
      final link = RegExp(r'<a[^>]+href="(http[^"]+)"[^>]*>(.*?)</a>',
              dotAll: true, caseSensitive: false)
          .firstMatch(chunk);
      if (link == null) continue;
      final url = _unescape(link.group(1)!);
      final title = _htmlToText(link.group(2)!);
      final snippet = _htmlToText(
          RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
                  .firstMatch(chunk)
                  ?.group(1) ??
              '');
      if (title.isEmpty) continue;
      count++;
      buffer.writeln('- $title\n  $url\n  $snippet');
    }
    return count == 0 ? null : buffer.toString();
  }

  static Future<String?> _ddgSearch(String query) async {
    final html = await _httpGet(Uri.parse(
        'https://lite.duckduckgo.com/lite/?q=${Uri.encodeQueryComponent(query)}'));
    if (html == null) return null;
    final results = <(String, String)>[];
    for (final match in RegExp(
            r'<a[^>]+class="result-link"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
            dotAll: true,
            caseSensitive: false)
        .allMatches(html)) {
      results.add((_htmlToText(match.group(2)!), _unescape(match.group(1)!)));
    }
    if (results.isEmpty) return null;
    final snippets = RegExp(r'class="result-snippet"[^>]*>(.*?)</td>',
            dotAll: true, caseSensitive: false)
        .allMatches(html)
        .map((m) => _htmlToText(m.group(1)!))
        .toList();
    final buffer = StringBuffer('搜索「$query」（DuckDuckGo）：\n');
    for (var i = 0; i < results.length && i < 6; i++) {
      buffer.writeln('- ${results[i].$1}\n  ${results[i].$2}\n'
          '  ${i < snippets.length ? snippets[i] : ''}');
    }
    return buffer.toString();
  }

  static Future<String?> _baiduSearch(String query) async {
    final html = await _httpGet(Uri.parse(
        'https://www.baidu.com/s?wd=${Uri.encodeQueryComponent(query)}'));
    if (html == null) return null;
    final buffer = StringBuffer('搜索「$query」（百度）：\n');
    var count = 0;
    for (final match in RegExp(
            r'<h3[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
            dotAll: true,
            caseSensitive: false)
        .allMatches(html)) {
      final url = _unescape(match.group(1)!);
      final title = _htmlToText(match.group(2)!);
      if (title.isEmpty) continue;
      count++;
      buffer.writeln('- $title\n  $url');
      if (count >= 6) break;
    }
    return count == 0 ? null : buffer.toString();
  }

  // ── 抓网页 ──────────────────────────────────────────────────────

  static final AiTool _webFetchTool = AiTool(
    name: 'web_fetch',
    category: 'web',
    description: '抓取网页并转成纯文本（最多 6000 字）。',
    parameters: '{"url":"https://..."}',
    run: (args) async {
      final raw = args['url']?.toString().trim() ?? '';
      final uri = Uri.tryParse(raw);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return '错误：只支持 http/https 链接';
      }
      if (!isPublicHost(uri.host)) {
        return '错误：出于安全考虑，只允许访问公网地址';
      }
      final html = await _httpGet(uri);
      if (html == null) return '抓取失败：网络不可达或状态码异常';
      final text = _htmlToText(html);
      return text.isEmpty ? '页面没有可读文本' : text;
    },
  );

  // ── 算术 ────────────────────────────────────────────────────────

  static final AiTool _calculatorTool = AiTool(
    name: 'calculator',
    category: 'calc',
    description: '做基础算术（+ - * / % 与括号），避免心算出错。',
    parameters: '{"expression":"(1+2)*3"}',
    run: (args) async {
      final expression = args['expression']?.toString() ?? '';
      if (expression.isEmpty) return '错误：expression 不能为空';
      final value = _safeEval(expression);
      return value == null
          ? '错误：表达式不合法（只支持数字与 + - * / % 括号）'
          : '$expression = $value';
    },
  );

  // ── HTML：自检 + 保存（AI 可反复修正） ──────────────────────────

  static final AiTool _htmlCheckTool = AiTool(
    name: 'html_check',
    category: 'html',
    description: '自检 HTML：报出未闭合标签、缺 DOCTYPE、'
        'script/style 括号不平衡、属性引号未闭合等问题。写完页面先自检。',
    parameters: '{"html":"<!DOCTYPE html>...","name":"已有项目名"}',
    run: (args) async {
      var html = args['html']?.toString() ?? '';
      if (html.trim().isEmpty) {
        final name = args['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) html = await _htmlProjects.read(name) ?? '';
      }
      if (html.trim().isEmpty) return '错误：html 不能为空';
      final issues = checkHtml(html);
      if (issues.isEmpty) return '自检通过：没有发现结构性问题。';
      return '发现 ${issues.length} 个问题：\n'
          '${issues.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}';
    },
  );

  static final AiTool _saveHtmlTool = AiTool(
    name: 'save_html',
    category: 'html',
    description: '把 HTML 保存成草稿（内置编辑器可预览/导出）。'
        '保存前建议先用 html_check 自检。',
    parameters: '{"title":"标题","html":"<!DOCTYPE html>..."}',
    run: (args) async {
      final title = args['title']?.toString().trim() ?? '未命名';
      final html = args['html']?.toString() ?? '';
      if (html.trim().isEmpty) return '错误：html 不能为空';
      final file = await _htmlProjects.save(title, html);
      final issues = checkHtml(html);
      return '已保存项目「${file.uri.pathSegments.last}」（${html.length} 字符）。'
          '${issues.isEmpty ? '结构自检通过。' : '注意仍有 ${issues.length} 个问题：${issues.first}'}'
          '用户可在「设置 → 工具箱 → HTML 编辑器」打开预览或导出。';
    },
  );

  static final AiTool _listHtmlProjectsTool = AiTool(
    name: 'html_project_list',
    category: 'html',
    description: '列出已经保存的 HTML 项目，供继续编辑或调试。',
    parameters: '{}',
    run: (args) async {
      final projects = await _htmlProjects.list();
      if (projects.isEmpty) return '还没有保存的 HTML 项目。';
      return 'HTML 项目：\n${projects.map((p) => '- ${p.name}（${p.sizeBytes} 字节）').join('\n')}';
    },
  );

  static final AiTool _readHtmlProjectTool = AiTool(
    name: 'html_project_read',
    category: 'html',
    description: '读取一个已保存的 HTML 项目，继续修改或调试。',
    parameters: '{"name":"项目名"}',
    run: (args) async {
      final name = args['name']?.toString().trim() ?? '';
      if (name.isEmpty) return '错误：name 不能为空';
      final html = await _htmlProjects.read(name);
      return html ?? '没有找到 HTML 项目「$name」。';
    },
  );

  static final AiTool _deleteHtmlProjectTool = AiTool(
    name: 'html_project_delete',
    category: 'html',
    description: '删除一个已保存的 HTML 项目。',
    parameters: '{"name":"项目名"}',
    run: (args) async {
      final name = args['name']?.toString().trim() ?? '';
      if (name.isEmpty) return '错误：name 不能为空';
      return await _htmlProjects.delete(name)
          ? '已删除 HTML 项目「$name」。'
          : '没有找到 HTML 项目「$name」。';
    },
  );

  /// HTML 结构自检（纯文本模型也能"调试"的关键：可验证的检查项）。
  static List<String> checkHtml(String html) {
    final issues = <String>[];
    final lower = html.toLowerCase();
    if (!lower.contains('<!doctype html>')) {
      issues.add('缺少 <!DOCTYPE html>（浏览器会进入怪异模式）。');
    }
    if (!lower.contains('<html')) issues.add('缺少 <html> 根标签。');
    if (!lower.contains('<body')) issues.add('缺少 <body> 标签。');

    const pairs = [
      'html',
      'head',
      'body',
      'div',
      'span',
      'p',
      'ul',
      'ol',
      'li',
      'table',
      'tr',
      'td',
      'th',
      'section',
      'header',
      'footer',
      'main',
      'nav',
      'style',
      'script',
      'title',
      'h1',
      'h2',
      'h3',
      'button'
    ];
    for (final tag in pairs) {
      final opens = RegExp('<$tag(\\s[^>]*)?>', caseSensitive: false)
          .allMatches(html)
          .length;
      final closes =
          RegExp('</$tag\\s*>', caseSensitive: false).allMatches(html).length;
      if (opens != closes) {
        issues.add('<$tag> 开合不匹配：$opens 个开始标签 vs $closes 个结束标签。');
      }
    }
    for (final tag in ['script', 'style']) {
      final blocks =
          RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true, caseSensitive: false);
      for (final block in blocks.allMatches(html)) {
        final body = block.group(1) ?? '';
        final open = '{'.allMatches(body).length;
        final close = '}'.allMatches(body).length;
        if (open != close) {
          issues.add('<$tag> 里花括号不平衡（{ $open 个 vs } $close 个）。');
        }
        for (final pair in [('(', ')'), ('[', ']')]) {
          final a = pair.$1.allMatches(body).length;
          final b = pair.$2.allMatches(body).length;
          if (a != b) {
            issues.add('<$tag> 里 ${pair.$1}${pair.$2} 数量不匹配（$a vs $b）。');
          }
        }
      }
    }
    final unclosedQuotes =
        RegExp(r'''=\s*"[^"]*$''', multiLine: true).allMatches(html).length;
    if (unclosedQuotes > 0) {
      issues.add('有 $unclosedQuotes 处属性引号没有闭合。');
    }
    return issues;
  }

  // ── 待办清单（多步任务自己推进） ────────────────────────────────

  static const _todoPrefsKey = 'ai_tool_todo_items';

  static final AiTool _todoWriteTool = AiTool(
    name: 'todo_write',
    category: 'todo',
    description: '写入/更新待办清单（多步任务先列计划）。'
        '传完整清单，已完成项用 [x] 开头。',
    parameters: '{"items":["[ ] 步骤一","[x] 已完成步骤"]}',
    run: (args) async {
      final raw = args['items'];
      final items = <String>[];
      if (raw is List) {
        for (final item in raw) {
          final text = item.toString().trim();
          if (text.isNotEmpty) items.add(text);
        }
      } else if (raw is String && raw.trim().isNotEmpty) {
        items.addAll(raw
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty));
      }
      if (items.isEmpty) return '错误：items 不能为空';
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_todoPrefsKey, items);
      } catch (e) {
        debugPrint('[Tools] 保存待办失败: $e');
      }
      return '已更新待办清单：\n${items.join('\n')}';
    },
  );

  static final AiTool _todoReadTool = AiTool(
    name: 'todo_read',
    category: 'todo',
    description: '读取当前待办清单。',
    parameters: '{}',
    run: (args) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final items = prefs.getStringList(_todoPrefsKey) ?? const [];
        if (items.isEmpty) return '待办清单为空。';
        return '当前待办清单：\n${items.join('\n')}';
      } catch (e) {
        return '读取待办失败：$e';
      }
    },
  );

  /// 界面展示用：当前待办清单。
  static Future<List<String>> readTodoList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_todoPrefsKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  // ── 新闻（RSS，稳定且带日期） ───────────────────────────────────

  static final AiTool _newsSearchTool = AiTool(
    name: 'news_search',
    category: 'news',
    description: '按关键词获取最新新闻（带发布时间与来源）。'
        '问"今天的新闻/最新动态"优先用这个，比通用搜索准。',
    parameters: '{"query":"人工智能 国际","limit":8}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return '错误：query 不能为空';
      final limit = (args['limit'] as num?)?.toInt() ?? 8;

      // 依次尝试：Bing 新闻 RSS → Google 新闻 RSS → 百度新闻 RSS。
      final feeds = <(String, String)>[
        (
          'Bing 新闻',
          'https://www.bing.com/news/search?q=${Uri.encodeQueryComponent(query)}&format=RSS'
        ),
        (
          'Google 新闻',
          'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent(query)}&hl=zh-CN&gl=CN&ceid=CN:zh-Hans'
        ),
        (
          '百度新闻',
          'https://news.baidu.com/ns?word=${Uri.encodeQueryComponent(query)}&tn=newsrss&sr=0&cl=2&rn=20'
        ),
      ];
      for (final (engine, url) in feeds) {
        final xml = await _httpGet(Uri.parse(url));
        if (xml == null) continue;
        final items = _parseRss(xml).take(limit).toList();
        if (items.isEmpty) continue;
        final buffer = StringBuffer('「$query」最新新闻（$engine，'
            '${items.length} 条）：\n');
        for (final item in items) {
          buffer.writeln('- ${item.$1}');
          if (item.$2.isNotEmpty) buffer.writeln('  ${item.$2}');
          if (item.$3.isNotEmpty) buffer.writeln('  ${item.$3}');
        }
        return buffer.toString();
      }
      return '新闻获取失败：三个新闻源都不可达（可检查网络或换个关键词）。';
    },
  );

  /// 极简 RSS/Atom 解析：title / link / pubDate。
  static List<(String title, String link, String date)> _parseRss(String xml) {
    final results = <(String, String, String)>[];
    final itemPattern =
        RegExp(r'<item[\s>][\s\S]*?</item>', caseSensitive: false);
    for (final item in itemPattern.allMatches(xml)) {
      final chunk = item.group(0)!;
      String pick(String tag) {
        final match =
            RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false)
                .firstMatch(chunk);
        var value = match?.group(1) ?? '';
        value = value.replaceAll(
            RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true), r'$1');
        value = _htmlToText(value);
        return value.trim();
      }

      final title = pick('title');
      if (title.isEmpty) continue;
      final link = pick('link');
      final date = pick('pubDate');
      results.add((title, link, date));
    }
    return results;
  }

  // ── 维基百科 ────────────────────────────────────────────────────

  static final AiTool _wikipediaTool = AiTool(
    name: 'wikipedia',
    category: 'news',
    description: '查询维基百科条目摘要（概念、人物、事件的背景知识）。',
    parameters: '{"query":"Transformer 模型"}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return '错误：query 不能为空';
      // 先中文，再英文。
      for (final lang in ['zh', 'en']) {
        final searchUrl = Uri.parse(
            'https://$lang.wikipedia.org/w/api.php?action=query&format=json'
            '&list=search&srsearch=${Uri.encodeQueryComponent(query)}&srlimit=1');
        final raw = await _httpGet(searchUrl);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;
          final queryNode = decoded['query'];
          if (queryNode is! Map) continue;
          final list = queryNode['search'];
          if (list is! List || list.isEmpty) continue;
          final title = (list.first as Map)['title']?.toString() ?? '';
          if (title.isEmpty) continue;
          final summaryUrl = Uri.parse(
              'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}');
          final summaryRaw = await _httpGet(summaryUrl);
          if (summaryRaw == null) continue;
          final summary = jsonDecode(summaryRaw);
          if (summary is! Map) continue;
          final extract = summary['extract']?.toString() ?? '';
          if (extract.isEmpty) continue;
          return '【$title】（$lang 维基）\n$extract';
        } catch (e) {
          debugPrint('[Tools] wiki 解析失败: $e');
        }
      }
      return '没有找到「$query」的维基条目。';
    },
  );

  // ── GitHub 搜索 ─────────────────────────────────────────────────

  static final AiTool _githubSearchTool = AiTool(
    name: 'github_search',
    category: 'github',
    description: '搜索 GitHub 仓库（找模型实现、工具、看 star 数）。',
    parameters: '{"query":"gguf vision model","limit":5}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return '错误：query 不能为空';
      final limit = (args['limit'] as num?)?.toInt() ?? 5;
      final raw = await _httpGet(Uri.parse(
          'https://api.github.com/search/repositories?q=${Uri.encodeQueryComponent(query)}'
          '&sort=stars&order=desc&per_page=$limit'));
      if (raw == null) return 'GitHub 搜索失败：网络不可达或限流。';
      try {
        final decoded = jsonDecode(raw);
        final items =
            (decoded is Map ? decoded['items'] : null) as List? ?? const [];
        if (items.isEmpty) return '没有搜到相关仓库。';
        final buffer = StringBuffer('GitHub「$query」结果：\n');
        for (final item in items.whereType<Map>()) {
          buffer.writeln('- ${item['full_name']}（★${item['stargazers_count']}，'
              '${item['language'] ?? '—'}）');
          final desc = item['description']?.toString() ?? '';
          if (desc.isNotEmpty) buffer.writeln('  $desc');
          buffer.writeln('  ${item['html_url']}');
        }
        return buffer.toString();
      } catch (e) {
        return 'GitHub 结果解析失败：$e';
      }
    },
  );

  // ── 下载管理 ────────────────────────────────────────────────────

  static final AiTool _downloadStatusTool = AiTool(
    name: 'model_download_status',
    category: 'downloads',
    description: '查看模型下载情况（进行中/失败/未完成，含已下载字节与原因）。',
    parameters: '{}',
    run: (args) async {
      final handler = ToolHost.downloadStatus;
      if (handler == null) return '下载状态不可用（宿主未注册）';
      return handler();
    },
  );

  static final AiTool _listDownloadedTool = AiTool(
    name: 'model_list_downloaded',
    category: 'downloads',
    description: '列出已经下载好的本地模型（可离线对话的）。',
    parameters: '{}',
    run: (args) async {
      final handler = ToolHost.listDownloaded;
      if (handler == null) return '本地模型列表不可用（宿主未注册）';
      return handler();
    },
  );

  // ── 时间 ────────────────────────────────────────────────────────

  static final AiTool _currentTimeTool = AiTool(
    name: 'current_time',
    category: 'time',
    description: '获取当前日期与时间（需要"今天""现在"相关回答时先调用）。',
    parameters: '{}',
    run: (args) async {
      final now = DateTime.now();
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      return '现在是 ${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}'
          '（星期${weekdays[now.weekday - 1]}，本地时区）';
    },
  );

  // ── 长期记忆 ────────────────────────────────────────────────────

  static final AiTool _memorySaveTool = AiTool(
    name: 'memory_save',
    category: 'memory',
    description: '把值得长期记住的用户事实存下来（偏好、身份、常用信息）。'
        '只在用户明确表达"记住/以后都用"或信息确实长期有用时调用。',
    parameters: '{"text":"用户最喜欢的颜色是蓝色","tags":["偏好"]}',
    run: (args) async {
      final text = args['text']?.toString().trim() ?? '';
      if (text.isEmpty) return '错误：text 不能为空';
      final tags = (args['tags'] as List?)
              ?.whereType<String>()
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          const <String>[];
      final entry = await MemoryStore.save(text, tags: tags);
      return '已记住：${entry.text}'
          '（用户可在「设置 → 工具箱」里查看或删除）';
    },
  );

  static final AiTool _memorySearchTool = AiTool(
    name: 'memory_search',
    category: 'memory',
    description: '按关键词检索长期记忆（找用户以前说过的偏好/事实）。',
    parameters: '{"query":"颜色"}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      final recalled = await MemoryStore.recall(query);
      if (recalled.isEmpty) return '没有找到相关记忆。';
      return '相关记忆：\n'
          '${recalled.map((e) => '- ${e.text}').join('\n')}';
    },
  );

  // ── 找模型 / 入库下载 ───────────────────────────────────────────

  static final AiTool _modelSearchTool = AiTool(
    name: 'model_search',
    category: 'models',
    description: '在 HuggingFace 与魔搭搜索 GGUF 模型（真实数据：文件清单与体积）。',
    parameters: '{"query":"qwen3 gguf"}',
    run: (args) async {
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return '错误：query 不能为空';
      final handler = ToolHost.searchModels;
      if (handler == null) return '模型搜索不可用（宿主未注册）';
      return handler(query);
    },
  );

  static final AiTool _modelSaveTool = AiTool(
    name: 'model_save',
    category: 'models',
    description: '把一个模型仓库（HuggingFace / 魔搭 / GitHub 链接或 owner/repo）'
        '解析成可下载条目，写入「我的社区模型」；download=true 时立即开始下载。',
    parameters: '{"repo":"XHToken/Spark-X2.5-4B-GGUF","download":true}',
    run: (args) async {
      final repo = args['repo']?.toString().trim() ?? '';
      if (repo.isEmpty) return '错误：repo 不能为空';
      final download = args['download'] == true;
      final handler = ToolHost.saveModel;
      if (handler == null) return '模型入库不可用（宿主未注册）';
      return handler(repo, download);
    },
  );

  // ── 截屏自查（多模态模型可直接"看"） ────────────────────────────

  /// 最近一次截屏路径（AgentRunner 作为图片附件回灌给模型）。
  static String? lastScreenshotPath;

  static final AiTool _screenshotTool = AiTool(
    name: 'screenshot',
    category: 'screen',
    description: '截取 Apilot 当前屏幕并保存到下载目录；如果当前路由支持图片输入，'
        '下一轮会附上截图，否则只返回保存结果。',
    parameters: '{}',
    run: (args) async => (await _runScreenshot(args)).text,
    runDetailed: _runScreenshot,
  );

  static Future<ToolExecutionResult> _runScreenshot(
    Map<String, dynamic> args,
  ) async {
    final handler = ToolHost.screenshot;
    if (handler == null) {
      return const ToolExecutionResult(text: '截屏不可用（宿主未注册）');
    }
    final path = await handler();
    if (path == null) {
      return const ToolExecutionResult(text: '截屏失败：无法获取屏幕画面');
    }
    lastScreenshotPath = path;
    return ToolExecutionResult(
      text: '截图已保存至系统 Download/Apilot/Screenshots。'
          '${ToolHost.visionEnabled ? '你可以直接分析收到的截图。' : '图片已生成；只有实际支持图片输入的模型才能描述画面。'}',
      attachmentPath: path,
    );
  }

  // ── 基础设施 ────────────────────────────────────────────────────
  static Future<String?> _httpGet(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        final request = await client.getUrl(uri);
        request.headers.set('User-Agent',
            'Mozilla/5.0 (Linux; Android 14) Apilot/2.6 Safari/537.36');
        request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
        final response =
            await request.close().timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          client.close();
          continue;
        }
        final body = await response.transform(utf8.decoder).join();
        client.close();
        return body;
      } catch (e) {
        debugPrint('[Tools] GET $uri 失败: $e');
      }
    }
    return null;
  }

  static String _htmlToText(String html) {
    var text = html
        .replaceAll(
            RegExp(r'<(script|style|noscript)[^>]*>.*?</\1>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(
            RegExp(r'<(br|/p|/div|/li|/h[1-6])[^>]*>', caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _unescape(text);
    return text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
        .trim();
  }

  static String _unescape(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static int _index = 0;
  static List<String> _tokens = const [];

  static num? _safeEval(String expression) {
    final cleaned = expression.replaceAll(' ', '');
    if (!RegExp(r'^[\d+\-*/%().]+$').hasMatch(cleaned)) return null;
    try {
      return _evalTokens(_tokenize(cleaned));
    } catch (_) {
      return null;
    }
  }

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (final char in input.split('')) {
      if ('+-*/%()'.contains(char)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(char);
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }

  static num _evalTokens(List<String> tokens) {
    _tokens = tokens;
    _index = 0;
    final value = _parseExpression();
    if (_index != _tokens.length) throw const FormatException('多余字符');
    return value;
  }

  static num _parseExpression() {
    var value = _parseTerm();
    while (_index < _tokens.length &&
        (_tokens[_index] == '+' || _tokens[_index] == '-')) {
      final op = _tokens[_index++];
      final rhs = _parseTerm();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  static num _parseTerm() {
    var value = _parseFactor();
    while (_index < _tokens.length &&
        (_tokens[_index] == '*' ||
            _tokens[_index] == '/' ||
            _tokens[_index] == '%')) {
      final op = _tokens[_index++];
      final rhs = _parseFactor();
      if ((op == '/' || op == '%') && rhs == 0) {
        throw const FormatException('除零');
      }
      value = switch (op) {
        '*' => value * rhs,
        '/' => value / rhs,
        _ => value % rhs,
      };
    }
    return value;
  }

  static num _parseFactor() {
    if (_index >= _tokens.length) throw const FormatException('意外结束');
    final token = _tokens[_index];
    if (token == '-') {
      _index++;
      return -_parseFactor();
    }
    if (token == '(') {
      _index++;
      final value = _parseExpression();
      if (_index >= _tokens.length || _tokens[_index] != ')') {
        throw const FormatException('括号不匹配');
      }
      _index++;
      return value;
    }
    _index++;
    final number = num.tryParse(token);
    if (number == null) throw const FormatException('非法数字');
    return number;
  }
}

/// 宿主能力注入点（需要页面/Provider 才能提供的能力）。
class ToolHost {
  ToolHost._();

  /// 兼容旧宿主的状态字段。新代码由 AgentRunner 按实际引擎能力设置，
  /// 截图工具本身不会再依赖它决定是否回灌图片。
  static bool visionEnabled = false;

  /// 截屏（返回保存路径）。
  static Future<String?> Function()? screenshot;

  /// 截图用户可访问的位置，与推理用临时文件路径分离。
  static String? screenshotLocation;

  /// 模型搜索（返回真实候选清单文本）。
  static Future<String> Function(String query)? searchModels;

  /// 模型入库（解析仓库 → 存进"我的社区模型"，可选立即下载）。
  static Future<String> Function(String repo, bool download)? saveModel;

  /// 下载状态（进行中/失败/未完成）。
  static Future<String> Function()? downloadStatus;

  /// 已下载模型清单。
  static Future<String> Function()? listDownloaded;
}

/// 是否公网地址（拒绝本机、内网、保留地址）。
bool isPublicHost(String host) {
  if (host.isEmpty) return false;
  final lower = host.toLowerCase();
  if (lower == 'localhost' || lower.endsWith('.local')) return false;
  final ip = InternetAddress.tryParse(lower);
  if (ip == null) return true;
  if (ip.isLoopback) return false;
  final bytes = ip.rawAddress;
  if (bytes.length == 4) {
    final a = bytes[0], b = bytes[1];
    if (a == 10) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a == 169 && b == 254) return false;
    if (a == 127 || a == 0) return false;
    if (a >= 224) return false;
  } else if (bytes.length == 16) {
    if (bytes.every((b) => b == 0) ||
        (bytes.sublist(0, 15).every((b) => b == 0) && bytes[15] == 1)) {
      return false;
    }
    if ((bytes[0] & 0xfe) == 0xfc) return false;
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return false;
  }
  return true;
}
