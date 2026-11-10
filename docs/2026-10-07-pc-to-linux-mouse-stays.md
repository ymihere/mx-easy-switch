# 2026-10-07 — Mouse stays on the PC when switching to Linux

**For:** the agent on the Linux machine (`linux-a`), to check the Linux side.
**Written:** 2026-10-07 from the Windows machine (`windows-pc`). All times are CEST (UTC+2).

**Short version:** this is fault 3 from [`setup.md`](setup.md#fault-3-in-detail--it-is-the-subtle-one).
Options+ on the PC sees the keyboard's slot 1 named `Logitech Bolt receiver` and the mouse's
slot 1 named `linux-a`, finds no match, and does nothing. The keyboard spent 50 minutes on
Linux (15:08–15:58) and came back with the wrong name still in place, so `mx-hostname-keeper`
apparently did not repair it. **Why the keeper did not fix it is the open question** — section 6.

**Resolved on Linux the same day — see section 8.** None of causes 1–6 exactly: the keeper was running
but deaf, because a suspend had switched off the receiver's connection notifications. Nothing to
change on the PC.

---

## 1. Symptom

| Direction | Mechanism | State |
|---|---|---|
| Linux → PC | Solaar rule → `mx-push-mouse` | works |
| PC → Linux | Logi Options+ on the PC, needs matching names | **broken**: keyboard switches, mouse stays |

The user noticed it after Options+ updated itself on the PC (2.8.981479, installed 2026-10-04,
probably from 2.7.961922). Switching the link toggle off and on in Options+ changed nothing.

## 2. What Options+ logged when key 1 was pressed on the PC

Debug logging was turned on in the running agent (section 7). Key 1 was pressed three times.
Every press logged the same four lines (thread ids and source fields trimmed):

```
14:49:32.510  feature_1814_change_host::onChangeHostRequested for dev00000005 from 1 to 0.
14:49:32.511  Posting host changed on device dev00000005 with host info of Logitech Bolt receiver.
14:49:32.513  Follow device dev00000004 received host changed event with target host Logitech Bolt receiver.
14:49:32.513  [warning] Follow device dev00000004 with same host as the keyboard not found .
```

- `dev00000005` = MX Mechanical (keyboard), `dev00000004` = MX Anywhere 3S (mouse).
- `from 1 to 0` = host index 1 (key 2, the PC) to host index 0 (key 1, Linux).
- Same result at **14:50:33** and **15:08:29**.
- The keyboard came back to the PC at 14:49:37, 15:08:10 and **15:58:50** (logged as
  `Lead device dev00000005. Is firmware coupled easy switch capable = 1.`).

The success line, never seen yet, is in the agent binary as
`Follow device %s with same host found at channel %d.`

## 3. How Options+ decides

Read from the log above plus the agent's built-in strings (Logitech's internal name for the
feature is "coupled easy switch"):

1. The keyboard sends its `CHANGE HOST` (0x1814) notification as it leaves.
2. Options+ takes the keyboard's stored name for the target slot (`HOSTS INFO`, 0x1815).
3. It looks for a slot in the **mouse's** host table with the **same name**.
4. Match → it sends the mouse to that slot. No match → it does nothing. The only trace is a
   warning in the debug log, which is off by default.

Other checks in the same code path did **not** fire: no `linked devices are empty`, no
`lead serial number hash not matched`. So the keyboard–mouse link itself is intact. Only the
names don't match.

**Correction to an earlier guess:** name matching is not new in Options+ 2.8. `setup.md` already
documents it on 2026-09-09, against the older Options+. So the update probably did not cause
this. The timing may be coincidence. (A 2.8 change in *when* Options+ re-reads the names is not
excluded yet — the test in section 6 settles that.)

## 4. Host tables as Options+ on the PC sees them

From Options+'s cache (`settings.db`, written 15:58:52, right after the keyboard came back):

| Device | Slot 1 (Linux, via Bolt) | Slot 2 (PC, Bluetooth) | Slot 3 |
|---|---|---|---|
| MX Mechanical | `Logitech Bolt receiver` | `windows-pc` | empty |
| MX Anywhere 3S | `linux-a` | `windows-pc` | empty |

Slot 2 matches because Options+ writes the PC's own name into the slot it is connected on (the
agent's startup code has a `Rename result` step next to the host-name lookup — inferred from the
binary, not observed). Nothing writes slot 1 except the Bolt receiver and Solaar or the keeper on
Linux.

Caveat: this is Options+'s **cached** view. The log shows it re-registering for the keyboard's
host names on reconnect, so it most likely re-read them, but the log does not print the names.
Only `mx-discover` on Linux shows what is really stored.

## 5. Ruled out on the PC

- **Install:** clean, public release channel, agent running since 2026-10-05 09:31, no agent
  crashes in the Windows event log.
- **Pairing:** Windows has exactly one Bluetooth pairing per device.
- **Keyboard firmware:** 71.3.21 (updated 2026-09-07); the agent reports it as capable.
- **Link toggle:** off/on changed nothing — expected, it does not touch the names.
- **Logi Flow:** not connected (its peer address times out). Irrelevant: Logitech says
  Enhanced Easy-Switch uses no network, and the log shows the decision is made locally.

