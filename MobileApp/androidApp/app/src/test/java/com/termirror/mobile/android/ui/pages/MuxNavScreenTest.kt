package com.termirror.mobile.android.ui.pages

import com.termirror.mobile.android.core.SettingsStore.GROUPING_DIRECTORY
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MuxNavScreenTest {
    @Test
    fun deduplicatesAttachedClientsAcrossWindows() {
        val raw = """
            {"windows":[
              {"title":"Terminal A","tabs":[{"title":"tab-14","active":true,"mux":"TMUX","session":"tab-14","cwd":"~/Repo"}]},
              {"title":"Terminal B","tabs":[{"title":"tab-14","active":false,"mux":"tmux","session":"tab-14","cwd":"~/Repo"}]}
            ],"detached":[]}
        """.trimIndent()

        val result = parseMuxResult(raw, "window")

        assertEquals(1, result.size)
        assertEquals(1, result.single().tabs.size)
    }

    @Test
    fun directoryModeUsesServerGroupTitleAndKeepsUniqueSessions() {
        val raw = """
            {"windows":[{"title":"~/Repo/TermHook","tabs":[
              {"title":"tab-14","active":true,"mux":"TMUX","session":"tab-14","cwd":"tab-14"},
              {"title":"tab-13","active":false,"mux":"TMUX","session":"tab-13","cwd":"tab-13"},
              {"title":"duplicate","active":false,"mux":"TMUX","session":"tab-14","cwd":"duplicate"}
            ]}],"detached":[]}
        """.trimIndent()

        val result = parseMuxResult(raw, GROUPING_DIRECTORY, useServerDirectory = true)

        assertEquals(1, result.size)
        assertEquals("~/Repo/TermHook", result.single().title)
        assertEquals(2, result.single().tabs.size)
    }

    @Test
    fun attachCommandRejectsNestedMuxAndNeverSwitchesClients() {
        val tmux = buildMuxAttachCommand("TMUX", "tab'14")
        val rmux = buildMuxAttachCommand("RMUX", "team")

        assertTrue(tmux.contains("if [ -n \"\${TMUX-}\${RMUX_SESSION-}\${RMUX-}\" ]"))
        assertTrue(tmux.contains("exec tmux attach-session -f ignore-size -t 'tab'\"'\"'14'"))
        assertTrue(rmux.contains("exec rmux attach-session -f ignore-size -t 'team'"))
        assertTrue(tmux.contains("tmux refresh-client -t \"\$client\" -D 999"))
        assertTrue(tmux.contains("SSH_TTY"))
        assertFalse(tmux.contains("switch-client"))
        assertFalse(rmux.contains("switch-client"))
    }
}
