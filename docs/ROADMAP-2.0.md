# Apilot 2.0 路线图（草案）

> 依据：全仓库架构审读 + 性能/体验专项审读 + 竞品与生态调研（2026-09-30）。
> 基线：v1.27.0（155+ 用例、analyze 零告警）。本文档是 2.0 的执行蓝图，按阶段推进，全程可发布。

---

## 主题定位

2.0 的三个关键词：**结构升级**（Repository/协议接口/服务作用域化）、**体验升级**（动画体系/桌面端/无障碍）、**能力升级**（Key 池 UI/网关模式/多端点/国际化）。

---

## 阶段 0：已完成的前置修复（本路线图制定过程中发现并修复）

- ✅ 生产数据库降级删库（onDowngrade 只接了测试路径，P0）
- ✅ 流式"停止"按钮失效（订阅未赋回字段）
- ✅ `copyWith` 字段漂移（缺 4 字段，收藏/刷新静默抹掉 Key 生命周期数据）+ 3 个回归测试
- 遗留观察：回收站"重启复活"在真机上的完整复现路径仍未锁定（数据层已证明无损，防护已封死所有已知写入口）

## 阶段 1：架构地基（渐进、全程可发布）

| # | 事项 | 说明 |
|---|------|------|
| 1 | Repository 接口层 | ApiConfig/Group/History/InteropAudit 四接口，DatabaseService 实现之；7 处屏幕直连清零 |
| 2 | 服务作用域化 | HealthCheckService（ChangeNotifier 化）/SyncService/BluetoothSyncService 挂 App 作用域；修徽标陈旧、双实例体检、切 tab 停服、离页确认失效 |
| 3 | IndexedStack | 四 tab 保活，滚动/搜索/多选状态保留；同步服务由页面可见性驱动 |
| 4 | DatabaseService 拆分 | 4 Repository 实现 + MigrationRunner（迁移列表化）+ RowCodec；986 行 → 5 个内聚单元 |
| 5 | 协议接口化 | ChatProtocol 接口 + Registry，协议知识从 4 文件 8 函数收敛为"新文件+1 行注册"；为 Responses API 铺路 |
| 6 | Sync 拆分 | LanDiscovery/SyncHttpServer/SyncHttpClient/SyncMergeEngine/SyncCrypto；静态回调换事件流 |
| 7 | UI Controller 化 | ApiFormController（12 状态位）、ApiConfigAssembler（字段映射唯一出处）；三大 UI 巨石瘦身 |

依赖链：1→2→3 可立即并行；4/5/6 依赖 1；7 随时可做。**不换 Riverpod**（现有体量 provider 够用，混用触发条件另议）；引入 go_router 收拢 14+ 处 push；加 mocktail + ApiService 注入 http.Client。

## 阶段 2：性能与稳定性

- 历史列表懒格式化（展开才 pretty-print + LRU 缓存）——全 app 收益最大单项
- 500 行解析 / LiteLLM 大 JSON 走 isolate（compute）
- DB v8：created_at / api_config_id 索引 + 用量聚合下推 SQL（GROUP BY）
- 流式渲染改追加式列表 + delta 合帧（16ms flush），done 后切 SelectableText
- 搜索输入防抖 300ms；Consumer 下沉行级；MaterialApp 层只 select 所需布尔
- 全局错误兜底三件套（FlutterError.onError / PlatformDispatcher.onError / ErrorWidget.builder）→ 本地滚动日志文件
- DB 损坏自愈：corrupt 识别 → 文件改名保留 → 重建空库 → 引导备份恢复
- http.Client 模块级复用（体检 N Key = N 次 TLS 握手 → 1）

## 阶段 3：体验与动画（全部 Flutter 内置，不引重库）

| 项 | 方式 |
|----|------|
| Tab 切换过渡 | IndexedStack + AnimatedSwitcher fadeThrough 250ms |
| 列表增删重排 | AnimatedList 或 AnimatedSize |
| 流式打字机 + 呼吸光标 | 尾块渐入 + AnimatedOpacity 光标 |
| 骨架屏 | 自绘 shimmer（ShaderMask + AnimationController）替换 18 处转圈 |
| 锁屏 | 数字点 AnimatedContainer、PIN 错误 shake + 触觉、入场 FadeTransition |
| Hero | 卡片标题 → 详情头部（tag: api.id） |
| 数字滚动/预算条 | TweenAnimationBuilder |
| 主题切换过渡 | themeAnimationDuration 300ms（一行配置） |
| Dismissible 反馈 | 确认瞬间 mediumImpact；背景图标随滑动进度缩放 |
| 下拉刷新一致性 | 4 页补齐统一参数 |
| 表单错误微动效 | 边框色 AnimatedContainer + errorText AnimatedSize |

## 阶段 4：兼容性

- Android 预测性返回：manifest 开 `enableOnBackInvokedCallback` + 表单/锁屏真机回归
- 桌面窗口管理：window_manager（最小尺寸/记忆几何/可选托盘最小化）；FAB 让位 Rail 的 padding hack 重做
- 键盘：AppShell 全局快捷键（Ctrl+F/N/R、Delete）；列表方向键导航
- 无障碍：复制行/锁屏退格/二维码 Semantics；ApiCard 增加长按菜单（无障碍与鼠标用户共同诉求）；textScaler 1.3~2.0 回归
- 小屏：测试页手机竖屏改 Tab 切换；平板横屏三栏布局

