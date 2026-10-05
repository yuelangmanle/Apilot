#!/usr/bin/env bash
set -euo pipefail

dart format --output=none --set-exit-if-changed \
  lib/app.dart \
  lib/core/services/ai/agent_runner.dart \
  lib/core/services/ai/ai_service.dart \
  lib/core/services/ai/chat_attachment_encoder.dart \
  lib/core/services/ai/tool_registry.dart \
  lib/core/services/api_protocol_adapter.dart \
  lib/core/services/api_service.dart \
  lib/core/services/health_check_service.dart \
  lib/core/services/local_llm/chat_conversation_store.dart \
  lib/core/services/local_llm/local_llm_engine.dart \
  lib/core/services/local_llm/local_llm_tuning.dart \
  lib/core/services/local_llm/model_storage_settings.dart \
  lib/core/services/screenshot_storage.dart \
  lib/features/api_management/screens/api_detail_screen.dart \
  lib/features/local_llm/screens/api_chat_screen.dart \
  lib/features/local_llm/screens/local_chat_screen.dart \
  lib/features/sync/services/local_gateway_service.dart \
  test/unit/services/ai_service_test.dart \
  test/unit/services/api_protocol_adapter_test.dart \
  test/unit/services/api_service_stream_test.dart \
  test/unit/services/chat_attachment_encoder_test.dart \
  test/unit/services/chat_conversation_store_test.dart \
  test/unit/services/health_check_service_test.dart \
  test/unit/services/local_llm_tuning_test.dart \
  test/unit/services/local_gateway_service_test.dart \
  test/unit/services/tool_plugins_test.dart
flutter analyze
flutter test
if [[ "${APILOT_SKIP_ANDROID_BUILD:-0}" != "1" ]]; then
  flutter build apk --debug
fi
