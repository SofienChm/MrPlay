package com.mrplay.app

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/** Hub-page Native Advanced ad (factoryId `mrplayNative`), same card as iOS. */
class MrPlayNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

  override fun createNativeAd(
      nativeAd: NativeAd,
      customOptions: MutableMap<String, Any>?
  ): NativeAdView {
    val adView =
        LayoutInflater.from(context).inflate(R.layout.native_ad_hub, null) as NativeAdView

    val media = adView.findViewById<MediaView>(R.id.native_ad_media)
    val headline = adView.findViewById<TextView>(R.id.native_ad_headline)
    val body = adView.findViewById<TextView>(R.id.native_ad_body)
    val cta = adView.findViewById<Button>(R.id.native_ad_cta)

    adView.mediaView = media
    adView.headlineView = headline
    adView.bodyView = body
    adView.callToActionView = cta

    headline.text = nativeAd.headline
    media.mediaContent = nativeAd.mediaContent

    if (nativeAd.body == null) {
      body.visibility = View.INVISIBLE
    } else {
      body.visibility = View.VISIBLE
      body.text = nativeAd.body
    }
    if (nativeAd.callToAction == null) {
      cta.visibility = View.INVISIBLE
    } else {
      cta.visibility = View.VISIBLE
      cta.text = nativeAd.callToAction
    }

    adView.setNativeAd(nativeAd)
    return adView
  }
}
