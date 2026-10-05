import '../config/trainer_release.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show WorkoutRecord;
import '../trainer/trainer_inbox_page.dart';
import '../trainer/trainer_inbox_repository.dart';
import 'friend_comment_inbox.dart';
import 'friends_ui.dart';

class NotificationSourcesPage extends StatefulWidget {
  const NotificationSourcesPage({
    super.key,
    this.friends,
    this.trainer,
    this.showTrainerNotifications = trainerPublicAccessEnabled,
    required this.onStart,
    this.onReadChanged,
  });
  final FriendCommentInboxRepository? friends;
  final TrainerInboxRepository? trainer;
  final bool showTrainerNotifications;
  final Future<void> Function(WorkoutRecord) onStart;
  final VoidCallback? onReadChanged;
  @override
  State<NotificationSourcesPage> createState() =>
      _NotificationSourcesPageState();
}

class _NotificationSourcesPageState extends State<NotificationSourcesPage>
    with WidgetsBindingObserver {
  int friends = 0, trainer = 0, generation = 0;
  String? error;
  StreamSubscription<void>? auth;
  String tr(String ja, String en) => label(context, ja, en);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth = widget.trainer?.authChanges.listen((_) {
      friends = trainer = 0;
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final current = ++generation;
    final errors = <String>[];
    await Future.wait([
      () async {
        try {
          final count = await widget.friends?.unreadCount() ?? 0;
          if (mounted && current == generation) setState(() => friends = count);
        } catch (_) {
          errors.add('friends');
        }
      }(),
      if (widget.showTrainerNotifications)
        () async {
          try {
            final count = await widget.trainer?.unreadCount() ?? 0;
            if (mounted && current == generation) {
              setState(() => trainer = count);
            }
          } catch (_) {
            errors.add('trainer');
          }
        }(),
    ]);
    if (mounted && current == generation) {
      setState(
        () => error = errors.isEmpty
            ? null
            : tr(
                '未読件数を取得できませんでした。下に引いて再試行してください。',
                'Could not load unread counts. Pull down to retry.',
              ),
      );
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await refresh();
    widget.onReadChanged?.call();
  }

  @override
  void dispose() {
    generation++;
    auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('通知', 'Notifications'))),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null) Text(error!),
          Card(
            child: ListTile(
              key: const Key('friendNotificationSource'),
              leading: const Icon(Icons.people_outline),
              title: Text(tr('フレンドから', 'From friends')),
              subtitle: Text(
                tr('あなたの共有トレーニングへのコメント', 'Comments on your shared workouts'),
              ),
              trailing: Text(tr('未読 $friends', '$friends unread')),
              onTap: () => open(
                FriendCommentInboxPage(
                  repository: widget.friends,
                  onReadChanged: widget.onReadChanged,
                ),
              ),
            ),
          ),
          if (widget.showTrainerNotifications)
            Card(
              child: ListTile(
                key: const Key('trainerNotificationSource'),
                leading: const Icon(Icons.fitness_center),
                title: Text(tr('トレーナーから', 'From your trainer')),
                subtitle: Text(tr('メニューとコメント', 'Menus and comments')),
                trailing: Text(tr('未読 $trainer', '$trainer unread')),
                onTap: () => open(
                  TrainerInboxPage(
                    repository: widget.trainer,
                    onStart: widget.onStart,
                    onReadChanged: widget.onReadChanged,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class FriendCommentInboxPage extends StatefulWidget {
  const FriendCommentInboxPage({
    super.key,
    this.repository,
    this.onReadChanged,
  });
  final FriendCommentInboxRepository? repository;
  final VoidCallback? onReadChanged;
  @override
  State<FriendCommentInboxPage> createState() => _FriendCommentInboxPageState();
}

class _FriendCommentInboxPageState extends State<FriendCommentInboxPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  int generation = 0;
  String? error;
  StreamSubscription<dynamic>? auth;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth = widget.repository?.friends.client.auth.onAuthStateChange.listen((_) {
      rows = [];
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final current = ++generation;
    final owner = widget.repository?.userId;
    try {
      final result =
          await widget.repository?.comments() ?? <Map<String, dynamic>>[];
      if (mounted &&
          current == generation &&
          owner == widget.repository?.userId) {
        setState(() {
          rows = result;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(() {
          rows = [];
          loading = false;
          error = label(
            context,
            '通知を読み込めませんでした。下に引いて再試行してください。',
            'Could not load notifications. Pull down to retry.',
          );
        });
      }
    }
  }

  Future<void> open(Map<String, dynamic> row) async {
    final repo = widget.repository!;
    final owner = repo.userId;
    if (owner == null) return;
    try {
      final valid = (await repo.comments()).any(
        (latest) => latest['id'] == row['id'],
      );
      if (!mounted || repo.userId != owner) return;
      if (!valid) {
        await refresh();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FriendActivityPage(
            repository: repo.friends,
            owner: owner,
            selectedId: row['workout_id'] as String,
            commentNotificationId: row['id'] as String,
            notificationRepository: repo,
            onCommentViewed: () async {
              try {
                if (await repo.markRead(row['id'] as String)) {
                  widget.onReadChanged?.call();
                }
              } catch (_) {
                if (mounted) {
                  setState(
                    () => error = label(
                      context,
                      '既読状態を保存できませんでした。再試行してください。',
                      'Could not save read status. Retry.',
                    ),
                  );
                }
              }
            },
          ),
        ),
      );
      if (mounted) await refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = label(
            context,
            'コメントを開けませんでした。再試行してください。',
            'Could not open comment. Retry.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    generation++;
    auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(label(context, 'フレンドから', 'From friends'))),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (!loading && rows.isEmpty && error == null)
            Text(
              label(context, 'コメント通知はまだありません', 'No comment notifications yet'),
            ),
          for (final row in rows)
            Card(
              child: ListTile(
                key: ValueKey('friendCommentNotification_${row['id']}'),
                leading: Icon(
                  row['read'] == true
                      ? Icons.chat_bubble_outline
                      : Icons.mark_chat_unread_outlined,
                ),
                title: Text(row['friend_name'] as String),
                subtitle: Text('${row['body']}\n${row['created_at']}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(row),
              ),
            ),
        ],
      ),
    ),
  );
}
