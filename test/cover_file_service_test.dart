import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:finamp/services/album_image_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:flutter_test/flutter_test.dart';

import 'counting_http_server.dart';

class _TempFileSystem implements cache.FileSystem {
  _TempFileSystem(this.directory);

  final io.Directory directory;

  @override
  Future<File> createFile(String name) async => const LocalFileSystem().file('${directory.path}/$name');
}

void main() {
  late io.Directory directory;

  setUp(() async {
    directory = await io.Directory.systemTemp.createTemp('finamp-covers');
  });

  tearDown(() => directory.delete(recursive: true));

  cache.CacheManager covers() => cache.CacheManager(
    cache.Config(
      'covers-under-test',
      repo: cache.NonStoringObjectProvider(),
      fileSystem: _TempFileSystem(directory),
      fileService: coverFileService(),
    ),
  );

  test('prefetching player covers takes two connections, leaving the rest for browsing', () async {
    final server = await CountingHttpServer.start(body: List.filled(1024, 7));
    addTearDown(server.close);
    final cache = covers();

    final files = await Future.wait([
      for (var i = 0; i < 10; i++) downloadCover(cache, server.uri('/Items/$i/Images/Primary').toString()),
    ]);

    expect(files.map((f) => f.file.lengthSync()), everyElement(1024));
    expect(server.connections, lessThanOrEqualTo(2));
  });

  test('a cover download that fails once, as on a network hand-off, is retried', () async {
    final server = await CountingHttpServer.start(body: List.filled(1024, 7), failFirst: 1);
    addTearDown(server.close);

    final file = await downloadCover(covers(), server.uri('/Items/1/Images/Primary').toString());

    expect(file.file.lengthSync(), 1024);
    expect(server.requests, 2);
  });
}
