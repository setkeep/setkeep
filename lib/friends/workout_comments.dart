import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'friend_avatar.dart';
import 'friend_comment_inbox.dart';
import 'friends_repository.dart';

String _label(BuildContext context, String ja, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : ja;

String _commentOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Opens the existing shared session. Local records are never published or
/// duplicated merely to open their comments.
class HistoryWorkoutCommentsEntry extends StatefulWidget {
  const HistoryWorkoutCommentsEntry({
    super.key,
    required this.repository,
    required this.clientId,
  });

  final FriendsRepository repository;
  final String clientId;

  @override
  State<HistoryWorkoutCommentsEntry> createState() =>
      _HistoryWorkoutCommentsEntryState();
}

class _HistoryWorkoutCommentsEntryState
    extends State<HistoryWorkoutCommentsEntry> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening || !widget.repository.commentsEnabled) return;
    setState(() => _opening = true);
    try {
      final viewer = widget.repository.userId;
      final row = await widget.repository.workoutForRecord(widget.clientId);
      if (!mounted || widget.repository.userId != viewer) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _label(
                context,
                'この記録の共有コメントはまだありません。同期後に再試行してください',
                'No shared thread for this record yet. Retry after syncing',
              ),
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutCommentsPage(
            repository: widget.repository,
            workoutId: row['id'] as String,
            ownerId: row['user_id'] as String,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _label(
                context,
                'コメントを開けませんでした。再試行してください',
                'Could not open comments. Please retry',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => !widget.repository.commentsEnabled
      ? const SizedBox.shrink()
      : OutlinedButton.icon(
          key: const Key('historyWorkoutComments'),
          onPressed: _opening ? null : _open,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_bubble_outline_rounded),
          label: Text(_label(context, 'この記録のコメント', 'Comments on this workout')),
        );
}

/// One comment thread per shared workout, irrespective of the entry route.
class WorkoutCommentsPage extends StatefulWidget {
  const WorkoutCommentsPage({
    super.key,
    required this.repository,
    required this.workoutId,
    required this.ownerId,
    this.commentNotificationId,
    this.notificationRepository,
    this.onCommentViewed,
    this.onReport,
  });

  final FriendsRepository repository;
  final String workoutId;
  final String ownerId;
  final String? commentNotificationId;
  final FriendCommentInboxRepository? notificationRepository;
  final Future<void> Function()? onCommentViewed;
  final Future<void> Function(Map<String, dynamic> comment)? onReport;

  @override
  State<WorkoutCommentsPage> createState() => _WorkoutCommentsPageState();
}

class _WorkoutCommentsPageState extends State<WorkoutCommentsPage>
    with WidgetsBindingObserver {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  final _notificationKey = GlobalKey();
  late final String _viewer = widget.repository.userId;
  StreamSubscription<dynamic>? _auth;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _available = false;
  bool _failed = false;
  bool _mutation = false;
  bool _notified = false;
  int _generation = 0;
  String? _operationId;
  String? _operationBody;

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
    _draft.addListener(_draftChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WorkoutCommentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId ||
        oldWidget.ownerId != widget.ownerId) {
      _operationId = null;
      _operationBody = null;
      _draft.clear();
      _messages = [];
      _notified = false;
      unawaited(_load());
    }
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _canView() async {
    if (!widget.repository.commentsEnabled || !_sameAccount) return false;
    final notificationId = widget.commentNotificationId;
    if (notificationId != null) {
      final inbox =
          widget.notificationRepository ??
          FriendCommentInboxRepository(widget.repository);
      final notifications = await inbox.comments();
      if (!_sameAccount ||
          !notifications.any(
            (row) =>
                row['id'] == notificationId &&
                row['workout_id'] == widget.workoutId,
          )) {
        return false;
      }
    }
    final row = await widget.repository.workoutById(widget.workoutId);
    return _sameAccount &&
        row != null &&
        row['id'] == widget.workoutId &&
        row['user_id'] == widget.ownerId;
  }

  void _clearAccess() {
    if (!mounted) return;
    if (!_sameAccount) {
      _operationId = null;
      _operationBody = null;
      _draft.clear();
    }
    setState(() {
      _messages = [];
      _available = false;
      _failed = false;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) setState(() => _loading = true);
    try {
      if (!await _canView()) {
        if (generation == _generation) _clearAccess();
        return;
      }
      final messages = await widget.repository.comments(widget.workoutId);
      if (!mounted || generation != _generation) return;
      if (!_sameAccount ||
          (widget.commentNotificationId != null &&
              !messages.any(
                (row) => row['id'] == widget.commentNotificationId,
              ))) {
        _clearAccess();
        return;
      }
      setState(() {
        _messages = messages;
        _available = true;
        _failed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_revealNotification(generation));
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _messages = [];
          _available = false;
          _failed = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _revealNotification(int generation) async {
    if (widget.commentNotificationId == null ||
        _notified ||
        !_scroll.hasClients) {
      return;
    }
    // Lazy list children outside the viewport have no context. Walk the list
    // only for a notification route until its exact comment is laid out.
    while (mounted && _sameAccount && generation == _generation) {
      final target = _notificationKey.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(target);
        if (mounted && _sameAccount && generation == _generation) {
          try {
            await widget.onCommentViewed?.call();
            _notified = true;
          } catch (_) {
            _error(
              '既読を保存できませんでした。再読み込みしてください',
              'Could not save read status. Refresh to retry',
            );
          }
        }
        return;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scroll.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _error(String ja, String en) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_label(context, ja, en))));
    }
  }

  Future<void> _send() async {
    final body = _draft.text.trim();
    if (_sending ||
        _mutation ||
        !_available ||
        body.isEmpty ||
        body.runes.length > 140) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (!await _canView()) {
        _clearAccess();
        return;
      }
      // Preserve the exact operation across a failed response/retry. Editing
      // the body starts a new operation; a successful refresh alone never does.
      if (_operationId == null || _operationBody != body) {
        _operationId = _commentOperationId();
        _operationBody = body;
      }
      await widget.repository.sendComment(
        widget.workoutId,
        body,
        operationId: _operationId!,
      );
      if (!mounted || !_sameAccount) {
        _clearAccess();
        return;
      }
      // A refresh failure must not invite resubmission of an already sent body.
      _operationId = null;
      _operationBody = null;
      _draft.clear();
      await _load();
      if (mounted && _scroll.hasClients && _available) {
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      _error(
        '送信できませんでした。入力内容を確認して再試行してください',
        'Could not send. Your draft is kept; please retry',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(Map<String, dynamic> message, String action) async {
    if (_mutation || _sending || !_available) return;
    if (action == 'delete') {
      if (message['user_id'] != _viewer) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_label(context, 'コメントを削除しますか？', 'Delete comment?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_label(context, 'キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_label(context, '削除', 'Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _mutation = true);
    try {
      if (!await _canView()) {
        _clearAccess();
        return;
      }
      if (action == 'delete') {
        await widget.repository.deleteComment(message['id'] as String);
      } else {
        await widget.onReport?.call(message);
      }
      await _load();
    } catch (_) {
      _error('操作できませんでした。再試行してください', 'Could not complete action. Please retry');
    } finally {
      if (mounted) setState(() => _mutation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _draft.text.trim();
    if (!widget.repository.commentsEnabled) {
      return const FriendCommentsUnavailablePage();
    }
    final length = _draft.text.runes.length;
    final enabled = _available && !_loading && !_sending && !_mutation;
    final sendingReady = widget.repository.supportsIdempotentComments;
    final canSend = enabled && sendingReady;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F0),
      appBar: AppBar(
        title: Text(_label(context, 'トレーニングのコメント', 'Workout comments')),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                children: [
                  if (!_loading && !_available)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          children: [
                            Text(
                              _failed
                                  ? _label(
                                      context,
                                      '読み込めませんでした',
                                      'Could not load comments',
                                    )
                                  : _label(
                                      context,
                                      'この記録のコメントは表示できません',
                                      'This thread is unavailable',
                                    ),
                            ),
                            TextButton(
                              onPressed: _load,
                              child: Text(_label(context, '再試行', 'Retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_available && _messages.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          _label(context, 'まだコメントはありません', 'No comments yet'),
                        ),
                      ),
                    ),
                  for (final message in _messages)
                    WorkoutCommentBubble(
                      key: message['id'] == widget.commentNotificationId
                          ? _notificationKey
                          : ValueKey('comment-${message['id']}'),
                      repository: widget.repository,
                      message: message,
                      isOwn: message['user_id'] == _viewer,
                      onAction: enabled
                          ? (action) => _action(message, action)
                          : null,
                      canReport: widget.onReport != null,
                    ),
                ],
              ),
            ),
          ),
          if (_available && !_loading && !sendingReady)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _label(
                  context,
                  'コメント送信は準備中です',
                  'Comment sending is being prepared',
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('workoutCommentDraft'),
                      controller: _draft,
                      enabled: canSend,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 140,
                      // PostgreSQL char_length and the repository both count Unicode
                      // code points. Grapheme-only limiting permits oversized emoji.
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => Text(
                            '$length/140',
                            style: TextStyle(
                              color: length > 140
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                      decoration: InputDecoration(
                        hintText: _label(context, 'コメントを入力', 'Write a comment'),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: IconButton.filled(
                      key: const Key('sendWorkoutComment'),
                      tooltip: _label(context, '送信', 'Send'),
                      onPressed: canSend && body.isNotEmpty && length <= 140
                          ? _send
                          : null,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutCommentBubble extends StatelessWidget {
  const WorkoutCommentBubble({
    super.key,
    required this.repository,
    required this.message,
    required this.isOwn,
    this.onAction,
    this.canReport = false,
  });
  final FriendsRepository repository;
  final Map<String, dynamic> message;
  final bool isOwn;
  final void Function(String)? onAction;
  final bool canReport;

  @override
  Widget build(BuildContext context) {
    final profile = message['friend_profiles'] as Map?;
    final name = (profile?['display_name'] as String?)?.trim();
    final displayName = name != null && name.isNotEmpty
        ? name
        : _label(context, isOwn ? 'あなた' : 'フレンド', isOwn ? 'You' : 'Friend');
    final date = DateTime.tryParse(message['created_at'] as String? ?? '')
        ?.toLocal();
    final time = date == null
        ? null
        : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final color = isOwn ? const Color(0xFFC7F36B) : Colors.white;
    final avatar = FriendAvatar(
      repository: repository,
      path: profile?['avatar_path'] as String?,
      radius: 17,
    );
    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: isOwn
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF556052)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOwn)
                CustomPaint(
                  size: const Size(8, 16),
                  painter: _BubbleTail(color, false),
                ),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    message['body'] as String? ?? '',
                    style: const TextStyle(
                      color: Color(0xFF101820),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (isOwn)
                CustomPaint(
                  size: const Size(8, 16),
                  painter: _BubbleTail(color, true),
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (time != null)
                Flexible(
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF66705F),
                    ),
                  ),
                ),
              if (isOwn || canReport)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: _label(context, 'コメントの操作', 'Comment actions'),
                    enabled: onAction != null,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: isOwn ? 'delete' : 'report',
                        child: Text(
                          isOwn
                              ? _label(context, '削除', 'Delete')
                              : _label(context, '通報', 'Report'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isOwn
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: isOwn
            ? [
                const SizedBox(width: 24),
                bubble,
                const SizedBox(width: 4),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 4),
                bubble,
                const SizedBox(width: 24),
              ],
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  _BubbleTail(this.color, this.own);
  final Color color;
  final bool own;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(own ? 0 : size.width, 2)
      ..lineTo(own ? size.width : 0, 4)
      ..lineTo(own ? 0 : size.width, size.height)
      ..close(),
    Paint()..color = color,
  );
  @override
  bool shouldRepaint(_BubbleTail old) => old.color != color || old.own != own;
}

/// Decorative, authorized avatars next to the existing count. No name list or
/// separate interaction is attached to these images.
class LikeAvatarStrip extends StatelessWidget {
  const LikeAvatarStrip({
    super.key,
    required this.repository,
    required this.likes,
    this.maxVisible = 4,
  }) : assert(maxVisible > 0);
  final FriendsRepository repository;
  final List<Map<String, dynamic>> likes;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final unique = <String, Map<String, dynamic>>{};
    for (final row in likes) {
      final id = row['user_id'] as String?;
      if (id != null) unique.putIfAbsent(id, () => row);
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in unique.values.take(maxVisible))
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: FriendAvatar(
                  repository: repository,
                  path:
                      row['avatar_path'] as String? ??
                      (row['friend_profiles'] as Map?)?['avatar_path']
                          as String?,
                  radius: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A stale route cannot reveal a retained thread or offer comment actions.
class FriendCommentsUnavailablePage extends StatelessWidget {
  const FriendCommentsUnavailablePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SETKEEP')),
    body: SafeArea(
      child: Center(
        child: Text(
          _label(
            context,
            '現在この機能は利用できません',
            'This feature is currently unavailable',
          ),
        ),
      ),
    ),
  );
}
