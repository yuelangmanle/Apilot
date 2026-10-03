import 'package:api_manager/features/local_llm/widgets/chat_code_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未带 markdown 围栏的完整 HTML 被识别为可运行代码块', () {
    const html = '<!DOCTYPE html><html><body><h1>Hello</h1></body></html>';

    final segments = MessageSegment.parse(html);

    expect(segments, hasLength(1));
    expect(segments.single.isCode, isTrue);
    expect(segments.single.language, 'html');
    expect(segments.single.text, html);
  });
}
