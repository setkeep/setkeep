// Mock the SDK's existing HTTP dependency; no application dependency changes.
// All identities, sessions, records and responses in this file are synthetic.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/friends/friend_snapshot_journal.dart';
import 'package:setkeep/friends/friends_repository.dart';
import 'package:setkeep/friends/friends_ui.dart';
import 'package:setkeep/friends/friend_invite.dart';
import 'package:setkeep/main.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_snapshot_retry_test.dart' show login, ownerA, ownerB;
import 'support/legal_consent_fixture.dart';
import 'workout_completion_test.dart' show draft;

WorkoutRecord localRecord({
  String? owner,
  String note = 'Synthetic old record',
}) => WorkoutRecord(
  date: DateTime(2026, 9, 25, 10),
  friendOwnerUserId: owner,
  note: note,
  sets: const [RecordedSet(weight: 40, reps: 5, completed: true)],
);

void main() {
  late SupabaseClient client;
  late EmptyLocalStorage storage;
  late List<Map<String, dynamic>> requests;
  late Map<String, String> visibility;
  late Map<String, List<Map<String, dynamic>>> trainer;
  late Map<String, Set<String>> snapshots;
  late Set<String> existingProfiles;
  var explicitConsent = false;

  Future<void> start(
    WidgetTester tester,
    String owner, {
    List<WorkoutRecord>? history,
  }) async {
    FriendsRepository.resetPublicationQueueForTesting();
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'legal_consent': acceptedLegalConsentJson,
      if (history != null)
        FriendSnapshotJournal.historyKey: jsonEncode(
          history.map((w) => w.toJson()).toList(),
        ),
    });
    await tester.runAsync(() => login(client, owner));
    await tester.pumpWidget(
      SetkeepApp(auth: SupabaseAccountAuthService(client, storage)),
    );
    await tester.pumpAndSettle();
  }

  List<Map<String, dynamic>> writes() => requests
      .where(
        (r) =>
            (r['path'] as String).contains('sync_') ||
            (r['path'] as String).contains('acknowledge_') ||
            (r['method'] == 'POST' && r['path'] == '/rest/v1/workouts'),
      )
      .toList();

  setUp(() async {
    await FriendInviteStore.reset();
    SharedPreferences.setMockInitialValues({});
    requests = [];
    explicitConsent = false;
    existingProfiles = {ownerA, ownerB};
    visibility = {ownerA: 'friends', ownerB: 'private'};
    trainer = {ownerA: [], ownerB: []};
    snapshots = {
      ownerA: {'server-only-A'},
      ownerB: {'server-only-B'},
    };
    storage = EmptyLocalStorage();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'synthetic',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: storage,
      ),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object? body = request.body.isEmpty ? null : jsonDecode(request.body);
        requests.add({'method': request.method, 'path': path, 'body': body});
        final token = request.headers['authorization']?.split(' ').last;
        final owner = token != null && token.split('.').length == 3
            ? (jsonDecode(
                    utf8.decode(
                      base64Url.decode(
                        base64Url.normalize(token.split('.')[1]),
                      ),
                    ),
                  ) as Map)['sub']
                  as String
            : ownerA;
        Object? result = [];
        if (path == '/rest/v1/friend_profiles') {
          if (request.method == 'POST') {
            expectSync((body as Map)['user_id'], owner);
            expectSync(body.containsKey('visibility'), false);
            existingProfiles.add(owner);
            result = null;
          } else if (!existingProfiles.contains(owner)) {
            result = null;
          } else {
            result = {
              'user_id': owner,
              'display_name': 'Synthetic member',
              'visibility': visibility[owner],
              'invite_code': '71000000-0000-0000-0000-000000000099',
              'avatar_path': null,
              'sharing_consent_version': 1,
              'friend_owned_sync_version': 1,
            };
          }
        } else if (path == '/rest/v1/workouts') {
          expectSync(request.method, 'GET');
          result = trainer[owner];
        } else if (path == '/rest/v1/rpc/sync_owned_friend_workouts') {
          final params = body as Map;
          expectSync(params['expected_owner'], owner);
          final records = params['records'] as List;
          for (final row in records) {
            expectSync(row['friendOwnerUserId'], owner);
          }
          snapshots[owner]!.removeAll(
            (params['deleted_client_ids'] as List).cast<String>(),
          );
          if (visibility[owner] == 'friends') {
            snapshots[owner]!.addAll(records.map((r) => r['date'] as String));
          }
          result = {
            'accepted': true,
            'published': visibility[owner] == 'friends' && records.isNotEmpty,
          };
        } else if (explicitConsent &&
            path == '/rest/v1/rpc/acknowledge_owned_friend_sharing') {
          expectSync((body as Map)['expected_owner'], owner);
          visibility[owner] = 'friends';
          result = null;
        } else if (path == '/rest/v1/rpc/my_friend_invite_code') {
          result = 'ABCD2345';
        } else if (path == '/rest/v1/rpc/lookup_friend_invite_v2') {
          result = {
            'ok': true,
            'display_name': 'Synthetic friend',
            'status': null,
          };
        } else if (path == '/rest/v1/rpc/request_friend_v2') {
          expectSync(explicitConsent, true);
          expectSync(visibility[owner], 'friends');
          result = {'ok': true};
        } else if (path.contains('acknowledge_') ||
            path.contains('sync_friend_workouts')) {
          throw StateError('Unexpected automatic or legacy write: $path');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client = Supabase.instance.client;
    SupabaseConfig.initialized = true;
    SupabaseConfig.authStorage = storage;
    WorkoutUiPreference.completionCheckEnabled = false;
    WorkoutUiPreference.workoutTimerEnabled = false;
    WorkoutUiPreference.workoutDurationEnabled = false;
    RestTimerPreference.enabled = false;
  });
  tearDown(() async {
    await FriendInviteStore.reset();
    SupabaseConfig.initialized = false;
    SupabaseConfig.authStorage = null;
    await Supabase.instance.dispose();
  });

  testWidgets(
    'A logout B login keeps old local history without sharing it; restart and resume preserve private',
    (tester) async {
      final old = localRecord();
      final encoded = jsonEncode([old.toJson()]);
      await start(tester, ownerA, history: [old]);
      expect(writes(), isEmpty);
      await tester.runAsync(
        () => client.auth.signOut(scope: SignOutScope.local),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsNothing);
      await tester.runAsync(() => login(client, ownerB));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DashboardPage>(find.byType(DashboardPage))
            .history
            .single
            .toJson(),
        old.toJson(),
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        SetkeepApp(auth: SupabaseAccountAuthService(client, storage)),
      );
      await tester.pumpAndSettle();
      expect(visibility[ownerB], 'private');
      expect(writes(), isEmpty);
      expect(snapshots[ownerA], {'server-only-A'});
      expect(snapshots[ownerB], {'server-only-B'});
      expect(
        (await SharedPreferences.getInstance()).getString(
          FriendSnapshotJournal.historyKey,
        ),
        encoded,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'clean friends-enabled device does not prune server-only history',
    (tester) async {
      await start(tester, ownerA);
      expect(
        tester.widget<DashboardPage>(find.byType(DashboardPage)).history,
        isEmpty,
      );
      expect(writes(), isEmpty);
      expect(snapshots[ownerA], {'server-only-A'});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TRAINER read persists its authoritative owner without publishing normal or trainer history',
    (tester) async {
      trainer[ownerA] = [
        {
          'id': 'synthetic-trainer-id',
          'performed_at': '2026-09-26T10:00:00Z',
          'duration_seconds': 60,
          'gym_name': null,
          'note': 'Synthetic trainer',
          'canceled_at': null,
          'sets': [
            const RecordedSet(weight: 50, reps: 5, completed: true).toJson(),
          ],
        },
      ];
      final old = localRecord();
      await start(tester, ownerA, history: [old]);
      final history = tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .history;
      expect(history, hasLength(2));
      expect(
        history
            .singleWhere((w) => w.trainerWorkoutId != null)
            .trainerOwnerUserId,
        ownerA,
      );
      expect(
        history
            .singleWhere((w) => w.trainerWorkoutId == null)
            .friendOwnerUserId,
        isNull,
      );
      expect(writes(), isEmpty);
      expect((await FriendSnapshotJournal().batch(ownerA)).pending, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new B record shares only B provenance and preserves inherited local and server-only records',
    (tester) async {
      visibility[ownerB] = 'friends';
      await start(
        tester,
        ownerB,
        history: [
          localRecord(),
          localRecord(owner: ownerA, note: 'Owned A'),
        ],
      );
      expect(writes(), isEmpty);
      final newB = WorkoutRecord(
        date: DateTime(2026, 10, 6, 10),
        sets: localRecord().sets,
        friendOwnerUserId: ownerB,
      );
      final home = tester.widget<DashboardPage>(find.byType(DashboardPage));
      await home.onWorkoutCompleted(newB);
      await tester.pumpAndSettle();
      final sent = writes().single['body'] as Map;
      expect(sent['expected_owner'], ownerB);
      expect((sent['records'] as List).map((r) => r['date']), [
        newB.date.toIso8601String(),
      ]);
      expect(snapshots[ownerB], {'server-only-B', newB.date.toIso8601String()});
      expect(snapshots[ownerA], {'server-only-A'});
      expect(
        tester.widget<DashboardPage>(find.byType(DashboardPage)).history,
        hasLength(3),
      );
      expect((await FriendSnapshotJournal().batch(ownerB)).pending, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'new private account explicitly connects and publishes its owned workout',
    (tester) async {
      existingProfiles.remove(ownerB);
      await start(tester, ownerB);
      expect(existingProfiles, contains(ownerB));
      expect(visibility[ownerB], 'private');
      expect(writes(), isEmpty);
      final own = WorkoutRecord(
        date: DateTime(2026, 10, 6, 11),
        sets: localRecord().sets,
        friendOwnerUserId: ownerB,
      );
      await tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .onWorkoutCompleted(own);
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
      expect((await FriendSnapshotJournal().batch(ownerB)).pending, true);
      await tester.pumpWidget(
        MaterialApp(
          home: FriendsSettingsPage(
            repository: FriendsRepository(client),
            history: [own],
            initialInvite: 'EFGH6789',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = find.text('Send request');
      await Scrollable.ensureVisible(tester.element(request));
      await tester.pumpAndSettle();
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(visibility[ownerB], 'private');
      explicitConsent = true;
      await tester.tap(find.byKey(const Key('consentFriendsSharing')));
      await tester.pumpAndSettle();
      expect(visibility[ownerB], 'friends');
      expect(writes().map((r) => r['path']), [
        '/rest/v1/rpc/acknowledge_owned_friend_sharing',
        '/rest/v1/rpc/sync_owned_friend_workouts',
      ]);
      expect(
        requests.any((r) => r['path'] == '/rest/v1/rpc/request_friend_v2'),
        true,
      );
      expect(snapshots[ownerB], {'server-only-B', own.date.toIso8601String()});
      expect((await FriendSnapshotJournal().batch(ownerB)).pending, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'editing legacy or A record as B never assigns it to B or writes A',
    (tester) async {
      visibility[ownerB] = 'friends';
      final old = localRecord(owner: ownerA);
      await start(tester, ownerB, history: [old]);
      final edit = WorkoutRecord(
        date: old.date,
        sets: old.sets,
        note: 'Edited on B',
        friendOwnerUserId: ownerB,
      );
      await tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .onWorkoutUpdated(old, edit);
      await tester.pumpAndSettle();
      final saved = tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .history
          .single;
      expect(saved.note, 'Edited on B');
      expect(saved.friendOwnerUserId, isNull);
      expect(writes(), isEmpty);
      expect((await FriendSnapshotJournal().batch(ownerA)).pending, false);
      expect(snapshots[ownerA], {'server-only-A'});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('legacy draft remains unowned when completed by B', (
    tester,
  ) async {
    await tester.runAsync(() => login(client, ownerB));
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: draft(),
    });
    WorkoutRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          onSave: (r) async {
            saved = r;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.friendOwnerUserId, isNull);
    expect(writes(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owned A draft survives B resume without rebinding', (
    tester,
  ) async {
    await tester.runAsync(() => login(client, ownerB));
    final data = Map<String, dynamic>.from(jsonDecode(draft()) as Map)
      ..['friendOwnerUserId'] = ownerA;
    SharedPreferences.setMockInitialValues({
      activeWorkoutDraftStorageKey: jsonEncode(data),
    });
    WorkoutRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutPage(
          onSave: (r) async {
            saved = r;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(saved!.friendOwnerUserId, ownerA);
    expect(writes(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'new session captures A before interrupted authentication and repeated completion',
    (tester) async {
      await tester.runAsync(() => login(client, ownerA));
      SharedPreferences.setMockInitialValues({});
      final saving = Completer<void>();
      final saved = <WorkoutRecord>[];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutPage(
            resumeDraft: false,
            initialWorkout: localRecord(),
            onSave: (r) async {
              saved.add(r);
              await saving.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => login(client, ownerB));
      final press = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('completeWorkoutButton')),
          )
          .onPressed!;
      press();
      press();
      await tester.pump();
      expect(saved, hasLength(1));
      expect(saved.single.friendOwnerUserId, ownerA);
      saving.complete();
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(writes(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
