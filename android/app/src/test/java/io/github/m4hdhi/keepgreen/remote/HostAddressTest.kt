package io.github.m4hdhi.keepgreen.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostAddressTest {
    @Test
    fun `reads what the desktop shows`() {
        assertEquals(HostAddress("192.168.1.20", null), HostAddress.parse("192.168.1.20"))
        assertEquals(HostAddress("192.168.1.20", 47321), HostAddress.parse(" 192.168.1.20:47321 "))
        assertEquals(HostAddress("my-pc.local", 47321), HostAddress.parse("http://my-pc.local:47321/"))
    }

    @Test
    fun `reads IPv6 with and without a port`() {
        assertEquals(HostAddress("fe80::1", null), HostAddress.parse("fe80::1"))
        assertEquals(HostAddress("fe80::1", 47321), HostAddress.parse("[fe80::1]:47321"))
    }

    @Test
    fun `rejects things that aren't addresses`() {
        assertNull(HostAddress.parse(""))
        assertNull(HostAddress.parse("my pc"))
        assertNull(HostAddress.parse("192.168.1.20:"))
        assertNull(HostAddress.parse("192.168.1.20:99999"))
        assertNull(HostAddress.parse("user@host"))
        assertNull(HostAddress.parse("[fe80::1"))
    }
}
