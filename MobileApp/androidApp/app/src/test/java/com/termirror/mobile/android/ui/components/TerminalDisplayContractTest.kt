package com.termirror.mobile.android.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class TerminalDisplayContractTest {
    @Test
    fun encodesSgrAndX10WheelEvents() {
        assertEquals("\u001B[<64;12;7M", encodeTerminalWheel(TerminalMouseProtocol.SGR, TerminalWheelDirection.UP, 12, 7))
        assertEquals("\u001B[<65;1;1M", encodeTerminalWheel(TerminalMouseProtocol.SGR, TerminalWheelDirection.DOWN, -2, 0))
        assertEquals("\u001B[M`!!", encodeTerminalWheel(TerminalMouseProtocol.X10, TerminalWheelDirection.UP, 1, 1))
        assertEquals("", encodeTerminalWheel(TerminalMouseProtocol.NONE, TerminalWheelDirection.UP, 1, 1))
    }

    @Test
    fun accumulatesAndBoundsWheelSteps() {
        val pending = consumeTerminalWheelDelta(0f, 20f)
        assertEquals(0, pending.steps)
        assertEquals(20f, pending.remainder)

        val upward = consumeTerminalWheelDelta(pending.remainder, 40f)
        assertEquals(TerminalWheelDirection.UP, upward.direction)
        assertEquals(2, upward.steps)
        assertEquals(4f, upward.remainder)

        val bounded = consumeTerminalWheelDelta(0f, -300f)
        assertEquals(TerminalWheelDirection.DOWN, bounded.direction)
        assertEquals(4, bounded.steps)
    }
}
