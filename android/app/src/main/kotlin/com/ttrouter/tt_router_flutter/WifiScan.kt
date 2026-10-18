package com.ttrouter.tt_router_flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Read-only access to the phone's own Wi-Fi scan results
 * (channel `tt_router/wifi_scan`, method `scan`). Never joins, changes or
 * forgets a network. Android shares results only with location permission.
 */
class WifiScan(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "scan") {
            result.notImplemented()
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error("precise_location", "Enable Precise location for TT Router in Android settings.", null)
            return
        }
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifi == null) {
            result.error("unavailable", "Wi-Fi is not available on this device.", null)
            return
        }
        if (!wifi.isWifiEnabled) {
            result.success(mapOf("wifiEnabled" to false, "results" to emptyList<Any>()))
            return
        }
        try {
            // Best effort: Android throttles scans; cached results are returned either way.
            try {
                @Suppress("DEPRECATION")
                wifi.startScan()
            } catch (_: SecurityException) {
            }
            val results = wifi.scanResults.map { r ->
                @Suppress("DEPRECATION")
                val ssid = r.SSID ?: ""
                mapOf(
                    "ssid" to ssid,
                    "bssid" to (r.BSSID ?: ""),
                    "frequency" to r.frequency,
                    "level" to r.level,
                    "capabilities" to (r.capabilities ?: ""),
                    "ageSeconds" to ((android.os.SystemClock.elapsedRealtime() * 1000 - r.timestamp).coerceAtLeast(0) / 1000000),
                )
            }
            @Suppress("DEPRECATION")
            val info = wifi.connectionInfo
            result.success(
                mapOf(
                    "wifiEnabled" to true,
                    "connectedBssid" to info?.bssid,
                    "connectedSsid" to info?.ssid,
                    "results" to results,
                ),
            )
        } catch (e: SecurityException) {
            result.error("permission", "Location permission is needed to read Wi-Fi scan results.", null)
        } catch (e: Exception) {
            result.error("scan_failed", "Wi-Fi scan failed.", e.message)
        }
    }
}
