# Mobile session status verification

## Human checks

Link each phone, enable **Forward sessions** on the sending Mac, and use the
installed desktop CLI. Connect and authorize a Dot for LED checks.

1. Send `sidepulse report --scope mobile-check --state working --title "Mobile check"`.
   The session appears without requiring hardware. Send Blocked, Error, Done,
   and Clear and verify the row's latest state or removal. Repeat from a second
   paired computer with the same session name; its row must remain independent.
2. In Settings → Session display, choose saved patterns for Working, Done, and Ask.
   On iOS, choosing a pattern or enabling a state immediately previews that
   state's pattern once on the connected Dot, even with no matching session.
   Repeat with automatic session LEDs off: explicit previews still work.
   Previewing must not add/change session rows or create a synthetic Live Activity.
   Unplug/reconnect after a preview: it must not replay. A fresh enabled status
   may replace it normally.
   Only Ask is on by default. Blocked and Error both use Ask; hidden/Idle updates do not overwrite other output.
   Repeat the reports and check the connected Dot. Delete a chosen pattern and
   verify its built-in fallback on the next render/update. Settings survive restart.
3. While a session animation is playing, turn **Use sessions for LEDs** off.
   LEDs turn off and session rows still update. Play a manual/Shortcut pattern,
   then send a newer session report while the master switch is off: the manual
   pattern must keep playing. Re-enable session LEDs and verify the current
   enabled state is rendered.
4. Send a direct manual LED command to the phone with `sidepulse push 'off' --to
   '<phone name>'`. The LED changes without adding/removing sessions. A duplicate
   status or reconnect must not override that successful write; a newer accepted enabled
   session report gets one LED attempt.
5. On iOS, run **Play SidePulse Pattern** or **Write SidePulse LEDS.LED** from
   Shortcuts. On Android, use a saved pattern's home-screen shortcut or
   `sidepulse://write?pattern=success`. These have the same manual ownership
   behavior and do not change tracked sessions.
6. Clear a row (iOS swipe-left Clear; Android Clear session). Replaying its
   previous sequence must keep it hidden across restart; a newer report restores it.
7. Enable only Ask. Send Ask, then a newer Done: the row shows Done and the
   previous orange session pattern stops. Repeat with Working, Idle and Clear.
   With Ask sessions from two senders, resolving one must preserve the other
   without replaying its unchanged pattern; resolving the last turns LEDs off.
   Play a manual/Shortcut/preview pattern between Ask and Done: Done must leave
   that pattern alone. Duplicate/stale reports and reconnects must stay quiet.
   Session rows must have no Done acknowledgement action.
8. On iOS, enable **Session Live Activity**, open SidePulse, then lock the phone.
   Verify one combined eight-light visualization and Dynamic Island, with no titles, messages, paths, or counts. Tap it to open Sessions. Disable session LEDs and repeat;
   the activity still updates. Turn Live Activity off or clear/revoke all sessions;
   the activity ends. Old reports dim when stale. With only Ask enabled, Ask → Done ends the activity while retaining the Done row. iOS controls background delivery.
9. In Settings → Session display, verify only Working, Done, and Ask appear.
   Turn Working off and leave Done and Ask on. Send Error from one source and
   Done from another: both stay listed; Error uses the Ask pattern. Turn Ask off:
   Done controls LEDs and iOS Live Activity. Re-enable Ask while the app is open:
   Error takes priority again. Switch all three off: LEDs turn off and Live
   Activity ends without removing sessions. Restart and verify switches and
   chosen patterns persist. Manual remote and Shortcut writes still work.
   Restore the original settings.
10. Submit an old `program_status_snapshot` envelope, even with a valid outer
   key and an LED field. It must neither alter sessions nor become a direct write.

## Last pattern source

- Home identifies the last successful write with its source, pattern and local date/time. Exercise a session, remote push, Shortcut, library pattern, manual Off and settings preview.
- A failed/disconnected write, duplicate status, background refresh or opening a session must not replace that receipt. Restart must retain the receipt without replaying LEDs.
- Existing installations show “Not recorded yet” until the first successful write on the updated build. A finite pattern finishing does not erase its last-write receipt.

## Review follow-up checks

