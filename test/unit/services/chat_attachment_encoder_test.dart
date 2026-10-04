import 'dart:io';

import 'package:api_manager/core/services/ai/chat_attachment_encoder.dart';
import 'package:api_manager/core/services/local_llm/chat_conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatAttachmentEncoder', () {
    test('keeps text-only messages as strings and appends text files',
        () async {
      final content = await ChatAttachmentEncoder.encodeUserContent(
        '总结文件',
        const [
          ChatAttachment(name: 'notes.md', type: 'text', content: '# 标题'),
        ],
      );

      expect(content, isA<String>());
      expect(content, contains('总结文件'));
      expect(content, contains('notes.md'));
      expect(content, contains('# 标题'));
    });

    test('encodes image attachments as OpenAI-compatible data URLs', () async {
      final root = Directory.systemTemp.createTempSync('apilot_image_');
      addTearDown(() => root.deleteSync(recursive: true));
      final image = File('${root.path}/sample.png')
        ..writeAsBytesSync([0, 1, 2, 3]);

      final content = await ChatAttachmentEncoder.encodeUserContent(
        '描述图片',
        [
          ChatAttachment(name: 'sample.png', type: 'image', path: image.path),
        ],
      );

      expect(content, isA<List<Map<String, dynamic>>>());
      final blocks = content as List<Map<String, dynamic>>;
      expect(blocks.first, {'type': 'text', 'text': '描述图片'});
      expect(blocks.last['type'], 'image_url');
      expect(
        (blocks.last['image_url'] as Map<String, dynamic>)['url'],
        'data:image/png;base64,AAECAw==',
      );
    });

    test('rejects missing image files instead of silently dropping them',
        () async {
      await expectLater(
        ChatAttachmentEncoder.encodeUserContent('看图', const [
          ChatAttachment(
            name: 'missing.png',
            type: 'image',
            path: '/not/a/real/image.png',
          ),
        ]),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
