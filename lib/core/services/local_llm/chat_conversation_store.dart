import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 单条聊天消息（含附件与思考过程）。
class ChatMessageRecord {
  final String role; // user / assistant
  final String text;
  final String? thinking; // 模型的思考过程（可折叠展示）
  final List<ChatAttachment> attachments;

  /// 工具调用过程（每条形如"web_search(query=…)：结果摘要"，可折叠展示）。
  final List<String> toolSteps;

  /// 生成速度行（如 "28 tok/s · 3.2s · 首字 0.6s"），本地与云端都记录。
  final String? speed;

  const ChatMessageRecord({
    required this.role,
    required this.text,
    this.thinking,
    this.attachments = const [],
    this.toolSteps = const [],
    this.speed,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        if (thinking != null && thinking!.isNotEmpty) 'thinking': thinking,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
        if (toolSteps.isNotEmpty) 'toolSteps': toolSteps,
        if (speed != null && speed!.isNotEmpty) 'speed': speed,
      };

  static ChatMessageRecord fromJson(Map<String, dynamic> json) =>
      ChatMessageRecord(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
        thinking: json['thinking'] as String?,
        attachments: (json['attachments'] as List?)
                ?.whereType<Map>()
                .map((a) =>
                    ChatAttachment.fromJson(Map<String, dynamic>.from(a)))
                .toList() ??
            const [],
        toolSteps: (json['toolSteps'] as List?)
                ?.whereType<String>()
                .toList() ??
            const [],
        speed: json['speed'] as String?,
      );
}

/// 附件（图片或文本文件）。
class ChatAttachment {
  final String name;
  final String type; // image / text
  final String? path; // 本地文件路径（图片用）
  final String? content; // 文本文件内容（内联进提示词）

  const ChatAttachment({
    required this.name,
    required this.type,
    this.path,
    this.content,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (path != null) 'path': path,
        if (content != null) 'content': content,
      };

  static ChatAttachment fromJson(Map<String, dynamic> json) => ChatAttachment(
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'text',
        path: json['path'] as String?,
        content: json['content'] as String?,
      );
}

/// 生成参数（每个对话独立保存）。
class ChatGenerationSettings {
  final double temp;
  final double topP;
  final int maxTokens;
  final bool thinkingEnabled;

  /// 系统提示词（可为空）。设置后作为对话的第一条 system 消息发送。
  final String systemPrompt;

  /// 上下文压缩阈值（按对话字符数估算）：超过后自动把较早的消息
  /// 压成摘要，保留最近的对话。0 = 不自动压缩。
  final int autoCompressAtChars;

  const ChatGenerationSettings({
    this.temp = 0.8,
    this.topP = 0.9,
    this.maxTokens = 2048,
    this.thinkingEnabled = false,
    this.systemPrompt = '',
    this.autoCompressAtChars = 12000,
  });

  ChatGenerationSettings copyWith({
    double? temp,
    double? topP,
    int? maxTokens,
    bool? thinkingEnabled,
    String? systemPrompt,
    int? autoCompressAtChars,
  }) =>
      ChatGenerationSettings(
        temp: temp ?? this.temp,
        topP: topP ?? this.topP,
        maxTokens: maxTokens ?? this.maxTokens,
        thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        autoCompressAtChars:
            autoCompressAtChars ?? this.autoCompressAtChars,
      );

  Map<String, dynamic> toJson() => {
        'temp': temp,
        'topP': topP,
        'maxTokens': maxTokens,
        'thinkingEnabled': thinkingEnabled,
        if (systemPrompt.isNotEmpty) 'systemPrompt': systemPrompt,
        'autoCompressAtChars': autoCompressAtChars,
      };

  static ChatGenerationSettings fromJson(Map<String, dynamic> json) =>
      ChatGenerationSettings(
        temp: (json['temp'] as num?)?.toDouble() ?? 0.8,
        topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 2048,
        thinkingEnabled: json['thinkingEnabled'] == true,
        systemPrompt: json['systemPrompt'] as String? ?? '',
        autoCompressAtChars:
            (json['autoCompressAtChars'] as num?)?.toInt() ?? 12000,
      );
}

/// 一次完整对话。
class ChatConversation {
  final String id;
  final String title;
  final String modelPath;
  final String modelName;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessageRecord> messages;
  ChatGenerationSettings settings;

  /// 上下文压缩后的历史摘要（替代被压掉的老消息，随对话持久化）。
  String summary;

  ChatConversation({
    required this.id,
    required this.title,
    required this.modelPath,
    required this.modelName,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.settings = const ChatGenerationSettings(),
    this.summary = '',
  });

  /// 最后一条消息摘要（列表展示用）。
  String get preview {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].text.trim().isNotEmpty) {
        final text = messages[i].text.replaceAll('\n', ' ').trim();
        return text.length > 60 ? '${text.substring(0, 60)}…' : text;
      }
    }
    return '（空对话）';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'modelPath': modelPath,
        'modelName': modelName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'settings': settings.toJson(),
        if (summary.isNotEmpty) 'summary': summary,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static ChatConversation fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'] as String,
        title: json['title'] as String? ?? '对话',
        modelPath: json['modelPath'] as String? ?? '',
        modelName: json['modelName'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        messages: (json['messages'] as List?)
                ?.whereType<Map>()
                .map((m) =>
                    ChatMessageRecord.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            [],
        settings: json['settings'] is Map
            ? ChatGenerationSettings.fromJson(
                Map<String, dynamic>.from(json['settings'] as Map))
            : const ChatGenerationSettings(),
        summary: json['summary'] as String? ?? '',
      );
}

/// 对话存储：JSON 文件（每对话一个文件），原子写入。
class ChatConversationStore {
  ChatConversationStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;

  Future<Directory> _dir() async {
    final base = _overrideDir ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'conversations'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String id) async =>
      File(p.join((await _dir()).path, '$id.json'));

  /// 列出全部对话（按更新时间倒序）。
  Future<List<ChatConversation>> list() async {
    try {
      final dir = await _dir();
      final results = <ChatConversation>[];
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) {
            results.add(ChatConversation.fromJson(
                Map<String, dynamic>.from(decoded)));
          }
        } catch (e) {
          debugPrint('[ChatStore] 跳过损坏的对话 ${file.path}: $e');
        }
      }
      results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return results;
    } catch (e) {
      debugPrint('[ChatStore] 列出对话失败: $e');
      return [];
    }
  }

  Future<ChatConversation?> load(String id) async {
    try {
      final file = await _fileFor(id);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return ChatConversation.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('[ChatStore] 读取对话失败: $e');
      return null;
    }
  }

  /// 保存（原子写：先写临时文件再 rename，避免中断导致半截 JSON）。
  Future<void> save(ChatConversation conversation) async {
    try {
      conversation.updatedAt = DateTime.now();
      final file = await _fileFor(conversation.id);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(conversation.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[ChatStore] 保存对话失败: $e');
    }
  }

  Future<void> delete(String id) async {
    try {
      final file = await _fileFor(id);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('[ChatStore] 删除对话失败: $e');
    }
  }
}
