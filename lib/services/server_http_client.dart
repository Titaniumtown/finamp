import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Sends requests to the Jellyfin server and reuses a small number of connections.
///
/// A single screen can send dozens of requests at once. By default, dart:io opens a new
/// connection for each of them and closes it after 15 seconds without use. Some networks
/// drop most connections when many are opened at the same time, which makes requests
/// hang. Limiting the number of connections and reusing them avoids this.
class ServerHttpClient extends http.BaseClient {
  ServerHttpClient({this.maxConnectionsPerHost = mainIsolateConnections}) : _inner = _create(maxConnectionsPerHost);

  /// How many connections each isolate may open. Together they add up to five, which is
  /// how many new connections one strict network was seen to allow at once. The worker
  /// isolate only loads lists, so it gets fewer.
  static const mainIsolateConnections = 3;
  static const workerIsolateConnections = 2;

  /// How long an unused connection stays open. This is shorter than the timeouts of
  /// nginx (75 seconds) and Jellyfin (130 seconds), so the app closes the connection
  /// before the server does.
  static const idleTimeout = Duration(seconds: 60);

  /// How long to wait for a connection to open. This also keeps the server connection
  /// test short.
  static const connectionTimeout = Duration(seconds: 10);

  static ServerHttpClient? _instance;

  /// The client for the current isolate. Each isolate gets its own, because isolates do
  /// not share static fields.
  static ServerHttpClient get instance => _instance ??= ServerHttpClient();

  /// Use the worker isolate's lower connection limit. Call this before the isolate sends
  /// its first request.
  static void useWorkerPool() {
    assert(_instance == null, 'the worker pool must be chosen before the first request');
    _instance = ServerHttpClient(maxConnectionsPerHost: workerIsolateConnections);
  }

  final int maxConnectionsPerHost;

  http.Client _inner;

  static http.Client _create(int maxConnectionsPerHost) => IOClient(
    HttpClient()
      ..maxConnectionsPerHost = maxConnectionsPerHost
      ..idleTimeout = idleTimeout
      ..connectionTimeout = connectionTimeout,
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  /// Close all connections and cancel any requests in progress. Call this after the
  /// network changes, because existing connections still go through the old network.
  void reset() {
    final old = _inner;
    _inner = _create(maxConnectionsPerHost);
    old.close();
  }

  /// Does nothing. Other code uses this same client, so it must not be closed. Use
  /// [reset] to close its connections instead.
  @override
  void close() {}
}
