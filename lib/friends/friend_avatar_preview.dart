import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'friend_avatar.dart';
import 'friends_repository.dart';

String _label(BuildContext context, String ja, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : ja;

/// The friend's calendar photo has a viewing action, separate from editing.
class FriendProfilePhoto extends StatefulWidget {
  const FriendProfilePhoto({
    super.key,
    required this.repository,
    required this.owner,
    required this.path,
    this.onClosed,
  });
  final FriendsRepository repository;
  final String owner;
  final String? path;
  final Future<void> Function()? onClosed;

  @override
  State<FriendProfilePhoto> createState() => _FriendProfilePhotoState();
}

class _FriendProfilePhotoState extends State<FriendProfilePhoto> {
  bool _previewOpen = false;

  Future<void> _open() async {
    if (_previewOpen) return;
    final path = widget.path;
    if (path == null || path.isEmpty) return;
    _previewOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => FriendAvatarPreview(
          repository: widget.repository,
          owner: widget.owner,
          path: path,
        ),
      );
      if (mounted) await widget.onClosed?.call();
    } finally {
      _previewOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = FriendAvatar(
      repository: widget.repository,
      path: widget.path,
      radius: 28,
    );
    if (widget.path == null || widget.path!.isEmpty) {
      return Center(child: avatar);
    }
    return Center(
      child: Tooltip(
        message: _label(context, 'プロフィール写真を見る', 'View profile photo'),
        child: InkWell(
          key: const Key('viewFriendProfilePhoto'),
          customBorder: const CircleBorder(),
          onTap: _open,
          child: avatar,
        ),
      ),
    );
  }
}

/// Signed URLs use existing Storage RLS. The visible record is revalidated
/// before signing and after the response, on auth/resume, and every 30 seconds.
class FriendAvatarPreview extends StatefulWidget {
  const FriendAvatarPreview({
    super.key,
    required this.repository,
    required this.owner,
    required this.path,
  });
  final FriendsRepository repository;
  final String owner;
  final String path;
  @override
  State<FriendAvatarPreview> createState() => _FriendAvatarPreviewState();
}

class _FriendAvatarPreviewState extends State<FriendAvatarPreview>
    with WidgetsBindingObserver {
  late final String _viewer = widget.repository.userId;
  StreamSubscription<dynamic>? _auth;
  Timer? _refresh;
  String? _url;
  bool _loading = true;
  bool _active = true;
  int _generation = 0;
  bool _closing = false;

  bool get _sameAccount {
    try {
      return widget.repository.userId == _viewer;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.repository.client.auth.onAuthStateChange.listen((_) {
      if (mounted) unawaited(_load());
    });
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active) unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FriendAvatarPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.owner != widget.owner ||
        oldWidget.repository != widget.repository) {
      unawaited(_load());
    }
  }

  void _clear() {
    final previous = _url;
    if (mounted) setState(() => _url = null);
    if (previous != null) unawaited(NetworkImage(previous).evict());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    _clear();
    if (_active) unawaited(_load());
  }

  Future<bool> _canView() async {
    if (!_sameAccount || widget.path.isEmpty) return false;
    final rows = await widget.repository.feed(owner: widget.owner);
    return _sameAccount &&
        rows.any(
          (row) =>
              row['user_id'] == widget.owner &&
              (row['friend_profiles'] as Map?)?['avatar_path'] == widget.path,
        );
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _clear();
    if (mounted) setState(() => _loading = true);
    try {
      if (!await _canView()) return;
      final url = await widget.repository.avatarUrl(widget.path);
      if (!await _canView()) return;
      if (mounted && _active && generation == _generation) {
        setState(() => _url = url);
      }
    } catch (_) {
      // Offline, changed-photo and revoked-access cases never reuse old pixels.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _refresh?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final previous = _url;
    if (previous != null) unawaited(NetworkImage(previous).evict());
    super.dispose();
  }

  Widget _unavailable(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        _label(context, '写真を表示できません', 'Photo unavailable'),
        textAlign: TextAlign.center,
      ),
    ),
  );

  void _close() {
    if (_closing || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final diameter = math.min(
        560.0,
        math.max(
          0.0,
          math.min(constraints.maxWidth, constraints.maxHeight) - 48,
        ),
      );
      return Center(
        child: SizedBox.square(
          key: const Key('friendProfilePhotoPreview'),
          dimension: diameter,
          child: Semantics(
            button: true,
            label: _label(context, '再度タップして閉じる', 'Tap again to close'),
            child: GestureDetector(
              key: const Key('dismissFriendProfilePhoto'),
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ClipOval(
                key: const Key('friendProfilePhotoCircle'),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _url == null
                    ? _unavailable(context)
                    : Image.network(
                        _url!,
                        key: const Key('friendProfilePhotoImage'),
                        fit: BoxFit.cover,
                        semanticLabel: _label(
                          context,
                          'プロフィール写真',
                          'Profile photo',
                        ),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, _, _) => _unavailable(context),
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
