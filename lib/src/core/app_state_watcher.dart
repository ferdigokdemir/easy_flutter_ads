import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// The single subscription to the SDK's app state event channel, re-broadcast
/// to as many listeners as the app needs.
///
/// This exists because `AppStateEventNotifier.appStateStream` cannot be
/// listened to twice. Each call builds a new `EventChannel.receiveBroadcastStream()`,
/// and a Flutter binary messenger keeps **one** handler per channel name: the
/// second subscriber silently replaces the first one's handler, and whichever
/// subscriber cancels first tears the channel down for everyone by sending
/// `cancel` to the platform side.
///
/// So the package subscribes once, for the lifetime of the process, and hands
/// out [stream] instead. Host apps must listen to `EasyAds.instance.appState`
/// rather than to `AppStateEventNotifier` directly — otherwise the App Open
/// resume ad stops working the moment their own listener wins the race.
class AppStateWatcher {
  AppStateWatcher._();

  /// The process-wide instance.
  static final AppStateWatcher instance = AppStateWatcher._();

  final StreamController<AppState> _controller =
      StreamController<AppState>.broadcast();

  StreamSubscription<AppState>? _source;

  /// Foreground/background events. Listening starts the platform side on the
  /// first subscriber and never stops it.
  Stream<AppState> get stream {
    if (_source == null) {
      unawaited(AppStateEventNotifier.startListening());
      _source = AppStateEventNotifier.appStateStream.listen(_controller.add);
    }
    return _controller.stream;
  }
}
