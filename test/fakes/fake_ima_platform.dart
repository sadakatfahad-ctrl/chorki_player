import 'package:flutter/widgets.dart';
import 'package:interactive_media_ads/src/platform_interface/platform_interface.dart';

base class FakeImaPlatform extends InteractiveMediaAdsPlatform {
  final List<FakeAdDisplayContainer> containers = [];
  final List<FakeAdsLoader> loaders = [];
  final List<FakeAdsManagerDelegate> delegates = [];
  final List<FakeContentProgressProvider> progressProviders = [];

  FakeAdsLoader get loader => loaders.last;

  @override
  PlatformAdsLoader createPlatformAdsLoader(
    PlatformAdsLoaderCreationParams params,
  ) {
    final loader = FakeAdsLoader(params);
    loaders.add(loader);
    return loader;
  }

  @override
  PlatformAdsManagerDelegate createPlatformAdsManagerDelegate(
    PlatformAdsManagerDelegateCreationParams params,
  ) {
    final delegate = FakeAdsManagerDelegate(params);
    delegates.add(delegate);
    return delegate;
  }

  @override
  PlatformAdDisplayContainer createPlatformAdDisplayContainer(
    PlatformAdDisplayContainerCreationParams params,
  ) {
    final container = FakeAdDisplayContainer(params);
    containers.add(container);
    return container;
  }

  @override
  PlatformContentProgressProvider createPlatformContentProgressProvider(
    PlatformContentProgressProviderCreationParams params,
  ) {
    final provider = FakeContentProgressProvider(params);
    progressProviders.add(provider);
    return provider;
  }

  @override
  PlatformAdsRenderingSettings createPlatformAdsRenderingSettings(
    PlatformAdsRenderingSettingsCreationParams params,
  ) {
    return FakeAdsRenderingSettings(params);
  }

  @override
  PlatformCompanionAdSlot createPlatformCompanionAdSlot(
    PlatformCompanionAdSlotCreationParams params,
  ) {
    throw UnsupportedError('Companion slots are not used by ChorkiAdLayer.');
  }

  @override
  PlatformImaSettings createPlatformImaSettings(
    PlatformImaSettingsCreationParams params,
  ) {
    return FakeImaSettings(params);
  }
}

/// Container whose widget is a [SizedBox] that reports itself to the SDK
/// (via `onContainerAdded`) once it has been built.
base class FakeAdDisplayContainer extends PlatformAdDisplayContainer {
  FakeAdDisplayContainer(super.params)
    : super.implementation();

  @override
  Widget build(BuildContext context) {
    return _ContainerProbe(onBuilt: () => params.onContainerAdded(this));
  }
}

class _ContainerProbe extends StatefulWidget {
  const _ContainerProbe({required this.onBuilt});

  final VoidCallback onBuilt;

  @override
  State<_ContainerProbe> createState() => _ContainerProbeState();
}

class _ContainerProbeState extends State<_ContainerProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBuilt();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// Records `requestAds` / `contentComplete`. Tests trigger loading through
/// `params.onAdsLoaded` or `params.onAdsLoadError`.
base class FakeAdsLoader extends PlatformAdsLoader {
  FakeAdsLoader(super.params)
    : super.implementation();

  final List<PlatformAdsRequest> requests = [];
  int contentCompleteCalls = 0;

  PlatformAdsRequest get lastRequest => requests.last;

  void loadManager(FakeAdsManager manager) {
    params.onAdsLoaded(PlatformOnAdsLoadedData(manager: manager));
  }

  void failLoad(AdError error) {
    params.onAdsLoadError(AdsLoadErrorData(error: error));
  }

  @override
  Future<void> requestAds(PlatformAdsRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> contentComplete() async {
    contentCompleteCalls++;
  }
}

/// Records lifecycle calls. Tests push events through the delegate that the
/// layer installed via [setAdsManagerDelegate].
class FakeAdsManager extends PlatformAdsManager {
  FakeAdsManager() : super(adCuePoints: const []);

  PlatformAdsManagerDelegate? delegate;
  int initCalls = 0;
  int startCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int destroyCalls = 0;

  /// Delivers [event] to the layer's `onAdEvent` callback.
  void emit(AdEventType type) {
    _delegate.params.onAdEvent?.call(PlatformAdEvent(type: type));
  }

  /// Delivers an ad playback error to the layer's `onAdErrorEvent` callback.
  void emitError(AdError error) {
    _delegate.params.onAdErrorEvent?.call(AdErrorEvent(error: error));
  }

  PlatformAdsManagerDelegate get _delegate {
    final d = delegate;
    if (d == null) throw StateError('setAdsManagerDelegate was not called');
    return d;
  }

  @override
  Future<void> init({PlatformAdsRenderingSettings? settings}) async {
    initCalls++;
  }

  @override
  Future<void> start(AdsManagerStartParams params) async {
    startCalls++;
  }

  @override
  Future<void> setAdsManagerDelegate(PlatformAdsManagerDelegate delegate) async {
    this.delegate = delegate;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<void> skip() async {}

  @override
  Future<void> discardAdBreak() async {}

  @override
  Future<void> destroy() async {
    destroyCalls++;
  }
}

base class FakeAdsManagerDelegate extends PlatformAdsManagerDelegate {
  FakeAdsManagerDelegate(super.params)
    : super.implementation();
}

/// Records every `setProgress` call as `(progress, duration)`.
base class FakeContentProgressProvider extends PlatformContentProgressProvider {
  FakeContentProgressProvider(super.params)
    : super.implementation();

  final List<(Duration, Duration)> calls = [];

  Duration? get lastProgress => calls.isEmpty ? null : calls.last.$1;

  @override
  Future<void> setProgress({
    required Duration progress,
    required Duration duration,
  }) async {
    calls.add((progress, duration));
  }
}

base class FakeAdsRenderingSettings extends PlatformAdsRenderingSettings {
  FakeAdsRenderingSettings(super.params)
    : super.implementation();
}

base class FakeImaSettings extends PlatformImaSettings {
  FakeImaSettings(super.params)
    : super.implementation();

  @override
  Future<void> setPpid(String ppid) async {}

  @override
  Future<void> setMaxRedirects(int maxRedirects) async {}

  @override
  Future<void> setFeatureFlags(Map<String, String> featureFlags) async {}

  @override
  Future<void> setAutoPlayAdBreaks(bool autoPlayAdBreaks) async {}

  @override
  Future<void> setPlayerType(String playerType) async {}

  @override
  Future<void> setPlayerVersion(String playerVersion) async {}

  @override
  Future<void> setSessionID(String sessionID) async {}

  @override
  Future<void> setDebugMode(bool enabled) async {}
}
