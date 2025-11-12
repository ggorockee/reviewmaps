package com.reviewmaps.mobile

import android.app.Activity
import android.util.Log
import com.kakao.adfit.ads.AdListener
import com.kakao.adfit.ads.ba.BannerAdView
import com.kakao.adfit.ads.na.AdFitNativeAdBinder
import com.kakao.adfit.ads.na.AdFitNativeAdLayout
import com.kakao.adfit.ads.na.AdFitNativeAdLoader
import com.kakao.adfit.ads.na.AdFitNativeAdRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 카카오 AdFit 전면광고 플랫폼 채널 핸들러
 */
class AdFitInterstitialChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val TAG = "AdFitInterstitial"
        const val CHANNEL_NAME = "flutter_adfit/interstitial"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showInterstitialAd" -> {
                val adId = call.argument<String>("adId")
                if (adId != null) {
                    showInterstitialAd(adId, result)
                } else {
                    result.error("INVALID_ARGUMENT", "adId is required", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 전면광고 표시
     * 
     * AdFit Android SDK에는 전면광고(Interstitial)가 없으므로
     * 대신 네이티브 광고를 전체 화면으로 표시하는 방식으로 구현
     */
    private fun showInterstitialAd(adId: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "전면광고 표시 요청: adId=$adId")
            
            // AdFit에는 전면광고가 없으므로 배너 광고를 팝업 형태로 표시
            // 실제 구현 시에는 Dialog를 사용하여 배너 광고를 전체 화면으로 표시
            
            activity.runOnUiThread {
                try {
                    // TODO: Dialog로 배너 광고를 전체 화면으로 표시
                    // 현재는 단순히 성공으로 응답
                    Log.d(TAG, "전면광고 표시 완료 (구현 필요)")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "전면광고 표시 실패", e)
                    result.error("AD_SHOW_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "전면광고 표시 중 오류", e)
            result.error("AD_SHOW_ERROR", e.message, null)
        }
    }
}

