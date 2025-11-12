package com.reviewmaps.mobile

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import com.kakao.adfit.ads.na.*
import io.flutter.plugin.platform.PlatformView

/**
 * 카카오 AdFit 네이티브 광고 플랫폼 뷰
 * AdFit SDK 3.19.5 기반
 * 
 * 공식 문서: https://github.com/adfit/adfit-android-sdk/blob/master/docs/NATIVEAD.md
 */
class AdFitNativeAdView(
    private val context: Context,
    id: Int,
    creationParams: Map<String, Any>?
) : PlatformView {
    
    companion object {
        private const val TAG = "AdFitNativeAdView"
    }

    private val container: FrameLayout = FrameLayout(context)
    private var nativeAdLoader: AdFitNativeAdLoader? = null
    private var nativeAdBinder: AdFitNativeAdBinder? = null
    private lateinit var nativeAdViewContainer: AdFitNativeAdView
    private lateinit var mediaView: AdFitMediaView
    private lateinit var titleTextView: TextView
    private lateinit var bodyTextView: TextView
    private lateinit var callToActionButton: Button

    init {
        val adId = creationParams?.get("adId") as? String
        if (adId != null) {
            setupNativeAdLayout()
            loadNativeAd(adId)
        } else {
            Log.e(TAG, "adId가 제공되지 않음")
        }
    }

    /**
     * 네이티브 광고 레이아웃 구성
     */
    private fun setupNativeAdLayout() {
        // AdFitNativeAdView 생성 (광고 컨테이너)
        nativeAdViewContainer = AdFitNativeAdView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            setPadding(dpToPx(16), dpToPx(16), dpToPx(16), dpToPx(16))
            setBackgroundColor(Color.WHITE)
        }

        // 광고 레이아웃 구성
        val contentLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        // "광고" 라벨
        val adLabel = TextView(context).apply {
            text = "광고"
            textSize = 10f
            setTextColor(Color.GRAY)
            gravity = Gravity.END
            setPadding(0, 0, 0, dpToPx(8))
        }
        contentLayout.addView(adLabel)

        // 제목 (필수)
        titleTextView = TextView(context).apply {
            textSize = 16f
            setTextColor(Color.BLACK)
            setPadding(0, 0, 0, dpToPx(8))
        }
        contentLayout.addView(titleTextView)

        // 미디어 뷰 (필수)
        mediaView = AdFitMediaView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(200)
            )
        }
        contentLayout.addView(mediaView)

        // 본문
        bodyTextView = TextView(context).apply {
            textSize = 14f
            setTextColor(Color.DKGRAY)
            setPadding(0, dpToPx(8), 0, dpToPx(8))
        }
        contentLayout.addView(bodyTextView)

        // 행동유도 버튼
        callToActionButton = Button(context).apply {
            textSize = 14f
            setBackgroundColor(Color.parseColor("#FEE500"))
            setTextColor(Color.BLACK)
        }
        contentLayout.addView(callToActionButton)

        nativeAdViewContainer.addView(contentLayout)
        container.addView(nativeAdViewContainer)
    }

    /**
     * 네이티브 광고 로드
     */
    private fun loadNativeAd(adId: String) {
        try {
            Log.d(TAG, "네이티브 광고 로드 시작: adId=$adId")

            // AdFitNativeAdLoader 생성
            nativeAdLoader = AdFitNativeAdLoader.create(context, adId)

            // 광고 요청 설정
            val request = AdFitNativeAdRequest.Builder()
                .setAdInfoIconPosition(AdFitAdInfoIconPosition.RIGHT_TOP)
                .setVideoAutoPlayPolicy(AdFitVideoAutoPlayPolicy.WIFI_ONLY)
                .build()

            // 광고 로드
            nativeAdLoader?.loadAd(request, object : AdFitNativeAdLoader.AdLoadListener {
                override fun onAdLoaded(binder: AdFitNativeAdBinder) {
                    Log.d(TAG, "네이티브 광고 로드 완료")
                    
                    nativeAdBinder = binder
                    
                    // AdFitNativeAdLayout 구성
                    val nativeAdLayout = AdFitNativeAdLayout.Builder(nativeAdViewContainer)
                        .setTitleView(titleTextView)
                        .setBodyView(bodyTextView)
                        .setMediaView(mediaView)
                        .setCallToActionButton(callToActionButton)
                        .build()
                    
                    // 광고 노출
                    binder.bind(nativeAdLayout)
                }

                override fun onAdLoadError(errorCode: Int) {
                    Log.e(TAG, "네이티브 광고 로드 실패: errorCode=$errorCode")
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 로드 중 오류", e)
        }
    }

    /**
     * DP를 픽셀로 변환
     */
    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        try {
            nativeAdBinder?.unbind()
            nativeAdBinder = null
            nativeAdLoader = null
            container.removeAllViews()
            Log.d(TAG, "네이티브 광고 리소스 해제")
        } catch (e: Exception) {
            Log.e(TAG, "네이티브 광고 리소스 해제 중 오류", e)
        }
    }
}

