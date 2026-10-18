package com.ttrouter.tt_router_flutter

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Bluetooth Classic (RFCOMM/SPP) client for Argon's read-only monitoring bridge
 * (argon-bt-bridge on the Pi). One request = connect, send one JSON line, read
 * one JSON line, close. Requests run one at a time on a single worker thread.
 * Never prompts for permissions; the Dart side asks once, on user action.
 */
class ArgonBluetooth(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    companion object {
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
        private const val MAX_REPLY = 512 * 1024
        private val MAC = Regex("^[0-9A-F]{2}(:[0-9A-F]{2}){5}$")
    }

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                result.success(
                    mapOf(
                        "supported" to (adapter != null),
                        "enabled" to (adapter?.isEnabled == true),
                        "permission" to hasConnectPermission(),
                    ),
                )
            }
            "request" -> {
                val address = call.argument<String>("address").orEmpty().uppercase()
                val line = call.argument<String>("line").orEmpty()
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 12000).coerceIn(2000, 30000)
                if (!MAC.matches(address) || line.isEmpty() || line.contains('\n') || line.length > 16384) {
                    result.error("invalid", "Invalid Bluetooth request.", null)
                    return
                }
                if (!hasConnectPermission()) {
                    result.error("permission", "Bluetooth permission not granted.", null)
                    return
                }
                worker.execute { request(address, line, timeoutMs, result) }
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("MissingPermission")
    private fun request(address: String, line: String, timeoutMs: Int, result: MethodChannel.Result) {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null || !adapter.isEnabled) {
            main.post { result.error("unavailable", "Bluetooth is off or unsupported.", null) }
            return
        }
        var socket: BluetoothSocket? = null
        val watchdog = Executors.newSingleThreadScheduledExecutor()
        try {
            // The bridge accepts unauthenticated RFCOMM; every monitoring read is
            // still authorised by the companion credential inside the request.
            socket = adapter.getRemoteDevice(address).createInsecureRfcommSocketToServiceRecord(SPP_UUID)
            val s = socket
            watchdog.schedule({ try { s.close() } catch (_: Exception) {} }, timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            s.connect()
            s.outputStream.write((line + "\n").toByteArray(StandardCharsets.UTF_8))
            s.outputStream.flush()
            val buffer = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            val input = s.inputStream
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                val nl = chunk.indexOfFirst(n) { it == '\n'.code.toByte() }
                if (nl >= 0) { buffer.write(chunk, 0, nl); break }
                buffer.write(chunk, 0, n)
                if (buffer.size() > MAX_REPLY) throw IllegalStateException("reply too large")
            }
            val reply = buffer.toString(StandardCharsets.UTF_8.name())
            main.post { result.success(reply) }
        } catch (e: Exception) {
            main.post { result.error("io", e.message ?: "Bluetooth request failed.", null) }
        } finally {
            watchdog.shutdownNow()
            try { socket?.close() } catch (_: Exception) {}
        }
    }

    private inline fun ByteArray.indexOfFirst(limit: Int, predicate: (Byte) -> Boolean): Int {
        for (i in 0 until limit) if (predicate(this[i])) return i
        return -1
    }
}
