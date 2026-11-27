import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';

/// 设备卡片本地头像：图片只保存在当前 App 的私有目录，
/// 路径按 peer.id 记入 LocalConfig.flutter_option，不进仓库、不上传服务器。
final RxString peerAvatarRevision = '0'.obs;

void bumpPeerAvatarRevision() {
  peerAvatarRevision.value =
      ((int.tryParse(peerAvatarRevision.value) ?? 0) + 1).toString();
}

String peerAvatarOptionKey(String peerId) =>
    '$kOptionPeerAvatarPrefix$peerId';

String getPeerAvatarPath(String peerId) {
  try {
    return bind.getLocalFlutterOption(k: peerAvatarOptionKey(peerId));
  } catch (e) {
    debugPrint('failed to get peer avatar: $e');
    return '';
  }
}

bool hasPeerAvatar(String peerId) {
  final path = getPeerAvatarPath(peerId);
  return path.isNotEmpty && File(path).existsSync();
}

String _avatarFileName(String peerId) =>
    '${base64Url.encode(utf8.encode(peerId)).replaceAll('=', '')}.jpg';

Future<Directory> _avatarDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}peer_avatars');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 从相册选择一张图片，居中裁成正方形并压缩后保存为这台机器的头像。
Future<void> pickAndSetPeerAvatar(String peerId) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('无法解码图片');

    final side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    var square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    if (side != 256) {
      square = img.copyResize(square, width: 256, height: 256);
    }
    final encoded = img.encodeJpg(square, quality: 85);

    final dir = await _avatarDir();
    final file = File(
        '${dir.path}${Platform.pathSeparator}${_avatarFileName(peerId)}');
    await file.writeAsBytes(encoded, flush: true);

    bind.setLocalFlutterOption(k: peerAvatarOptionKey(peerId), v: file.path);
    bumpPeerAvatarRevision();
    showToast('头像已设置');
  } catch (e) {
    debugPrint('set peer avatar failed: $e');
    showToast('设置头像失败');
  }
}

/// 移除指定机器的头像：删掉本地图片并清空配置。
Future<void> removePeerAvatar(String peerId) async {
  try {
    final path = getPeerAvatarPath(peerId);
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    bind.setLocalFlutterOption(k: peerAvatarOptionKey(peerId), v: '');
    bumpPeerAvatarRevision();
    showToast('头像已移除');
  } catch (e) {
    debugPrint('remove peer avatar failed: $e');
    showToast('移除头像失败');
  }
}

/// 有自定义头像时显示图片，否则原样返回色块 + 平台图标 fallback。
Widget buildPeerAvatar({
  required String peerId,
  required Widget fallback,
}) {
  return Obx(() {
    peerAvatarRevision.value;
    final path = getPeerAvatarPath(peerId);
    if (path.isEmpty) return fallback;
    final file = File(path);
    if (!file.existsSync()) return fallback;
    return Image.file(
      file,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  });
}
