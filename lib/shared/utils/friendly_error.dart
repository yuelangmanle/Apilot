/// 统一的用户可读错误翻译：把常见异常分类成人话，避免把堆栈甩给用户。
/// 各页面原有的零散 _friendlyError 收敛到这里。
String friendlyError(Object error) {
  final msg = error.toString();
  if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
    return '无法连接到服务器，请检查网络和 API 地址是否正确';
  }
  if (msg.contains('TimeoutException') ||
      msg.toLowerCase().contains('timeout') ||
      msg.contains('timed out')) {
    return '请求超时，服务器响应太慢';
  }
  if (msg.contains('Connection refused')) {
    return '连接被拒绝，请检查 API 地址和端口';
  }
  if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE')) {
    return 'SSL 握手失败，请检查 HTTPS 配置';
  }
  if (msg.contains('DatabaseException') || msg.contains('sqlite')) {
    return '本地数据库读写失败，请重启应用后重试';
  }
  if (msg.contains('FormatException')) {
    return '数据格式不正确';
  }
  if (msg.contains('PlatformException')) {
    return '系统功能调用失败，请检查权限设置';
  }
  if (msg.contains('401') || msg.contains('403')) {
    return '鉴权失败（${_statusCode(msg)}），请检查 API Key';
  }
  return '操作失败：${_firstLine(msg)}';
}

String _statusCode(String msg) {
  final match = RegExp(r'\b(40[138]|429)\b').firstMatch(msg);
  return match?.group(0) ?? '401/403';
}

String _firstLine(String msg) {
  final line = msg.split('\n').first.trim();
  return line.length > 120 ? '${line.substring(0, 120)}…' : line;
}