## 6. Open question: why did the keeper not fix the name?

The keyboard was on Linux from 15:08:29 to 15:58:50. The keeper should have rewritten slot 1
about 1.5 s after the keyboard arrived. Options+ still saw the old name afterwards. Possible
reasons, most likely first:

1. **The keeper is not running** (not installed, autostart failed after a reboot, or it crashed).
2. **It ran but failed or skipped the keyboard** — look for a traceback, `receiver gone`, a
   `device …:` error line, or `FAILED` in its log.
3. **Something re-stamped the name after the keeper wrote it.**
4. **Hostname changed** — the keeper writes `socket.gethostname()`, which must still be
   `linux-a` to match the mouse.
5. **Solaar was upgraded and the helpers' imports broke.** The scripts use the old API
   (`hidpp20.FEATURE`, module-level `h20.feature_request` and `h20.set_host_name`). Current Solaar
   (1.1.20) no longer has these at module level. Unlikely here, because `mx-push-mouse` uses
   the same `FEATURE` import and Linux → PC still works — but the keeper is a separate process,
   so check its log anyway.
6. **Options+ 2.8 keeps a stale copy of the names** — the only Windows-side cause left.

### Checks on Linux

```sh
systemctl --user status mx-hostname-keeper      # or: pgrep -af mx-hostname-keeper
tail -n 50 ~/.cache/mx-hostname-keeper.log      # or: journalctl --user -u mx-hostname-keeper --since "2026-10-07 14:00"
hostname
solaar --version                                # guide was written against 1.1.11
```

In the keeper log, look at 2026-10-07 15:08–15:58. If the keeper worked, there is a line like
`MX Mechanical host 0: 'Logitech Bolt receiver' -> 'linux-a'`. No line at all, while the
keyboard visited, means it did not run or never saw the reconnect.

### The test that settles it

1. With the keyboard on Linux, wait a few seconds, then run `mx-discover`. Read the keyboard's
   slot 1 name (`host 0 (index) = slot 1`).
2. **`'Logitech Bolt receiver'`** → the problem is on Linux (causes 1–5). Fix the keeper, repeat.
3. **`'linux-a'`** → Linux is fine. Press key 2 to go to the PC, then key 1 on the PC.
   If the mouse still stays, Options+ is using a stale name (cause 6). Hand it back to the
   Windows side with the time of the press.

## 7. Windows side: how to check the result

Debug logging in the Options+ agent is **still on** (since 14:47). It writes a lot, and the files
rotate at 10 MB × 3, so only roughly the last hour is kept (observed: 20–35 minutes per file).

```bat
:: turn on / off (signals the running agent; no restart)
"C:\Program Files\LogiOptionsPlus\logioptionsplus_agent.exe" --enable_logging
"C:\Program Files\LogiOptionsPlus\logioptionsplus_agent.exe" --disable_logging
```

Logs: `%TEMP%\com.logi.optionsplus.agent.logs\<start-time>-agent-<pid>.log` (plus `.1.log`,
`.2.log`). Search for `Follow device` — success is `with same host found at channel 0`.

Options+'s cached host tables live in `%LOCALAPPDATA%\LogiOptionsPlus\settings.db`: table `data`,
one JSON blob, key `easy_switch`. Copy the `settings.db*` files somewhere else before opening
them; the agent keeps the live file open.

## 8. Result from the Linux side (16:40–16:50)

The cause is on Linux. Options+ was not working from a stale copy.

- **Keeper running, but deaf since 2026-10-04 15:42.** It was started on 10-01 via XDG autostart
  (no systemd unit on this machine), and its last name repair was 10-02 15:40. On 10-04 the
  receiver re-enumerated after a resume (`receiver gone: [Errno 5]`), and the keeper re-attached
  to `/dev/hidraw3` at 14:52. The laptop suspended at 15:42, and the keeper logged nothing after that.
- **Why:** the Bolt receiver's HID++ notification flags (register 0x00) read **`0x0`**. Without
  the `wireless` bit (0x100) the receiver sends no device-connect notifications (0x41), so the
  keeper never learns that the keyboard arrived. The suspend cleared the flags, and Solaar
  1.1.11 sets them only at startup. Linux → PC kept working because the keyboard's `CHANGE HOST`
  notification is a device feature notification and does not need the flag.
- **Confirmed:** `mx-discover` at 16:45 showed the keyboard's slot 1 as
  `'Logitech Bolt receiver'`, exactly as Options+ cached it.
  Hostname `linux-a`, Solaar 1.1.11 (causes 4 and 5 ruled out).
- **Fixed live:** flags re-enabled by hand at ~16:47 (now `0x900`). The keyboard came back at
  16:48 and the unchanged keeper logged
  `16:48:45 MX Mechanical host 0: 'Logitech Bolt receiver' -> 'linux-a'`, its first
  repair in five days.
- **Fixed permanently:** `mx-hostname-keeper` now checks the flags every 60 s, re-arms them, and
  then repairs any name it missed while deaf. The re-arm path was tested against the real
  receiver. The new keeper has been installed and restarted (16:49:49).

**For the Windows side:** press key 1 on the PC once. The debug log should now show
`Follow device dev00000004 with same host found at channel 0`. Then debug logging can be turned off.
