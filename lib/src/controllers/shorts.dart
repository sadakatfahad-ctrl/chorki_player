import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

enum ShortsSlotStatus { idle, loading, ready, failed, unplayable }

@immutable
class ShortsSlot {
  const ShortsSlot({required this.status, this.controller, this.error});

  static const ShortsSlot idle = ShortsSlot(status: ShortsSlotStatus.idle);

  final ShortsSlotStatus status;
  final VideoPlayerController? controller;
  final Object? error;

  bool get isReady =>
      status == ShortsSlotStatus.ready &&
      controller != null &&
      controller!.value.isInitialized;
}
