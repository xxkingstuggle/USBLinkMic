package io.github.teamclouday.androidMic.utils

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UtilsTest {
    @Test
    fun checkIpAcceptsOnlyValidIpv4Literals() {
        assertTrue(checkIp("192.168.1.8"))
        assertTrue(checkIp(" 10.0.0.1 "))
        assertFalse(checkIp("192.168."))
        assertFalse(checkIp("256.1.1.1"))
        assertFalse(checkIp("example.com"))
    }

    @Test
    fun checkPortEnforcesTcpPortRange() {
        assertTrue(checkPort("1"))
        assertTrue(checkPort("65535"))
        assertFalse(checkPort("0"))
        assertFalse(checkPort("65536"))
        assertFalse(checkPort("not-a-port"))
    }

    @Test
    fun chunkedCoversTheWholeArray() {
        val chunks = byteArrayOf(1, 2, 3, 4, 5).chunked(2)
        assertTrue(chunks.size == 3)
        assertArrayEquals(byteArrayOf(1, 2), chunks[0])
        assertArrayEquals(byteArrayOf(3, 4), chunks[1])
        assertArrayEquals(byteArrayOf(5), chunks[2])
    }
}
