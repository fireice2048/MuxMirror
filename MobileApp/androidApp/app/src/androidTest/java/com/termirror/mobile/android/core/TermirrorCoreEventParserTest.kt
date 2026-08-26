package com.termirror.mobile.android.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TermirrorCoreEventParserTest {
    @Test
    fun parsesTerminalStyleRanges() {
        val event = TermirrorCore.parseEventJson(
            """
            {
              "sessionId": 7,
              "type": "output",
              "data": "red inverse",
              "cursor": 11,
              "styles": [
                {"start": 0, "end": 3, "style": "normal", "foreground": "#FF0000"},
                {"start": 4, "end": 11, "style": "inverse", "foreground": "#FFFFFF", "background": "#000000"}
              ]
            }
            """.trimIndent()
        )

        assertEquals(7L, event.sessionId)
        assertEquals("output", event.type)
        assertEquals(11, event.cursor)
        assertEquals(2, event.styles.size)
        assertEquals("#FF0000", event.styles[0].foreground)
        assertEquals("inverse", event.styles[1].style)
        assertEquals("#000000", event.styles[1].background)
    }

    @Test
    fun acceptsOutputWithoutStyles() {
        val event = TermirrorCore.parseEventJson(
            """{"sessionId": 8, "type": "output", "data": "plain"}"""
        )

        assertTrue(event.styles.isEmpty())
        assertEquals("plain", event.data)
    }
}
