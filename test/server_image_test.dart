import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finamp/services/server_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'counting_http_server.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

Future<ImageInfo> _load(ImageProvider provider) {
  final done = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      stream.removeListener(listener);
      done.complete(image);
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      done.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 5));
}

void main() {
  late CountingHttpServer server;
  final previousOverrides = HttpOverrides.current;

  setUp(() async {
    // Flutter's test setup makes every real HTTP request fail with a 400. Turn that off.
    HttpOverrides.global = null;
    server = await CountingHttpServer.start(body: _onePixelPng, contentType: ContentType('image', 'png'));
  });

  tearDown(() async {
    HttpOverrides.global = previousOverrides;
    await server.close();
  });

  testWidgets('a screen of user avatars loads over the shared server pool', (tester) async {
    final images = await tester.runAsync(
      () => Future.wait([for (var i = 0; i < 8; i++) _load(serverImage(server.uri('/Users/$i/Images/Primary')))]),
    );

    expect(images, hasLength(8));
    expect(images!.first.image.width, 1);
    expect(server.connections, lessThanOrEqualTo(3));
  });
}
