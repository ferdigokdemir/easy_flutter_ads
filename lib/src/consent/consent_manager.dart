import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_runtime.dart';

/// Google User Messaging Platform (UMP) consent, wrapped so that consent is
/// always gathered *before* the first ad request.
///
/// Order matters: an ad requested before the consent string exists is served
/// without it, and AdMob's dashboard then reports low "consent coverage" for
/// EEA/UK/Switzerland traffic, which depresses fill and eCPM. That is why
/// `EasyAds.initialize()` awaits this step before `MobileAds.initialize()`.
///
/// Every failure path is fail-open: if the network is down or the form errors
/// out, ads still get requested. A broken consent SDK must not mean zero
/// revenue for everyone outside the EEA.
class ConsentManager {
  /// Creates a consent manager bound to [runtime].
  ConsentManager(this._runtime);

  final AdRuntime _runtime;

  /// True when consent has been gathered (or was not required).
  bool get canRequestAdsCached => _canRequestAds;
  bool _canRequestAds = false;

  /// Requests the consent info update and shows the form when required.
  ///
  /// Completes when the form is dismissed, or immediately when no form is
  /// needed. Never throws.
  Future<void> gather({Duration timeout = const Duration(seconds: 60)}) async {
    try {
      final completer = Completer<void>();

      final params = _runtime.config.forceConsentDebugGeographyEea
          ? ConsentRequestParameters(
              consentDebugSettings: ConsentDebugSettings(
                debugGeography: DebugGeography.debugGeographyEea,
                testIdentifiers: _runtime.config.testDeviceIds,
              ),
            )
          : ConsentRequestParameters();

      // requestConsentInfoUpdate returns void and reports platform failures
      // asynchronously, so a throw inside it escapes this try block entirely
      // and lands in the host app's zone as an unhandled error. Guarding the
      // call keeps a misbehaving consent plugin from taking the app with it.
      runZonedGuarded(() {
        ConsentInformation.instance.requestConsentInfoUpdate(
          params,
          () async {
            try {
              await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
                if (formError != null) {
                  _runtime.logError(
                    StateError('Consent form error: ${formError.message}'),
                    StackTrace.current,
                  );
                }
              });
            } catch (error, stackTrace) {
              _runtime.logError(error, stackTrace);
            }
            if (!completer.isCompleted) completer.complete();
          },
          (error) {
            _runtime.logError(
              StateError('Consent info update failed: ${error.message}'),
              StackTrace.current,
            );
            if (!completer.isCompleted) completer.complete();
          },
        );
      }, (error, stackTrace) {
        _runtime.logError(error, stackTrace);
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future.timeout(timeout, onTimeout: () {});
    } catch (error, stackTrace) {
      _runtime.logError(error, stackTrace);
    }

    _canRequestAds = await _safeCanRequestAds();
  }

  /// Whether the app may request ads according to UMP.
  Future<bool> canRequestAds() async {
    _canRequestAds = await _safeCanRequestAds();
    return _canRequestAds;
  }

  /// Whether a privacy options entry point must be offered — typically a
  /// "Privacy settings" row in your settings screen. Required for EEA users
  /// who accepted, so they can change their mind.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (error, stackTrace) {
      _runtime.logError(error, stackTrace);
      return false;
    }
  }

  /// Shows the privacy options form. Call this from the entry point that
  /// [isPrivacyOptionsRequired] told you to display.
  Future<void> showPrivacyOptionsForm() async {
    try {
      final completer = Completer<void>();
      unawaited(ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          _runtime.logError(
            StateError('Privacy options form error: ${formError.message}'),
            StackTrace.current,
          );
        }
        if (!completer.isCompleted) completer.complete();
      }));
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );
    } catch (error, stackTrace) {
      _runtime.logError(error, stackTrace);
    }
  }

  /// Wipes the stored consent state so the form shows again. Testing only.
  Future<void> reset() async {
    assert(
      kDebugMode,
      'ConsentInformation.reset() must never run in production code.',
    );
    try {
      await ConsentInformation.instance.reset();
      _canRequestAds = false;
    } catch (error, stackTrace) {
      _runtime.logError(error, stackTrace);
    }
  }

  Future<bool> _safeCanRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (error, stackTrace) {
      _runtime.logError(error, stackTrace);
      return true; // fail-open
    }
  }
}
