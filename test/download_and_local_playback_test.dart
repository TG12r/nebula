import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nebula/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/data/repositories/player_repository_impl.dart';
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:rxdart/rxdart.dart';

class FakeNebulaAudioHandler extends Fake implements NebulaAudioHandler {
  final _currentIndexController = StreamController<int?>.broadcast();
  @override
   final BehaviorSubject<MediaItem?> mediaItem =
      BehaviorSubject<MediaItem?>.seeded(null);
  @override
  final BehaviorSubject<PlaybackState> playbackState =
      BehaviorSubject<PlaybackState>.seeded(PlaybackState());
  @override
  final BehaviorSubject<List<MediaItem>> queue =
      BehaviorSubject<List<MediaItem>>.seeded(const []);

  final List<List<AudioSource>> setSourceListCalls = [];
  bool failLocalFileSources = false;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  int? get currentIndex => 0;

  @override
  bool get hasAudioSource => setSourceListCalls.isNotEmpty;

  @override
  int get sequenceLength =>
      setSourceListCalls.isEmpty ? 0 : setSourceListCalls.last.length;

  @override
  Future<void> setSourceList(
    List<AudioSource> sources, {
    int initialIndex = 0,
  }) async {
    setSourceListCalls.add(sources);
    final first = sources.first;
    if (failLocalFileSources &&
        first is UriAudioSource &&
        first.uri.isScheme('file')) {
      throw Exception('PlayerException (0): Source error / EOFException');
    }
  }

  @override
  Future<void> addAudioSourceToQueue(AudioSource source) async {}

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {}

  double _volume = 1.0;
  final BehaviorSubject<double> _volumeController =
      BehaviorSubject<double>.seeded(1.0);

  @override
  double get volume => _volume;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
    _volumeController.add(value);
  }
}

class FakeDownloadRepository implements DownloadRepository {
  final Map<String, String> localPaths = {};
  final List<String> deletedTrackIds = [];

  @override
  String? getLocalPath(String trackId) => localPaths[trackId];

  @override
  bool isDownloaded(String trackId) => localPaths.containsKey(trackId);

  @override
  Future<void> deleteTrack(String trackId) async {
    deletedTrackIds.add(trackId);
    final path = localPaths.remove(trackId);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  @override
  Future<void> downloadTrack(Track track) async {}

  @override
  Map<String, String> getAllDownloads() => Map.unmodifiable(localPaths);

  @override
  Stream<double> getDownloadProgress(String trackId) => const Stream.empty();

  @override
  Future<void> updateDownloadPath(String trackId, String newPath) async {
    localPaths[trackId] = newPath;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  String? customDownloadPath;

  @override
  Future<void> init() async {}

  @override
  ImageQuality get imageQuality => ImageQuality.medium;
  @override
  Future<void> setImageQuality(ImageQuality value) async {}

  @override
  bool get highAudioQuality => true;
  @override
  Future<void> setHighAudioQuality(bool value) async {}

  @override
  bool get gaplessPlayback => true;
  @override
  Future<void> setGaplessPlayback(bool value) async {}

  @override
  bool get anonymousMetrics => false;
  @override
  Future<void> setAnonymousMetrics(bool value) async {}

  @override
  bool get isDarkMode => true;
  @override
  Future<void> setDarkMode(bool value) async {}

  @override
  String? get downloadPath => customDownloadPath;
  @override
  Future<void> setDownloadPath(String? value) async {
    customDownloadPath = value;
  }

  @override
  TrackSource get searchSource => TrackSource.soundcloud;
  @override
  Future<void> setSearchSource(TrackSource source) async {}

  @override
  bool get dataSaver => false;
  @override
  Future<void> setDataSaver(bool value) async {}

  @override
  int get lookaheadTracks => 0;
  @override
  Future<void> setLookaheadTracks(int value) async {}

  @override
  int get audioCacheLimitMb => 100;
  @override
  Future<void> setAudioCacheLimitMb(int value) async {}

  @override
  double volume = 1.0;
  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }
}

class FakeSoundCloudRepository extends Fake implements SoundCloudRepository {
  String? streamUrlToReturn;

