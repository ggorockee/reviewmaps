package com.reviewmaps.mobile

import android.content.Context
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import com.kakao.adfit.ads.AdListener
import com.kakao.adfit.ads.na.AdFitNativeAdBinder
import com.kakao.adfit.ads.na.AdFitNativeAdLayout
import com.kakao.adfit.ads.na.AdFitNativeAdLoader
import com.kakao.adfit.ads.na.AdFitNativeAdRequest
import io.flutter.plugin.platform.PlatformView

/**
 * 카카오 AdFit 네이티브 광고 플랫폼 뷰
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
    private var nativeAdLoader: AdFitNativeAdLoader? = null
    private var adLayout: AdFitNativeAdLayout? = null

    init {
        val adId = creationParams?.get("adId") as? String
        if (adId != null) {
            loadNativeAd(context, adId)
        } else {
            Log.e(TAG, "adId가 제공되지 않음")
        }
    }

    /**
     * 네이티브 광고 로드
     */
    private fun loadNativeAd(context: Context, adId: String) {
        try {
            Log.d(TAG, "네이티브 광고 로드 시작: adId=$adId")

            // 네이티브 광고 레이아웃 생성
            adLayout = AdFitNativeAdLayout(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }

            // 네이티브 광고 로더 생성
            nativeAdLoader = AdFitNativeAdLoader.create(context, adId)

            // 네이티브 광고 요청 및 로드
            val request = AdFitNativeAdRequest.Builder().build()
            
            nativeAdLoader?.loadAd(request, object : AdListener {
                override fun onAdLoaded() {
                    Log.d(TAG, "네이티브 광고 로드 완료")
                    
                    // 광고 바인딩
                    nativeAdLoader?.let { loader ->
                        adLayout?.let { layout ->
                            val binder = AdFitNativeAdBinder.Builder()
                                .build()
                            
                            loader.bindAd(binder, layout)
                            
                            // 컨테이너에 광고 레이아웃 추가
                            container.removeAllViews()
                            container.addView(layout)
                        }
                    }
                }

                override fun onAdFailed(errorCode: Int) {
                    Log.e(TAG, "네이티브 광고 로드 실패: errorCode=$errorCode")
                }

                override fun onAdClicked() {
                    Log.d(TAG, "네이티브 광고 클릭됨")
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 로드 중 오류", e)
        }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        try {
            nativeAdLoader?.destroy()
            nativeAdLoader = null
            adLayout = null
            container.removeAllViews()
            Log.d(TAG, "네이티브 광고 리소스 해제")
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 리소스 해제 중 오류", e)
        }
    }
}

