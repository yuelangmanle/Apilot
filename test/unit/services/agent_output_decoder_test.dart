import 'package:api_manager/core/services/ai/agent_output_decoder.dart';
import 'package:api_manager/core/services/ai/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('跨 chunk 工具协议不泄漏到可见正文', () {
    final visible = StringBuffer();
    final decoder = AgentOutputDecoder(onText: visible.write);

    decoder
      ..add('先说明一下')
      ..add('@')
      ..add('@TO')
      ..add('OL {"name":"web_search","args":{"query":"中文 {嵌套}"}}')
      ..add('工具调用后的模型尾巴')
      ..finish(isToolCall: true);

    final call = ToolRegistry.parseCall(decoder.answer);
    expect(call?.name, 'web_search');
    expect(call?.args['query'], '中文 {嵌套}');
    expect(visible.toString(), '先说明一下');
    expect(ToolRegistry.stripCall(decoder.answer), '先说明一下工具调用后的模型尾巴');
  });

  test('思考标签和正文可以跨 chunk 正确分离', () {
    final visible = StringBuffer();
    final thinking = StringBuffer();
    final decoder = AgentOutputDecoder(
      onText: visible.write,
      onThinking: thinking.write,
    );

    decoder
      ..add('<thi')
      ..add('nk>先分析')
      ..add('工具结果</think>最终答案')
      ..finish(isToolCall: false);

    expect(thinking.toString(), '先分析工具结果');
    expect(decoder.answer, '最终答案');
    expect(visible.toString(), '最终答案');
  });

  test('包在 think 中的工具协议仍可执行但不显示', () {
    final visible = StringBuffer();
    final thinking = StringBuffer();
    final decoder = AgentOutputDecoder(
      onText: visible.write,
      onThinking: thinking.write,
    );

    decoder
      ..add('<think>分析中 @@TOOL {"name":"current_time","args":{}}')
      ..add('</think>用户可见回答')
      ..finish(isToolCall: true);

    expect(ToolRegistry.parseCall(decoder.answer)?.name, 'current_time');
    expect(visible.toString(), '');
    expect(thinking.toString(), '分析中 ');
  });

  test('非工具 fenced 文本在结束时完整回放', () {
    final visible = StringBuffer();
    final decoder = AgentOutputDecoder(onText: visible.write);

    decoder
      ..add('```json\n{"title":"中文"}\n```')
      ..finish(isToolCall: false);

    expect(decoder.answer, '```json\n{"title":"中文"}\n```');
    expect(visible.toString(), decoder.answer);
  });
}
