import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/friends/friend_avatar_preview.dart';

import 'friend_release_feedback_test.dart'
    show ClosedFriends, PhotoClient, activity, settlePhotos;

class PhotoRoutes extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  testWidgets('rapid photo taps open one overlay and close only that overlay', (
    t,
  ) async {
    debugNetworkImageHttpClientProvider = () => PhotoClient();
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    final routes = PhotoRoutes();
    var closed = 0;
    await t.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: Scaffold(
          body: FriendProfilePhoto(
            repository: ClosedFriends()..hasPhoto = true,
            owner: 'friend',
            path: 'friend/photo.png',
            onClosed: () async => closed++,
          ),
        ),
      ),
    );
    await settlePhotos(t);
    final open = find.byKey(const Key('viewFriendProfilePhoto'));
    for (var i = 0; i < 3; i++) {
      await t.tap(open);
    }
    await settlePhotos(t);
    expect(routes.pushes, 2); // Home and one preview.
    expect(find.byType(FriendAvatarPreview), findsOneWidget);
    final dismiss = find.byKey(const Key('dismissFriendProfilePhoto'));
    for (var i = 0; i < 3; i++) {
      await t.tap(dismiss);
    }
    await settlePhotos(t);
    expect(routes.pops, 1);
    expect(closed, 1);
    expect(find.byType(FriendAvatarPreview), findsNothing);
    expect(open, findsOneWidget);
    await t.tap(open);
    await settlePhotos(t);
    expect(find.byType(FriendAvatarPreview), findsOneWidget);
    await t.binding.handlePopRoute();
    await settlePhotos(t);
    expect(closed, 2);
    expect(find.byType(FriendAvatarPreview), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets(
    'outside tap and device Back dismiss without a visible close button',
    (t) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      await activity(t, ClosedFriends()..hasPhoto = true);
      final open = find.byKey(const Key('viewFriendProfilePhoto'));
      await t.tap(open);
      await settlePhotos(t);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      await t.tapAt(const Offset(5, 100));
      await settlePhotos(t);
      expect(find.byType(FriendAvatarPreview), findsNothing);
      await t.tap(open);
      await settlePhotos(t);
      await t.binding.handlePopRoute();
      await settlePhotos(t);
      expect(find.byType(FriendAvatarPreview), findsNothing);
      expect(open, findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  for (final size in [const Size(320, 844), const Size(844, 390)]) {
    testWidgets('round photo fits safe screen with large text at $size', (
      t,
    ) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      await activity(t, ClosedFriends()..hasPhoto = true, scale: 2);
      t.view.physicalSize = size;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await settlePhotos(t);
      final photo = find.byKey(const Key('friendProfilePhotoPreview'));
      final actual = t.getSize(photo);
      expect(actual.width, actual.height);
      expect(actual.width, lessThanOrEqualTo(size.shortestSide - 48));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ClipOval), findsWidgets);
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsOneWidget);
      expect(
        t.widget<Image>(find.byKey(const Key('friendProfilePhotoImage'))).fit,
        BoxFit.cover,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('dismissFriendProfilePhoto')));
      await settlePhotos(t);
      expect(find.byType(FriendAvatarPreview), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    });
  }
}
