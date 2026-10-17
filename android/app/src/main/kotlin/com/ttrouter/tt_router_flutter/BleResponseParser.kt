package com.ttrouter.tt_router_flutter

import org.json.JSONException
import org.json.JSONObject

/** A decrypted reply from the router's Bluetooth setup service. */
data class BleResponse(
    val command: String,
    val errorCode: Int,
    val body: JSONObject,
)

class BleProtocolException(message: String) : Exception(message)

/**
 * Parses `<Command>,<json>` replies. Never lets JSON or index errors escape:
 * anything malformed becomes a [BleProtocolException] the caller turns into a
 * Flutter error instead of crashing the activity.
 */
object BleResponseParser {
    fun parse(
        message: String,
        knownCommands: Set<String>,
        fallbackCommand: String,
    ): BleResponse {
        val separator = message.indexOf(',')
        if (separator < 1) {
            throw BleProtocolException("Router reply has no command prefix.")
        }
        val responseCommand = "/${message.substring(0, separator).trim()}"
        val command = if (responseCommand in knownCommands) {
            responseCommand
        } else {
            fallbackCommand
        }
        val json = message.substring(separator + 1).trim()
        val body = try {
            JSONObject(json)
        } catch (e: JSONException) {
            throw BleProtocolException("Router reply for $command is not valid JSON.")
        }
        if (!body.has("ErrorCode")) {
            throw BleProtocolException("Router reply for $command has no ErrorCode.")
        }
        val errorCode = body.optInt("ErrorCode", Int.MIN_VALUE)
        if (errorCode == Int.MIN_VALUE) {
            throw BleProtocolException("Router reply for $command has a non-numeric ErrorCode.")
        }
        return BleResponse(command, errorCode, body)
    }
}
