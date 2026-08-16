import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:business_hub_mobile/core/backend/backend_api_client.dart';
import 'package:business_hub_mobile/core/models/mobile_auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renewing an expired token without throwing the shopkeeper out.
///
/// Run against a real HttpServer rather than a mock, because the behaviour
/// being checked lives in the request loop itself — which header the retry
/// carries, and how many refreshes a burst of parallel 401s produces. A mock of
/// the client would assert the design back to itself and catch nothing.
void main() {
  late HttpServer server;
  late String baseUrl;

  /// Requests seen, in order, as (path, authorization header).
  late List<(String, String)> seen;

  /// Access tokens the server will accept. Mutated by the refresh endpoint.
  late Set<String> valid;
  late int refreshCalls;
  late String? refreshTokenSent;

  setUp(() async {
    // flutter_test's binding installs an HttpOverrides that stubs every
    // request with a 400 and never touches the network. This suite is testing
    // the real request loop against a real socket, so the override has to go.
    HttpOverrides.global = null;

    seen = <(String, String)>[];
    valid = <String>{'good-token'};
    refreshCalls = 0;
    refreshTokenSent = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';

    unawaited(() async {
      await for (final request in server) {
        final path = request.uri.path;
        final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        seen.add((path, auth));

        if (path == '/session/token/refresh/') {
          refreshCalls++;
          final body = await utf8.decodeStream(request);
          refreshTokenSent =
              (jsonDecode(body) as Map<String, dynamic>)['refresh'] as String?;
          valid
            ..clear()
            ..add('renewed-token');
          request.response
            ..statusCode = 200
            ..write(jsonEncode(<String, String>{
              'access': 'renewed-token',
              'refresh': 'renewed-refresh',
            }));
          await request.response.close();
          continue;
        }

        final presented = auth.replaceFirst('Bearer ', '');
        if (!valid.contains(presented)) {
          request.response
            ..statusCode = 401
            ..write(jsonEncode(<String, String>{'detail': 'Session was signed out.'}));
          await request.response.close();
          continue;
        }
        request.response
          ..statusCode = 200
          ..write(jsonEncode(<String, dynamic>{'ok': true}));
        await request.response.close();
      }
    }());
  });

  tearDown(() async => server.close(force: true));

  User userWith(String token) => User(
        uid: 'u1',
        email: 'owner@example.com',
        displayName: 'Owner',
        authToken: token,
      );

  BackendApiClient clientWith({
    required String storedRefresh,
    void Function(String access, String refresh)? onStored,
  }) =>
      BackendApiClient(
        baseUrl: baseUrl,
        readRefreshToken: () async => storedRefresh,
        onTokensRefreshed: (access, refresh) async =>
            onStored?.call(access, refresh),
      );

  test('a valid token is not refreshed', () async {
    await clientWith(storedRefresh: 'r1')
        .fetchShopSettings(user: userWith('good-token'), shopId: 's1');

    expect(refreshCalls, 0);
  });

  test('an expired token is renewed and the call repeated', () async {
    final client = clientWith(storedRefresh: 'r1');

    // 'stale-token' is not in the accepted set, so the first call 401s.
    await client.fetchShopSettings(user: userWith('stale-token'), shopId: 's1');

    expect(refreshCalls, 1);
    expect(refreshTokenSent, 'r1');

    final shopCalls =
        seen.where((e) => e.$1 != '/session/token/refresh/').toList();
    expect(shopCalls, hasLength(2));
    // The retry must carry the new token. Reusing the User's in-memory token
    // would loop until the attempt limit and then fail anyway.
    expect(shopCalls.first.$2, 'Bearer stale-token');
    expect(shopCalls.last.$2, 'Bearer renewed-token');
  });

  test('the renewed pair is handed back to be stored', () async {
    // The server rotates the refresh token on every exchange. Storing only the
    // access token would leave the next refresh presenting a spent one.
    String? access;
    String? refresh;
    final client = clientWith(
      storedRefresh: 'r1',
      onStored: (a, r) {
        access = a;
        refresh = r;
      },
    );

    await client.fetchShopSettings(user: userWith('stale-token'), shopId: 's1');

    expect(access, 'renewed-token');
    expect(refresh, 'renewed-refresh');
  });

  test('parallel calls hitting 401 together share one refresh', () async {
    // A screen opening with several requests produces a burst of 401s. Without
    // a shared in-flight refresh each would exchange independently, and all but
    // one would be spending a refresh token another had already rotated away.
    final client = clientWith(storedRefresh: 'r1');
    final user = userWith('stale-token');

    await Future.wait<void>(<Future<void>>[
      client.fetchShopSettings(user: user, shopId: 's1'),
      client.fetchShopSettings(user: user, shopId: 's2'),
      client.fetchShopSettings(user: user, shopId: 's3'),
    ]);

    expect(refreshCalls, 1);
  });

  test('a dead refresh token surfaces the original 401, not a refresh error', () async {
    // Nothing can be done from here — the sync coordinator's heartbeat owns
    // signing the app out. What must not happen is a confusing error from the
    // recovery attempt replacing the real one.
    final client = BackendApiClient(
      baseUrl: baseUrl,
      readRefreshToken: () async => '',
      onTokensRefreshed: (_, _) async {},
    );

    await expectLater(
      client.fetchShopSettings(user: userWith('stale-token'), shopId: 's1'),
      throwsA(
        isA<BackendApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
    expect(refreshCalls, 0);
  });

  test('a client with no refresh hook behaves as before', () async {
    // Tests and any other construction site pass neither callback, and must
    // not start throwing a different error because of this change.
    final client = BackendApiClient(baseUrl: baseUrl);

    await expectLater(
      client.fetchShopSettings(user: userWith('stale-token'), shopId: 's1'),
      throwsA(isA<BackendApiException>()),
    );
    expect(refreshCalls, 0);
  });
}
