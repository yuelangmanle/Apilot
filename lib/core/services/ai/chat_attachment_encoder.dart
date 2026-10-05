import 'dart:convert';
import 'dart:io';

import '../../services/local_llm/chat_conversation_store.dart';

class ChatAttachmentEncoder {
  ChatAttachmentEncoder._();

  static const int maxImageBytes = ChatAttachment.maxImageBytes;
  static const int maxTextCharacters = 200000;

  static Future<Object> encodeUserContent(
    String text,
    List<ChatAttachment> attachments,
  ) async {
    final textFiles = attachments.where((a) => a.type == 'text').toList();
    final images = attachments.where((a) => a.type == 'image').toList();
    final remoteFiles = attachments
        .where((a) => a.remoteFileId?.trim().isNotEmpty == true)
        .toList();
    final messageText = StringBuffer(text);
    for (final attachment in textFiles) {
      // 用户已经主动上传到当前 API 时，优先引用服务端文件，避免把大文件
      // 再内联一次；没有 file_id 的附件继续走原来的文本内联兼容路径。
      if (attachment.remoteFileId?.trim().isNotEmpty == true) continue;
      final content = attachment.content ?? '';
      if (content.isEmpty) continue;
      final clipped = content.length > maxTextCharacters
          ? '${content.substring(0, maxTextCharacters)}\n（文件内容超出上限，已截断）'
          : content;
      messageText
        ..writeln()
        ..writeln('文件「${attachment.name}」内容：')
        ..writeln('```')
        ..writeln(clipped)
        ..writeln('```');
    }

    if (images.isEmpty && remoteFiles.isEmpty) return messageText.toString();

    final normalizedText = messageText.toString();
    final blocks = <Map<String, dynamic>>[
      if (normalizedText.isNotEmpty) {'type': 'text', 'text': normalizedText},
    ];
    for (final file in remoteFiles) {
      final fileId = file.remoteFileId!.trim();
      // `file` 是 OpenAI 兼容服务目前最常见的 Chat Completions 文件块；
      // 同时保留顶层 file_id，兼容部分中转站的简化解析器。
      blocks.add({
        'type': 'file',
        'file': {'file_id': fileId},
        'file_id': fileId,
      });
    }
    for (final image in images) {
      final bytes = await _readImageBytes(image);
      if (bytes.length > maxImageBytes) {
        throw FileSystemException(
          '图片超过 ${maxImageBytes ~/ (1024 * 1024)} MB 限制',
          image.path,
        );
      }
      final mimeType = _mimeType(image.name);
      blocks.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
        },
      });
    }
    return blocks;
  }

  static Future<List<int>> _readImageBytes(ChatAttachment image) async {
    final path = image.path;
    if (path != null) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('图片附件已不存在', path);
      }
      final length = await file.length();
      if (length > maxImageBytes) {
        throw FileSystemException(
          '图片超过 ${maxImageBytes ~/ (1024 * 1024)} MB 限制',
          path,
        );
      }
      return file.readAsBytes();
    }
    final encoded = image.content;
    if (encoded != null && encoded.isNotEmpty) {
      final data = encoded.replaceFirst(RegExp(r'^data:[^,]+,'), '');
      if (data.length > ((maxImageBytes + 2) ~/ 3) * 4) {
        throw FileSystemException(
          '图片超过 ${maxImageBytes ~/ (1024 * 1024)} MB 限制',
          image.name,
        );
      }
      final decoded = base64Decode(data);
      if (decoded.length > maxImageBytes) {
        throw FileSystemException(
          '图片超过 ${maxImageBytes ~/ (1024 * 1024)} MB 限制',
          image.name,
        );
      }
      return decoded;
    }
    throw FileSystemException('图片附件没有可读取的数据', image.name);
  }

  static String _mimeType(String name) {
    return switch (name.split('.').last.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
  }
}
