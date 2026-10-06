import 'dart:async';

import 'package:flutter/material.dart';

import 'friend_avatar.dart';
import 'friend_like_inbox.dart';

class FriendLikeInboxPage extends StatefulWidget {
  const FriendLikeInboxPage({
    super.key,
    required this.repository,
    this.visibleClientIds,
    this.onOpenWorkout,
    this.onReadChanged,
  });
  final FriendLikeInboxRepository repository;
  final Set<String>? Function()? visibleClientIds;
  final Future<bool> Function(String clientId)? onOpenWorkout;
  final VoidCallback? onReadChanged;
  @override
  State<FriendLikeInboxPage> createState() => _FriendLikeInboxPageState();
}

class _FriendLikeInboxPageState extends State<FriendLikeInboxPage>
    with WidgetsBindingObserver {
  late final String? _owner = widget.repository.userId;
  StreamSubscription<dynamic>? _auth;
  Timer? _timer;
  List<Map<String, dynamic>> _rows = [];
  int _generation = 0;
  bool _active = true, _loading = true, _opening = false;
  String? _error;
  bool get _sameOwner => _owner != null && widget.repository.userId == _owner;
  String tr(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : ja;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.repository.friends.client.auth.onAuthStateChange.listen((_) {
      if (mounted) unawaited(refresh());
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active) unawaited(refresh());
    });
    unawaited(refresh());
  }

  void _clear() {
    if (mounted) {
      setState(() {
        _rows = [];
        _error = null;
        _loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    _clear();
    if (_active) unawaited(refresh());
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    _clear();
    if (!_sameOwner || !_active) return;
    setState(() => _loading = true);
    try {
      final rows = await widget.repository.notifications(
        clientIds: widget.visibleClientIds?.call(),
      );
      if (mounted && generation == _generation && _sameOwner && _active) {
        setState(() => _rows = rows);
      }
    } catch (_) {
      if (mounted && generation == _generation && _sameOwner && _active) {
        setState(
          () => _error = tr(
            '通知を読み込めませんでした。下に引いて再試行してください。',
            'Could not load notifications. Pull down to retry.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> open(Map<String, dynamic> row) async {
    if (_opening || !_sameOwner) return;
    _opening = true;
    try {
      final current = await widget.repository.resolve(
        row['id'] as String,
        clientIds: widget.visibleClientIds?.call(),
      );
      if (!mounted || !_sameOwner) return;
      if (current == null) {
        await refresh();
        return;
      }
      final opened =
          await widget.onOpenWorkout?.call(current['client_id'] as String) ??
          false;
      if (!mounted || !_sameOwner) return;
      if (opened) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_sameOwner) return;
        await widget.repository.markRead(
          current['id'] as String,
          clientIds: widget.visibleClientIds?.call(),
        );
        widget.onReadChanged?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('この記録は現在表示できません', 'This workout is no longer available'),
            ),
          ),
        );
      }
      if (mounted) await refresh();
    } catch (_) {
      if (mounted && _sameOwner) {
        _clear();
        setState(
          () => _error = tr(
            '通知を開けませんでした。下に引いて再試行してください。',
            'Could not open notification. Pull down to retry.',
          ),
        );
      }
    } finally {
      _opening = false;
    }
  }

  String timestamp(Map<String, dynamic> row) {
    final date = DateTime.parse(row['created_at'] as String).toLocal();
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatShortDate(date)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _auth?.cancel();
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
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_loading && _rows.isEmpty && _error == null)
            Text(tr('いいね通知はまだありません', 'No like notifications yet')),
          for (final row in _rows)
            Card(
              child: ListTile(
                key: ValueKey('friendLikeNotification_${row['id']}'),
                leading: FriendAvatar(
                  repository: widget.repository.friends,
                  path: row['avatar_path'] as String?,
                  radius: 20,
                ),
                title: Text(
                  tr(
                    '${row['display_name'] ?? 'フレンド'}さんがあなたのトレーニングにいいねしました',
                    '${row['display_name'] ?? 'A friend'} liked your workout',
                  ),
                ),
                subtitle: Text(timestamp(row)),
                trailing: row['read'] == true
                    ? null
                    : const Icon(
                        Icons.circle,
                        color: Color(0xFFC7F36B),
                        size: 12,
                      ),
                onTap: () => open(row),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            tr('既読はこの端末に保存されます', 'Read status is saved on this device'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
