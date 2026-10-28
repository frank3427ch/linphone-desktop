.pragma library

// Pure helpers for the single-view call history panel (no app dependencies, unit-tested
// by tests/singleview/tst_historyHelper.qml with qmltestrunner).

// Classify a call log entry. `st` is the LinphoneEnums.CallStatus enum object.
// Returns "missed" | "incoming" | "outgoing" | "declined" | "unanswered".
function classify(status, isOutgoing, st) {
	if (status === st.Missed) return "missed"
	if (status === st.Success || status === st.AcceptedElsewhere) return isOutgoing ? "outgoing" : "incoming"
	if (isOutgoing) return "unanswered"
	if (status === st.Declined || status === st.DeclinedElsewhere) return "declined"
	// Aborted / EarlyAborted on an incoming call: the caller gave up before we answered
	return "missed"
}

function isMissed(kind) {
	return kind === "missed"
}

// Join the non-empty parts with a middle dot
function subtitle(parts) {
	return parts.filter(function(p) { return p && p.length > 0 }).join(" · ")
}

// Duration is only meaningful for calls that were actually connected
function durationLabel(kind, seconds, fmt) {
	if ((kind === "incoming" || kind === "outgoing") && seconds > 0) return fmt(seconds)
	return ""
}

// Missed entries strictly newer than the last time the panel was opened
function missedSince(entries, lastSeenMs) {
	var n = 0
	for (var i = 0; i < entries.length; ++i)
		if (isMissed(entries[i].kind) && entries[i].dateMs > lastSeenMs) ++n
	return n
}

function windowWidth(baseWidth, panelWidth, open) {
	return baseWidth + (open ? panelWidth : 0)
}
