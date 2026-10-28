import QtQuick
import QtTest
import "../../Linphone/view/Page/SingleView/historyHelper.js" as H

// Pure-logic tests for the single-view call history panel. Run with:
//   ~/Qt/6.10.3/macos/bin/qmltestrunner -input tests/singleview
TestCase {
	name: "historyHelper"

	// Mirrors LinphoneEnums.CallStatus (same order as linphone::Call::Status)
	readonly property var st: ({ Declined: 0, Missed: 1, Success: 2, Aborted: 3, EarlyAborted: 4,
								 AcceptedElsewhere: 5, DeclinedElsewhere: 6 })

	function test_classify_missed_incoming() {
		compare(H.classify(st.Missed, false, st), "missed")
	}
	function test_classify_answered_by_direction() {
		compare(H.classify(st.Success, true, st), "outgoing")
		compare(H.classify(st.Success, false, st), "incoming")
	}
	function test_classify_accepted_elsewhere_is_incoming() {
		compare(H.classify(st.AcceptedElsewhere, false, st), "incoming")
	}
	function test_classify_incoming_declined_is_declined() {
		compare(H.classify(st.Declined, false, st), "declined")
		compare(H.classify(st.DeclinedElsewhere, false, st), "declined")
	}
	function test_classify_caller_gave_up_counts_as_missed() {
		compare(H.classify(st.Aborted, false, st), "missed")
		compare(H.classify(st.EarlyAborted, false, st), "missed")
	}
	function test_classify_outgoing_failures_are_unanswered() {
		compare(H.classify(st.Declined, true, st), "unanswered")
		compare(H.classify(st.Aborted, true, st), "unanswered")
		compare(H.classify(st.EarlyAborted, true, st), "unanswered")
	}

	function test_isMissed_only_for_missed_kind() {
		verify(H.isMissed("missed"))
		verify(!H.isMissed("incoming"))
		verify(!H.isMissed("declined"))
	}

	function test_subtitle_joins_non_empty_parts() {
		compare(H.subtitle(["Missed", "10:42", ""]), "Missed · 10:42")
		compare(H.subtitle(["Outgoing", "10:12", "3:40"]), "Outgoing · 10:12 · 3:40")
		compare(H.subtitle(["", "", ""]), "")
	}

	function test_durationLabel_only_for_answered_calls() {
		var fmt = function(s) { return "D" + s }
		compare(H.durationLabel("incoming", 65, fmt), "D65")
		compare(H.durationLabel("outgoing", 5, fmt), "D5")
		compare(H.durationLabel("outgoing", 0, fmt), "")
		compare(H.durationLabel("missed", 65, fmt), "")
		compare(H.durationLabel("declined", 65, fmt), "")
	}

	function test_missedSince_counts_missed_newer_than_last_seen() {
		var entries = [
			{ kind: "missed",   dateMs: 1000 },
			{ kind: "missed",   dateMs: 2000 },
			{ kind: "incoming", dateMs: 3000 },
			{ kind: "missed",   dateMs: 4000 }
		]
		compare(H.missedSince(entries, 0), 3)
		compare(H.missedSince(entries, 2000), 1)   // strictly newer than last seen
		compare(H.missedSince(entries, 4000), 0)
		compare(H.missedSince([], 0), 0)
	}

	function test_windowWidth_adds_panel_only_when_open() {
		compare(H.windowWidth(400, 280, false), 400)
		compare(H.windowWidth(400, 280, true), 680)
	}
}
