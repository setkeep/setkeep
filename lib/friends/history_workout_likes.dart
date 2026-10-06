import 'dart:async';

import 'package:flutter/material.dart';

import 'friends_repository.dart';
import 'workout_comments.dart' show LikeAvatarStrip;

/// Reads the existing shared session without publishing or creating a record.
class HistoryWorkoutLikes extends StatefulWidget {
  const HistoryWorkoutLikes({
    super.key,
    required this.repository,
    required this.clientId,
  });
  final FriendsRepository repository;
  final String clientId;
  @override
  State<HistoryWorkoutLikes> createState() => HistoryWorkoutLikesState();
}

class HistoryWorkoutLikesState extends State<HistoryWorkoutLikes>
    with WidgetsBindingObserver {
  String? _viewer() {
    try {
      return widget.repository.userId;
    } catch (_) {
      return null;
    }
  }

  late final String? _owner = _viewer();
  StreamSubscription<dynamic>? _auth;
  Timer? _timer;
  int _generation = 0;
  bool _active = true;
  bool _available = false;
  bool _failed = false;
  List<Map<String, dynamic>> _likes = [];

  bool get _sameViewer => _owner != null && _viewer() == _owner;
  bool _owned(Map<String, dynamic>? row) =>
      row != null &&
      row['id'] is String &&
      (row['id'] as String).isNotEmpty &&
      row['user_id'] == _owner &&
      row['client_id'] == widget.clientId;

  void _listen() {
    _auth?.cancel();
    _auth = widget.repository.client.auth.onAuthStateChange.listen((_) {
      if (mounted) unawaited(refresh());
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_active) unawaited(refresh());
    });
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(HistoryWorkoutLikes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.clientId != widget.clientId) {
      _listen();
      unawaited(refresh());
    }
  }

  void _clear() {
    if (mounted) {
      setState(() {
        _available = false;
        _failed = false;
        _likes = [];
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
    if (!_active || !_sameViewer) return;
    final repository = widget.repository;
    final clientId = widget.clientId;
    try {
      final row = await repository.workoutForRecord(clientId);
      if (!mounted ||
          generation != _generation ||
          !_sameViewer ||
          !_owned(row)) {
        return;
      }
      final id = row!['id'] as String;
      final likes = await repository.likerAvatars(id);
      if (!mounted || generation != _generation || !_sameViewer || !_active) {
        return;
      }
      final current = await repository.workoutForRecord(clientId);
      if (!mounted ||
          generation != _generation ||
          !_sameViewer ||
          !_active ||
          !_owned(current) ||
          current!['id'] != id) {
        return;
      }
      final unique = <String, Map<String, dynamic>>{};
      for (final like in likes) {
        final author = like['user_id'];
        if (author is String && author.isNotEmpty) {
          unique.putIfAbsent(author, () => like);
        }
      }
      setState(() {
        _likes = unique.values.toList();
        _available = true;
      });
    } catch (_) {
      if (mounted && generation == _generation && _sameViewer && _active) {
        setState(() => _failed = true);
      }
    }
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
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context).languageCode == 'en';
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          en
              ? 'Could not load likes. Pull down to retry.'
              : 'いいねを読み込めませんでした。下に引いて再試行してください。',
        ),
      );
    }
    if (!_available || !_sameViewer) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const Key('historyWorkoutLikes'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  size: 20,
                  color: Color(0xFF8BB331),
                ),
                const SizedBox(width: 6),
                Text(
                  '${en ? 'Likes' : 'いいね'} ${_likes.length}',
                  key: const Key('historyWorkoutLikeCount'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            LikeAvatarStrip(repository: widget.repository, likes: _likes),
          ],
        ),
      ),
    );
  }
}