  @override
  Future<String?> getStreamUrl(String trackId) async => streamUrlToReturn;
}

class FakeHiveBox extends Fake implements Box {
  final Map<dynamic, dynamic> _store = {};

  @override
  bool containsKey(dynamic key) => _store.containsKey(key);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _store.containsKey(key) ? _store[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _store.remove(key);
  }

  @override
  Iterable<dynamic> get keys => _store.keys;
}

void main() {
  late Directory tempDir;
  late FakeNebulaAudioHandler fakeHandler;
  late FakeDownloadRepository fakeDownloadRepo;
  late FakeSettingsRepository fakeSettingsRepo;
  late FakeSoundCloudRepository fakeScRepo;
  late PlayerRepositoryImpl playerRepo;

  final longTrack = Track(
    id: 'sc:999888777',
    title: '20 Minute Progressive Mix',
    artist: 'DJ Nebula',
    thumbnailUrl: 'https://example.com/art.jpg',
    duration: const Duration(minutes: 20),
    source: TrackSource.soundcloud,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nebula_dl_test_');
    fakeHandler = FakeNebulaAudioHandler();
    fakeDownloadRepo = FakeDownloadRepository();
    fakeSettingsRepo = FakeSettingsRepository()
      ..customDownloadPath = tempDir.path;
    fakeScRepo = FakeSoundCloudRepository()
      ..streamUrlToReturn = 'https://cdn.example.com/stream/999888777.mp3';

    playerRepo = PlayerRepositoryImpl(
      fakeHandler,
      fakeDownloadRepo,
      fakeSettingsRepo,
      fakeScRepo,
    );
  });

  tearDown(() async {
    playerRepo.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Self-Healing Local Playback & Online Fallback', () {
    test(
      'setQueue falls back to online stream and deletes local file when ExoPlayer throws on corrupted 20m file',
      () async {
        // Create a 30 KB file with binary bytes that passes header check but fails in ExoPlayer
        final brokenFilePath = '${tempDir.path}/corrupted_20m.m4a';
        await File(brokenFilePath).writeAsBytes(List<int>.filled(30000, 0x42));
        fakeDownloadRepo.localPaths[longTrack.id] = brokenFilePath;
        fakeHandler.failLocalFileSources = true;

        await playerRepo.setQueue([longTrack], initialIndex: 0, autoPlay: true);

        // 1. First attempt tried local file:// source, second attempt fell back to https:// online stream
        expect(fakeHandler.setSourceListCalls.length, 2);
        final firstAttempt =
            fakeHandler.setSourceListCalls[0].first as UriAudioSource;
        final secondAttempt =
            fakeHandler.setSourceListCalls[1].first as UriAudioSource;

        expect(firstAttempt.uri.scheme, 'file');
        expect(secondAttempt.uri.scheme, 'https');
        expect(
          secondAttempt.uri.toString(),
          'https://cdn.example.com/stream/999888777.mp3',
        );

        // 2. Corrupted local file was automatically deleted from DownloadRepository
        expect(fakeDownloadRepo.deletedTrackIds, contains(longTrack.id));
        expect(fakeDownloadRepo.isDownloaded(longTrack.id), isFalse);

        // 3. Playback started cleanly
        expect(fakeHandler.playCalls, 1);
      },
    );

    test(
      'play() falls back to online stream and deletes local file when ExoPlayer throws on corrupted file',
      () async {
        final brokenFilePath = '${tempDir.path}/corrupted_single.m4a';
        await File(brokenFilePath).writeAsBytes(List<int>.filled(25000, 0x55));
        fakeDownloadRepo.localPaths[longTrack.id] = brokenFilePath;
        fakeHandler.failLocalFileSources = true;

        final err = await playerRepo.play(longTrack, autoPlay: true);

        expect(err, isNull);
        expect(fakeHandler.setSourceListCalls.length, 2);
        final secondAttempt =
            fakeHandler.setSourceListCalls[1].first as UriAudioSource;
        expect(secondAttempt.uri.scheme, 'https');
        expect(fakeDownloadRepo.deletedTrackIds, contains(longTrack.id));
        expect(fakeHandler.playCalls, 1);
      },
    );

    test(
      '_createAudioSource immediately deletes local files smaller than 10KB or starting with #EXTM3U',
      () async {
        // 1. File smaller than 10KB (e.g. 2KB truncated header)
        final tinyPath = '${tempDir.path}/tiny.mp3';
        await File(tinyPath).writeAsBytes(List<int>.filled(2048, 0x11));
        fakeDownloadRepo.localPaths[longTrack.id] = tinyPath;

        await playerRepo.play(longTrack);

        expect(fakeDownloadRepo.deletedTrackIds, contains(longTrack.id));
        expect(fakeHandler.setSourceListCalls.length, 1);
        final source =
            fakeHandler.setSourceListCalls.first.first as UriAudioSource;
        expect(source.uri.scheme, 'https');
      },
    );
  });

