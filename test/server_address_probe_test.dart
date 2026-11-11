import 'dart:convert';

import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'counting_http_server.dart';

void main() {
  test('probing a server address keeps its connection for the login that follows', () async {
    final server = await CountingHttpServer.start(body: utf8.encode(jsonEncode({'ServerName': 'home'})));
    addTearDown(server.close);

    final first = await JellyfinApiHelper.fetchPublicServerInfo(server.uri(''));
    final second = await JellyfinApiHelper.fetchPublicServerInfo(server.uri(''));

    expect(first?.serverName, 'home');
    expect(second?.serverName, 'home');
    expect(server.ports, hasLength(2));
    expect(server.connections, 1);
  });
}
