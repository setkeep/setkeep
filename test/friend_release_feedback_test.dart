import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:setkeep/config/friends_release.dart';
import 'package:setkeep/friends/friend_avatar_preview.dart';
import 'package:setkeep/friends/friend_comment_inbox.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/friends/notification_sources_page.dart';
import 'package:setkeep/friends/workout_comments.dart';
import 'package:setkeep/main.dart';

import 'friends_mvp_test.dart' show FakeFriends;
import 'support/trainer_delivery_flow.dart' show DeliveryRepository;

const feedbackSets = [
  RecordedSet(
    exerciseName: 'Synthetic press',
    bodyPart: '胸',
    equipment: 'マシン',
    weight: 20,
    reps: 8,
    completed: true,
  ),
  RecordedSet(
    exerciseName: 'Synthetic press',
    bodyPart: '胸',
    equipment: 'マシン',
    weight: 25,
    reps: 6,
    completed: true,
  ),
  RecordedSet(
    exerciseName: 'Synthetic bodyweight',
    weight: 0,
    bodyPart: '脚',
    recordType: ExerciseRecordType.bodyweightReps,
    reps: 12,
    completed: true,
  ),
  RecordedSet(
    exerciseName: 'Synthetic hold',
    weight: 0,
    reps: 0,
    bodyPart: '腹',
    recordType: ExerciseRecordType.timed,
    durationSeconds: 45,
    completed: true,
  ),
  RecordedSet(
    exerciseName: 'Synthetic cardio',
    weight: 0,
    reps: 0,
    bodyPart: '有酸素',
    recordType: ExerciseRecordType.cardio,
    durationSeconds: 600,
    distanceKm: 1.2,
    inclinePercent: 4,
    resistanceLevel: 3,
    completed: true,
  ),
];

class ClosedFriends extends FakeFriends {
  @override
  bool get commentsEnabled => false;
  String viewer = 'me';
  bool accessible = true;
  bool hasPhoto = false;
  bool photoFail = false;
  bool revokeWhileSigning = false;
  int commentReads = 0;
  int photoSigns = 0;
  @override
  String get userId => viewer;
  @override
  Future<List<Map<String, dynamic>>> comments(String id) async {
    commentReads++;
    throw StateError('Closed feature must not load comments');
  }

  @override
  Future<List<Map<String, dynamic>>> feed({String? owner}) async => accessible
      ? [
          {
            ...(await super.feed(owner: owner)).first,
            'sets': feedbackSets.map((set) => set.toJson()).toList(),
            'friend_profiles': {
              'display_name': 'Synthetic friend',
              'avatar_path': hasPhoto ? 'friend/photo.png' : null,
            },
          },
        ]
      : [];
  @override
  Future<String> avatarUrl(String path) async {
    photoSigns++;
    if (photoFail) throw StateError('Storage denied');
    if (revokeWhileSigning) accessible = false;
    return 'https://synthetic.invalid/profile.png';
  }
}

class ClosedInbox extends FriendCommentInboxRepository {
  ClosedInbox(super.friends);
  int loads = 0;
  @override
  Future<List<Map<String, dynamic>>> comments() async {
    loads++;
    throw StateError('Closed inbox must not load data');
  }

  @override
  Future<int> unreadCount() async {
    loads++;
    throw StateError('Closed inbox must not count');
  }
}

