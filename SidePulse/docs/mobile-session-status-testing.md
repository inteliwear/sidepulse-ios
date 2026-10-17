# Mobile session status verification

## Human checks

Link each phone, enable **Forward sessions** on the sending Mac, and use the
installed desktop CLI. Connect and authorize a Dot for LED checks.

1. Send `sidepulse report --scope mobile-check --state working --title "Mobile check"`.
   The session appears without requiring hardware. Send Blocked, Error, Done,
   and Clear and verify the row's latest state or removal. Repeat from a second
   paired computer with the same session name; its row must remain independent.
2. In Settings → Session LED patterns, choose a saved pattern for each condition.
   Repeat the reports and check the connected Dot. Delete a chosen pattern and
   verify its built-in fallback on the next render/update. Settings survive restart.
3. Turn **Use sessions for LEDs** off. Session rows still update, and the current
   LED output stays unchanged. Direct remote and shortcut writes still work.
4. Send a direct manual LED command to the phone with `sidepulse push 'off' --to
   '<phone name>'`. The LED changes without adding/removing sessions. A duplicate
   status or reconnect must not override that successful write; a newer accepted
   session report resumes session LEDs when enabled.
5. On iOS, run **Play SidePulse Pattern** or **Write SidePulse LEDS.LED** from
   Shortcuts. On Android, use a saved pattern's home-screen shortcut or
   `sidepulse://write?pattern=success`. These have the same manual ownership
   behavior and do not change tracked sessions.
6. Clear a row (iOS swipe-left Clear; Android Clear session). Replaying its
   previous sequence must keep it hidden across restart; a newer report restores it.
7. On iOS, enable **Session Live Activity**, open SidePulse, then lock the phone.
   Verify one combined card, counts, representative title/status/message, and
   Dynamic Island. Tap it to open Sessions. Disable session LEDs and repeat;
   the activity still updates. Turn Live Activity off or clear/revoke all sessions;
   the activity ends. Old reports show their last-reported timestamp rather than
   implying a live connection. iOS controls background delivery.
8. Submit an old `program_status_snapshot` envelope, even with a valid outer
   key and an LED field. It must neither alter sessions nor become a direct write.

## Latest automated checks (2026-10-16)

- Swift package: 84 tests pass, covering individual-update fixtures, validation,
  sender isolation, saved replay guards, 64-session eviction, manual ownership,
  configurable patterns, and combined-activity data.
- Android: 89 unit tests, debug lint, and debug build pass. Three focused emulator
  checks pass for session updates, paired-source isolation, and rejected snapshot
  routing after the single-validation cleanup.
- iOS simulator app and widget build pass. Each accepted update now refreshes
  the session list and Live Activity once; LEDs use that same session list.
- Desktop: 914 tests and 600 subtests pass, including six isolated local bridge
  checks. Distinct active source/session rows are counted separately. Mac sleep
  control, history sampling, and output holds run in the daemon without the tray;
  those local controls do not change the bridge/mobile status format.
- These latest source changes were not deployed to production or reinstalled on
  the physical iPhone. Physical USB playback was not retested.

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
