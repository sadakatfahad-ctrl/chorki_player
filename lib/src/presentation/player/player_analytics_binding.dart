part of '../chorki_player_widget.dart';

/// Wires the player's analytics session to its video and controller.
extension _AnalyticsBinding on _ChorkiPlayerState {
  ChorkiAnalyticsConfig? get _analyticsConfig =>
      widget.analytics ?? widget.controller?.analytics;

  void _syncSession() {
    final config = _analyticsConfig;
    final session = _session;
    if (config == null) {
      if (session != null) {
        session.dispose();
        _session = null;
        _reattach();
      }
      return;
    }
    if (session != null) {
      session.config = config;
      return;
    }
    final created = ChorkiAnalyticsSession(config: config, metadata: _metadata);
    _session = created;
    created.adContext = adContextOf(_byteData);
    final c = _controller;
    if (c != null) created.bind(c);
    if (!_preloading) created.activate();
    _reattach();
  }

  /// Hands the current session to the controller.
  void _reattach() {
    final c = _controller;
    if (c != null && !_preloading) {
      _chorki.attach(c, onRetry: _retry, analytics: _session);
    }
  }

  ChorkiMediaMetadata _metadata() =>
      metadataFor(widget.metadata, _byteData, widget.videoUrl);
}