## 阶段 5：新功能模块（按价值排序）

| 模块 | 说明 | 成本 |
|------|------|------|
| **Key 池 UI** | 配置挂多把备用 Key 的编辑界面（底层 KeyPool 已在 v1.27 落地）：增删/排序/单 Key 体检状态 | 中 |
| **本地网关模式** | Apilot 起一个 localhost OpenAI 兼容反代：任意 SDK/工具把 base_url 指向本地即可用上 Apilot 的 Key+日志+故障转移——复用现有同步 HTTP server 能力，是差异化杀手锏 | 中高 |
| **多轮对话 Playground** | 测试页单发/对话切换，气泡式 messages 编辑 | 中 |
| **Embeddings/Images 测试卡** | 向量维度+余弦相似度演示；base64 图片预览；多模态图片输入 | 中 |
| **WebDAV 备份同步** | opt-in 云备份（坚果云生态），与本地优先叙事兼容 | 中 |
| **单配置二维码迁移** | 面对面分享单方案（复用配对密钥加密通道） | 低中 |
| **Key 生命周期提醒** | 后台周期体检 + 到期/低余额本地通知 | 中 |
| **第三方授权白名单/吊销** | 基于已有审计记录，一键收回对某 App 的 Key 暴露 | 中 |
| **自动备份计划** | 每周自动备份到选定目录 | 低 |
| **备份文件口令加密** | 口令派生密钥加密备份 JSON | 低中 |
| **Responses API 协议** | 落在阶段 1 协议接口的新实现位 | 中高 |
| **批量评测（Batch）** | jsonl 打包+轮询+逐条报告 | 高 |
| **MCP Inspector** | 连 MCP server → tools 转 chat 请求字段 | 高 |
| **国际化（中/英）** | 硬编码中文全量提取 .arb | 高（机械量大） |

## 阶段 6：2.0 发布门禁

- analyze 零告警、全量测试通过且新增交互级 widget 测试 ≥ 4（每 tab 一条）
- 冷启动（首帧）与历史页进入的耗时基线测量并对比 v1.27
- 回归清单：锁屏（PIN/指纹/后台返回/错误退避）、同步（确认/加密/恢复保护）、回收站全链路、备份恢复
- 安全复审一轮（子代理）+ 密钥扫描 + 构建（APK/DMG/EXE）本地验证

---

*本文档由架构审读（依赖图谱/巨石清单/扩展性 7 处触点）、性能专项（3 个 P0/6 个 P1）、竞品调研（多 Key 池空白/生命周期提醒空档）与生态调研（LiteLLM 价格源/MCP/Responses API）综合而成。*


---

## 2.1 附录：本地大模型方案调研（2026-10）

目标设备：小米 15 Ultra（骁龙 8 Elite，Hexagon NPU v79 + Adreno 830）、红米 K80 至尊版（天玑 9400+，Immortalis-G925 + APU 890）。

### 结论

**首选：llamadart（llama.cpp 的 Flutter 封装）**——目前唯一"自带 Vulkan 预编译原生库 + 全平台（Android/桌面）+ 活跃维护（MIT）+ 可平滑升级 LiteRT-LM NPU"的方案，零 C++ 工具链依赖。CPU 基线即可用（3-4B Q4 模型 10-18 tok/s），GPU 作为灰度增强。

### 分层加速路线

| 层 | 方案 | 覆盖 | 状态 |
|---|---|---|---|
| L0 CPU 基线 | llama.cpp CPU（NEON） | 全平台 | 稳定，3-4B Q4 约 10-18 tok/s |
| L1 Vulkan | llamadart 内置开关 | 骁龙 Adreno + 天玑 Mali 均可 | 可用：prefill 提速 3-4 倍，TG 看机型（8E 上生成或降 17%） |
| L2 NPU（远期） | llama.cpp Hexagon 后端（实验性）/ ExecuTorch QNN | 仅骁龙 8E（v79 在支持列表） | 1-2B 可达 47-52 tok/s，但需专用工具链；天玑 APU 对第三方开发者 2026 年仍是黑盒 |

### 模型推荐（Q4 量化）

- 首选 **Qwen3-1.7B / 4B**：中文最强、支持 thinking budget 开关
- **Gemma 3n E2B/E4B**：走 LiteRT-LM 路线时首选，多模态
- **Llama 3.2 1B/3B**：英文基线，基准数据最全
- 不推荐 DeepSeek-R1-Distill 做默认：思考链 token 太多，手机生成速度下延迟感差

### 已知坑

- llama.cpp Vulkan 在部分机型上 prefill 反而更慢、或输出乱码——必须做运行时基准+自动回退 CPU
- 天玑侧 NPU 对第三方开发者封闭（NeuroPilot 面向大客户定制）
- MLC-LLM 无 Flutter 绑定、维护放缓，性价比低于 llamadart

### 数据来源

- llama.cpp Vulkan 基准: github.com/ggml-org/llama.cpp/discussions/10879
- 骁龙 8E Vulkan 实测: github.com/ggml-org/llama.cpp/discussions/23736
- Hexagon 后端文档: github.com/ggml-org/llama.cpp/blob/master/docs/backend/snapdragon/README.md
- llamadart: pub.dev/packages/llamadart（0.9.0，3 天前更新）
- LiteRT-LM: github.com/google-ai-edge/LiteRT-LM
