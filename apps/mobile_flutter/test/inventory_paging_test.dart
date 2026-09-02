import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:business_hub_mobile/core/backend/backend_api_client.dart';
import 'package:business_hub_mobile/core/models/mobile_auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Getting the whole catalogue onto the phone, not just the first page.
///
/// The client made one request and took what it was given. The server returns
/// 200 rows by default and names the next page in an X-Next-Cursor header, so
/// a shop with more than 200 products had the rest missing on mobile - with no
/// error, no empty state and nothing to notice. Scanning a barcode for a
/// product past the cut said the item did not exist.
///
/// Run against a real HttpServer rather than a mock, like token_refresh_test,
/// because what is being checked is the request loop: which header is read,
/// which query parameter goes back, and when the walk stops. A mock would
/// assert the design back to itself.
void main() {
  late HttpServer server;
  late String baseUrl;

  /// Cursors the client sent, in order. Null for the first, unparameterised
  /// request.
  late List<String?> cursorsSeen;

  /// Pages the server will serve, in order: rows, and the cursor to hand back.
  late List<(List<Map<String, dynamic>>, String?)> pages;

  /// When set, every page returns this cursor - a server making no progress.
  String? stuckCursor;

  setUp(() async {
    // flutter_test's binding stubs every request with a 400 and never touches
    // the network. This suite drives a real socket, so the override has to go.
    HttpOverrides.global = null;

    cursorsSeen = <String?>[];
    stuckCursor = null;
    pages = <(List<Map<String, dynamic>>, String?)>[];

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';

    unawaited(() async {
      await for (final request in server) {
        final cursor = request.uri.queryParameters['cursor'];
        cursorsSeen.add(cursor);

        final index = cursorsSeen.length - 1;
        final page = index < pages.length
            ? pages[index]
            : (<Map<String, dynamic>>[], null);

        final next = stuckCursor ?? page.$2;
        if (next != null) {
          request.response.headers.set('X-Next-Cursor', next);
        }
        request.response
          ..statusCode = 200
          ..write(jsonEncode(page.$1));
        await request.response.close();
      }
    }());
  });

  tearDown(() async => server.close(force: true));

  User owner() => User(
    uid: 'u1',
    email: 'owner@example.com',
    displayName: 'Owner',
    authToken: 'good-token',
  );

  BackendApiClient client() => BackendApiClient(
    baseUrl: baseUrl,
    readRefreshToken: () async => 'r1',
    onTokensRefreshed: (_, __) async {},
  );

  List<Map<String, dynamic>> rows(int from, int count) => List.generate(
    count,
    (i) => <String, dynamic>{
      'id': 'item-${from + i}',
      'name': 'Product ${from + i}',
    },
  );

  test('a single page is returned as it always was', () async {
    pages = [(rows(1, 3), null)];

    final items = await client().fetchInventoryItems(
      user: owner(),
      shopId: 's1',
    );

    expect(items.length, 3);
    expect(cursorsSeen, <String?>[null]);
  });

  test('every page is followed to the end', () async {
    // The bug, stated plainly: 250 products across two pages used to arrive
    // as 200.
    pages = [(rows(1, 200), 'cursor-1'), (rows(201, 50), null)];

    final items = await client().fetchInventoryItems(
      user: owner(),
      shopId: 's1',
    );

    expect(items.length, 250);
    expect(items.last['id'], 'item-250');
  });

  test('the cursor the server gave is the cursor sent back', () async {
    pages = [
      (rows(1, 200), 'cursor-1'),
      (rows(201, 200), 'cursor-2'),
      (rows(401, 10), null),
    ];

    await client().fetchInventoryItems(user: owner(), shopId: 's1');

    expect(cursorsSeen, <String?>[null, 'cursor-1', 'cursor-2']);
  });

  test('a search keeps its query while paging', () async {
    // The search path already carries ?q=, so the cursor has to join with &.
    // Getting this wrong drops the search and returns the whole catalogue,
    // which looks like the search silently matching everything.
    pages = [(rows(1, 200), 'cursor-1'), (rows(201, 5), null)];

    await client().fetchInventoryItems(
      user: owner(),
      shopId: 's1',
      query: 'salt',
    );

    expect(cursorsSeen.length, 2);
    expect(cursorsSeen.last, 'cursor-1');
  });

  test('a server repeating one cursor does not loop forever', () async {
    // Otherwise this spins on a phone, on someone's mobile data, with no
    // symptom except a battery going flat.
    pages = [(rows(1, 200), 'stuck')];
    stuckCursor = 'stuck';

    final items = await client()
        .fetchInventoryItems(user: owner(), shopId: 's1')
        .timeout(const Duration(seconds: 10));

    expect(items, isNotEmpty);
    expect(cursorsSeen.length, lessThan(4));
  });

  test('the limit still caps what comes back', () async {
    pages = [(rows(1, 200), 'cursor-1'), (rows(201, 200), 'cursor-2')];

    final items = await client().fetchInventoryItems(
      user: owner(),
      shopId: 's1',
      limit: 220,
    );

    expect(items.length, 220);
  });

  test('an empty shop is empty rather than an error', () async {
    pages = [(<Map<String, dynamic>>[], null)];

    final items = await client().fetchInventoryItems(
      user: owner(),
      shopId: 's1',
    );

    expect(items, isEmpty);
  });
}
