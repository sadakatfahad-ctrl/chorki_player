import 'package:dio/dio.dart';

import '../core/diagnostics.dart';

/// When an ad break plays relative to the content.
enum ChorkiAdBreakKind {
  /// Before the content starts.
  preRoll,

  /// At an offset inside the content.
  midRoll,

  /// After the content ends.
  postRoll,
}

/// An ad break as written in a VMAP document, before the video's duration
/// is known.
class VmapBreak {
  /// A break [id] of [kind] at [absolute] or at [fraction] of the video.
  const VmapBreak({
    required this.id,
    required this.kind,
    this.absolute,
    this.fraction,
  });

  /// The VMAP `breakId`.
  final String id;

  /// Pre-, mid- or post-roll.
  final ChorkiAdBreakKind kind;

  /// A fixed time offset (`timeOffset="00:00:15"`).
  final Duration? absolute;

  /// A relative offset (`timeOffset="25%"`), 0 to 1.
  final double? fraction;

  /// Where this break falls in a video [duration] long; null for a mid-roll
  /// outside the content.
  ChorkiAdBreak? resolve(Duration duration) {
    switch (kind) {
      case ChorkiAdBreakKind.preRoll:
        return ChorkiAdBreak(id: id, kind: kind, offset: Duration.zero);
      case ChorkiAdBreakKind.postRoll:
        return ChorkiAdBreak(id: id, kind: kind, offset: duration);
      case ChorkiAdBreakKind.midRoll:
        final offset =
            absolute ??
            (fraction == null
                ? null
                : Duration(
                    microseconds: (duration.inMicroseconds * fraction!).round(),
                  ));
        if (offset == null || offset <= Duration.zero || offset >= duration) {
          return null;
        }
        return ChorkiAdBreak(id: id, kind: kind, offset: offset);
    }
  }
}

/// An ad break at a known offset in the content.
class ChorkiAdBreak {
  /// Break [id] of [kind] at [offset].
  const ChorkiAdBreak({
    required this.id,
    required this.kind,
    required this.offset,
  });

  /// The VMAP `breakId`.
  final String id;

  /// Pre-, mid- or post-roll.
  final ChorkiAdBreakKind kind;

  /// When it plays (0 for a pre-roll, the duration for a post-roll).
  final Duration offset;

  @override
  String toString() => 'ChorkiAdBreak($id, $kind, $offset)';
}

final RegExp _adBreakTag = RegExp(r'<(?:[\w.-]+:)?AdBreak\b([^>]*)>');
final RegExp _attr = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final RegExp _clock = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$');
final RegExp _percent = RegExp(r'^(\d+(?:\.\d+)?)%$');

/// The ad breaks in a VMAP [xml] document; empty when it has none or is
/// not VMAP.
List<VmapBreak> parseVmap(String xml) {
  final result = <VmapBreak>[];
  var index = 0;
  for (final match in _adBreakTag.allMatches(xml)) {
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(match.group(1) ?? '')) {
      attrs[a.group(1)!] = (a.group(2) ?? a.group(3) ?? '').trim();
    }

    final type = attrs['breakType']?.toLowerCase();
    if (type != null && type.isNotEmpty && !type.contains('linear')) continue;
    if (type != null && type.contains('nonlinear')) continue;

    final raw = attrs['timeOffset']?.toLowerCase();
    if (raw == null || raw.isEmpty) continue;

    final id = (attrs['breakId'] ?? '').isNotEmpty
        ? attrs['breakId']!
        : 'break-$index';
    index++;

    if (raw == 'start') {
      result.add(VmapBreak(id: id, kind: ChorkiAdBreakKind.preRoll));
    } else if (raw == 'end') {
      result.add(VmapBreak(id: id, kind: ChorkiAdBreakKind.postRoll));
    } else if (_clock.firstMatch(raw) case final m?) {
      final minutes = int.parse(m.group(2)!);
      final seconds = int.parse(m.group(3)!);
      if (minutes > 59 || seconds > 59) continue;
      final millis = m.group(4) == null
          ? 0
          : int.parse(m.group(4)!.padRight(3, '0'));
      final d = Duration(
        hours: int.parse(m.group(1)!),
        minutes: minutes,
        seconds: seconds,
        milliseconds: millis,
      );
      result.add(
        d == Duration.zero
            ? VmapBreak(id: id, kind: ChorkiAdBreakKind.preRoll)
            : VmapBreak(id: id, kind: ChorkiAdBreakKind.midRoll, absolute: d),
      );
    } else if (_percent.firstMatch(raw) case final m?) {
      final pct = double.parse(m.group(1)!);
      if (pct > 100) continue;
      result.add(
        pct == 0
            ? VmapBreak(id: id, kind: ChorkiAdBreakKind.preRoll)
            : pct == 100
            ? VmapBreak(id: id, kind: ChorkiAdBreakKind.postRoll)
            : VmapBreak(
                id: id,
                kind: ChorkiAdBreakKind.midRoll,
                fraction: pct / 100,
              ),
      );
    }
  }
  return result;
}

/// Downloads a VMAP document (replaceable in tests).
typedef VmapFetcher = Future<String> Function(String url);

const Duration _vmapTimeout = Duration(seconds: 8);

/// One client for all VMAP requests. Deliberately not the route client: the
/// app's headers (auth tokens) must never reach a third-party ad server.
final Dio _vmapDio = Dio(
  BaseOptions(
    responseType: ResponseType.plain,
    connectTimeout: _vmapTimeout,
    sendTimeout: _vmapTimeout,
    receiveTimeout: _vmapTimeout,
  ),
);

/// Downloads [url] with a client that never sends the app's headers.
Future<String> defaultVmapFetcher(String url) async {
  final response = await _vmapDio.get<String>(url);
  return response.data ?? '';
}

/// Fetches and parses the VMAP at [url]. Any failure is reported as
/// `ads.vmap` and gives no breaks (IMA still plays the tag).
Future<List<VmapBreak>> loadVmapBreaks(
  String url, {
  VmapFetcher fetcher = defaultVmapFetcher,
}) async {
  try {
    return parseVmap(await fetcher(url));
  } catch (e, st) {
    // No markers; IMA still plays the breaks from the same tag.
    ChorkiDiagnostics.report(e, st, 'ads.vmap');
    return const [];
  }
}
