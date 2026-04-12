import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../config/env.dart';

/// Category of filler clip. See `FE-Voice-Integration.md §5` for usage:
/// - [fillers]    : short noises like "hmm..." — played during 800–1500 ms
///                  expected latency.
/// - [thinking]   : slightly longer interjections like "let me think..." —
///                  played when expected latency > 1500 ms.
/// - [ack]        : short agreements. Not used by the current controller
///                  but available if a flow wants to acknowledge terse
///                  user input.
enum FillerCategory { fillers, thinking, ack }

/// A single preloaded filler clip.
class FillerClip {
  final FillerCategory category;
  final String text;
  final String url;

  const FillerClip({
    required this.category,
    required this.text,
    required this.url,
  });

  /// Parses a single entry from the `voice-assets/manifest.json` shape
  /// documented in `FE-Voice-Integration.md §5`. Unknown categories are
  /// dropped by returning null so a bad entry doesn't poison the whole
  /// list.
  static FillerClip? fromJson(Map<String, dynamic> json) {
    final categoryStr = json['category'] as String?;
    final text = json['text'] as String?;
    final url = json['url'] as String?;
    if (categoryStr == null || text == null || url == null) return null;

    final category = switch (categoryStr) {
      'fillers' => FillerCategory.fillers,
      'thinking' => FillerCategory.thinking,
      'ack' => FillerCategory.ack,
      _ => null,
    };
    if (category == null) return null;

    return FillerClip(category: category, text: text, url: url);
  }
}

/// Offline fallback copy of `voice-assets/manifest.json`, used only when
/// the cold-start fetch from Supabase Storage fails (first-run offline,
/// DNS issue, bucket misconfigured). The authoritative source is the
/// remote manifest URL — see [FillerAudioService._fetchManifest].
///
/// Keep this list in sync with `viespeak-be/docs/filler-manifest.json`
/// when you change the catalog, so offline cold starts still work.
const List<FillerClip> kFallbackFillerManifest = [
  FillerClip(
    category: FillerCategory.fillers,
    text: 'hmm...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/fillers/00-hmm.mp3',
  ),
  FillerClip(
    category: FillerCategory.fillers,
    text: 'uh-huh...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/fillers/01-uh-huh.mp3',
  ),
  FillerClip(
    category: FillerCategory.fillers,
    text: 'hmm, okay...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/fillers/02-hmm-okay.mp3',
  ),
  FillerClip(
    category: FillerCategory.thinking,
    text: 'let me think...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/thinking/00-let-me-think.mp3',
  ),
  FillerClip(
    category: FillerCategory.thinking,
    text: 'hmm, good question...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/thinking/01-hmm-good-question.mp3',
  ),
  FillerClip(
    category: FillerCategory.thinking,
    text: 'okay, so...',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/thinking/02-okay-so.mp3',
  ),
  FillerClip(
    category: FillerCategory.ack,
    text: 'okay',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/ack/00-okay.mp3',
  ),
  FillerClip(
    category: FillerCategory.ack,
    text: 'got it',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/ack/01-got-it.mp3',
  ),
  FillerClip(
    category: FillerCategory.ack,
    text: 'right',
    url:
        'https://bjjshrwoetnfwhswjsti.supabase.co/storage/v1/object/public/voice-assets/ack/02-right.mp3',
  ),
];

/// Preloads and plays filler clips used to mask backend latency during the
/// `THINKING` phase of a voice turn.
///
/// On cold start the service fetches the authoritative manifest from
/// `<SUPABASE_URL>/storage/v1/object/public/voice-assets/manifest.json`
/// (per `FE-Voice-Integration.md §5`) so the catalog can change without
/// shipping a new app build. A baked [kFallbackFillerManifest] is used if
/// the fetch fails.
///
/// The service owns a single [AudioPlayer] — only one filler is audible at
/// a time. [fadeOut] is a timer-driven volume ramp (just_audio has no
/// native volume automation) so the filler can crossfade cleanly into the
/// reply player.
class FillerAudioService {
  /// Relative path inside the `voice-assets` public bucket where the
  /// seed script publishes the authoritative manifest.
  static const _manifestObjectPath =
      '/storage/v1/object/public/voice-assets/manifest.json';

  /// How long to wait for the manifest fetch before falling back to the
  /// baked list. Kept tight so a slow network doesn't delay cold start.
  static const _manifestFetchTimeout = Duration(seconds: 3);

  final AudioPlayer _player = AudioPlayer();
  final Map<String, Uint8List> _cache = {};
  final Map<FillerCategory, List<int>> _recentPerCategory = {
    FillerCategory.fillers: [],
    FillerCategory.thinking: [],
    FillerCategory.ack: [],
  };
  final Random _rng = Random();

  /// Catalog used for the current session. Populated by [preloadAll] —
  /// either from the remote manifest or the baked fallback.
  List<FillerClip> _manifest = const [];

  bool _preloaded = false;
  Future<void>? _preloadFuture;

  /// Whether [preloadAll] has at least one cached clip. Consumers can use
  /// this to short-circuit filler playback when the cache is entirely
  /// empty (e.g. offline cold start).
  bool get hasAnyClips => _cache.isNotEmpty;

  /// Fetches the manifest from Supabase Storage and downloads every clip
  /// it lists in parallel. Idempotent and safe to call concurrently —
  /// callers all await the same inflight future.
  ///
  /// Errors are logged but not rethrown: filler playback is best-effort
  /// and a failing preload should never block the user from starting a
  /// conversation.
  Future<void> preloadAll() {
    if (_preloaded) return Future.value();
    return _preloadFuture ??= _doPreload();
  }

