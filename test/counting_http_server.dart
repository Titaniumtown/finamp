import 'dart:io';

/// A local server for tests that counts connections. Each TCP connection uses its own
/// client port, so the number of different ports is the number of connections. Every
/// response waits [hold] before it is sent, so requests sent together overlap.
class CountingHttpServer {
  CountingHttpServer._(this._server);

  final HttpServer _server;
  final ports = <int>[];

  static Future<CountingHttpServer> start({Duration hold = const Duration(milliseconds: 50)}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final counting = CountingHttpServer._(server);
    server.listen((request) async {
      counting.ports.add(request.connectionInfo!.remotePort);
      await Future<void>.delayed(hold);
      request.response.write('ok');
      await request.response.close();
    });
    return counting;
  }

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  int get connections => ports.toSet().length;

  int get openSockets => _server.connectionsInfo().total;

  Future<void> close() => _server.close(force: true);
}