Future<void> activity(
  WidgetTester t,
  ClosedFriends repo, {
  double width = 390,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(bottom: 24);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPadding);
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FriendActivityPage(
        repository: repo,
        owner: 'friend',
        selectedId: 'workout',
        commentNotificationId: 'stale',
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> settlePhotos(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 100));
  await t.runAsync(() async {
    await precacheImage(
      const NetworkImage('https://synthetic.invalid/profile.png'),
      t.element(find.byType(MaterialApp)),
      onError: (_, _) {},
    );
  });
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'production defaults closed; repository reads/writes do not reach network',
    () async {
      expect(friendCommentsPublicEnabled, isFalse);
      final client = SupabaseClient(
        'http://localhost',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final repo = FriendsRepository(client);
      expect(repo.commentsEnabled, isFalse);
      expect(await repo.comments('retained'), isEmpty);
      expect(await FriendCommentInboxRepository(repo).comments(), isEmpty);
      expect(
        await FriendCommentInboxRepository(repo).markRead('retained'),
        isFalse,
      );
      await expectLater(
        repo.sendComment('retained', 'text', operationId: 'old'),
        throwsStateError,
      );
      await expectLater(repo.comment('retained', 'text'), throwsStateError);
      await expectLater(repo.deleteComment('retained'), throwsStateError);
    },
  );

  testWidgets(
    'default release hides feed counts, friend comments, stale routes and general bell',
    (t) async {
      final repo = ClosedFriends();
      final inbox = ClosedInbox(repo);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                HomeHeader(friendRepository: inbox, onStart: (_) async {}),
                Expanded(
                  child: SingleChildScrollView(
                    child: FriendsSection(history: const [], repository: repo),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trainerInboxBell')), findsNothing);
      expect(find.textContaining('Comments'), findsNothing);
      expect(find.text('Synthetic friend'), findsOneWidget);
      expect(inbox.loads, 0);
      await activity(t, repo);
      expect(find.byType(WorkoutCommentsPage), findsNothing);
      expect(find.byKey(const Key('openWorkoutComments')), findsNothing);
      expect(repo.commentReads, 0);
      await t.pumpWidget(
        MaterialApp(
          home: WorkoutCommentsPage(
            repository: repo,
            workoutId: 'workout',
            ownerId: 'friend',
            commentNotificationId: 'stale',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('sendWorkoutComment')), findsNothing);
      expect(
        find.text('This feature is currently unavailable'),
        findsOneWidget,
      );
      await t.pumpWidget(
        MaterialApp(
          home: HistoryWorkoutCommentsEntry(
            repository: repo,
            clientId: 'local',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('historyWorkoutComments')), findsNothing);
      await t.pumpWidget(
        MaterialApp(home: FriendCommentInboxPage(repository: inbox)),
      );
      await t.pumpAndSettle();
      expect(
        find.text('This feature is currently unavailable'),
        findsOneWidget,
      );
      expect(inbox.loads, 0);
      expect(repo.commentReads, 0);
    },
  );

  testWidgets('trainer notifications stay available with comments closed', (
    t,
  ) async {
    final trainer = DeliveryRepository();
    addTearDown(trainer.auth.close);
    final inbox = ClosedInbox(ClosedFriends());
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(
            repository: trainer,
            friendRepository: inbox,
            showTrainerNotifications: true,
            onStart: (_) async {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byKey(const Key('trainerInboxBell')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('friendNotificationSource')), findsNothing);
    expect(find.byKey(const Key('trainerNotificationSource')), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(inbox.loads, 0);
  });

  for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'friend cards preserve order and all values without checks at $size',
      (t) async {
        final repo = ClosedFriends();
        await activity(t, repo, width: size.$1, scale: size.$2);
        await t.scrollUntilVisible(
          find.text('Synthetic press'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        final list = t.widget<ListView>(find.byType(ListView));
        final cards = (list.childrenDelegate as SliverChildListDelegate)
            .children
            .whereType<WorkoutDetailExerciseCard>()
            .toList();
        expect(cards.map((card) => card.sets.first.exerciseName), [
          'Synthetic press',
          'Synthetic bodyweight',
          'Synthetic hold',
          'Synthetic cardio',
        ]);
        expect(
          cards.expand((card) => card.sets).toList().map((set) => set.toJson()),
          feedbackSets.map((set) => set.toJson()),
        );
        expect(cards.every((card) => !card.showCompletionChecks), isTrue);
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
        expect(find.text('胸 ・ マシン'), findsOneWidget);
        expect(find.text('20 kg × 8 回'), findsOneWidget);
        expect(find.text('25 kg × 6 回'), findsOneWidget);
        expect(find.text('2026/10/3'), findsNothing);
        for (final set in feedbackSets) {
          await t.scrollUntilVisible(
            find.text(set.displaySummary),
            140,
            scrollable: find.byType(Scrollable).first,
          );
          expect(t.takeException(), isNull);
        }
        await t.scrollUntilVisible(
          find.text('Like 0'),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          t.getRect(find.text('Like 0')).bottom,
          lessThanOrEqualTo(844 - 24),
        );
        await t.tap(find.text('Like 0'));
        await t.pumpAndSettle();
        expect(repo.liked, isTrue);
        await t.scrollUntilVisible(
          find.text('Like 1'),
          80,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('openWorkoutComments')), findsNothing);
        repo.accessible = false;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(find.byType(WorkoutDetailExerciseCard), findsNothing);
        expect(repo.commentReads, 0);
      },
    );
  }

  testWidgets('own detail retains completion checks', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: WorkoutDetailPage(
          workout: WorkoutRecord(
            date: DateTime(2026, 10, 3),
            sets: feedbackSets,
          ),
          selectedGym: null,
          onWorkoutCompleted: (_) async {},
          onWorkoutUpdated: (_, _) async {},
          onWorkoutDeleted: (_) async => true,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Synthetic press'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      t
          .widgetList<WorkoutDetailExerciseCard>(
            find.byType(WorkoutDetailExerciseCard),
          )
          .every((card) => card.showCompletionChecks),
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byType(WorkoutDetailExerciseCard).first,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets(
    'photo absent does not offer preview; denied or removed photo never signs',
    (t) async {
      final repo = ClosedFriends();
      await activity(t, repo);
      expect(find.byKey(const Key('viewFriendProfilePhoto')), findsNothing);
      repo.accessible = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendAvatarPreview(
              repository: repo,
              owner: 'friend',
              path: 'friend/photo.png',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(repo.photoSigns, 0);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'photo preview contains full image, closes, and clears on revocation/resume',
    (t) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      final repo = ClosedFriends()..hasPhoto = true;
      await activity(t, repo);
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await settlePhotos(t);
      expect(
        find.byKey(const Key('friendProfilePhotoPreview')),
        findsOneWidget,
      );
      expect(
        t.widget<Image>(find.byKey(const Key('friendProfilePhotoImage'))).fit,
        BoxFit.contain,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('closeFriendProfilePhoto')));
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoPreview')), findsNothing);
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await settlePhotos(t);
      repo.accessible = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsNothing);
      expect(find.text('Photo unavailable'), findsOneWidget);
      await t.tapAt(const Offset(5, 100));
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoPreview')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'photo periodic revocation and close clears the underlying calendar photo and record',
    (t) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      final repo = ClosedFriends()..hasPhoto = true;
      await activity(t, repo);
      await t.tap(find.byKey(const Key('viewFriendProfilePhoto')));
      await settlePhotos(t);
      repo.accessible = false;
      await t.pump(const Duration(seconds: 30));
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsNothing);
      await t.tap(find.byKey(const Key('closeFriendProfilePhoto')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('viewFriendProfilePhoto')), findsNothing);
      expect(find.byType(WorkoutDetailExerciseCard), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'photo request failure, signing race, account change and periodic recheck fail closed',
    (t) async {
      debugNetworkImageHttpClientProvider = () => PhotoClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      Future<void> preview(ClosedFriends repo) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FriendAvatarPreview(
                key: UniqueKey(),
                repository: repo,
                owner: 'friend',
                path: 'friend/photo.png',
              ),
            ),
          ),
        );
        await settlePhotos(t);
      }

      await preview(
        ClosedFriends()
          ..hasPhoto = true
          ..photoFail = true,
      );
      expect(find.text('Photo unavailable'), findsOneWidget);
      await preview(
        ClosedFriends()
          ..hasPhoto = true
          ..revokeWhileSigning = true,
      );
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsNothing);
      final repo = ClosedFriends()..hasPhoto = true;
      await preview(repo);
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsOneWidget);
      repo.viewer = 'other';
      await t.pump(const Duration(seconds: 30));
      await settlePhotos(t);
      expect(find.byKey(const Key('friendProfilePhotoImage')), findsNothing);
      expect(find.text('Photo unavailable'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      debugNetworkImageHttpClientProvider = null;
    },
  );
}

// Offline synthetic pixels; no real image, credentials or network is used.
class PhotoClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => PhotoRequest();
}

class PhotoRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => PhotoResponse();
}

class PhotoResponse extends Stream<List<int>> implements HttpClientResponse {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5XcAAAAASUVORK5CYII=',
  );
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
