package com.ttrouter.tt_router_flutter

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Non-exportable P-256 signing keys for Argon VPN commands, one per pairing
 * (`argon.vpn.<instanceId>.<deviceId>`; the legacy per-install alias
 * `argon.vpn.<instanceId>` is still accepted so an existing grant keeps
 * working). StrongBox is preferred; the TEE is the fallback. Which one holds
 * the key is recorded as a non-secret label the UI can show.
 */
class ArgonDeviceKeys(context: Context) {
    private val prefs = context.getSharedPreferences("argon_device_keys", Context.MODE_PRIVATE)

    companion object {
        private const val UUID = "[0-9a-f-]{36}"
        private val ALIAS = Regex("^argon\\.vpn\\.$UUID(\\.$UUID)?$")
    }

    private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "list") {
                result.success(store().aliases().toList().filter { ALIAS.matches(it) })
                return
            }
            val alias = call.argument<String>("alias").orEmpty()
            require(ALIAS.matches(alias))
            val store = store()
            when (call.method) {
                "exists" -> result.success(store.containsAlias(alias))
                "delete" -> {
                    if (store.containsAlias(alias)) store.deleteEntry(alias)
                    prefs.edit().remove(alias).apply()
                    result.success(null)
                }
                "publicKey" -> {
                    if (!store.containsAlias(alias)) generate(alias)
                    result.success(Base64.encodeToString(store.getCertificate(alias).publicKey.encoded, Base64.NO_WRAP))
                }
                "hardware" -> result.success(if (store.containsAlias(alias)) hardware(store, alias) else null)
                "sign" -> {
                    val message = call.argument<String>("message").orEmpty()
                    require(message.startsWith("argon-device-v2\n") && message.length <= 4096)
                    val signature = Signature.getInstance("SHA256withECDSA")
                    signature.initSign(store.getKey(alias, null) as PrivateKey)
                    signature.update(message.toByteArray(Charsets.UTF_8))
                    result.success(Base64.encodeToString(signature.sign(), Base64.NO_WRAP))
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("key_unavailable", "Phone signing key is unavailable", null)
        }
    }

    private fun generate(alias: String) {
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(
            alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .apply { if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setIsStrongBoxBacked(true) }
            .build()
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generator.initialize(spec(true))
                generator.generateKeyPair()
                prefs.edit().putString(alias, "strongbox").apply()
                return
            } catch (_: StrongBoxUnavailableException) {
                // No StrongBox on this phone: fall through to the TEE.
            }
        }
        generator.initialize(spec(false))
        generator.generateKeyPair()
        prefs.edit().remove(alias).apply()
    }

    /** "strongbox", "tee" or "software". Never secret. */
    private fun hardware(store: KeyStore, alias: String): String {
        prefs.getString(alias, null)?.let { return it }
        val key = store.getKey(alias, null) as PrivateKey
        val info = KeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                else -> "tee"
            }
        }
        @Suppress("DEPRECATION")
        return if (info.isInsideSecureHardware) "tee" else "software"
    }
}