- Cold start, reconnect, and unplugged writes stay quiet. No persisted LED ownership or automatic retry is restored.
- Open a shared session link, return to all sessions, and open the same link again. A missing row explains why. No link changes LEDs or session state.
- Recovery supplies each active paired key separately and never reveals or drains another key’s records.
- iOS: dismiss/end the activity, then send a fresh Ask while active; test stale/expired Done on foreground, suspended/terminated delivery, and the system lifetime limit. These physical lifecycle cases remain TODO.
- Repeat Direct remote LED write and Shortcut actions with attached authorized Dot hardware. Local parsing/build checks do not establish USB or provider delivery.

## Latest automated checks (2026-10-19)

- Swift package: 91 tests pass, covering individual-update fixtures, validation,
  sender isolation, bounded replay guards, 64-session eviction, one-shot output,
  configurable patterns, and combined-activity data.
- Android: 96 unit tests, debug lint, and debug build pass. Four focused emulator
  checks pass for editable settings, LED master-off behavior, repeated session links, and paired-source
  isolation. Manual LED ownership while disabled is covered by both unit suites.
- iOS simulator app and widget build pass. Each accepted update now refreshes
  the session list and Live Activity once; LEDs use that same session list.
- Desktop: 941 tests and 600 subtests pass, including isolated local bridge
  checks. Distinct active source/session rows are counted separately. Mac sleep
  control, history sampling, and output holds run in the daemon without the tray;
  those local controls do not change the bridge/mobile status format.
- The latest signed iPhone build is installed after reconnecting. Apple accepted
  test push through the local bridge. After manual app launch, fresh Working and
  Ask states were confirmed in the phone ledger through the real Claude hook,
  isolated daemon socket, local bridge, and APNs. Visual Live Activity and Dot
  checks remain pending; Apple developer services still block remote launch
  and screenshots. Nothing was deployed to production.

## Physical follow-up (2026-10-20)

- iPhone USB developer services and remote launch work. Physical screenshots
  confirm fresh Needs approval and a session deep link showing only its row.
- Dot is disconnected. LED/Shortcut output and Live Activity lifecycle remain
  pending; XCTest automation requires passcode confirmation on the phone.
- Android debug/test APKs build. The Pixel debugging endpoint times out and no
  USB/mDNS device is visible, so current Android installation is still pending.
- Local bridge tests only; no production deployment.

## Earlier device and simulator evidence

Earlier builds passed all 11 Android UI checks across a full run and focused
reruns, and Android release compilation. The pattern dropdown selector was
corrected to select the popup rather than its same-named settings row.

Earlier iOS simulator checks covered the session list, swipe clearing, newer
pushed restoration, settings/Live Activity toggles, custom patterns, Lock Screen
card, and Dynamic Island. The card worked with session LED output disabled.
A signed iPhone build was installed before the later cleanups; remote launch
was blocked while the phone was locked. This is not installation evidence for
the latest source.

A clean disposable simulator rendered the widget after an in-place extension
update had left cached blank cards. Its final view used a fixed last-reported
timestamp. External-URL automation stopped at the system Open-in-App confirmation,
so the complete activity-tap interaction remains a human phone check. The
disposable simulator was removed and original simulator preferences restored.
No ActivityKit server or push channel was added; iOS controls background delivery.

October 20 later device pass: Android 0.2.3/build 7 is installed and the Dot is
connected. Local Shortcut-style success and Off actions received firmware applied
acknowledgements (commands 3 and 4). The Mac’s saved Pixel sender key is absent
from the phone’s active keys; remote FCM receiver checks await permission for a
temporary test key. The iPhone’s later local LED URL could not launch because
it had locked again; no iPhone hardware success is claimed.


October 20 authorized Android end-to-end pass: created a temporary sender key
through the Pixel UI, then revoked it after testing. Both original keys and
saved output settings were preserved. Actual Claude hooks passed through an
isolated daemon/socket and a loopback Rust bridge over real FCM to the phone.
Working, Ask, Done and Clear reached accounting. Dot firmware acknowledged Ask,
Done, acknowledgement/clear Off, direct remote success, and final manual Off
(commands 5–15). Disabled Working left the manual pattern unchanged. Correctly
wrapped duplicate/stale updates caused no extra LED write; Clear survived their
replay, and a fresh Ask restored the session. Done acknowledgement kept Idle,
and the session deep link filtered one row. After revocation, a fresh update
could not restore a row or write LEDs. The Mac’s old saved Pixel link was not
changed and still needs re-pairing for normal forwarding. Physical unplug/replug,
background lifecycle and iPhone LED/Live Activity checks remain pending.


