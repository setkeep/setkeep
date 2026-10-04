import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'friends_repository.dart';

/// Re-encode a square PNG. Photo metadata is not carried into the upload.
Future<Uint8List> prepareFriendAvatar(Uint8List source) async {
  if (source.isEmpty || source.length > 10 * 1024 * 1024) {
    throw ArgumentError('Photo size');
  }
  final codec = await ui.instantiateImageCodec(source, targetWidth: 1024);
  try {
    final frame = await codec.getNextFrame();
    final original = frame.image;
    try {
      final side = original.width < original.height
          ? original.width
          : original.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        original,
        Rect.fromLTWH(
          (original.width - side) / 2,
          (original.height - side) / 2,
          side.toDouble(),
          side.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, 256, 256),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(256, 256);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Photo encoding');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      original.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class FriendAvatar extends StatefulWidget {
  const FriendAvatar({
    super.key,
    required this.repository,
    this.path,
    this.radius = 22,
  });
  final FriendsRepository? repository;
  final String? path;
  final double radius;
  @override
  State<FriendAvatar> createState() => _FriendAvatarState();
}

class _FriendAvatarState extends State<FriendAvatar> {
  String? url;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(FriendAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.repository?.userId != widget.repository?.userId) {
      load();
    }
  }

  Future<void> load() async {
    final current = ++generation;
    if (mounted) setState(() => url = null);
    if (widget.path == null || widget.repository == null) return;
    try {
      final result = await widget.repository!.avatarUrl(widget.path!);
      if (mounted && current == generation) setState(() => url = result);
    } catch (_) {
      /* Unauthorized/offline photos use the default icon. */
    }
  }

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: widget.radius,
    backgroundColor: const Color(0xFFC7F36B),
    child: url == null
        ? Icon(Icons.person_rounded, size: widget.radius + 2)
        : ClipOval(
            child: Image.network(
              url!,
              width: widget.radius * 2,
              height: widget.radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.person_rounded, size: widget.radius + 2),
            ),
          ),
  );
}
