import 'package:flutter/foundation.dart';

import 'tool_registry.dart';

/// 宿主（App 层）能力注入点：工具注册表是静态的，页面/Provider 能力
/// 由 App 启动时挂到这里，工具通过它访问 App 内部数据。
///
/// 安全：**只读查询 + 显式页面跳转**，不做任何写操作与删除，
/// 避免模型误伤用户数据。
class AppToolHost {
  AppToolHost._();

  /// 列出 API 配置（名称/地址/模型数，不含 Key）。
  static Future<String> Function()? listApis;

  /// 用量摘要。
  static Future<String> Function()? usageSummary;

  /// 打开 App 内页面（白名单：recycle / usage / models / gateway / settings / html）。
  static Future<String> Function(String page)? openPage;

  /// 是否有能力（用于工具说明里提示"当前可用"）。
  static bool get ready => listApis != null;
}

/// 注册 App 操作类工具（在 App 启动时调用一次）。
void registerAppTools() {
  ToolRegistry.register(AiTool(
    name: 'app_list_apis',
    category: 'app',
    description: '列出用户在 Apilot 里保存的 API 方案（名称、地址、模型数量；不含密钥）。',
    parameters: '{}',
    run: (args) async {
      final handler = AppToolHost.listApis;
      if (handler == null) return 'App 工具未就绪';
      return handler();
    },
  ));

  ToolRegistry.register(AiTool(
    name: 'app_usage',
    category: 'app',
    description: '查询 Apilot 的用量统计摘要（请求次数、token 消耗、失败次数）。',
    parameters: '{}',
    run: (args) async {
      final handler = AppToolHost.usageSummary;
      if (handler == null) return 'App 工具未就绪';
      return handler();
    },
  ));

  ToolRegistry.register(AiTool(
    name: 'app_open_page',
    category: 'app',
    description: '打开 Apilot 内的页面（recycle=回收站, usage=用量统计, '
        'models=模型商店, gateway=本地网关, settings=设置, html=HTML 编辑器）。',
    parameters: '{"page":"recycle"}',
    run: (args) async {
      final page = args['page']?.toString().trim() ?? '';
      const allowed = {
        'recycle',
        'usage',
        'models',
        'gateway',
        'settings',
        'html',
      };
      if (!allowed.contains(page)) {
        return '错误：只支持这些页面：${allowed.join('、')}';
      }
      final handler = AppToolHost.openPage;
      if (handler == null) return 'App 工具未就绪';
      try {
        return await handler(page);
      } catch (e) {
        debugPrint('[AppTools] 打开页面失败: $e');
        return '打开失败：$e';
      }
    },
  ));
}
