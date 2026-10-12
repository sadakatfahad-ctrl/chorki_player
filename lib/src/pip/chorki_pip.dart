import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';

/// Picture-in-picture state of the app.
enum ChorkiPipStatus {
  /// PiP is not supported (non-Android, old Android, or disabled by the OS).
  unavailable,

  /// Not in PiP.
  disabled,

  /// The app will enter PiP when the user leaves it (Home gesture).
  automatic,

  /// The app is currently shown in PiP.
  enabled,
}

/// Platform bridge for picture-in-picture. Replaceable in tests.
abstract class ChorkiPipDelegate {
  Future<ChorkiPipStatus> status();

  /// Enters PiP now. [aspectRatio] is width / height of the video.
  Future<ChorkiPipStatus> enter(double aspectRatio);

  /// Arms (or disarms) entering PiP automatically when the user leaves the app.
  Future<void> setAuto(bool enabled, double aspectRatio);
}

/// Android whole-app PiP backed by the `floating` package.
///
/// Requires `android:supportsPictureInPicture="true"` on the host activity.
class FloatingPipDelegate implements ChorkiPipDelegate {
  FloatingPipDelegate([Floating? floating]) : _floating = floating;

  Floating? _floating;
  Floating get _f => _floating ??= Floating();

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<ChorkiPipStatus> status() async {
    if (!_supported) return ChorkiPipStatus.unavailable;
    try {
      return _map(await _f.pipStatus);
    } catch (_) {
      return ChorkiPipStatus.unavailable;
    }
  }

  @override
  Future<ChorkiPipStatus> enter(double aspectRatio) async {
    if (!_supported) return ChorkiPipStatus.unavailable;
    try {
      return _map(
        await _f.enable(ImmediatePiP(aspectRatio: _rational(aspectRatio))),
      );
    } catch (_) {
      return ChorkiPipStatus.unavailable;
    }
  }

  @override
  Future<void> setAuto(bool enabled, double aspectRatio) async {
    if (!_supported) return;
    try {
      if (enabled) {
        await _f.enable(OnLeavePiP(aspectRatio: _rational(aspectRatio)));
      } else {
        await _f.cancelOnLeavePiP();
      }
    } catch (_) {}
  }

  static ChorkiPipStatus _map(PiPStatus s) => switch (s) {
    PiPStatus.enabled => ChorkiPipStatus.enabled,
    PiPStatus.disabled => ChorkiPipStatus.disabled,
    PiPStatus.automatic => ChorkiPipStatus.automatic,
    PiPStatus.unavailable => ChorkiPipStatus.unavailable,
  };

  /// Android accepts ratios in [1/2.39, 2.39]; clamp anything outside.
  static Rational _rational(double aspectRatio) {
    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      return const Rational.landscape();
    }
    // Per-mille, kept strictly inside the bounds after rounding.
    final perMille = (aspectRatio * 1000).round().clamp(419, 2390);
    return Rational(perMille, 1000);
  }
}
