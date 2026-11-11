import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finamp/services/album_image_provider.dart';
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

  testWidgets('a screen of thumbnails loads over the shared server pool', (tester) async {
    final images = await tester.runAsync(
      () => Future.wait([
        for (var i = 0; i < 12; i++) _load(thumbnailImage(server.uri('/Items/$i/Images/Primary'), 'thumb-$i')),
      ]),
    );

    expect(images, hasLength(12));
    expect(images!.first.image.width, 1);
    expect(server.connections, lessThanOrEqualTo(3));
  });

  testWidgets('a thumbnail that failed to load is fetched again when it is next shown', (tester) async {
    final flaky = (await tester.runAsync(
      () => CountingHttpServer.start(body: _onePixelPng, contentType: ContentType('image', 'png'), failFirst: 1),
    ))!;
    addTearDown(flaky.close);
    final url = flaky.uri('/Items/1/Images/Primary');

    final first = await tester.runAsync(
      () => _load(thumbnailImage(url, 'retry-thumb')).then<Object?>((_) => null, onError: (Object e) => e),
    );
    final second = await tester.runAsync(
      () => _load(thumbnailImage(url, 'retry-thumb')).then<Object?>((image) => image, onError: (Object e) => e),
    );

    expect(first, isNotNull);
    expect(second, isA<ImageInfo>());
    expect(flaky.requests, 2);
  });
}
