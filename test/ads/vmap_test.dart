import 'package:chorki_player/src/ads/vmap.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleVmap = '''<?xml version="1.0" encoding="UTF-8"?>
<vmap:VMAP xmlns:vmap="http://www.iab.net/videosuite/vmap" version="1.0">
  <vmap:AdBreak timeOffset="00:02:00" breakType="linear" breakId="midroll-0">
    <vmap:AdSource id="ad-1" allowMultipleAds="false" followRedirects="true">
      <vmap:AdTagURI templateType="vast3"><![CDATA[https://example.com/vast/1.xml]]></vmap:AdTagURI>
    </vmap:AdSource>
  </vmap:AdBreak>
  <vmap:AdBreak timeOffset="00:04:00" breakType="linear" breakId="midroll-1">
    <vmap:AdSource id="ad-2" allowMultipleAds="false" followRedirects="true">
      <vmap:AdTagURI templateType="vast3"><![CDATA[https://example.com/vast/2.xml]]></vmap:AdTagURI>
    </vmap:AdSource>
  </vmap:AdBreak>
  <vmap:AdBreak timeOffset="00:06:00" breakType="linear" breakId="midroll-2">
    <vmap:AdSource id="ad-3" allowMultipleAds="false" followRedirects="true">
      <vmap:AdTagURI templateType="vast3"><![CDATA[https://example.com/vast/3.xml]]></vmap:AdTagURI>
    </vmap:AdSource>
  </vmap:AdBreak>
</vmap:VMAP>''';

String _brk(String attrs) => '<AdBreak $attrs/>';

void main() {
  group('parseVmap', () {
    test('parses the real sample into three mid-rolls', () {
      final breaks = parseVmap(_sampleVmap);
      expect(breaks.length, 3);
      expect(breaks.map((b) => b.id), [
        'midroll-0',
        'midroll-1',
        'midroll-2',
      ]);
      expect(breaks.map((b) => b.kind).toSet(), {ChorkiAdBreakKind.midRoll});
      expect(breaks[0].absolute, const Duration(minutes: 2));
      expect(breaks[1].absolute, const Duration(minutes: 4));
      expect(breaks[2].absolute, const Duration(minutes: 6));
      expect(breaks[0].fraction, isNull);
    });

    test('accepts tags without a namespace prefix', () {
      final breaks = parseVmap(
        '<AdBreak timeOffset="00:01:00" breakType="linear" breakId="a"/>',
      );
      expect(breaks.single.id, 'a');
      expect(breaks.single.absolute, const Duration(minutes: 1));
    });

    test('accepts single-quoted attributes', () {
      final breaks = parseVmap(
        "<vmap:AdBreak timeOffset='00:01:30' breakType='linear' breakId='q'/>",
      );
      expect(breaks.single.id, 'q');
      expect(breaks.single.absolute, const Duration(seconds: 90));
    });

    test('start and end are pre-roll and post-roll, case-insensitive', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="start" breakId="pre"')}'
        '${_brk('timeOffset="END" breakId="post"')}'
        '${_brk('timeOffset="Start" breakId="pre2"')}',
      );
      expect(breaks.map((b) => b.kind).toList(), [
        ChorkiAdBreakKind.preRoll,
        ChorkiAdBreakKind.postRoll,
        ChorkiAdBreakKind.preRoll,
      ]);
    });

    test('00:00:00 becomes a pre-roll', () {
      final breaks = parseVmap(_brk('timeOffset="00:00:00" breakId="z"'));
      expect(breaks.single.kind, ChorkiAdBreakKind.preRoll);
      expect(breaks.single.absolute, isNull);
    });

    test('percent offsets: 0% pre-roll, 100% post-roll, others fraction', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="0%" breakId="p0"')}'
        '${_brk('timeOffset="50%" breakId="p50"')}'
        '${_brk('timeOffset="100%" breakId="p100"')}'
        '${_brk('timeOffset="12.5%" breakId="pf"')}',
      );
      expect(breaks.length, 4);
      expect(breaks[0].kind, ChorkiAdBreakKind.preRoll);
      expect(breaks[1].kind, ChorkiAdBreakKind.midRoll);
      expect(breaks[1].fraction, closeTo(0.5, 1e-9));
      expect(breaks[2].kind, ChorkiAdBreakKind.postRoll);
      expect(breaks[3].kind, ChorkiAdBreakKind.midRoll);
      expect(breaks[3].fraction, closeTo(0.125, 1e-9));
    });

    test('percent above 100 is skipped', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="100.5%" breakId="over"')}'
        '${_brk('timeOffset="150%" breakId="over2"')}',
      );
      expect(breaks, isEmpty);
    });

    test('millisecond offsets are parsed', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="00:00:10.500" breakId="ms"')}'
        '${_brk('timeOffset="00:00:03.5" breakId="ms2"')}',
      );
      expect(breaks[0].absolute, const Duration(milliseconds: 10500));
      expect(breaks[1].absolute, const Duration(milliseconds: 3500));
    });

    test('hours beyond 59 are allowed', () {
      final breaks = parseVmap(_brk('timeOffset="01:00:00" breakId="h"'));
      expect(breaks.single.absolute, const Duration(hours: 1));
    });

    test('minutes or seconds above 59 are skipped', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="00:60:00" breakId="m"')}'
        '${_brk('timeOffset="00:00:60" breakId="s"')}'
        '${_brk('timeOffset="00:00:59" breakId="ok"')}',
      );
      expect(breaks.map((b) => b.id), ['ok']);
    });

    test('nonlinear breaks are skipped', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="00:01:00" breakType="nonlinear" breakId="nl"')}'
        '${_brk('timeOffset="00:02:00" breakType="NonLinear" breakId="nl2"')}'
        '${_brk('timeOffset="00:03:00" breakType="linear" breakId="lin"')}',
      );
      expect(breaks.map((b) => b.id), ['lin']);
    });

    test('#n positional offsets are skipped', () {
      final breaks = parseVmap(
        '${_brk('timeOffset="#2" breakId="hash"')}'
        '${_brk('timeOffset="00:01:00" breakId="real"')}',
      );
      expect(breaks.map((b) => b.id), ['real']);
    });

    test('missing breakId falls back to break-<index>', () {
      final breaks = parseVmap(_brk('timeOffset="00:01:00"'));
      expect(breaks.single.id, 'break-0');
    });

    test('missing breakType is treated as linear', () {
      final breaks = parseVmap(_brk('timeOffset="00:01:00" breakId="nt"'));
      expect(breaks.single.id, 'nt');
    });

    test('breaks without timeOffset are skipped', () {
      expect(parseVmap(_brk('breakId="none"')), isEmpty);
      expect(parseVmap(_brk('timeOffset="" breakId="empty"')), isEmpty);
    });

    test('garbage, empty and non-XML input returns an empty list', () {
      expect(parseVmap(''), isEmpty);
      expect(parseVmap('   '), isEmpty);
      expect(parseVmap('not xml at all'), isEmpty);
      expect(parseVmap('<html><body>oops</body></html>'), isEmpty);
      expect(parseVmap('<AdBreak timeOffset="garbage"'), isEmpty);
      expect(parseVmap('\u0000\u0001 <<<>>> %%%'), isEmpty);
    });
  });

  group('VmapBreak.resolve', () {
    test('mid-roll with absolute offset within the content', () {
      const b = VmapBreak(
        id: 'm',
        kind: ChorkiAdBreakKind.midRoll,
        absolute: Duration(minutes: 2),
      );
      final resolved = b.resolve(const Duration(minutes: 10))!;
      expect(resolved.id, 'm');
      expect(resolved.kind, ChorkiAdBreakKind.midRoll);
      expect(resolved.offset, const Duration(minutes: 2));
    });

    test('mid-roll at or before zero resolves to null', () {
      const zero = VmapBreak(
        id: 'z',
        kind: ChorkiAdBreakKind.midRoll,
        absolute: Duration.zero,
      );
      const neg = VmapBreak(
        id: 'n',
        kind: ChorkiAdBreakKind.midRoll,
        absolute: Duration(seconds: -5),
      );
      expect(zero.resolve(const Duration(minutes: 10)), isNull);
      expect(neg.resolve(const Duration(minutes: 10)), isNull);
    });

    test('mid-roll at or after the duration resolves to null', () {
      const atEnd = VmapBreak(
        id: 'e',
        kind: ChorkiAdBreakKind.midRoll,
        absolute: Duration(minutes: 10),
      );
      const past = VmapBreak(
        id: 'p',
        kind: ChorkiAdBreakKind.midRoll,
        absolute: Duration(minutes: 11),
      );
      expect(atEnd.resolve(const Duration(minutes: 10)), isNull);
      expect(past.resolve(const Duration(minutes: 10)), isNull);
    });

    test('mid-roll with no offset at all resolves to null', () {
      const none = VmapBreak(id: 'n', kind: ChorkiAdBreakKind.midRoll);
      expect(none.resolve(const Duration(minutes: 10)), isNull);
    });

    test('percent offsets resolve against the duration', () {
      const b = VmapBreak(
        id: 'pct',
        kind: ChorkiAdBreakKind.midRoll,
        fraction: 0.25,
      );
      final resolved = b.resolve(const Duration(seconds: 100))!;
      expect(resolved.offset, const Duration(seconds: 25));
    });

    test('percent offset of zero-length content resolves to null', () {
      const b = VmapBreak(
        id: 'pct',
        kind: ChorkiAdBreakKind.midRoll,
        fraction: 0.5,
      );
      expect(b.resolve(Duration.zero), isNull);
    });

    test('pre-roll resolves to zero regardless of duration', () {
      const b = VmapBreak(id: 'pre', kind: ChorkiAdBreakKind.preRoll);
      expect(b.resolve(const Duration(minutes: 3))!.offset, Duration.zero);
      expect(b.resolve(Duration.zero)!.offset, Duration.zero);
    });

    test('post-roll resolves to the duration', () {
      const b = VmapBreak(id: 'post', kind: ChorkiAdBreakKind.postRoll);
      const d = Duration(minutes: 3);
      expect(b.resolve(d)!.offset, d);
      expect(b.resolve(d)!.kind, ChorkiAdBreakKind.postRoll);
    });
  });

  group('loadVmapBreaks', () {
    test('returns parsed breaks and passes the url to the fetcher', () async {
      String? requested;
      final breaks = await loadVmapBreaks(
        'https://ads.example.com/vmap.xml',
        fetcher: (url) async {
          requested = url;
          return _sampleVmap;
        },
      );
      expect(requested, 'https://ads.example.com/vmap.xml');
      expect(breaks.length, 3);
    });

    test('returns an empty list when the fetcher throws', () async {
      final breaks = await loadVmapBreaks(
        'https://ads.example.com/vmap.xml',
        fetcher: (url) async => throw StateError('network down'),
      );
      expect(breaks, isEmpty);
    });

    test('returns an empty list when the fetcher returns garbage', () async {
      final breaks = await loadVmapBreaks(
        'https://ads.example.com/vmap.xml',
        fetcher: (url) async => '<<not a vmap>>',
      );
      expect(breaks, isEmpty);
    });
  });
}
