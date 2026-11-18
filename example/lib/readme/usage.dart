// README excerpts: regions between `// #region <name>` and `// #endregion`
// are copied verbatim into README.md and checked by
// test/guardrails/docs_test.dart. Edit here, then copy to the README.
// #region usage
import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 9 / 16,
      child: ChorkiPlayer(
        route: 'https://your-chorki-endpoint.example.com/api/byte/1',
        autoPlay: true,
        looping: true,
      ),
    );
  }
}
// #endregion
