class AgentOutputDecoder {
  AgentOutputDecoder({this.onText, this.onThinking});

  final void Function(String)? onText;
  final void Function(String)? onThinking;
  final _answer = StringBuffer();
  final _thinking = StringBuffer();
  String _pending = '';
  bool _inThinking = false;
  bool _hiddenProtocol = false;
  bool _hiddenThinkingProtocol = false;
  AgentOutputDecoder? _reasoningFilter;
  bool _started = false;
  bool _deferText = false;
  bool hasInput = false;
  static const _openTags = ['<think>', '<analysis>'];
  static const _closeTags = ['</think>', '</analysis>'];

  String get answer => _answer.toString();
  String get thinking => _thinking.toString();

  void add(String delta) {
    hasInput = true;
    _pending += delta;
    _drain(false);
  }

  void addThinking(String delta) {
    (_reasoningFilter ??= AgentOutputDecoder(onText: _emitThinking)).add(delta);
  }

  void _emitThinking(String delta) {
    _thinking.write(delta);
    onThinking?.call(delta);
  }

  void finish({required bool isToolCall}) {
    _drain(true);
    _reasoningFilter?.finish(isToolCall: false);
    if (_deferText && !isToolCall && !_hiddenProtocol) {
      onText?.call(answer);
    }
  }

  void _drain(bool finalChunk) {
    while (_pending.isNotEmpty) {
      final markers = [..._openTags, ..._closeTags, '@@'];
      var position = _pending.length;
      String? marker;
      for (final candidate in markers) {
        final found = _pending.indexOf(candidate);
        if (found >= 0 && found < position) {
          position = found;
          marker = candidate;
        }
      }
      if (marker != null) {
        _emit(_pending.substring(0, position));
        _pending = _pending.substring(position + marker.length);
        if (_openTags.contains(marker)) {
          _inThinking = true;
        } else if (_closeTags.contains(marker)) {
          _inThinking = false;
          _hiddenThinkingProtocol = false;
        } else {
          // 工具协议可能被推理模型包进 <think>。它必须继续留在内部
          // answer 供 AgentRunner 解析，但不能进入用户可见的思考/正文流。
          _answer.write(marker);
          _hiddenProtocol = true;
          if (_inThinking) _hiddenThinkingProtocol = true;
        }
        continue;
      }
      var keep = 0;
      if (!finalChunk) {
        for (final candidate in markers) {
          for (var length = 1; length < candidate.length; length++) {
            if (_pending.endsWith(candidate.substring(0, length)) &&
                length > keep) {
              keep = length;
            }
          }
        }
      }
      _emit(_pending.substring(0, _pending.length - keep));
      _pending = _pending.substring(_pending.length - keep);
      break;
    }
  }

  void _emit(String text) {
    if (text.isEmpty) return;
    if (_inThinking) {
      if (_hiddenThinkingProtocol) {
        _answer.write(text);
      } else {
        _emitThinking(text);
      }
      return;
    }
    _answer.write(text);
    if (!_started && text.trimLeft().isNotEmpty) {
      _started = true;
      final first = text.trimLeft();
      _deferText = first.startsWith('{') || first.startsWith('`');
    }
    if (!_hiddenProtocol && !_deferText) onText?.call(text);
  }
}
