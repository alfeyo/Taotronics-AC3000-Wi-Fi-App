package com.ttrouter.tt_router_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BleResponseParserTest {
    private val known = setOf("/GetDevInfo", "/SetWizardWireless")

    @Test
    fun parsesKnownCommandReply() {
        val reply = BleResponseParser.parse(
            "GetDevInfo,{\"ErrorCode\":0,\"Data\":{\"MeshId\":\"abc\"}}\n",
            known,
            "/SetWizardWireless",
        )
        assertEquals("/GetDevInfo", reply.command)
        assertEquals(0, reply.errorCode)
        assertEquals("abc", reply.body.getJSONObject("Data").getString("MeshId"))
    }

    @Test
    fun unknownPrefixFallsBackToLastWrittenCommand() {
        val reply = BleResponseParser.parse("Other,{\"ErrorCode\":2}", known, "/SetWizardWireless")
        assertEquals("/SetWizardWireless", reply.command)
        assertEquals(2, reply.errorCode)
    }

    @Test
    fun malformedRepliesRaiseProtocolErrorsNotCrashes() {
        val bad = listOf(
            "",
            "no separator",
            ",{\"ErrorCode\":0}",
            "GetDevInfo,{not json",
            "GetDevInfo,[1,2,3]",
            "GetDevInfo,{\"Data\":{}}",
            "GetDevInfo,{\"ErrorCode\":\"oops\"}",
        )
        for (message in bad) {
            assertThrows(message, BleProtocolException::class.java) {
                BleResponseParser.parse(message, known, "/GetDevInfo")
            }
        }
    }
}