  Future<void> _doPreload() async {
    final sw = Stopwatch()..start();

    final remote = await _fetchManifest();
    if (remote != null) {
      _manifest = remote;
      debugPrint(
        '[FillerAudio] using remote manifest '
        '(${remote.length} clips, ${sw.elapsedMilliseconds}ms to fetch)',
      );
    } else {
      _manifest = kFallbackFillerManifest;
      debugPrint(
        '[FillerAudio] using baked fallback manifest '
        '(${kFallbackFillerManifest.length} clips)',
      );
    }

    debugPrint('[FillerAudio] preloading ${_manifest.length} clips');
    await Future.wait(
      _manifest.map((clip) async {
        try {
          final resp = await http.get(Uri.parse(clip.url));
          if (resp.statusCode == 200) {
            _cache[clip.url] = resp.bodyBytes;
          } else {
            debugPrint(
              '[FillerAudio] ${clip.url} → ${resp.statusCode} (skipped)',
            );
          }
        } catch (e) {
          debugPrint('[FillerAudio] ${clip.url} failed: $e (skipped)');
        }
      }),
    );
    _preloaded = true;
    debugPrint(
      '[FillerAudio] preload done: ${_cache.length}/${_manifest.length} '
      'clips in ${sw.elapsedMilliseconds}ms',
    );
  }

  /// Fetches and parses the authoritative manifest. Returns `null` on any
  /// failure (missing env, HTTP error, timeout, malformed JSON) so the
  /// caller can fall back to the baked list.
  Future<List<FillerClip>?> _fetchManifest() async {
    final base = Env.supabaseUrl;
    if (base.isEmpty) {
      debugPrint('[FillerAudio] SUPABASE_URL empty — skipping manifest fetch');
      return null;
    }
    final url = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$_manifestObjectPath');
    try {
      final resp =
          await http.get(url).timeout(_manifestFetchTimeout);
      if (resp.statusCode != 200) {
        debugPrint(
          '[FillerAudio] manifest fetch → ${resp.statusCode} (falling back)',
        );
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        debugPrint('[FillerAudio] manifest not a list (falling back)');
        return null;
      }
      final parsed = <FillerClip>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          final clip = FillerClip.fromJson(entry);
          if (clip != null) parsed.add(clip);
        }
      }
      if (parsed.isEmpty) {
        debugPrint('[FillerAudio] manifest parsed empty (falling back)');
        return null;
      }
      return parsed;
    } catch (e) {
      debugPrint('[FillerAudio] manifest fetch failed: $e (falling back)');
      return null;
    }
  }

  /// Plays a random clip from [category], honoring a 2-deep no-repeat
  /// window so the user never hears the same "hmm..." twice in a row.
  ///
  /// Returns immediately after playback is started; the clip plays in the
  /// background. Call [fadeOut] or [stop] to interrupt it.
  Future<void> playRandom(FillerCategory category) async {
    if (!_preloaded) {
      // Fire-and-forget — we don't want to block on a cold preload here,
      // but we also can't play anything this turn if it wasn't ready.
      unawaited(preloadAll());
    }
    final clip = _pickClip(category);
    if (clip == null) {
      debugPrint('[FillerAudio] no cached clip for $category — skipping');
      return;
    }
    final bytes = _cache[clip.url];
    if (bytes == null) return;

    try {
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.setAudioSource(_BytesAudioSource(bytes));
      unawaited(_player.play());
      debugPrint('[FillerAudio] playing "${clip.text}"');
    } catch (e) {
      debugPrint('[FillerAudio] playback failed: $e');
    }
  }

  FillerClip? _pickClip(FillerCategory category) {
    final candidates = _manifest
        .asMap()
        .entries
        .where((e) =>
            e.value.category == category && _cache.containsKey(e.value.url))
        .toList();
    if (candidates.isEmpty) return null;

    final recent = _recentPerCategory[category]!;
    final fresh =
        candidates.where((e) => !recent.contains(e.key)).toList();
    final pool = fresh.isNotEmpty ? fresh : candidates;

    final choice = pool[_rng.nextInt(pool.length)];
    recent.add(choice.key);
    while (recent.length > 2) {
      recent.removeAt(0);
    }
    return choice.value;
  }

  /// Ramps volume from its current value to 0 over [duration], then stops
  /// the player. Safe to call when nothing is playing.
  Future<void> fadeOut({
    Duration duration = const Duration(milliseconds: 150),
  }) async {
    if (!_player.playing) return;
    const stepMs = 15;
    final steps = (duration.inMilliseconds / stepMs).ceil();
    final start = _player.volume;
    for (var i = 1; i <= steps; i++) {
      final v = start * (1 - i / steps);
      try {
        await _player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
    }
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Stops playback immediately. No-op if nothing is playing.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
    _cache.clear();
  }
}

/// A trivial `StreamAudioSource` that serves an in-memory MP3 buffer to
/// `AudioPlayer.setAudioSource`. just_audio's built-in
/// `AudioSource.uri(Uri.dataFromBytes(...))` path works on mobile but is
/// awkward with arbitrary `Uint8List`s — a custom stream source is simpler
/// and avoids the data-URI size limits on Android.
// ignore: experimental_member_use
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}
