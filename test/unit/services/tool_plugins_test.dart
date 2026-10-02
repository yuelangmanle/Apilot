import 'package:api_manager/core/services/ai/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    ToolRegistry.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  group('插件分类与开关', () {
    test('每个分类有独立 prefs key 与默认值', () {
      const categories = ToolRegistry.categories;
      expect(categories.length, greaterThanOrEqualTo(6));
      final ids = categories.map((c) => c.id).toSet();
      expect(ids, containsAll(
          ['search', 'web', 'calc', 'html', 'todo', 'screen', 'app']));
      // 截屏默认关闭（只有多模态模型才有意义）。
      expect(categories.firstWhere((c) => c.id == 'screen').defaultEnabled,
          isFalse);
      expect(
          categories.firstWhere((c) => c.id == 'search').prefsKey,
          'ai_tool_enabled_search');
    });

    test('关闭某分类后：工具清单与执行都被拦住', () async {
      ToolRegistry.registerBuiltins();
      ToolRegistry.register(AiTool(
        name: 'dummy_search',
        description: '测试用',
        parameters: '{}',
        category: 'search',
        run: (_) async => 'ok',
      ));
      expect(ToolRegistry.isCategoryEnabled('search'), isTrue);
      expect(await ToolRegistry.execute('dummy_search', {}), 'ok');

      await ToolRegistry.setCategoryEnabled('search', false);
      expect(ToolRegistry.isCategoryEnabled('search'), isFalse);
      // 模型看到的工具清单里不再包含它。
      expect(ToolRegistry.describeForPrompt(), isNot(contains('dummy_search')));
      // 即使模型硬要调用也会被拒绝。
      expect(await ToolRegistry.execute('dummy_search', {}),
          contains('已被用户关闭'));
    });

    test('开关持久化后能重新加载（重启保留）', () async {
      ToolRegistry.registerBuiltins();
      await ToolRegistry.setCategoryEnabled('calc', false);
      await ToolRegistry.setCategoryEnabled('todo', true);
      ToolRegistry.resetForTest();
      ToolRegistry.registerBuiltins();
      await ToolRegistry.loadEnabledFromPrefs();
      expect(ToolRegistry.isCategoryEnabled('calc'), isFalse);
      expect(ToolRegistry.isCategoryEnabled('todo'), isTrue);
      expect(ToolRegistry.isCategoryEnabled('search'), isTrue);
    });
  });

  group('html_check（AI 自检迭代）', () {
    test('结构完整的页面自检通过', () {
      final issues = ToolRegistry.checkHtml('''<!DOCTYPE html>
<html><head><title>t</title><style>body{color:red;}</style></head>
<body><h1>hi</h1><ul><li>a</li></ul><script>var x={a:1};</script></body></html>''');
      expect(issues, isEmpty);
    });

    test('缺 DOCTYPE / 标签不闭合 / 括号不平衡都能报出来', () {
      final issues = ToolRegistry.checkHtml(
          '<html><body><div><p>hi</p></body><script>function a(){</script>');
      expect(issues.any((i) => i.contains('DOCTYPE')), isTrue);
      expect(issues.any((i) => i.contains('<div>')), isTrue);
      expect(issues.any((i) => i.contains('花括号不平衡')), isTrue);
    });

    test('属性引号未闭合也会被指出', () {
      final issues = ToolRegistry.checkHtml(
          '<!DOCTYPE html><html><body><a href="x>click</a></body></html>');
      expect(issues.any((i) => i.contains('引号')), isTrue);
    });
  });

  group('待办清单', () {
    test('写入后能读回（模型多步任务用）', () async {
      ToolRegistry.registerBuiltins();
      await ToolRegistry.execute('todo_write', {
        'items': ['[ ] 搜索资料', '[x] 列计划'],
      });
      final read = await ToolRegistry.execute('todo_read', {});
      expect(read, contains('搜索资料'));
      expect(read, contains('列计划'));
      final fromUi = await ToolRegistry.readTodoList();
      expect(fromUi, hasLength(2));
    });

    test('空 items 报错而不是清空', () async {
      ToolRegistry.registerBuiltins();
      await ToolRegistry.execute('todo_write', {'items': ['任务 A']});
      final result = await ToolRegistry.execute('todo_write', {'items': []});
      expect(result, contains('不能为空'));
      expect(await ToolRegistry.readTodoList(), hasLength(1));
    });
  });

  group('截屏工具', () {
    test('宿主未注册时给出明确说明', () async {
      ToolRegistry.registerBuiltins();
      ToolHost.screenshot = null;
      final result = await ToolRegistry.execute('screenshot', {});
      expect(result, contains('不可用'));
    });

    test('已注册时返回路径并记录（供多模态回灌）', () async {
      ToolRegistry.registerBuiltins();
      ToolHost.screenshot = () async => '/tmp/fake-screen.png';
      ToolHost.visionEnabled = true;
      final result = await ToolRegistry.execute('screenshot', {});
      expect(result, contains('/tmp/fake-screen.png'));
      expect(result, contains('你可以直接分析画面'));
      expect(ToolRegistry.lastScreenshotPath, '/tmp/fake-screen.png');
    });
  });

  group('联网搜索（内置多引擎）', () {
    test('query 为空直接报错，不发请求', () async {
      ToolRegistry.registerBuiltins();
      final result = await ToolRegistry.execute('web_search', {'query': ''});
      expect(result, contains('不能为空'));
    });
  });
}