October 20 unlocked iPhone follow-up: the actual local hook/daemon/loopback
bridge/APNs Ask wrote 29 bytes to LEDS.LED. A direct remote success push wrote
36 bytes and was recorded as a foreground push. Done was confirmed in accounting;
the disabled-state sends caused no replacement of the manual program. Replaying
the already-received Ask and an older sequence caused no additional file write.
iOS confirms the filesystem write rather than firmware application. Physical
XCTest timed out enabling automation mode. Live Activity visual confirmation and
a native Shortcut action are awaiting the user’s device checks. The unsupported
sidepulse://write URL was not counted as a Shortcut test; native App Intents are
the intended iOS Shortcut path. No production bridge deployment.


October 20 user-assisted acceptance: the user confirmed eight static dark-red
Live Activity lights and ran the native Blink action. The phone recorded
`Shortcut: Pulse Red (Wrote LEDS.LED)` at 20:04:57Z, with a 48-byte write.
All three core foreground paths are verified: session-driven LEDs, remote manual
LEDs and native Shortcuts. Foreground cleanup confirmed the test session cleared
and a remote 4-byte Off write at 20:06:01Z. Continuous flashing is not implemented
in Live Activity; existing stale dimming reduces opacity to 35% after five minutes.
Physical manual dismissal/restart lifecycle remains an open check. No behavior
was changed during this device pass and no production bridge was deployed.


October 20: last-pattern update built and installed after 91 package tests and native app/widget build passed. The physical phone saved “Shortcut · Ocean” at 21:15:28Z after the user ran the action. UI automation remains unavailable; this is receipt verification, not a new iPhone screenshot.

## Ask completion fix — October 20

Removed the local Done-to-Idle acknowledgement action and its accounting code.
A newly received hidden/Idle/Clear state now updates an existing session output
only when the resulting LED program changes. With only Ask enabled, Ask → Done
sends Off. Other senders' unchanged Ask output is not replayed, and later
successful manual/Shortcut/preview writes retain ownership. Startup, reconnect,
accounting-only reception, and duplicate/stale reports stay quiet.

Automated checks: Android 95 unit tests, debug build, lint and instrumentation
compilation; iOS 90 package tests and signed app/widget build. Both physical
phones were updated in place, preserving their settings and pairing.
Pixel local-bridge/FCM test: Ask was applied as commands 204/204, followed by
Off 205/205 with Done disabled. A separate manual-success write retained its
source and timestamp after Done. Initial attachment discovery was also fixed so
it does not discard ownership of a push sent before the first foreground check.
iPhone remote launch timed out; physical iOS receipt/LED checks await opening
SidePulse. Automated iOS tests also verify the filtered Live Activity summary
ends when the last Ask resolves. No production bridge deployment.

October 20 retry: iPhone remote launch now succeeds and APNs Ask → Done updates reach session accounting. Physical LED verification is blocked by iOS error “No valid file provider found with identifier com.apple.filesystems.UserFS.FileProvider” for the saved USB bookmark. A direct Off also fails with that exact error; Last pattern correctly remains the previous successful Ocean Shortcut. The app also logs ActivityKit “Activity cannot be persisted” when trying to start a Live Activity. The temporary test session was cleared; user asked to reconnect/reselect the Dot folder.

October 20 reconnect follow-up: iPhone USB folder access recovered after reconnect. Local Claude hook → isolated daemon → local bridge → APNs delivered Ask; iPhone recorded Needs You at 23:20:12 PDT, followed by Done with Done disabled and a successful 4-byte Off write at 23:20:58 PDT. This confirms the iOS stale-Ask output fix at the filesystem-write boundary; firmware application/visual LED playback is not independently acknowledged on iOS. A later manual-success write was also tested against Done. ActivityKit still logs “Activity cannot be persisted”; Live Activity display remains unresolved separately. No production bridge deployment.
