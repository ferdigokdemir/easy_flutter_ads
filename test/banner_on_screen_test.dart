import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A banner below the fold of a scrollable must not request an ad until the
/// user scrolls it into the viewport; filled-but-unseen banners are what drag
/// AdMob's show rate down.
void main() {
  final calls = <bool>[];

  setUp(() {
    calls.clear();
    final runtime = AdRuntime(
      config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
    );
    runtime.ensureInitialized = () async {
      calls.add(true);
      return false; // Stop before touching platform channels.
    };
    EasyBannerAd.runtime = runtime;
  });
  tearDown(() => EasyBannerAd.runtime = null);

  testWidgets('a banner below the fold loads only when scrolled to', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          controller: controller,
          child: const Column(
            children: [
              SizedBox(height: 2000),
              EasyBannerAd(),
              SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, isEmpty, reason: 'ekran dışındaki banner istek atmamalı');

    controller.jumpTo(1000);
    await tester.pump();
    expect(calls, isEmpty, reason: 'hâlâ ekran dışında');

    controller.jumpTo(1800);
    await tester.pump();
    expect(calls, hasLength(1), reason: 'viewport\'a girince yüklenmeli');

    controller.jumpTo(0);
    await tester.pump();
    controller.jumpTo(1800);
    await tester.pump();
    expect(calls, hasLength(1), reason: 'bir kez yüklenir, tekrar değil');
  });

  testWidgets('a banner above the fold loads after its first layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Column(children: [SizedBox(height: 100), EasyBannerAd()]),
        ),
      ),
    );
    await tester.pump();
    expect(calls, hasLength(1));
  });
}
