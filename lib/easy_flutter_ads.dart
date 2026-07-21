/// A production-grade AdMob wrapper for Flutter.
///
/// Wraps `google_mobile_ads` with the parts every real app ends up writing:
/// preloading with TTL and backoff, AdMob-policy-safe App Open placement, UMP
/// consent ordering, adaptive banners, and impression-level revenue events.
library;

export 'package:google_mobile_ads/google_mobile_ads.dart'
    show AdSize, AppState, MaxAdContentRating, TagForChildDirectedTreatment,
        TagForUnderAgeOfConsent;

export 'src/app_open/app_open_ad_manager.dart';
export 'src/banner/easy_banner_ad.dart';
export 'src/config/easy_ad_unit_ids.dart';
export 'src/config/easy_ads_config.dart';
export 'src/consent/consent_manager.dart';
export 'src/core/easy_ad_event.dart';
export 'src/core/easy_ad_reward.dart';
export 'src/core/easy_ads.dart';
export 'src/core/easy_ads_store.dart';
export 'src/full_screen/full_screen_ad_manager.dart';
export 'src/full_screen/interstitial_ad_manager.dart';
export 'src/full_screen/rewarded_ad_manager.dart';
export 'src/full_screen/rewarded_interstitial_ad_manager.dart';
