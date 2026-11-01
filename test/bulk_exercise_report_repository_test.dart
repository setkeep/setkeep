import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/gym/gym_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friend_profile_identity_test.dart' show login, owner;

void main() {
  test('one atomic INSERT, identical retry, legacy single/other payloads and validation', () async {
    final payloads = <Object?>[];
    var fail = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/auth/v1/logout') {
        request.response.statusCode = 204;
        await request.response.close();
        return;
      }
      expect(request.uri.path, '/rest/v1/gym_exercise_reports');
      expect(request.method, 'POST');
      payloads.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.headers.contentType = ContentType.json;
      if (fail) {
        request.response.statusCode = 400;
        request.response.write(
          jsonEncode({
            'message': 'Please wait before reporting again',
            'code': 'P0001',
          }),
        );
      } else {
        request.response.statusCode = 201;
      }
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    await login(client, owner);
    final repo = SupabaseGymRepository(client);
    Future<void> send() => repo.reportExercises(
      storeId: 'synthetic-store',
      kind: 'missing_exercise',
      exerciseIds: {'bench_press', 'barbell_squat'},
      comment: '  共通コメント  ',
    );
    await expectLater(send(), throwsA(isA<PostgrestException>()));
    expect(payloads.length, 1);
    expect(payloads.single, [
      for (final id in ['bench_press', 'barbell_squat'])
        {
          'store_id': 'synthetic-store',
          'exercise_id': id,
          'report_kind': 'missing_exercise',
          'comment': '共通コメント',
        },
    ]);
    fail = false;
    await send();
    expect(payloads.length, 2);
    expect(payloads.first, payloads.last);
    await repo.reportExercises(
      storeId: 'synthetic-store',
      kind: 'incorrect_exercise',
      exerciseIds: {'bench_press'},
      comment: '',
    );
    expect((payloads.last as List).single, {
      'store_id': 'synthetic-store',
      'exercise_id': 'bench_press',
      'report_kind': 'incorrect_exercise',
      'comment': '',
    });
    await repo.reportExercise(
      storeId: 'synthetic-store',
      kind: 'other',
      comment: ' 確認 ',
    );
    expect(payloads.last, {
      'store_id': 'synthetic-store',
      'exercise_id': null,
      'report_kind': 'other',
      'comment': '確認',
    });
    await repo.reportExercise(
      storeId: 'synthetic-store',
      kind: 'missing_exercise',
      exerciseId: 'bench_press',
      comment: '',
    );
    expect(payloads.last, {
      'store_id': 'synthetic-store',
      'exercise_id': 'bench_press',
      'report_kind': 'missing_exercise',
      'comment': '',
    });
    for (final ids in [
      <String>{},
      {''},
      {for (var i = 0; i < 21; i++) 'exercise-$i'},
    ]) {
      await expectLater(
        repo.reportExercises(
          storeId: 'synthetic-store',
          kind: 'missing_exercise',
          exerciseIds: ids,
          comment: '',
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      repo.reportExercises(
        storeId: 'synthetic-store',
        kind: 'other',
        exerciseIds: {'bench_press'},
        comment: '',
      ),
      throwsArgumentError,
    );
    expect(payloads.length, 5);
    await client.auth.signOut(scope: SignOutScope.local);
    await expectLater(send(), throwsStateError);
    expect(payloads.length, 5);
  });
}
