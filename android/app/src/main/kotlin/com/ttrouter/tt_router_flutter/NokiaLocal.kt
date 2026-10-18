package com.ttrouter.tt_router_flutter

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.URL
import java.util.concurrent.Executors

/** Nokia requests use the Wi-Fi Network only, never bind the whole process.
 * Argon/Tailscale and TaoTronics retain their existing independent transports. */
class NokiaLocal(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val resolverExecutor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private fun wifi() = cm.allNetworks.firstOrNull {
        cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    } ?: throw IllegalStateException("Join the Beacon setup Wi-Fi or its household LAN first.")

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "openWifi") {
            context.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(null)
            return
        }
        if (call.method !in setOf("context", "resolve", "request", "encryptForm", "internet")) { result.notImplemented(); return }
        val worker = if (call.method == "resolve") resolverExecutor else executor
        worker.execute {
            try {
                val network = if (call.method == "encryptForm") null else wifi()
                val value: Any? = when (call.method) {
                    "encryptForm" -> {
                        val pem = call.argument<String>("publicKey").orEmpty()
                        val encoded = pem.replace(Regex("-----[^-]+-----"), "").replace(Regex("\\s"), "")
                        val publicKey = java.security.KeyFactory.getInstance("RSA").generatePublic(
                            java.security.spec.X509EncodedKeySpec(android.util.Base64.decode(encoded, android.util.Base64.DEFAULT)))
                        val random = java.security.SecureRandom()
                        val key = ByteArray(16).also { random.nextBytes(it) }
                        val iv = ByteArray(16).also { random.nextBytes(it) }
                        val aes = javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding")
                        aes.init(javax.crypto.Cipher.ENCRYPT_MODE, javax.crypto.spec.SecretKeySpec(key, "AES"), javax.crypto.spec.IvParameterSpec(iv))
                        val ct = aes.doFinal(call.argument<String>("plain").orEmpty().toByteArray(Charsets.UTF_8))
                        val b64 = { b: ByteArray -> android.util.Base64.encodeToString(b, android.util.Base64.NO_WRAP) }
                        val rsa = javax.crypto.Cipher.getInstance("RSA/ECB/PKCS1Padding")
                        rsa.init(javax.crypto.Cipher.ENCRYPT_MODE, publicKey)
                        val ck = rsa.doFinal((b64(key) + " " + b64(iv)).toByteArray(Charsets.UTF_8))
                        mapOf("encrypted" to "1", "ct" to b64(ct).replace('+','-').replace('/','_').trimEnd('='),
                            "ck" to b64(ck).replace('+','-').replace('/','_').replace('=','.'))
                    }

                    "internet" -> {
                        val c = network!!.openConnection(URL("https://connectivitycheck.gstatic.com/generate_204")) as HttpURLConnection
                        try { c.connectTimeout=5000;c.readTimeout=5000;c.instanceFollowRedirects=false
                            mapOf("ok" to (c.responseCode == 204), "network" to network.toString())
                        } finally { c.disconnect() }
                    }
                    "context" -> {
                        val links = cm.getLinkProperties(network)
                        val manager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        @Suppress("DEPRECATION") val info = manager.connectionInfo
                        @Suppress("DEPRECATION") val dhcp = manager.dhcpInfo
                        fun ipv4(v: Int?): String? = if(v == null || v == 0) null else (0..3).joinToString(".") { i -> ((v ushr (i*8)) and 255).toString() }
                        mapOf("ssid" to info?.ssid?.trim('"'), "bssid" to info?.bssid,
                            "dhcpServer" to ipv4(dhcp?.serverAddress),
                            "prefixLength" to links?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.prefixLength,
                            "ip" to links?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress,
                            "gateway" to links?.routes?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress,
                            "network" to network.toString())
                    }
                    "resolve" -> {
                        val host = call.argument<String>("host").orEmpty()
                        require(host in setOf("nokiadevice.local", "www.webgui.Nokiawifi.com"))
                        network!!.getAllByName(host).filter { it is Inet4Address && it.isSiteLocalAddress }.map { it.hostAddress }
                    }
                    else -> {
                        val url = URL(call.argument<String>("url").orEmpty().replace("%25", "%"))
                        val octets = url.host.split('.').map { it.toIntOrNull() ?: -1 }
                        val v6 = url.host.removePrefix("[").removeSuffix("]").lowercase()
                        val localV6 = Regex("^fe80:[0-9a-f:]+%wlan0$").matches(v6)
                        require(localV6 || (octets.size == 4 && octets.all { it in 0..255 } &&
                            (octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) ||
                            (octets[0] == 172 && octets[1] in 16..31))))
                        require(url.protocol in setOf("http", "https") && url.userInfo == null && url.ref == null && url.port == -1)
                        require(url.path in PATHS)
                        val method = call.argument<String>("method") ?: "GET"
                        require(method in setOf("GET", "POST"))
                        val body = call.argument<String>("body").orEmpty().toByteArray(Charsets.UTF_8)
                        require(body.size <= 16384)
                        val conn = network!!.openConnection(url) as HttpURLConnection
                        try {
                            conn.connectTimeout = 4000; conn.readTimeout = 5000
                            conn.instanceFollowRedirects = false; conn.useCaches = false
                            conn.requestMethod = method
                            call.argument<String>("cookie")?.let { cookie ->
                                require(!cookie.contains('\r') && !cookie.contains('\n'))
                                conn.setRequestProperty("Cookie", cookie)
                            }
                            if (method == "POST") {
                                conn.doOutput = true
                                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                                conn.setFixedLengthStreamingMode(body.size)
                                conn.outputStream.use { it.write(body) }
                            }
                            val status = conn.responseCode
                            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
                            val bytes = stream?.use { input ->
                                val output = java.io.ByteArrayOutputStream()
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val size = input.read(buffer); if (size < 0) break
                                    require(output.size() + size <= 1048576)
                                    output.write(buffer, 0, size)
                                }
                                output.toByteArray()
                            } ?: ByteArray(0)
                            var text = String(bytes, Charsets.UTF_8)
                            val responseKey = call.argument<String>("responseKey")
                            val responseIv = call.argument<String>("responseIv")
                            if (responseKey != null && responseIv != null && !text.trimStart().startsWith("{")) {
                                val aes = javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding")
                                aes.init(javax.crypto.Cipher.DECRYPT_MODE,
                                    javax.crypto.spec.SecretKeySpec(android.util.Base64.decode(responseKey, android.util.Base64.DEFAULT), "AES"),
                                    javax.crypto.spec.IvParameterSpec(android.util.Base64.decode(responseIv, android.util.Base64.DEFAULT)))
                                text = String(aes.doFinal(android.util.Base64.decode(text, android.util.Base64.DEFAULT)), Charsets.UTF_8)
                            }
                            mapOf("status" to status, "body" to text)
                        } finally { conn.disconnect() }
                    }
                }
                main.post { result.success(value) }
            } catch (_: Exception) {
                // Never log credentials, cookies, bodies or vendor error pages.
                main.post { result.error("nokia_local", "Local Nokia request unavailable. Check Wi-Fi, address and device support.", null) }
            }
        }
    }
    fun close() { executor.shutdownNow(); resolverExecutor.shutdownNow() }
    companion object {
        private val PATHS = setOf("/login_app.cgi", "/get_devmap_cap_status_app.cgi",
            "/device_status_app.cgi", "/wan_internet_status_app.cgi", "/whw_beacon_mode_app.cgi",
            "/whw_onboarding_status_app.cgi", "/whw_gatewayrdy_status_app.cgi",
            "/whw_zerotouchonb_status_app.cgi", "/whw_zerotouchonb_app.cgi",
            "/login_web_app.cgi", "/device_status_web_app.cgi", "/main_web_app.cgi",
            "/whw_beacon_mode_app_status_web_app.cgi", "/whw_beacon_mode_app_web_app.cgi",
            "/mesh_web_app.cgi", "/mesh_status_web_app.cgi", "/device_name_status_web_app.cgi",
            "/wlan_config_status_web_app.cgi", "/wan_internet_status_web_app.cgi",
            "/lan_status_web_app.cgi", "/lan_ipv4_status_web_app.cgi", "/wlan_list_app.cgi", "/device_name_status_app.cgi", "/whw_onboarding_app.cgi")
    }
}
