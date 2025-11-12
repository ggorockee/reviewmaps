package com.reviewmaps.mobile

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import com.kakao.adfit.ads.AdListener
import com.kakao.adfit.ads.ba.BannerAdView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 카카오 AdFit 앱 전환형 광고 플랫폼 채널 핸들러
 * AdFit SDK 3.19.5 기반
 */
class AdFitInterstitialChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val TAG = "AdFitInterstitial"
        const val CHANNEL_NAME = "flutter_adfit/interstitial"
    }

    private var adDialog: Dialog? = null
    private var bannerAdView: BannerAdView? = null

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
     * 앱 전환형 광고 표시
     * 
     * AdFit에는 전면광고가 없으므로 배너 광고를 Dialog로 전체 화면 형태로 표시
     */
    private fun showInterstitialAd(adId: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "앱 전환형 광고 표시 요청: adId=$adId")
            
            activity.runOnUiThread {
                try {
                    // 기존 Dialog가 있으면 닫기
                    dismissAd()
                    
                    // Dialog 생성
                    adDialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                        requestWindowFeature(Window.FEATURE_NO_TITLE)
                        window?.setBackgroundDrawable(ColorDrawable(Color.argb(220, 0, 0, 0)))
                        setCancelable(true)
                        setOnCancelListener {
                            Log.d(TAG, "앱 전환형 광고 Dialog 취소됨")
                            dismissAd()
                        }
                    }
                    
                    // 컨테이너 레이아웃 생성
                    val container = FrameLayout(activity).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    }
                    
                    // 배너 광고 뷰 생성 (중간 크기)
                    bannerAdView = BannerAdView(activity).apply {
                        layoutParams = FrameLayout.LayoutParams(
                            dpToPx(320),
                            dpToPx(480)
                        ).apply {
                            gravity = Gravity.CENTER
                        }
                        setClientId(adId)
                        setAdListener(object : AdListener {
                            override fun onAdLoaded() {
                                Log.d(TAG, "앱 전환형 광고 로드 완료")
                                adDialog?.show()
                                result.success(true)
                            }

                            override fun onAdFailed(errorCode: Int) {
                                Log.e(TAG, "앱 전환형 광고 로드 실패: errorCode=$errorCode")
                                dismissAd()
                                result.error("AD_LOAD_FAILED", "광고 로드 실패: $errorCode", null)
                            }

                            override fun onAdClicked() {
                                Log.d(TAG, "앱 전환형 광고 클릭됨")
                            }
                        })
                    }
                    
                    // 닫기 버튼 생성
                    val closeButton = ImageButton(activity).apply {
                        layoutParams = FrameLayout.LayoutParams(
                            dpToPx(48),
                            dpToPx(48)
                        ).apply {
                            gravity = Gravity.TOP or Gravity.END
                            setMargins(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
                        }
                        setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
                        setBackgroundColor(Color.argb(180, 255, 255, 255))
                        scaleType = ImageView.ScaleType.CENTER_INSIDE
                        setPadding(dpToPx(8), dpToPx(8), dpToPx(8), dpToPx(8))
                        setOnClickListener {
                            Log.d(TAG, "앱 전환형 광고 닫기 버튼 클릭됨")
                            dismissAd()
                        }
                    }
                    
                    container.addView(bannerAdView)
                    container.addView(closeButton)
                    
                    adDialog?.setContentView(container)
                    
                    // 광고 로드
                    bannerAdView?.loadAd()
                } catch (e: Exception) {
                    Log.e(TAG, "앱 전환형 광고 표시 실패", e)
                    dismissAd()
                    result.error("AD_SHOW_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "앱 전환형 광고 표시 중 오류", e)
            result.error("AD_SHOW_ERROR", e.message, null)
        }
    }
    
    /**
     * 광고 닫기 및 리소스 해제
     */
    private fun dismissAd() {
        try {
            adDialog?.dismiss()
            adDialog = null
            bannerAdView?.destroy()
            bannerAdView = null
            Log.d(TAG, "앱 전환형 광고 리소스 해제")
        } catch (e: Exception) {
            Log.e(TAG, "앱 전환형 광고 리소스 해제 중 오류", e)
        }
    }
    
    /**
     * DP를 픽셀로 변환
     */
    private fun dpToPx(dp: Int): Int {
        return (dp * activity.resources.displayMetrics.density).toInt()
    }
    
    /**
     * 리소스 정리
     */
    fun dispose() {
        dismissAd()
    }
}