  group('Atomic & Verified Downloads (DownloadRepositoryImpl)', () {
    late HttpServer server;
    late FakeHiveBox fakeBox;
    late DownloadRepositoryImpl downloadRepo;

    setUp(() async {
      fakeBox = FakeHiveBox();
      downloadRepo = DownloadRepositoryImpl(
        fakeBox,
        fakeSettingsRepo,
        fakeScRepo,
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
      'Rejects truncated download when connection drops before Content-Length is reached',
      () async {
        // Simulate a 20MB track where socket closes after 20KB
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.add(
            'HTTP/1.1 200 OK\r\n'
                    'Content-Type: audio/mpeg\r\n'
                    'Content-Length: ${20 * 1024 * 1024}\r\n'
                    '\r\n'
                .codeUnits,
          );
          socket.add(List<int>.filled(20 * 1024, 0x33)); // Only 20 KB of 20 MB
          await socket.flush();
          socket.destroy();
        });

        fakeScRepo.streamUrlToReturn =
            'http://${server.address.host}:${server.port}/truncated.mp3';

        await downloadRepo.downloadTrack(longTrack);

        // Must NOT be marked as downloaded in Hive, and neither .part nor .mp3 should remain
        expect(downloadRepo.isDownloaded(longTrack.id), isFalse);
        expect(downloadRepo.getLocalPath(longTrack.id), isNull);
        final files = tempDir.listSync();
        expect(files, isEmpty);
      },
    );

    test(
      'Rejects HLS #EXTM3U manifest masquerading as audio download',
      () async {
        final hlsContent =
            '#EXTM3U\n#EXT-X-VERSION:3\n${List.filled(800, 'https://segment.ts\n').join()}';
        final hlsBytes = hlsContent.codeUnits;

        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.contentLength = hlsBytes.length;
          request.response.add(hlsBytes);
          await request.response.close();
        });

        fakeScRepo.streamUrlToReturn =
            'http://${server.address.host}:${server.port}/playlist.m3u8';

        await downloadRepo.downloadTrack(longTrack);

        expect(downloadRepo.isDownloaded(longTrack.id), isFalse);
        expect(downloadRepo.getLocalPath(longTrack.id), isNull);
        expect(tempDir.listSync(), isEmpty);
      },
    );

    test(
      'Commits download atomically from .part to final path when full valid audio is received',
      () async {
        final validAudioBytes = List<int>.filled(32 * 1024, 0x7F); // 32 KB

        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.contentLength = validAudioBytes.length;
          request.response.add(validAudioBytes);
          await request.response.close();
        });

        fakeScRepo.streamUrlToReturn =
            'http://${server.address.host}:${server.port}/valid.mp3';

        await downloadRepo.downloadTrack(longTrack);

        expect(downloadRepo.isDownloaded(longTrack.id), isTrue);
        final savedPath = downloadRepo.getLocalPath(longTrack.id);
        expect(savedPath, isNotNull);
        expect(File(savedPath!).existsSync(), isTrue);
        expect(File('$savedPath.part').existsSync(), isFalse);
        expect(File(savedPath).lengthSync(), validAudioBytes.length);
      },
    );
  });
}
