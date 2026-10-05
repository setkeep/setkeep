import '../design/workout_month_calendar.dart';

import 'dart:async';

import 'package:share_plus/share_plus.dart';

import '../profile/profile_preference.dart';
import 'friend_avatar.dart';
import 'friend_invite.dart';
import 'friend_comment_inbox.dart';
import 'workout_comments.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../main.dart'
    show
        WorkoutRecord,
        BodyMapPage,
        LegalConsentPreference,
        ExerciseRecordTypeUi;
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
      await repo?.ensureProfile(
        await ProfilePreference.load(owner: repo?.userId),
      );
      if (repo?.supportsMutualFriendSharing == true &&
          await LegalConsentPreference.load()) {
        await repo!.acknowledgeMutualSharing();
      }
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
            tooltip: label(context, 'フレンド', 'Friends'),
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
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(dateLabel(socialWorkout(row))),
                  Text(
                    '${socialWorkout(row).exerciseNames.length} ${label(context, '種目', 'exercises')}',
                  ),
                  Text(
                    '${socialWorkout(row).sets.where((set) => set.recordType.usesSets).length} ${label(context, 'セット', 'sets')}',
                  ),
                  for (final metric in socialWorkout(
                    row,
                  ).summaryLabel.split(' ・ '))
                    if (metric.endsWith(' kg') ||
                        metric == socialWorkout(row).durationLabel)
                      Text(metric),
                  Text(
                    '${label(context, 'コメント', 'Comments')} ${(row['friend_comments'] as List?)?.length ?? 0}',
                  ),
                ],
              ),
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
  late final String _viewer = widget.repository.userId;
  StreamSubscription<dynamic>? _auth;
  bool get _sameViewer {
    try {
      return widget.repository.userId == _viewer;
    } catch (_) {
      return false;
    }
  }

  String displayName = ProfilePreference.defaultDisplayName;
  String? invite;
  Map<String, dynamic>? preview;
  List<Map<String, dynamic>> connections = [];
  bool busy = false;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    code.text = widget.initialInvite ?? '';
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.repository.client.auth.onAuthStateChange.listen(
      (_) => run(load),
    );
    run(load);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) run(load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!_sameViewer) throw StateError('Account changed');
    final profile = await widget.repository.ensureProfile(
      await ProfilePreference.load(owner: widget.repository.userId),
    );
    final items = await widget.repository.connections();
    final ownCode = await widget.repository.myInviteCode();
    if (!_sameViewer) throw StateError('Account changed');
    if (!mounted) return;
    setState(() {
      displayName = profile['display_name'] as String;
      invite = ownCode;
      connections = items;
      loaded = true;
    });
    if (widget.initialInvite != null &&
        preview == null &&
        widget.repository.supportsProfileInvites) {
      final result = await widget.repository.invitePreview(
        widget.initialInvite!,
      );
      if (!_sameViewer) throw StateError('Account changed');
      if (mounted) setState(() => preview = result);
    }
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
      if (!_sameViewer) throw StateError('Account changed');
      await action();
    } catch (_) {
      if (!_sameViewer && mounted) {
        setState(() {
          invite = null;
          connections = [];
          preview = null;
          loaded = false;
        });
      }
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
          '相互承認したフレンドと、過去と今後のトレーニングの日時・種目・セット・所要時間を共有します。場所・メモ・体重は共有しません。',
          'Mutually approved friends share past and future workout dates, exercises, sets and duration. Locations, notes and body weight stay private.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(label(context, 'キャンセル', 'Cancel')),
        ),
        FilledButton(
          key: const Key('consentFriendsSharing'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(label(context, '確認して続ける', 'Confirm and continue')),
        ),
      ],
    ),
  );
  Future<void> connect(
    Future<void> Function() action,
    String ja,
    String en,
  ) async {
    if (await consent(ja, en) != true || !mounted) return;
    await run(() async {
      if (widget.repository.supportsMutualFriendSharing) {
        await widget.repository.acknowledgeMutualSharing();
      } else {
        // Older servers still enforce their original per-owner sharing choice.
        // This explicit confirmation grants only the current owner's sharing.
        await widget.repository.saveProfile(displayName, 'friends');
      }
      if (!_sameViewer) throw StateError('Account changed');
      await action();
      await widget.repository.publish(
        widget.history.map((w) => w.toJson()).toList(),
      );
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
    Map<String, dynamic>? target;
    if (widget.repository.supportsProfileInvites) {
      await run(() async {
        target = await widget.repository.invitePreview(value);
      });
      if (target == null || !mounted) return;
    }
    if (target?['status'] != null) {
      message(
        'この相手とは申請中またはフレンド登録済みです',
        'You already have a pending request or connection',
      );
      return;
    }
    final friend = target?['display_name'] as String?;
    await connect(
      () async {
        await widget.repository.request(value);
        await FriendInviteStore.consume(value);
        code.clear();
        if (mounted) setState(() => preview = null);
      },
      friend == null ? '招待コードの相手にフレンド申請' : '$friend にフレンド申請',
      friend == null
          ? 'Send a friend request using this invite code'
          : 'Send a friend request to $friend',
    );
  }

  Future<void> remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label(context, 'フレンド解除・申請取消', 'Remove / cancel')),
        content: Text(
          label(
            context,
            '${item['friend_name']} とのつながりを解除しますか？',
            'Remove your connection with ${item['friend_name']}?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(label(context, 'キャンセル', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label(context, '解除する', 'Remove')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run(() async {
        await widget.repository.remove(item['id'] as String);
        await load();
      });
    }
  }

  Widget card({required Widget child, Color? color}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
  Widget heading(String ja, String en) => Text(
    label(context, ja, en),
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
  );
  @override
  Widget build(BuildContext context) {
    final shortCode = invite != null && invite!.length == 8;
    final approved = connections
        .where((c) => c['status'] == 'accepted')
        .toList();
    final pending = connections
        .where((c) => c['status'] != 'accepted')
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F0),
      appBar: AppBar(
        title: Text(
          label(context, 'フレンド', 'Friends'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => run(load),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              card(
                color: const Color(0xFFC7F36B),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading('フレンドを招待', 'Invite a friend'),
                    const SizedBox(height: 8),
                    Text(
                      label(
                        context,
                        'リンクを送って、記録を共有',
                        'Send a link and share workouts',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF101820),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: busy || invite == null
                            ? null
                            : () async {
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                try {
                                  await SharePlus.instance.share(
                                    ShareParams(
                                      text:
                                          'SETKEEP\n${FriendInviteLink.url(invite!)}',
                                      sharePositionOrigin: box == null
                                          ? null
                                          : box.localToGlobal(Offset.zero) &
                                                box.size,
                                    ),
                                  );
                                } catch (_) {
                                  message(
                                    '招待を共有できませんでした',
                                    'Could not share invite',
                                  );
                                }
                              },
                        icon: const Icon(Icons.ios_share),
                        label: Text(
                          label(context, '招待リンクを共有', 'Share invite link'),
                        ),
                      ),
                    ),
                    if (!FriendInviteLink.supportsPublicLinks) ...[
                      const SizedBox(height: 8),
                      Text(
                        label(
                          context,
                          '現在はインストール済みのアプリで開くリンクです。HTTPS招待ページは準備中です。',
                          'This link opens an installed app. The HTTPS invite page is being prepared.',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const Divider(height: 28),
                    Text(label(context, 'あなたの招待コード', 'Your invite code')),
                    if (shortCode)
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SelectableText(
                            invite!,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: invite!),
                                    );
                                    message('コピーしました', 'Copied');
                                  },
                            icon: const Icon(Icons.copy),
                            label: Text(label(context, 'コピー', 'Copy')),
                          ),
                        ],
                      )
                    else
                      Text(
                        label(
                          context,
                          '短い招待コードはサーバー更新後に利用できます。リンクで招待してください。',
                          'Short invite codes need the server update. Share the link instead.',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading('コードから追加', 'Add by code'),
                    const SizedBox(height: 8),
                    Text(label(context, '相手の招待コード', 'Friend’s invite code')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      enabled: !busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() => preview = null),
                      decoration: InputDecoration(
                        hintText: label(
                          context,
                          '招待コード・リンクを入力',
                          'Enter invite code or link',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (preview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          label(
                            context,
                            '招待相手：${preview!['display_name']}',
                            'Invited by ${preview!['display_name']}',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF101820),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: busy || !loaded ? null : request,
                        child: Text(label(context, 'フレンド申請', 'Send request')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final group in [pending, approved])
                if (group.isNotEmpty || identical(group, approved)) ...[
                  card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading(
                          identical(group, approved)
                              ? 'フレンド ${group.length}'
                              : '申請 ${group.length}',
                          identical(group, approved)
                              ? 'Friends ${group.length}'
                              : 'Requests ${group.length}',
                        ),
                        const Divider(height: 24),
                        if (group.isEmpty)
                          Text(label(context, 'フレンドはまだいません', 'No friends yet')),
                        for (final item in group)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                FriendAvatar(
                                  repository: widget.repository,
                                  path: item['avatar_path'] as String?,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['friend_name'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        label(
                                          context,
                                          item['status'] == 'accepted'
                                              ? '承認済み'
                                              : '承認待ち',
                                          item['status'] == 'accepted'
                                              ? 'Approved'
                                              : 'Pending',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item['status'] == 'pending' &&
                                    item['recipient'] ==
                                        widget.repository.userId)
                                  IconButton(
                                    tooltip: label(context, '承認', 'Accept'),
                                    icon: const Icon(Icons.check),
                                    onPressed: busy
                                        ? null
                                        : () => connect(
                                            () => widget.repository.accept(
                                              item['id'] as String,
                                            ),
                                            '${item['friend_name']} の申請を承認',
                                            'Accept ${item['friend_name']}',
                                          ),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: label(context, 'その他', 'More'),
                                  enabled: !busy,
                                  onSelected: (_) => remove(item),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text(
                                        label(
                                          context,
                                          '解除・申請取消',
                                          'Remove / cancel',
                                        ),
                                      ),
                                    ),
                                  ],
                                  icon: const Icon(Icons.more_horiz),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }
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
  bool busy = false;
  Map<String, dynamic>? selected;
  List<Map<String, dynamic>> likerPhotos = [];
  bool _notificationOpened = false;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  bool _calendarInitialized = false;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  void _moveMonth(int amount) => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + amount);
    _selectedDay = null;
    selected = null;
    comments = [];
  });
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
      (r) =>
          r['id'] ==
          (selected?['id'] ??
              (_calendarInitialized ? null : widget.selectedId)),
    );
    final current = matches.isEmpty ? null : matches.first;
    final messages = current == null
        ? <Map<String, dynamic>>[]
        : await widget.repository.comments(current['id'] as String);
    var photos = <Map<String, dynamic>>[];
    if (current != null) {
      try {
        photos = await widget.repository.likerAvatars(current['id'] as String);
      } catch (_) {}
    }
    if (widget.repository.userId != _viewer) return;
    if (mounted) {
      setState(() {
        rows = result;
        selected = current;
        comments = messages;
        likerPhotos = photos;
        if (!_calendarInitialized) {
          final date = current == null
              ? null
              : socialWorkout(current).date.toLocal();
          if (date != null) {
            _visibleMonth = DateTime(date.year, date.month);
            _selectedDay = DateTime(date.year, date.month, date.day);
          }
          _calendarInitialized = true;
        }
      });
      if (widget.commentNotificationId != null &&
          current != null &&
          !_notificationOpened) {
        _notificationOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(openComments(current));
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

  Future<void> openComments(Map<String, dynamic> row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutCommentsPage(
          repository: widget.repository,
          workoutId: row['id'] as String,
          ownerId: widget.owner,
          commentNotificationId: widget.commentNotificationId,
          notificationRepository: widget.notificationRepository,
          onCommentViewed: widget.onCommentViewed,
        ),
      ),
    );
    if (mounted) await run(load);
  }

  @override
  Widget build(BuildContext context) {
    final shownRows = _selectedDay == null
        ? <Map<String, dynamic>>[]
        : rows
              .where(
                (r) => _sameDay(socialWorkout(r).date.toLocal(), _selectedDay!),
              )
              .toList();
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
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: label(context, '前の月', 'Previous month'),
                  onPressed: busy ? null : () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    label(
                      context,
                      '${_visibleMonth.year}年 ${_visibleMonth.month}月',
                      '${_visibleMonth.year}/${_visibleMonth.month}',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: label(context, '次の月', 'Next month'),
                  onPressed: busy ? null : () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            WorkoutMonthCalendar(
              visibleMonth: _visibleMonth,
              selectedDay: _selectedDay,
              recordedDates: rows.map((r) => socialWorkout(r).date.toLocal()),
              onSelectDay: (date, _) {
                if (busy) return;
                setState(() {
                  _selectedDay = date;
                  selected = null;
                  comments = [];
                });
              },
            ),
            const SizedBox(height: 22),
            Text(
              _selectedDay == null
                  ? label(context, '日付を選択してください', 'Select a day')
                  : label(
                      context,
                      '${_selectedDay!.month}月${_selectedDay!.day}日の記録',
                      'Workouts on ${_selectedDay!.month}/${_selectedDay!.day}',
                    ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (_selectedDay != null && shownRows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    label(context, 'この日の記録はありません', 'No workouts on this day'),
                  ),
                ),
              ),
            for (final r in shownRows)
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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
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
                    label: Text(
                      '${label(context, 'いいね', 'Like')} ${likes.length}',
                    ),
                  ),
                  LikeAvatarStrip(
                    repository: widget.repository,
                    likes: likerPhotos,
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: const Key('openWorkoutComments'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  '${label(context, 'コメント', 'Comments')} ${comments.length}',
                ),
                onPressed: busy ? null : () => openComments(row!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
