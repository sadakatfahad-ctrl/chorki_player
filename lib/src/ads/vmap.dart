import 'package:dio/dio.dart';

enum ChorkiAdBreakKind { preRoll, midRoll, postRoll }

class VmapBreak {
  const VmapBreak({
    required this.id,
    required this.kind,
    this.absolute,
    this.fraction,
  });

  final String id;
  final ChorkiAdBreakKind kind;
  final Duration? absolute;
  final double? fraction;

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

class ChorkiAdBreak {
  const ChorkiAdBreak({
    required this.id,
    required this.kind,
    required this.offset,
  });

  final String id;
  final ChorkiAdBreakKind kind;
  final Duration offset;

  @override
  String toString() => 'ChorkiAdBreak($id, $kind, $offset)';
}

final RegExp _adBreakTag = RegExp(r'<(?:[\w.-]+:)?AdBreak\b([^>]*)>');
final RegExp _attr = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final RegExp _clock = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$');
final RegExp _percent = RegExp(r'^(\d+(?:\.\d+)?)%$');

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

typedef VmapFetcher = Future<String> Function(String url);

Future<String> defaultVmapFetcher(String url) async {
  final response = await Dio().get<String>(
    url,
    options: Options(
      responseType: ResponseType.plain,
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  return response.data ?? '';
}

Future<List<VmapBreak>> loadVmapBreaks(
  String url, {
  VmapFetcher fetcher = defaultVmapFetcher,
}) async {
  try {
    return parseVmap(await fetcher(url));
  } catch (_) {
    return const [];
  }
}
