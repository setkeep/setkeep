import 'dart:async';

import 'package:share_plus/share_plus.dart';

import '../profile/profile_preference.dart';
import 'friend_avatar.dart';
import 'friend_invite.dart';
import 'friend_comment_inbox.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../main.dart' show WorkoutRecord, BodyMapPage;
import 'friends_repository.dart';

FriendsRepository? configuredFriends() =>
    SupabaseConfig.initialized &&
        Supabase.instance.client.auth.currentUser != null
    ? FriendsRepository(Supabase.instance.client)
    : null;

WorkoutRecord socialWorkout(Map<String, dynamic> row) =>
    WorkoutRecord.fromJson({
      'date': row['performed_at'],
      'durationSeconds': row['duration_seconds'],
      'sets': row['sets'],
    });
String friendName(Map<String, dynamic> row) =>
    (row['friend_profiles'] as Map?)?['display_name'] as String? ?? 'Friend';
String dateLabel(WorkoutRecord w) =>
    '${w.date.toLocal().year}/${w.date.toLocal().month}/${w.date.toLocal().day}';
bool english(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'en';
String label(BuildContext context, String ja, String en) =>
    english(context) ? en : ja;

List<Map<String, dynamic>> latestFriendWorkouts(
  List<Map<String, dynamic>> rows,
) {
  final sorted = [...rows]
    ..sort(
      (a, b) =>
          DateTime.parse(b['performed_at'] as String)
              .compareTo(DateTime.parse(a['performed_at'] as String)),
    );
  final seen = <String>{};
  return [
    for (final row in sorted)
      if (seen.add(row['user_id'] as String)) row,
  ];
}

class FriendsRefresh {
  static final _listeners = <Future<void> Function()>{};
  static void listen(Future<void> Function() callback) =>
      _listeners.add(callback);
  static void unlisten(Future<void> Function() callback) =>
      _listeners.remove(callback);
  static Future<void> refresh() async =>
      Future.wait(_listeners.map((callback) => callback()));
}

class FriendsSection extends StatefulWidget {
  const FriendsSection({
    super.key,
    required this.history,
    this.repository,
    this.historyReady = true,
    this.refreshToken = 0,
  });
  final List<WorkoutRecord> history;
  final FriendsRepository? repository;
  final bool historyReady;
  final int refreshToken;
  @override
  State<FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends State<FriendsSection>
    with WidgetsBindingObserver {
  late final FriendsRepository? repo = widget.repository ?? configuredFriends();
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  bool failed = false;
  int refreshGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FriendsRefresh._listeners.add(refresh);
    ProfilePreference.changes.addListener(_profileChanged);
    refresh();
  }

  void _profileChanged() => refresh();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FriendsRefresh._listeners.remove(refresh);
    ProfilePreference.changes.removeListener(_profileChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(FriendsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history ||
        oldWidget.historyReady != widget.historyReady ||
        oldWidget.refreshToken != widget.refreshToken) {
      refresh();
    }
  }

  Future<void> refresh() async {
    final generation = ++refreshGeneration;
    try {
      await repo?.ensureProfile(await ProfilePreference.load());
      if (widget.historyReady) {
        await repo?.publish(widget.history.map((w) => w.toJson()).toList());
      }
      final result = await repo?.feed() ?? <Map<String, dynamic>>[];
      if (mounted && generation == refreshGeneration) {
        setState(() {
          rows = latestFriendWorkouts(result);
          failed = false;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == refreshGeneration) {
        setState(() {
          rows = [];
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label(context, 'フレンドのトレーニング', 'Friends’ workouts'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: label(context, 'フレンド・公開範囲', 'Friends & privacy'),
            icon: const Icon(Icons.people_outline),
            onPressed: repo == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FriendsSettingsPage(
                          repository: repo!,
                          history: widget.history,
                        ),
                      ),
                    );
                    await refresh();
                  },
          ),
        ],
      ),
      if (loading)
        const LinearProgressIndicator()
      else if (failed)
        TextButton(
          onPressed: refresh,
          child: Text(
            label(context, '読み込めませんでした。再試行', 'Could not load. Retry'),
          ),
        )
      else if (rows.isEmpty)
        Text(
          label(
            context,
            repo == null ? 'ログインするとフレンドを利用できます' : 'フレンドの共有トレーニングはまだありません',
            repo == null ? 'Sign in to use friends' : 'No shared workouts yet',
          ),
        ),
      for (final row in rows)
        Card(
          child: ListTile(
            leading: FriendAvatar(
              repository: repo,
              path: (row['friend_profiles'] as Map?)?['avatar_path'] as String?,
            ),
            title: Text(friendName(row)),
            subtitle: Text(
              '${dateLabel(socialWorkout(row))} · ${socialWorkout(row).summaryLabel}\n${label(context, 'コメント', 'Comments')} ${(row['friend_comments'] as List?)?.length ?? 0}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FriendActivityPage(
                    repository: repo!,
                    owner: row['user_id'] as String,
                    selectedId: row['id'] as String,
                  ),
                ),
              );
              await refresh();
            },
          ),
        ),
    ],
  );
}

