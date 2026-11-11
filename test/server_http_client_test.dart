import 'package:finamp/services/server_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'counting_http_server.dart';

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late CountingHttpServer server;
  late ServerHttpClient client;

  setUp(() async {
    server = await CountingHttpServer.start();
    client = ServerHttpClient();
  });

  tearDown(() => server.close());

  test('a burst of requests stays within the main isolate share of the connection budget', () async {
    final responses = await Future.wait([for (var i = 0; i < 20; i++) client.get(server.uri('/Items/$i'))]);

    expect(responses.map((r) => r.statusCode), everyElement(200));
    expect(server.connections, lessThanOrEqualTo(3));
  });

  test('the worker isolate pool takes the rest of the budget', () async {
    ServerHttpClient.useWorkerPool();
    final worker = ServerHttpClient.instance;

    await Future.wait([for (var i = 0; i < 20; i++) worker.get(server.uri('/Items/$i'))]);

    expect(server.connections, lessThanOrEqualTo(2));
  });

  test('a connection survives a pause longer than dart:io keeps sockets by default', () async {
    await client.get(server.uri('/Artists'));
    await Future<void>.delayed(const Duration(seconds: 16));
    await client.get(server.uri('/Albums'));

    expect(server.connections, 1);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('reset drops pooled connections and later requests open fresh ones', () async {
    await client.get(server.uri('/before'));
    client.reset();
    await client.get(server.uri('/after'));
    await _until(() => server.openSockets == 1);

    expect(server.connections, 2);
    expect(server.openSockets, 1);
  });

  test('reset aborts a request in flight instead of leaving it on the old route', () async {
    final slow = await CountingHttpServer.start(hold: const Duration(seconds: 30));
    addTearDown(slow.close);
    final stalled = client.get(slow.uri('/stalled'));
    await _until(() => slow.ports.isNotEmpty);

    final started = DateTime.now();
    client.reset();

    await expectLater(stalled, throwsA(isA<http.ClientException>()));
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 2)));
    expect((await client.get(server.uri('/after'))).statusCode, 200);
  });

  test('a consumer closing the shared client does not break other consumers', () async {
    client.close();
    final response = await client.get(server.uri('/still-open'));

    expect(response.statusCode, 200);
  });
}
