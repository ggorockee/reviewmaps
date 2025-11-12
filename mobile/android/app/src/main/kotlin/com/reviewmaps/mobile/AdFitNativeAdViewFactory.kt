package com.reviewmaps.mobile

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * 카카오 AdFit 네이티브 광고 플랫폼 뷰 팩토리
 */
class AdFitNativeAdViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    companion object {
        const val VIEW_TYPE = "flutter_adfit/native"
    }

    @Suppress("UNCHECKED_CAST")
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String, Any>
        return AdFitNativeAdView(context!!, viewId, creationParams)
    }
}

