package com.reviewmaps.mobile

import android.content.Context
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import com.kakao.adfit.ads.AdListener
import com.kakao.adfit.ads.ba.BannerAdView
import io.flutter.plugin.platform.PlatformView

/**
 * 카카오 AdFit 네이티브 광고 플랫폼 뷰
 * AdFit SDK 3.19.5 기반
 * 
 * 참고: AdFit SDK에는 별도의 네이티브 광고 API가 없으므로
 * 배너 광고를 네이티브 형태로 표시
 */
class AdFitNativeAdView(
    context: Context,
    id: Int,
    creationParams: Map<String, Any>?
) : PlatformView {
    
    companion object {
        private const val TAG = "AdFitNativeAdView"
    }

    private val container: FrameLayout = FrameLayout(context)
    private var bannerAdView: BannerAdView? = null

    init {
        val adId = creationParams?.get("adId") as? String
        if (adId != null) {
            loadNativeAd(context, adId)
        } else {
            Log.e(TAG, "adId가 제공되지 않음")
        }
    }

    /**
     * 네이티브 광고 로드 (배너 광고를 네이티브 형태로 사용)
     */
    private fun loadNativeAd(context: Context, adId: String) {
        try {
            Log.d(TAG, "네이티브 광고 로드 시작: adId=$adId")

            // 배너 광고 뷰 생성
            bannerAdView = BannerAdView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT
                )
                setClientId(adId)
                setAdListener(object : AdListener {
                    override fun onAdLoaded() {
                        Log.d(TAG, "네이티브 광고 로드 완료")
                    }

                    override fun onAdFailed(errorCode: Int) {
                        Log.e(TAG, "네이티브 광고 로드 실패: errorCode=$errorCode")
                    }

                    override fun onAdClicked() {
                        Log.d(TAG, "네이티브 광고 클릭됨")
                    }
                })
            }

            // 컨테이너에 광고 추가
            container.removeAllViews()
            container.addView(bannerAdView)
            
            // 광고 로드
            bannerAdView?.loadAd()
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 로드 중 오류", e)
        }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        try {
            bannerAdView?.destroy()
            bannerAdView = null
            container.removeAllViews()
            Log.d(TAG, "네이티브 광고 리소스 해제")
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 리소스 해제 중 오류", e)
        }
    }
}

