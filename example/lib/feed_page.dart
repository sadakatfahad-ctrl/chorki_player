import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';

import 'analytics.dart';
import 'test_videos.dart';

const _feedRatios = {'9:16', '1:1', '4:5', '9:19.5'};

/// The portrait and square Commons clips, then the Chorki routes (with ads).
final feedVideos = <TestVideo>[
  ...commonsMp4.where((v) => _feedRatios.contains(v.ratio)),
  ...chorkiRoutes,
];

/// A Bytes-style vertical feed. The byte on screen plays; the ones above and
/// below it are built with `preload: true`, so a swipe starts instantly.
class BytesFeedPage extends StatefulWidget {
  const BytesFeedPage({super.key});

  @override
  State<BytesFeedPage> createState() => _BytesFeedPageState();
}

class _BytesFeedPageState extends State<BytesFeedPage> {
  // One controller for the whole feed: it drives whichever byte is current.
  // Its analytics config applies to every byte; each byte reports its own
  // views, and only while it is the one on screen.
  final ChorkiPlayerController _controller = ChorkiPlayerController(
    analytics: exampleAnalytics,
  );

  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _byte(TestVideo video, int index, {required bool preload}) {
    final route = video.route;
    final metadata = ChorkiMediaMetadata(
      contentId: route ?? video.url,
      title: video.title,
      category: 'bytes',
      contentType: 'byte',
      feedIndex: index,
    );
    if (route != null) {
      return ChorkiPlayer(
        route: route,
        preload: preload,
        controller: _controller,
        metadata: metadata,
        ads: const ChorkiAdConfig(),
      );
    }
    return ChorkiPlayer.url(
      video.url!,
      preload: preload,
      controller: _controller,
      metadata: metadata,
      mediaOptions: ChorkiMediaOptions(httpHeaders: video.headers),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Bytes feed ${_current + 1}/${feedVideos.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          // Outside the pages: follows whichever byte the controller drives.
          child: ValueListenableBuilder(
            valueListenable: _controller.value,
            builder: (context, value, _) {
              final total = value.duration.inMilliseconds;
              return LinearProgressIndicator(
                minHeight: 2,
                value: total > 0 ? value.position.inMilliseconds / total : 0,
              );
            },
          ),
        ),
      ),
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        // Builds the byte above and below the current one, so they preload.
        allowImplicitScrolling: true,
        itemCount: feedVideos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) =>
            _byte(feedVideos[i], i, preload: i != _current),
      ),
    );
  }
}
