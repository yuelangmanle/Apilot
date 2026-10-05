import 'dart:io';

import 'package:api_manager/core/services/local_llm/chat_conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;
  late ChatConversationStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('chat_store_test_');
    store = ChatConversationStore(overrideDir: tmpDir);
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  ChatConversation makeConversation(String id, {String? text}) {
    return ChatConversation(
      id: id,
      title: '测试对话 $id',
      modelPath: '/models/qwen3.gguf',
      modelName: 'Qwen3-4B',
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
      messages: [
        ChatMessageRecord(role: 'user', text: text ?? '你好'),
        const ChatMessageRecord(role: 'assistant', text: '你好！有什么可以帮你的？'),
      ],
    );
  }

  group('ChatConversationStore', () {
    test('copies image attachments into conversation storage and deletes them',
        () async {
      final source = File(p.join(tmpDir.path, 'picked.png'))
        ..writeAsBytesSync([1, 2, 3]);
      final attachment = await store.importAttachment(
        'with-image',
        sourcePath: source.path,
        name: 'picked.png',
        type: 'image',
      );

      expect(attachment.path, isNot(source.path));
      expect(await File(attachment.path!).readAsBytes(), [1, 2, 3]);
      await store.deleteAttachment(attachment.path);
      expect(await File(attachment.path!).exists(), isFalse);
    });

    test('stores bounded text attachment content inline', () async {
      final source = File(p.join(tmpDir.path, 'notes.md'))
        ..writeAsStringSync('# 标题');
      final attachment = await store.importAttachment(
        'text',
        sourcePath: source.path,
        name: 'notes.md',
        type: 'text',
      );

      expect(attachment.content, '# 标题');
      expect(attachment.path, isNotNull);
      expect(await File(attachment.path!).readAsString(), '# 标题');

      final uploaded = attachment.copyWith(remoteFileId: 'file_test_123');
      expect(
        ChatAttachment.fromJson(uploaded.toJson()).remoteFileId,
        'file_test_123',
      );
    });

    test('save then load round-trips all fields', () async {
      final conv = makeConversation('c1');
      conv.settings = const ChatGenerationSettings(
          temp: 0.5, topP: 0.8, maxTokens: 1024, thinkingEnabled: true);
      await store.save(conv);

      final loaded = await store.load('c1');
      expect(loaded, isNotNull);
      expect(loaded!.title, '测试对话 c1');
      expect(loaded.modelName, 'Qwen3-4B');
      expect(loaded.messages, hasLength(2));
      expect(loaded.messages.first.text, '你好');
      expect(loaded.settings.temp, 0.5);
      expect(loaded.settings.thinkingEnabled, isTrue);
    });

    test('persists system prompt across save/load', () async {
      final conv = makeConversation('sys');
      conv.settings = const ChatGenerationSettings(
        temp: 0.7,
        systemPrompt: '你是一个严谨的 API 调试助手。',
      );
      await store.save(conv);

      final loaded = await store.load('sys');
      expect(loaded, isNotNull);
      expect(loaded!.settings.systemPrompt, '你是一个严谨的 API 调试助手。');
      expect(loaded.settings.temp, 0.7);

      // 空系统提示词不写入 JSON（老版本文件读回也为空字符串）。
      conv.settings = const ChatGenerationSettings();
      await store.save(conv);
      final reloaded = await store.load('sys');
      expect(reloaded!.settings.systemPrompt, isEmpty);
    });

    test('persists attachments and thinking', () async {
      final conv = ChatConversation(
        id: 'c2',
        title: '附件测试',
        modelPath: '/m.gguf',
        modelName: 'M',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [
          const ChatMessageRecord(
            role: 'user',
            text: '看看这个',
            attachments: [
              ChatAttachment(name: 'a.png', type: 'image', path: '/tmp/a.png'),
              ChatAttachment(name: 'note.txt', type: 'text', content: '内容'),
            ],
          ),
          const ChatMessageRecord(
              role: 'assistant', text: '收到', thinking: '让我想想…'),
        ],
      );
      await store.save(conv);
      final loaded = await store.load('c2');
      expect(loaded!.messages.first.attachments, hasLength(2));
      expect(loaded.messages.first.attachments.first.type, 'image');
      expect(loaded.messages.last.thinking, '让我想想…');
    });

    test('list returns conversations sorted by updatedAt desc', () async {
      // save() 会刷新 updatedAt，故按时间顺序保存并用真实延时区分。
      await store.save(makeConversation('a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.save(makeConversation('c'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.save(makeConversation('b'));

      final list = await store.list();
      // 最近保存的排最前。
      expect(list.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });

    test('delete removes the conversation', () async {
      await store.save(makeConversation('d'));
      expect(await store.list(), hasLength(1));
      await store.delete('d');
      expect(await store.list(), isEmpty);
    });

    test('load returns null for missing id', () async {
      expect(await store.load('nope'), isNull);
    });

    test('skips corrupted json files without throwing', () async {
      await store.save(makeConversation('ok'));
      final bad = File(p.join(tmpDir.path, 'conversations', 'bad.json'));
      bad.writeAsStringSync('{ not valid json');
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.first.id, 'ok');
    });

    test('preview falls back to last non-empty message', () {
      final conv = makeConversation('p');
      expect(conv.preview, '你好！有什么可以帮你的？');
      final empty = ChatConversation(
        id: 'e',
        title: 't',
        modelPath: '',
        modelName: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: const [],
      );
      expect(empty.preview, '（空对话）');
    });
  });
}