class FriendsSettingsPage extends StatefulWidget {
  const FriendsSettingsPage({
    super.key,
    required this.repository,
    required this.history,
    this.initialInvite,
  });
  final FriendsRepository repository;
  final List<WorkoutRecord> history;
  final String? initialInvite;
  @override
  State<FriendsSettingsPage> createState() => _FriendsSettingsPageState();
}

class _FriendsSettingsPageState extends State<FriendsSettingsPage>
    with WidgetsBindingObserver {
  final code = TextEditingController();
  String visibility = 'private';
  String displayName = ProfilePreference.defaultDisplayName;
  String? invite;
  List<Map<String, dynamic>> connections = [];
  bool busy = false;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    code.text = widget.initialInvite ?? '';
    WidgetsBinding.instance.addObserver(this);
    run(load);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) run(load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final profile = await widget.repository.ensureProfile(
      await ProfilePreference.load(),
    );
    final items = await widget.repository.connections();
    if (!mounted) return;
    setState(() {
      displayName = profile['display_name'] as String;
      visibility = profile['visibility'] as String? ?? 'private';
      invite = profile['invite_code'] as String?;
      connections = items;
      loaded = true;
    });
  }

  void message(String ja, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(label(context, ja, en))));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      message(
        '操作できませんでした。接続・入力を確認して再試行してください',
        'Could not complete. Check connection and input, then retry',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool?> consent(String ja, String en) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label(context, ja, en)),
      content: Text(
        label(
          context,
          '記録を共有すると、過去と今後のトレーニングの日時・種目・セット・所要時間が、承認済みのフレンド全員に公開されます。場所・メモ・体重は共有しません。',
          'Sharing makes past and future workout dates, exercises, sets and duration visible to all approved friends. Locations, notes and body weight stay private.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(label(context, 'キャンセル', 'Cancel')),
        ),
        if (visibility == 'private')
          TextButton(
            key: const Key('connectWithoutSharing'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              label(context, '記録を共有せず続ける', 'Continue without sharing'),
            ),
          ),
        FilledButton(
          key: const Key('consentFriendsSharing'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            label(context, '記録を共有して続ける', 'Continue and share workouts'),
          ),
        ),
      ],
    ),
  );
  Future<void> connect(
    Future<void> Function() action,
    String ja,
    String en,
  ) async {
    final share = await consent(ja, en);
    if (share == null || !mounted) return;
    await run(() async {
      await action();
      if (share && visibility == 'private') {
        await widget.repository.saveProfile(displayName, 'friends');
        visibility = 'friends';
      }
      if (visibility == 'friends') {
        await widget.repository.publish(
          widget.history.map((w) => w.toJson()).toList(),
        );
      }
      await load();
    });
  }

  Future<void> request() async {
    final value = FriendInviteLink.parse(code.text);
    if (value == null) {
      message('有効な招待コード・リンクを入力してください', 'Enter a valid invite code or link');
      return;
    }
    if (value == invite) {
      message('自分の招待コードは使えません', 'You cannot use your own invite code');
      return;
    }
    Map<String, dynamic>? preview;
    if (widget.repository.supportsProfileInvites) {
      await run(() async {
        preview = await widget.repository.invitePreview(value);
      });
      if (preview == null || !mounted) return;
    }
    if (preview?['status'] != null) {
      message(
        'この相手とは申請中またはフレンド登録済みです',
        'You already have a pending request or connection',
      );
      return;
    }
    final friend = preview?['display_name'] as String?;
    await connect(
      () async {
        await widget.repository.request(value);
        code.clear();
      },
      friend == null ? '招待コードの相手にフレンド申請' : '$friend にフレンド申請',
      friend == null
          ? 'Send a friend request using this invite code'
          : 'Send a friend request to $friend',
    );
  }

  Future<void> sharing() async {
    if (visibility == 'private') {
      final share = await consent(
        '承認済みフレンドに記録を共有',
        'Share workouts with approved friends',
      );
      if (share != true || !mounted) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(label(context, '記録を非公開にする', 'Make workouts private')),
          content: Text(
            label(
              context,
              '承認済みフレンドもトレーニングとリアクションを閲覧できなくなります。',
              'Approved friends will lose access to workouts and reactions.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(label(context, 'キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label(context, '非公開にする', 'Make private')),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    await run(() async {
      await widget.repository.saveProfile(
        displayName,
        visibility == 'private' ? 'friends' : 'private',
      );
      await widget.repository.publish(
        widget.history.map((w) => w.toJson()).toList(),
      );
      await load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(label(context, 'フレンド・公開範囲', 'Friends & privacy')),
    ),
    body: RefreshIndicator(
      onRefresh: () => run(load),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          Text(
            displayName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            label(
              context,
              widget.repository.supportsProfileInvites
                  ? '表示名と写真はマイページで変更できます'
                  : '表示名はマイページで変更できます',
              widget.repository.supportsProfileInvites
                  ? 'Edit your name and photo in My Page'
                  : 'Edit your name in My Page',
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(label(context, '記録の公開範囲', 'Workout privacy')),
              subtitle: Text(
                visibility == 'friends'
                    ? label(context, '承認済みフレンドのみ', 'Approved friends only')
                    : label(context, '非公開', 'Private'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy || !loaded ? null : sharing,
            ),
          ),
          const SizedBox(height: 16),
          if (invite != null) ...[
            SelectableText(
              '${label(context, 'あなたの招待コード', 'Your invite code')}\n$invite',
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final box = context.findRenderObject() as RenderBox?;
                          await SharePlus.instance.share(
                            ShareParams(
                              text:
                                  'SETKEEP\n${FriendInviteLink.url(invite!)}\n${label(context, '招待コード', 'Invite code')}: $invite',
                              sharePositionOrigin: box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size,
                            ),
                          );
                        },
                  icon: const Icon(Icons.ios_share),
                  label: Text(label(context, '招待を共有', 'Share invite')),
                ),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: invite!)),
                  icon: const Icon(Icons.copy),
                  label: Text(label(context, 'コピー', 'Copy')),
                ),
              ],
            ),
            TextField(
              controller: code,
              decoration: InputDecoration(
                labelText: label(
                  context,
                  '相手の招待コード・リンク',
                  'Friend’s invite code or link',
                ),
              ),
            ),
            FilledButton(
              onPressed: busy ? null : request,
              child: Text(label(context, 'フレンド申請', 'Send request')),
            ),
          ],
          for (final item in connections)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ListTile(
                leading: FriendAvatar(
                  repository: widget.repository,
                  path: item['avatar_path'] as String?,
                ),
                title: Text(item['friend_name'] as String),
                subtitle: Text(
                  item['status'] == 'accepted'
                      ? label(context, '承認済みフレンド', 'Approved friend')
                      : label(context, '承認待ち', 'Pending request'),
                ),
                trailing: Wrap(
                  children: [
                    if (item['status'] == 'pending' &&
                        item['recipient'] == widget.repository.userId)
                      IconButton(
                        tooltip: label(context, '承認', 'Accept'),
                        onPressed: busy
                            ? null
                            : () => connect(
                                () => widget.repository.accept(
                                  item['id'] as String,
                                ),
                                '${item['friend_name']} の申請を承認',
                                'Accept ${item['friend_name']}',
                              ),
                        icon: const Icon(Icons.check),
                      ),
                    IconButton(
                      tooltip: label(context, '解除・申請取消', 'Remove / cancel'),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await widget.repository.remove(
                                item['id'] as String,
                              );
                              await load();
                            }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class FriendActivityPage extends StatefulWidget {
  const FriendActivityPage({
    super.key,
    required this.repository,
    required this.owner,
    required this.selectedId,
    this.commentNotificationId,
    this.notificationRepository,
    this.onCommentViewed,
  });
  final FriendsRepository repository;
  final String owner;
  final String selectedId;
  final String? commentNotificationId;
  final FriendCommentInboxRepository? notificationRepository;
  final Future<void> Function()? onCommentViewed;
  @override
  State<FriendActivityPage> createState() => _FriendActivityPageState();
}

class _FriendActivityPageState extends State<FriendActivityPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> comments = [];
  final text = TextEditingController();
  bool busy = false;
  Map<String, dynamic>? selected;
  final _commentKey = GlobalKey();
  late final String _viewer = widget.repository.userId;
  StreamSubscription<dynamic>? _auth;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.repository.client.auth.onAuthStateChange.listen(
      (_) => run(load),
    );
    run(load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) run(load);
  }

  Future<void> load() async {
    if (widget.repository.userId != _viewer) {
      if (mounted) {
        setState(() {
          rows = [];
          comments = [];
          selected = null;
        });
      }
      return;
    }
    if (widget.commentNotificationId != null) {
      final notifications =
          await (widget.notificationRepository ??
                  FriendCommentInboxRepository(widget.repository))
              .comments();
      if (!notifications.any(
        (row) => row['id'] == widget.commentNotificationId,
      )) {
        if (mounted) {
          setState(() {
            rows = [];
            comments = [];
            selected = null;
          });
        }
        return;
      }
    }
    final result = await widget.repository.feed(owner: widget.owner);
    final matches = result.where(
      (r) => r['id'] == (selected?['id'] ?? widget.selectedId),
    );
    final current = matches.isEmpty ? null : matches.first;
    final messages = current == null
        ? <Map<String, dynamic>>[]
        : await widget.repository.comments(current['id'] as String);
    if (mounted) {
      setState(() {
        rows = result;
        selected = current;
        comments = messages;
      });
      if (widget.commentNotificationId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _commentKey.currentContext;
          if (mounted && target != null) {
            Scrollable.ensureVisible(target);
            final callback = widget.onCommentViewed;
            if (callback != null) unawaited(callback());
          }
        });
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          rows = [];
          selected = null;
          comments = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label(
                context,
                '読み込み・操作に失敗しました。再試行してください',
                'Could not load or complete action. Retry',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = selected;
    final workout = row == null ? null : socialWorkout(row);
    final likes = (row?['friend_likes'] as List?) ?? [];
    final liked = likes.any((l) => l['user_id'] == widget.repository.userId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          rows.isEmpty
              ? label(context, 'フレンド', 'Friend')
              : friendName(rows.first),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => run(load),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (!busy && rows.isEmpty)
              Text(label(context, '公開トレーニングはありません', 'No visible workouts')),
            if (rows.isNotEmpty)
              FriendAvatar(
                repository: widget.repository,
                path:
                    (rows.first['friend_profiles'] as Map?)?['avatar_path']
                        as String?,
                radius: 28,
              ),
            if (rows.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.accessibility_new),
                label: Text(label(context, '筋肉ヒートマップ', 'Muscle heatmap')),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(friendName(rows.first))),
                      body: BodyMapPage(
                        history: rows.map(socialWorkout).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            for (final r in rows)
              ListTile(
                selected: r['id'] == row?['id'],
                title: Text(dateLabel(socialWorkout(r))),
                subtitle: Text(socialWorkout(r).summaryLabel),
                onTap: busy
                    ? null
                    : () => run(() async {
                        selected = r;
                        await load();
                      }),
              ),
            if (workout != null) ...[
              const Divider(),
              Text(
                '${dateLabel(workout)} · ${workout.summaryLabel}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final group in workout.exerciseGroups.values) ...[
                Text(
                  group.first.exerciseName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final set in group) Text(set.displaySummary),
              ],
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.repository.like(
                          row!['id'] as String,
                          !liked,
                        );
                        await load();
                      }),
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? const Color(0xFFC7F36B) : null,
                ),
                label: Text('${label(context, 'いいね', 'Like')} ${likes.length}'),
              ),
              for (final message in comments)
                ListTile(
                  key: message['id'] == widget.commentNotificationId
                      ? _commentKey
                      : null,
                  title: Text(message['body'] as String),
                  subtitle: Text(
                    message['user_id'] == widget.repository.userId
                        ? label(context, 'あなた', 'You')
                        : label(context, 'フレンド', 'Friend'),
                  ),
                  trailing: message['user_id'] != widget.repository.userId
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  await widget.repository.deleteComment(
                                    message['id'] as String,
                                  );
                                  await load();
                                }),
                        ),
                ),
              TextField(
                controller: text,
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: label(context, '短いコメント', 'Short comment'),
                ),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.repository.comment(
                          row!['id'] as String,
                          text.text,
                        );
                        text.clear();
                        await load();
                      }),
                child: Text(label(context, 'コメント', 'Comment')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
