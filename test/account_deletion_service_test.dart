import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Storage extends LocalStorage {
  String? session = 'saved session';
  bool failRemoval = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => session != null;
  @override
  Future<String?> accessToken() async => session;
  @override
  Future<void> persistSession(String value) async => session = value;
  @override
  Future<void> removePersistedSession() async {
    if (failRemoval) throw StateError('disk error');
    session = null;
  }
}

void main() {
  for (final scenario in [
    'success',
    'rejected',
    'owner blocked',
    'owner after photos',
    'avatar cleanup failed',
    'auth unconfirmed after photos',
    'retry',
    'concurrent',
    'unexpected',
    'logout failure',
    'storage failure',
  ]) {
    test('account deletion: $scenario', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.uri.path);
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/functions/v1/delete-account') {
          expect(request.headers.value('authorization'), startsWith('Bearer '));
          final attempt = requests
              .where((path) => path == '/functions/v1/delete-account')
              .length;
          request.response.statusCode =
              (scenario == 'owner blocked' || scenario == 'owner after photos')
              ? 409
              : (scenario == 'avatar cleanup failed' ||
                    scenario == 'auth unconfirmed after photos')
              ? 503
              : scenario == 'rejected'
              ? 403
              : scenario == 'retry' && attempt == 1
              ? 503
              : 200;
          request.response.write(
            jsonEncode(
              scenario == 'owner blocked'
                  ? {'error': 'tenant_owner_requires_transfer'}
                  : scenario == 'owner after photos'
                  ? {
                      'error':
                          'tenant_owner_requires_transfer_after_avatar_cleanup',
                    }
                  : scenario == 'avatar cleanup failed'
                  ? {'error': 'avatar_cleanup_unavailable'}
                  : scenario == 'auth unconfirmed after photos'
                  ? {'error': 'deletion_unconfirmed_after_avatar_cleanup'}
                  : {'deleted': scenario != 'unexpected'},
            ),
          );
        } else {
          expect(request.uri.path, '/auth/v1/logout');
          request.response.statusCode = scenario == 'logout failure'
              ? 500
              : 204;
          if (scenario == 'logout failure') {
            request.response.write('{"message":"failed"}');
          }
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final token =
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
          '${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.signature';
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': token,
          'refresh_token': 'refresh-test',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': '11111111-1111-4111-8111-111111111111',
            'app_metadata': {},
            'user_metadata': {},
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
          },
        }),
      );
      final storage = _Storage()..failRemoval = scenario == 'storage failure';
      final service = SupabaseAccountAuthService(client, storage);
      if (scenario == 'owner blocked') {
        await expectLater(
          service.deleteAccount(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.message,
              'message',
              allOf(contains('所有権'), contains('閉鎖')),
            ),
          ),
        );
        expect(client.auth.currentSession, isNotNull);
        expect(await storage.hasAccessToken(), isTrue);
        expect(requests, ['/functions/v1/delete-account']);
      } else if (scenario == 'owner after photos' ||
          scenario == 'avatar cleanup failed' ||
          scenario == 'auth unconfirmed after photos') {
        await expectLater(
          service.deleteAccount(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.message,
              'message',
              allOf(contains('プロフィール写真'), contains('アカウント削除')),
            ),
          ),
        );
        expect(client.auth.currentSession, isNotNull);
        expect(await storage.hasAccessToken(), isTrue);
        expect(requests, ['/functions/v1/delete-account']);
      } else if (scenario == 'retry') {
        await expectLater(
          service.deleteAccount(),
          throwsA(isA<AuthException>()),
        );
        expect(client.auth.currentSession, isNotNull);
        expect(await storage.hasAccessToken(), isTrue);
        await service.deleteAccount();
        expect(client.auth.currentSession, isNull);
        expect(await storage.hasAccessToken(), isFalse);
        expect(requests, [
          '/functions/v1/delete-account',
          '/functions/v1/delete-account',
          '/auth/v1/logout',
        ]);
      } else if (scenario == 'concurrent') {
        await Future.wait([service.deleteAccount(), service.deleteAccount()]);
        expect(requests, ['/functions/v1/delete-account', '/auth/v1/logout']);
        expect(client.auth.currentSession, isNull);
        expect(await storage.hasAccessToken(), isFalse);
      } else if (scenario == 'rejected' || scenario == 'unexpected') {
        await expectLater(
          service.deleteAccount(),
          throwsA(isA<AuthException>()),
        );
        expect(client.auth.currentSession, isNotNull);
        expect(await storage.hasAccessToken(), isTrue);
        expect(requests, ['/functions/v1/delete-account']);
      } else if (scenario == 'storage failure') {
        await expectLater(
          service.deleteAccount(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.message,
              'message',
              contains('アカウントは削除されましたが'),
            ),
          ),
        );
      } else {
        await service.deleteAccount();
        expect(client.auth.currentSession, isNull);
        expect(await storage.hasAccessToken(), isFalse);
        expect(requests, ['/functions/v1/delete-account', '/auth/v1/logout']);
      }
    });
  }
}
