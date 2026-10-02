import 'package:api_manager/features/local_llm/widgets/chat_code_block.dart';
import 'package:flutter_test/flutter_test.dart';

/// 聊天里的代码块解析（AI 写的 HTML 能不能直接复制/运行/存草稿都靠它）。
void main() {
  group('MessageSegment.parse', () {
    test('纯文本消息不产生代码段', () {
      final segments = MessageSegment.parse('你好，这是一段普通回复。');
      expect(segments, hasLength(1));
      expect(segments.first.isCode, isFalse);
    });

    test('```html 围栏被识别成代码段', () {
      final segments = MessageSegment.parse('''
给你写好了：
```html
<!DOCTYPE html>
<html><body><h1>Hi</h1></body></html>
```
直接点运行就能看。
''');
      expect(segments, hasLength(3));
      expect(segments[0].isCode, isFalse);
      expect(segments[1].isCode, isTrue);
      expect(segments[1].language, 'html');
      expect(segments[1].text, contains('<h1>Hi</h1>'));
      expect(segments[2].isCode, isFalse);
    });

    test('未闭合的围栏也能取出代码（模型经常漏结尾）', () {
      final segments = MessageSegment.parse('''
```html
<div>半截</div>
''');
      expect(segments.any((s) => s.isCode), isTrue);
      expect(segments.firstWhere((s) => s.isCode).text, contains('半截'));
    });

    test('多个代码块都能取到', () {
      final segments = MessageSegment.parse(
          '```python\nprint(1)\n```\n说明\n```js\nconsole.log(2)\n```');
      final codes = segments.where((s) => s.isCode).toList();
      expect(codes, hasLength(2));
      expect(codes[0].language, 'python');
      expect(codes[1].language, 'js');
    });

    test('无语言标注的围栏默认为空语言', () {
      final segments = MessageSegment.parse('```\nplain code\n```');
      expect(segments.single.isCode, isTrue);
      expect(segments.single.language, '');
    });
  });
}
