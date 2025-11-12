package com.reviewmaps.mobile

import android.app.Activity
import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.kakao.adfit.ads.popup.AdFitPopupAd
import com.kakao.adfit.ads.popup.AdFitPopupAdDialogFragment
import com.kakao.adfit.ads.popup.AdFitPopupAdLoader
import com.kakao.adfit.ads.popup.AdFitPopupAdRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 카카오 AdFit 앱 전환형 광고 플랫폼 채널 핸들러
 * AdFit SDK 3.19.5 공식 API 사용
 * 
 * 참고: https://github.com/adfit/adfit-android-sdk/blob/master/docs/app-transition-ad.md
 */
class AdFitInterstitialChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val TAG = "AdFitInterstitial"
        const val CHANNEL_NAME = "flutter_adfit/interstitial"
    }

    private var popupAdLoader: AdFitPopupAdLoader? = null
    private var methodResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showInterstitialAd" -> {
                val adId = call.argument<String>("adId")
                if (adId != null) {
                    loadAndShowInterstitialAd(adId, result)
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
     * 앱 전환형 광고 로드 및 표시
     * AdFit 공식 API 사용: AdFitPopupAdLoader + AdFitPopupAdDialogFragment
     */
    private fun loadAndShowInterstitialAd(adId: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "앱 전환형 광고 로드 시작: adId=$adId")
            
            // Activity가 FragmentActivity가 아니면 에러 반환
            if (activity !is FragmentActivity) {
                result.error("INVALID_ACTIVITY", "Activity must extend FragmentActivity", null)
                return
            }
            
            activity.runOnUiThread {
                try {
                    // 결과 콜백 저장
                    methodResult = result
                    
                    // AdFitPopupAdLoader 생성 (이미 있으면 재사용)
                    if (popupAdLoader == null) {
                        popupAdLoader = AdFitPopupAdLoader.create(activity, adId)
                        Log.d(TAG, "AdFitPopupAdLoader 생성됨")
                    }
                    
                    // 광고 요청 전 확인 사항
                    if (activity.isFinishing || activity.isDestroyed) {
                        Log.w(TAG, "Activity가 종료 중이거나 파괴됨")
                        result.error("ACTIVITY_FINISHING", "Activity is finishing or destroyed", null)
                        return@runOnUiThread
                    }
                    
                    popupAdLoader?.let { loader ->
                        // 중복 요청 방지
                        if (loader.isLoading) {
                            Log.w(TAG, "이미 광고를 로딩 중입니다")
                            result.error("ALREADY_LOADING", "Ad is already loading", null)
                            return@runOnUiThread
                        }
                        
                        // 요청 정책 확인 (빈도 제한, 오늘 그만보기 등)
                        if (loader.isBlockedByRequestPolicy) {
                            Log.w(TAG, "광고 요청이 정책에 의해 차단됨 (빈도 제한 또는 오늘 그만보기)")
                            result.error("BLOCKED_BY_POLICY", "Ad request blocked by policy", null)
                            return@runOnUiThread
                        }
                        
                        // 앱 전환형 광고 요청
                        Log.d(TAG, "광고 요청 시작")
                        loader.loadAd(
                            AdFitPopupAdRequest.build(AdFitPopupAd.Type.Transition),
                            object : AdFitPopupAdLoader.OnAdLoadListener {
                                override fun onAdLoaded(ad: AdFitPopupAd) {
                                    Log.d(TAG, "앱 전환형 광고 로드 성공")
                                    
                                    // Activity 상태 재확인
                                    if (activity.isFinishing || activity.isDestroyed) {
                                        Log.w(TAG, "광고 로드 후 Activity가 종료됨")
                                        methodResult?.error("ACTIVITY_FINISHING", "Activity finished before showing ad", null)
                                        methodResult = null
                                        return
                                    }
                                    
                                    try {
                                        // AdFitPopupAdDialogFragment로 광고 표시
                                        AdFitPopupAdDialogFragment(ad).show(
                                            activity.supportFragmentManager,
                                            AdFitPopupAdDialogFragment.TAG
                                        )
                                        
                                        Log.d(TAG, "앱 전환형 광고 표시 완료")
                                        methodResult?.success(true)
                                        methodResult = null
                                        
                                    } catch (e: Exception) {
                                        Log.e(TAG, "광고 표시 중 오류", e)
                                        methodResult?.error("AD_SHOW_ERROR", e.message, null)
                                        methodResult = null
                                    }
                                }

                                override fun onAdLoadError(errorCode: Int) {
                                    Log.e(TAG, "앱 전환형 광고 로드 실패: errorCode=$errorCode")
                                    
                                    val errorMessage = when (errorCode) {
                                        202 -> "네트워크 오류"
                                        301 -> "앱 전환 광고 소재 없음"
                                        302 -> "노출 가능한 광고 없음"
                                        else -> "광고 로드 실패"
                                    }
                                    
                                    methodResult?.error("AD_LOAD_FAILED", "$errorMessage: $errorCode", null)
                                    methodResult = null
                                }
                            }
                        )
                        
                    } ?: run {
                        Log.e(TAG, "AdFitPopupAdLoader가 null입니다")
                        result.error("LOADER_NULL", "AdFitPopupAdLoader is null", null)
                    }
                    
                } catch (e: Exception) {
                    Log.e(TAG, "앱 전환형 광고 로드 중 오류", e)
                    result.error("AD_LOAD_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "앱 전환형 광고 요청 중 오류", e)
            result.error("AD_REQUEST_ERROR", e.message, null)
        }
    }
    
    /**
     * 리소스 정리
     */
    fun dispose() {
        popupAdLoader = null
        methodResult = null
        Log.d(TAG, "리소스 정리 완료")
    }
}
