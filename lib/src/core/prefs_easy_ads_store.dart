import 'package:shared_preferences/shared_preferences.dart';

import 'easy_ads_store.dart';

/// The default [EasyAdsStore]: `shared_preferences`, so session counts, daily
/// caps, hourly windows and cooldowns survive a cold start without the host app
/// wiring up anything.
///
/// This is what `EasyAds.initialize` uses when no `store` is passed. Every
/// frequency control in the package is a persistence problem first — a cap that
/// forgets is not a cap — and the format with the strictest rules, App Open,
/// shows precisely at cold start, the moment an in-memory counter has just been
/// wiped. Leaving that wiring to each host app meant the caps silently did
/// nothing in any app that skipped it.
///
/// Keys are namespaced under `easy_ads.`, so they cannot collide with the host
/// app's own preferences. It reads and writes through the same
/// `SharedPreferences.getInstance()` API the package used to document as a
/// hand-written adapter, so an app deleting its own adapter keeps the counters
/// it had rather than handing every user a fresh allowance.
///
/// Failures degrade instead of throwing: if the platform channel is
/// unavailable, values are kept in memory for the rest of the process and
/// reported through [onError]. That is the same behaviour as the old default —
/// caps that reset on restart — rather than a broken startup.
class PrefsEasyAdsStore implements EasyAdsStore {
  /// Creates the store. [onError] is wired to [EasyAdsConfig.onError] by
  /// `EasyAds.initialize`.
  PrefsEasyAdsStore({this.onError});

  /// Reports a swallowed persistence failure.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Values held for this process, used when the platform channel fails and as
  /// the write-through cache that keeps a failed write from being lost twice.
  final Map<String, int> _fallback = {};

  Future<SharedPreferences>? _pending;
  bool _unavailable = false;

  Future<SharedPreferences?> _prefs() async {
    // One failure is enough: retrying a missing platform channel on every cap
    // check would cost an exception per ad decision for the rest of the run.
    if (_unavailable) return null;
    try {
      return await (_pending ??= SharedPreferences.getInstance());
    } catch (error, stackTrace) {
      _unavailable = true;
      _pending = null;
      onError?.call(error, stackTrace);
      return null;
    }
  }

  @override
  Future<int> readInt(String key) async {
    final prefs = await _prefs();
    if (prefs == null) return _fallback[key] ?? 0;
    try {
      return prefs.getInt(key) ?? _fallback[key] ?? 0;
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      return _fallback[key] ?? 0;
    }
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _fallback[key] = value;
    final prefs = await _prefs();
    if (prefs == null) return;
    try {
      await prefs.setInt(key, value);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }
}
