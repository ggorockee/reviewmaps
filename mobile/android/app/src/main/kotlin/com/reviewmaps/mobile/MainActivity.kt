package com.reviewmaps.mobile

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private var interstitialChannel: AdFitInterstitialChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 전면광고 플랫폼 채널 등록
        interstitialChannel = AdFitInterstitialChannel(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AdFitInterstitialChannel.CHANNEL_NAME
        ).setMethodCallHandler(interstitialChannel)

        // 네이티브 광고 플랫폼 뷰 등록
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                AdFitNativeAdViewFactory.VIEW_TYPE,
                AdFitNativeAdViewFactory()
            )
    }

    override fun onDestroy() {
        interstitialChannel = null
        super.onDestroy()
    }
}
