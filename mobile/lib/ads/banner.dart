import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class MyBannerAdWidget extends StatefulWidget {
  /// The requested size of the banner. Defaults to [AdSize.banner].
  final AdSize adSize;

  /// The AdMob ad unit to show.
  ///
  /// TODO: replace this test ad unit with your own ad unit
  final String adUnitId = Platform.isAndroid
  // Use this ad unit on Android...
      ? 'ca-app-pub-3219791135582658/4571348868'
  // ... or this one on iOS.
      : 'ca-app-pub-3219791135582658/2356249060';

  MyBannerAdWidget({super.key, this.adSize = AdSize.banner});

  @override
  State<MyBannerAdWidget> createState() => _MyBannerAdWidgetState();
}

class _MyBannerAdWidgetState extends State<MyBannerAdWidget> {
  /// The banner ad to show. This is `null` until the ad is actually loaded.
  BannerAd? _bannerAd;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: widget.adSize.width.toDouble(),
        height: widget.adSize.height.toDouble(),
        child: _bannerAd == null
        // Nothing to render yet.
            ? const SizedBox()
        // The actual ad.
            : AdWidget(ad: _bannerAd!),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  /// Loads a banner ad.
  void _loadAd() {
    // 빌드 모드에 따른 디버깅 정보 출력
    if (kDebugMode) {
      debugPrint('🎯 [BannerAd] DEBUG 모드에서 광고 로드 시작 - 테스트 광고 표시 예상');
    } else {
      debugPrint('🎯 [BannerAd] RELEASE 모드에서 광고 로드 시작 - 실제 광고 표시 예상');
    }
    
    final bannerAd = BannerAd(
      size: widget.adSize,
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        // Called when an ad is successfully received.
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          
          // 광고 로드 성공 시 빌드 모드 정보 출력
          if (kDebugMode) {
            debugPrint('✅ [BannerAd] 테스트 광고 로드 완료 (DEBUG 모드)');
          } else {
            debugPrint('✅ [BannerAd] 실제 광고 로드 완료 (RELEASE 모드)');
          }
          
          setState(() {
            _bannerAd = ad as BannerAd;
          });
        },
        // Called when an ad request failed.
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ [BannerAd] 광고 로드 실패: $error');
          ad.dispose();
        },
      ),
    );

    // Start loading.
    bannerAd.load();
  }

}