import 'dart:async';

import 'package:flutter/material.dart';

import 'friend_avatar.dart';
import 'friends_repository.dart';

String _label(BuildContext context, String ja, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : ja;

/// The friend's calendar photo has a viewing action, separate from editing.
class FriendProfilePhoto extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final avatar = FriendAvatar(repository: repository, path: path, radius: 28);
    if (path == null || path!.isEmpty) return Center(child: avatar);
    return Center(
      child: Tooltip(
        message: _label(context, 'プロフィール写真を見る', 'View profile photo'),
        child: InkWell(
          key: const Key('viewFriendProfilePhoto'),
          customBorder: const CircleBorder(),
          onTap: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => FriendAvatarPreview(
                repository: repository,
                owner: owner,
                path: path!,
              ),
            );
            if (context.mounted) await onClosed?.call();
          },
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

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('friendProfilePhotoPreview'),
    insetPadding: const EdgeInsets.all(20),
    child: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              key: const Key('closeFriendProfilePhoto'),
              tooltip: _label(context, '閉じる', 'Close'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _url == null
                ? _unavailable(context)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Image.network(
                      _url!,
                      key: const Key('friendProfilePhotoImage'),
                      fit: BoxFit.contain,
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
        ],
      ),
    ),
  );
}
