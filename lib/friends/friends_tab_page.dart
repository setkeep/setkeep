import 'package:flutter/material.dart';

import '../main.dart' show WorkoutRecord;
import 'friends_repository.dart';
import 'friends_ui.dart';

/// Reuses the same authorized feed and management/detail routes as Home.
class FriendsTabPage extends StatelessWidget {
  const FriendsTabPage({
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(label(context, 'フレンド', 'Friends')),
    ),
    body: RefreshIndicator(
      onRefresh: FriendsRefresh.refresh,
      child: ListView(
        key: const PageStorageKey('friendsTabScroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          FriendsSection(
            key: ValueKey(repository?.userId ?? configuredFriends()?.userId),
            repository: repository,
            history: history,
            historyReady: historyReady,
            refreshToken: refreshToken,
          ),
        ],
      ),
    ),
  );
}
