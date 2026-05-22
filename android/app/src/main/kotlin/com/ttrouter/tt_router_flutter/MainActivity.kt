package com.ttrouter.tt_router_flutter

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var provisioner: TtRouterProvisioner? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tt_router/ble_provisioning",
        ).setMethodCallHandler(::handleBleCall)
    }

    private fun handleBleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openWifiPicker" -> {
                openWifiPicker(result)
            }
            "discoverRouter" -> {
                provisioner?.cancel()
                provisioner = TtRouterProvisioner("", "", result, true).also { it.start() }
            }
            "provisionRouter" -> {
                val ssid = call.argument<String>("ssid").orEmpty()
                val password = call.argument<String>("password").orEmpty()
                if (ssid.isBlank() || password.isBlank()) {
                    result.error("invalid_wifi", "WiFi SSID and password are required.", null)
                    return
                }

                provisioner?.cancel()
                provisioner = TtRouterProvisioner(ssid, password, result, false).also { it.start() }
            }
            else -> result.notImplemented()
        }
    }

    private fun openWifiPicker(result: MethodChannel.Result) {
        try {
            startActivity(Intent("android.net.wifi.PICK_WIFI_NETWORK"))
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
        }
        result.success(null)
    }

    override fun onDestroy() {
        provisioner?.cancel()
        super.onDestroy()
    }

    private inner class TtRouterProvisioner(
        private val wifiSsid: String,
        private val wifiPassword: String,
        private val flutterResult: MethodChannel.Result,
        private val discoveryOnly: Boolean,
    ) {
        private val handler = Handler(Looper.getMainLooper())
        private val appId = UUID.randomUUID().toString()
        private val scanTimeout = Runnable { connectBestDevice() }
        private val commandTimeout = Runnable { fail("timeout", "Router setup timed out.") }
        private val pendingWrites = ArrayDeque<ByteArray>()
        private val incoming = ByteArrayOutputStream()
        private val xorKey = byteArrayOf(
            35, 53, 64, 56, 97, 113, 43, 115,
            101, 55, 48, 126, 51, 49, 122, 121,
            97, 51, 45, 46, 101, 118, 55, 96,
            33, 64, 48, 124, 98, 38, 42, 45,
        )
        private val bluetoothManager =
            getSystemService(BluetoothManager::class.java)
        private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter
        private val scanner get() = bluetoothAdapter?.bluetoothLeScanner
        private var bestScan: ScanResult? = null
        private var gatt: BluetoothGatt? = null
        private var writeCharacteristic: BluetoothGattCharacteristic? = null
        private var notifyCharacteristic: BluetoothGattCharacteristic? = null
        private var meshId = ""
        private var serialNumber = ""
        private var wanProto = 0
        private var restartRequired = false
        private var completed = false
        private var writeCommandName = ""
        private var writeChunkCount = 0
        private var writeChunkIndex = 0
        private val busyRetries = mutableMapOf<String, Int>()

        private val scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = result.device.name ?: result.scanRecord?.deviceName ?: return
                if (!name.startsWith("TTBT")) return
                if (bestScan == null || result.rssi > bestScan!!.rssi) {
                    bestScan = result
                }
            }

            override fun onScanFailed(errorCode: Int) {
                fail("scan_failed", "Bluetooth scan failed with code $errorCode.")
            }
        }

        private val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                handler.post {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        fail("connect_failed", "Bluetooth connection failed with status $status.")
                    } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                        gatt.discoverServices()
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED && !completed) {
                        fail("disconnected", "Router Bluetooth connection closed.")
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                handler.post {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        fail("services_failed", "Router Bluetooth services could not be read.")
                        return@post
                    }

                    val service = gatt.getService(SERVICE_UUID)
                    writeCharacteristic = service?.getCharacteristic(WRITE_UUID)
                    notifyCharacteristic = service?.getCharacteristic(NOTIFY_UUID)
                    val notify = notifyCharacteristic
                    if (writeCharacteristic == null || notify == null) {
                        fail("service_missing", "TT Router setup service is missing.")
                        return@post
                    }

                    gatt.setCharacteristicNotification(notify, true)
                    val descriptor = notify.getDescriptor(CLIENT_CONFIG_UUID)
                    if (descriptor == null) {
                        sendCapabilityInfo()
                        return@post
                    }
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    if (!gatt.writeDescriptor(descriptor)) {
                        fail("notify_failed", "Router notifications could not be enabled.")
                    }
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                handler.post {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        sendCapabilityInfo()
                    } else {
                        fail("notify_failed", "Router notifications failed with status $status.")
                    }
                }
            }

            @Deprecated("Deprecated in Android")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                handleNotification(characteristic.value ?: byteArrayOf())
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                handleNotification(value)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                handler.post {
                    Log.d(
                        LOG_TAG,
                        "BLE write result $writeCommandName chunk $writeChunkIndex/$writeChunkCount status $status",
                    )
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        writeNextChunk()
                    } else {
                        fail("write_failed", "Router Bluetooth write failed with status $status.")
                    }
                }
            }
        }

        fun start() {
            if (!hasBlePermissions()) {
                fail("permission_required", "Bluetooth scan and connect permissions are required.")
                return
            }
            if (bluetoothAdapter?.isEnabled != true || scanner == null) {
                fail("bluetooth_off", "Turn on Bluetooth before router setup.")
                return
            }

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner!!.startScan(null, settings, scanCallback)
            handler.postDelayed(scanTimeout, 12000L)
        }

        fun cancel() {
            cleanup()
        }

        private fun hasBlePermissions(): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                return hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
                    hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
            }
            return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        private fun hasPermission(permission: String): Boolean {
            return ContextCompat.checkSelfPermission(
                this@MainActivity,
                permission,
            ) == PackageManager.PERMISSION_GRANTED
        }

        private fun connectBestDevice() {
            stopScan()
            val device = bestScan?.device
            if (device == null) {
                fail("not_found", "No nearby TTBT router was found.")
                return
            }
            gatt = device.connectGatt(this@MainActivity, false, gattCallback)
            armTimeout(60000L)
        }

        private fun sendGetDevInfo() {
            writeCommand(
                "/GetDevInfo",
                JSONObject()
                    .put("Sn", "")
                    .put("MeshId", "")
                    .put("Type", 0)
                    .put("RestartFlag", 0)
                    .put("Timestamp", System.currentTimeMillis() / 1000),
            )
        }

        private fun sendCapabilityInfo() {
            writeCommand(
                "/GetCapablityInfo",
                JSONObject().put("abilityList", JSONArray()),
            )
        }

        private fun sendWizardWireless() {
            writeCommand(
                "/SetWizardWireless",
                JSONObject()
                    .put("Ssid", wifiSsid)
                    .put("Password", wifiPassword),
                timestamp = true,
            )
        }

        private fun sendWanInfo() {
            writeCommand(
                "/GetMWanInfo",
                JSONArray().put(JSONObject().put("WanProto", 0)),
            )
        }

        private fun sendMeshInit() {
            writeCommand("/SetMeshInitByBt", JSONObject().put("MeshId", "1"))
        }

        private fun writeCommand(command: String, data: Any, timestamp: Boolean = false) {
            writeCommandName = command
            val envelope = JSONObject()
                .put("AppId", appId)
                .put("Timeout", 0)
                .put("ErrorCode", 0)
                .put("Data", data)
            if (timestamp) {
                envelope.put("Timestamp", System.currentTimeMillis() / 1000)
            }
            val line = "${command.substring(1)},$envelope\n"
            writeEncrypted(line.toByteArray(StandardCharsets.UTF_8))
            armTimeout(15000L)
        }

        private fun writeEncrypted(payload: ByteArray) {
            pendingWrites.clear()
            val encrypted = crypt(payload.copyOf())
            var offset = 0
            while (offset < encrypted.size) {
                val end = minOf(offset + 20, encrypted.size)
                pendingWrites.addLast(encrypted.copyOfRange(offset, end))
                offset = end
            }
            writeChunkCount = pendingWrites.size
            writeChunkIndex = 0
            writeNextChunk()
        }

        @Suppress("DEPRECATION")
        private fun writeNextChunk() {
            if (pendingWrites.isEmpty()) return
            val characteristic = writeCharacteristic
            val connection = gatt
            if (characteristic == null || connection == null) {
                fail("write_missing", "Router Bluetooth write path is unavailable.")
                return
            }
            characteristic.writeType = writeTypeFor(characteristic)
            val chunk = pendingWrites.removeFirst()
            writeChunkIndex += 1
            Log.d(
                LOG_TAG,
                "BLE write $writeCommandName chunk $writeChunkIndex/$writeChunkCount length ${chunk.size} type ${characteristic.writeType}",
            )
            characteristic.value = chunk
            if (!connection.writeCharacteristic(characteristic)) {
                fail("write_failed", "Router Bluetooth write could not start.")
            }
        }

        private fun writeTypeFor(characteristic: BluetoothGattCharacteristic): Int {
            return if (
                characteristic.properties and
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
            ) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
        }

        private fun handleNotification(value: ByteArray) {
            handler.post {
                incoming.write(value)
                if (value.isEmpty() || value.last() != '\n'.code.toByte()) return@post
                val message = String(crypt(incoming.toByteArray()), StandardCharsets.UTF_8)
                incoming.reset()
                handleResponse(message)
            }
        }

        private fun handleResponse(message: String) {
            val separator = message.indexOf(',')
            if (separator < 1) return
            val responseCommand = "/${message.substring(0, separator)}"
            val command = if (responseCommand in ROUTER_COMMANDS) {
                responseCommand
            } else {
                writeCommandName
            }
            val body = JSONObject(message.substring(separator + 1).trim())
            val errorCode = body.optInt("ErrorCode", -1)
            if (errorCode != 0) {
                if (errorCode == ROUTER_BUSY_ERROR && retryBusyCommand(command)) {
                    return
                }
                fail("router_error", "$command failed with router code $errorCode.")
                return
            }
            busyRetries.remove(command)

            when (command) {
                "/GetCapablityInfo" -> sendGetDevInfo()
                "/GetDevInfo" -> {
                    val data = body.optJSONObject("Data") ?: JSONObject()
                    meshId = data.optString("MeshId")
                    serialNumber = data.optString("Sn")
                    restartRequired = data.optInt("RestartFlag") == 0
                    if (meshId.isBlank()) {
                        fail("mesh_missing", "Router did not return a mesh id.")
                    } else if (discoveryOnly) {
                        succeed()
                    } else {
                        sendWizardWireless()
                    }
                }
                "/SetWizardWireless" -> sendWanInfo()
                "/GetMWanInfo" -> {
                    val data = body.optJSONArray("Data")
                    wanProto = data?.optJSONObject(0)?.optInt("WanProto") ?: 0
                    sendMeshInit()
                }
                "/SetMeshInitByBt" -> succeed()
            }
        }

        private fun retryBusyCommand(command: String): Boolean {
            if (command !in RETRYABLE_BUSY_COMMANDS) return false

            val retries = busyRetries.getOrDefault(command, 0)
            if (retries >= MAX_BUSY_RETRIES) return false

            busyRetries[command] = retries + 1
            Log.d(
                LOG_TAG,
                "BLE router busy for $command, retry ${retries + 1}/$MAX_BUSY_RETRIES",
            )
            handler.postDelayed(
                {
                    when (command) {
                        "/SetWizardWireless" -> sendWizardWireless()
                        "/GetMWanInfo" -> sendWanInfo()
                        "/SetMeshInitByBt" -> sendMeshInit()
                    }
                },
                BUSY_RETRY_DELAY_MS,
            )
            armTimeout(30000L)
            return true
        }

        private fun crypt(bytes: ByteArray): ByteArray {
            for (index in bytes.indices) {
                val original = bytes[index]
                val encoded = (original.toInt() xor xorKey[index and 31].toInt()).toByte()
                if (!isReserved(original) && !isReserved(encoded)) {
                    bytes[index] = encoded
                }
            }
            return bytes
        }

        private fun isReserved(value: Byte): Boolean {
            return value == '$'.code.toByte() ||
                value == '\n'.code.toByte() ||
                value == 'e'.code.toByte() ||
                value == '}'.code.toByte() ||
                value == 'a'.code.toByte() ||
                value == 'o'.code.toByte()
        }

        private fun succeed() {
            if (completed) return
            completed = true
            handler.post {
                flutterResult.success(
                    mapOf(
                        "meshId" to meshId,
                        "serialNumber" to serialNumber,
                        "wanProto" to wanProto,
                        "restartRequired" to restartRequired,
                    ),
                )
                cleanup()
            }
        }

        private fun fail(code: String, message: String) {
            if (completed) return
            completed = true
            handler.post {
                flutterResult.error(code, message, null)
                cleanup()
            }
        }

        private fun armTimeout(delayMs: Long) {
            handler.removeCallbacks(commandTimeout)
            handler.postDelayed(commandTimeout, delayMs)
        }

        private fun stopScan() {
            handler.removeCallbacks(scanTimeout)
            try {
                scanner?.stopScan(scanCallback)
            } catch (_: SecurityException) {
            }
        }

        private fun cleanup() {
            stopScan()
            handler.removeCallbacks(commandTimeout)
            try {
                gatt?.disconnect()
                gatt?.close()
            } catch (_: SecurityException) {
            }
            gatt = null
        }
    }

    companion object {
        private const val BUSY_RETRY_DELAY_MS = 1000L
        private const val MAX_BUSY_RETRIES = 5
        private const val ROUTER_BUSY_ERROR = 2
        private val ROUTER_COMMANDS = setOf(
            "/GetCapablityInfo",
            "/GetDevInfo",
            "/SetWizardWireless",
            "/GetMWanInfo",
            "/SetMeshInitByBt",
        )
        private val RETRYABLE_BUSY_COMMANDS = setOf(
            "/SetWizardWireless",
            "/GetMWanInfo",
            "/SetMeshInitByBt",
        )
        private val SERVICE_UUID: UUID =
            UUID.fromString("0000E0FF-3C17-D293-8E48-14FE2E4DA212")
        private val WRITE_UUID: UUID =
            UUID.fromString("0000FFE1-0000-1000-8000-00805F9B34FB")
        private val NOTIFY_UUID: UUID =
            UUID.fromString("0000FFE2-0000-1000-8000-00805F9B34FB")
        private val CLIENT_CONFIG_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
        private const val LOG_TAG = "TtRouterBle"
    }
}
