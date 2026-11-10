# MX Easy-Switch linking — setup guide

**For:** a person or an AI coding agent with shell access on a Linux machine.
**Goal:** pressing a channel key on a Logitech MX keyboard also moves the MX mouse to the same
computer, in both directions.

The guide is distro-neutral — nothing here is specific to one distribution, since it is all
HID++ over hidraw plus Solaar's rule engine. Where behaviour genuinely differs by distribution or
desktop, **section 8** says so; Arch-based systems including Omarchy are called out explicitly
there because they differ in three concrete ways.

Written 2026-09-09 from a working setup on Linux Mint / Cinnamon with Solaar 1.1.11, an MX
Mechanical (`B366`), an MX Anywhere 3S (`B037`), a Logi Bolt receiver (`046d:c548`), and a
Windows machine running Logi Options+. Everything here was verified on the wire, not inferred.
Read section 1 before running anything — the failure modes are all silent, and knowing them is
most of the value of this document.

**Updated 2026-11-02:** a third computer joined on slot 3, a second Linux Mint machine paired over
Bluetooth. The installer now links the mouse to **every** other paired slot by default instead
of to a single target. It reaches devices paired over Bluetooth as well as through a receiver,
and it ships the suspend-proof keeper. **Section 0** describes the reference setup and what was
verified on it. **Section 11** explains how three or more hosts work. The Bluetooth install
turned up faults 7 and 8 (section 6).

**Updated 2026-11-10:** `mx-push-mouse` retries its device scan, because a Bluetooth keyboard
that is leaving the machine can crash Solaar's scan (fault 9). This matters when a non-Logitech
keyboard triggers the push, see section 12.

Host names in this guide are placeholders: `linux-a`, `windows-pc` and `linux-b`. Unit IDs and
serials in sample output are made up.

---

## 0. The reference setup (as of 2026-11-10)

| Key / slot | Host index | Machine | OS | Link to the devices | Linking software | Status |
|---|---|---|---|---|---|---|
| 1 | 0 | `linux-a` | Linux Mint | Logi Bolt receiver | Solaar rules → `mx-push-mouse` 1 and 2, `mx-hostname-keeper` | **done**, slot 3 added and verified 2026-11-02 |
| 2 | 1 | `windows-pc` (name still stored in both devices) | was Windows; the machine is gone since 2026-11-02 | as paired there | Logi Options+ while it existed | whatever uses slot 2 next needs its own linking software (Options+, or this setup if Linux) for the mouse to follow *away* from it |
| 3 | 2 | `linux-b` | Linux Mint, Solaar 1.1.11 | Bluetooth (no receiver) | Solaar rules → `mx-push-mouse` 0 and 1 (installer, 2026-11-02); no keeper, since there is no receiver | **done**, key 1 verified 2026-11-02; key 2 untested (nothing on slot 2); known gap: fault 8 |

`mx-discover` on 2026-11-02 showed all three slots paired (`status=1`) on both devices, with
identical names in both host tables.

**Verified on `linux-a` (2026-11-02):** with keyboard and mouse on slot 1, pressing key 3 moved
the keyboard to `linux-b`. The mouse followed, and the push log recorded
`pushed mouse to host 2 (linux-b) after 1 ping(s)`.

**Verified on `linux-b` (2026-11-02):** installed with the current `mx-setup.sh` over
Bluetooth, with no `--target`. It found slots 1 and 2 by itself, applied the backlight fix
(fault 7) and did not install the keeper (no receiver). Key 1 moves the mouse to `linux-a`; the
push log shows `pushed mouse to host 0 (linux-a) after 1 ping(s)` in 240–480 ms. Key 2 has its
rule but was not tested, because no machine was on slot 2. The moves *away from* slot 2 belong
to whatever machine ends up there (section 10 for Windows).

**Verified 2026-11-10:** the same `mx-push-mouse`, triggered by a Keychron keyboard through
`keychron-host-announce` instead of by a Solaar rule, moves the mouse in both directions between
`linux-a` and `linux-b`, once the scan retry (fault 9) was in.

Known gaps on a Bluetooth-only machine:

- A press of 1 or 2 within about 6 s after the keyboard came back is lost (fault 8, a Solaar
  bug, reported upstream). Wait a moment before switching away again.
- Once, `mx-push-mouse` logged `mouse not found on any receiver or Bluetooth link`, although the
  mouse had reconnected 17 s earlier. **Not explained yet.** Either the mouse had already left,
  or it did not answer the single ping that `mx-push-mouse` uses to recognise it over Bluetooth.
  Unlike the pings after it, that first ping is not retried, and both cases produce the same log
  line. If it happens again, note whether the mouse was on this machine at that moment.

---

## 1. What you are actually building, and why it is not simpler

**The two devices are not linked in hardware.** Easy-Switch is per-device, and the receiver
relays nothing between them, so the mouse has no idea the keyboard moved. Only software running
on a host that can still reach *both* devices can bridge them. That means the move is always
done by **the machine the keyboard is leaving**:

| Direction | Runs on | Mechanism |
|---|---|---|
| Leaving this machine, to any other slot | this Linux box | one Solaar rule per target slot → `mx-push-mouse <index>` |
| Returning to this machine | the machine the keyboard is leaving | its own copy of this setup (Linux) or Logi Options+ (Windows/macOS), helped by `mx-hostname-keeper` here |

This machine cannot automate the return: a mouse sitting on another host is not on our
receiver, and there is no path to send it anything. So **every** host in the rotation needs
linking software of its own. On Linux that is this whole setup, on Windows or macOS it is
Options+. With N hosts, each one pushes to the N − 1 others; see section 11.

**Why the trigger is a notification and not a keypress.** The `Host Switch Channel 1/2/3` keys
are enumerated in HID++ `REPROG CONTROLS V4` (0x1B04) but carry neither the `divertable` nor the
`reprogrammable` flag, so the keypress can never be intercepted. The rule matches the
**`CHANGE HOST` (0x1814) feature notification** instead, which the keyboard emits ~40–150 ms
*before* it drops its link — enough time to push the mouse after it. One exception over
Bluetooth: a press in the first few seconds after the keyboard reconnects is lost (fault 8).

**Every failure here is silent.** The mouse simply stays put. Nine distinct causes produce that
one symptom; section 6 tells them apart.

---

## 2. Preconditions

- A Logitech MX keyboard and mouse supporting `CHANGE HOST` (0x1814) and `HOSTS INFO` (0x1815).
  Verify with `solaar show`.
- Solaar installed and **actually running** (see 3).
- Both devices paired to this machine on one channel and to each other machine on the **same**
  channel number on both devices (keyboard key 3 and mouse slot 3 must be the same computer).
- Both devices on **this** machine while you run the installer: it reads the keyboard's host
  table to find which slot is this machine and which are the others.
- For the return direction: every other machine runs its own linking. That means this setup on
  Linux, or Logi Options+ with **both** devices added on Windows or macOS.

---

## 3. Install Solaar, and make sure it runs

```sh
# Debian / Ubuntu / Mint
sudo apt install solaar
# Arch / Omarchy / EndeavourOS
sudo pacman -S solaar
```

Four things to check, in this order:

**a) Device permissions.** Solaar ships udev rules granting the desktop user access to the
receiver's hidraw node. The discovery script in section 4 prints `NO ACCESS` if they are missing
or have not been applied — fix with `sudo udevadm control --reload && sudo udevadm trigger`, or
replug the receiver. Nothing else in this guide can work without it.

**b) Solaar is running.** The rule engine lives in the Solaar process; no process, no linking.
Distributions ship `/etc/xdg/autostart/solaar.desktop`, which **only works on desktops that
implement XDG autostart** — GNOME, KDE, Cinnamon, XFCE. On a bare Wayland compositor such as
Hyprland (Omarchy) nothing reads that directory, so Solaar will not start on login unless you
add it yourself. See section 8.

**c) Solaar's Python API version.** The helper scripts import Solaar's internals. They were
written against **1.1.11** and the API has drifted in later releases — `Receiver.open()` in
particular was replaced by a factory in the 1.2 series. Check before trusting the scripts:

```sh
solaar --version
python3 - <<'EOF'
import sys
for p in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
    sys.path.insert(0, p)
from logitech_receiver import base, Receiver
from logitech_receiver import hidpp20 as h20
print('base.receivers   ', callable(getattr(base, 'receivers', None)))
print('Receiver.open    ', callable(getattr(Receiver, 'open', None)))
print('h20.set_host_name', callable(getattr(h20, 'set_host_name', None)))
EOF
```

All three must print `True`. If any is `False`, the installer will fail; adapt the calls to the
installed version (the concepts and HID++ function numbers do not change — only the Python
wrappers around them do).

**d) Solaar survives the keyboard.** `solaar show 2>&1 | grep -A3 Traceback` must print nothing.
On Solaar older than 1.1.19, the MX Mechanical's backlight makes it crash. Over Bluetooth, that
crash silently kills the rule engine for the keyboard (fault 7 in section 6). The installer fixes
this itself, so the check matters again after the install, and whenever Solaar has been upgraded
or its config reset.

---

## 4. Discover this machine's values

The installer discovers these automatically, but run it once yourself: you need to know the
host names **as stored in the devices**, and every later diagnostic starts here.

`mx-discover` is written by the installer; to inspect before installing, extract it with
`./mx-setup.sh --dry-run --prefix /tmp/mx` and run `/tmp/mx/.local/bin/mx-discover`.

Sample output from the reference machine `linux-a`, 2026-11-02, with all three slots paired
(unit IDs made up):

```
hostname   : linux-a
solaar ver : solaar 1.1.11+dfsg-2

hidraw nodes owned by Logitech (046d); receiver HID++ nodes are marked:
  /dev/hidraw3     Logitech USB Receiver        rw          <- HID++ node

receiver   : /dev/hidraw3  (Bolt Receiver)
  device 1   MX Mechanical      kind=keyboard  unitId=1A2B3C4D serial=1A2B3C4D
      host 0 (index) = slot 1: status=1 nameLen=7   name='linux-a'   <- current
      host 1 (index) = slot 2: status=1 nameLen=10  name='windows-pc'
      host 2 (index) = slot 3: status=1 nameLen=7   name='linux-b'
  device 2   MX Anywhere 3S     kind=mouse     unitId=5E6F7A8B serial=5E6F7A8B
      host 0 (index) = slot 1: status=1 nameLen=7   name='linux-a'   <- current
      host 1 (index) = slot 2: status=1 nameLen=10  name='windows-pc'
      host 2 (index) = slot 3: status=1 nameLen=7   name='linux-b'
```

The hidraw number moves around between boots (it was `hidraw5` in September, `hidraw3` in
November), so look it up each time. On a machine where the devices are paired over Bluetooth
there is no `receiver` block. Each device shows up under its own `direct : /dev/hidrawN` line
instead.

A mouse line ending in `[not responding - on another channel]`, with `unitId=None`, means the
mouse is currently on another computer. Move it here and run again. Only the serial is known
while it is away.

Note the off-by-one that causes constant confusion: **host index 0 is the key labelled 1.**
Unit IDs are transport-independent — they survive re-pairing and moving between Bluetooth and a
receiver — which is why rules match on them rather than on names or paths.

---

## 5. Pairing notes

- **Slots are positional and cannot be reordered**, only overwritten by re-pairing that channel.
  If you need the same slot order on both devices, re-pair until they line up.
- **Bolt pairing uses a one-time passkey** — clicked as a left/right pattern on a mouse, typed as
  digits on a keyboard. Pair from the **Solaar GUI**, which displays it; `solaar pair bolt`
  prints it too but races its own timeout.
- **Bluetooth pairing: quit `blueman-applet` first.** It silently cancels the MX passkey
  handshake. Pair from `bluetoothctl` with a dedicated agent.
- **Restart Solaar after any pairing change.** This is fault 1 in section 6 and it will waste
  your afternoon otherwise.

---

## 6. The failure modes

All nine look identical from the user's chair: *the mouse doesn't follow*.

| # | Cause | How to confirm | Fix |
|---|---|---|---|
| 1 | Solaar's device registry went stale across a re-pairing | rule fires but nothing appears on the wire for the mouse | restart Solaar |
| 2 | Solaar's `Set` action skipped an offline device | `solaar -dd` logs `Set action:` then nothing | use `mx-push-mouse` (installed here) |
| 3 | The receiver re-stamps the keyboard's host name on reconnect, so Options+ can no longer match the two host tables | works exactly once after a manual fix, then stops | `mx-hostname-keeper` (installed here) |
| 4 | Options+ not running / device missing on the other machine | no traffic to the mouse at all when it should be pushed | fix on that machine |
| 5 | After a suspend the receiver stopped reporting device connects, so the keeper went deaf | fault 3 comes back after a suspend, the keeper is alive, its log is quiet | current keeper re-arms the flag once a minute (installed here) |
| 6 | No rule for the slot you pressed (e.g. a slot paired after the install) | push log has no line at all for that key | re-run `mx-setup.sh` (it covers every paired slot) and restart Solaar |
| 7 | Solaar < 1.1.19 crashes on the MX Mechanical's backlight (BACKLIGHT2 v3); over Bluetooth this kills the keyboard's listener thread, so no rule ever fires | `solaar show 2>&1 \| grep -A3 Traceback` prints a `TypeError: 'int' object is not subscriptable`; `solaar -dd` shows `Exception in thread ReceiverListener` | `backlight` in the device's `_absent` in `config.yaml`; `mx-setup.sh` does this since 2026-11-02 |
| 8 | Bluetooth only: the key was pressed within ~6 s after the keyboard reconnected here. Solaar was still setting the keyboard up, the keyboard dropped its link in the middle, Solaar's listener crashed and threw away the queued CHANGE HOST message | works when the keyboard has been here a while, fails right after coming back; push log has no line for that press; `solaar -ddd` shows the CHANGE HOST message (`r[11 FF 0900 …]` on the MX Mechanical) during setup, then `read failed` and a Traceback through `listener.py` line 160 | wait a few seconds after coming back before switching away; Solaar bug, reported as [Solaar #3367](https://github.com/pwr-Solaar/Solaar/issues/3367) |
| 9 | A Bluetooth keyboard that is leaving this machine triggered the push (for example a Keychron with `keychron-host-announce`). Its HID node disappears while `mx-push-mouse` scans, and Solaar's scan crashes on it | push log: `mouse not found ... (scan error: AttributeError: 'NoneType' object has no attribute 'get')`; never seen with a simulated key combo, because then the keyboard stays connected | `mx-push-mouse` retries the scan up to 8 times, 0.3 s apart (since 2026-11-10); update older installs (section 7) |

**A desktop notification is not proof that anything worked.** Solaar's `Set` action returns
`None` on *every* failure path, so a following `Execute: notify-send` fires whether or not the
write happened. This cost hours on the reference machine. `mx-push-mouse` notifies only *after*
the switch has actually been sent.

**Fault 7 in detail.** Solaar 1.1.11 reads the backlight mode of the MX Mechanical's BACKLIGHT2
feature version 3 as an `int` and then slices it like bytes. Where it hurts depends on the link
(found 2026-11-02, on a fresh install over Bluetooth):

- **Bluetooth (direct device):** the settings push runs in the listener's start-up code, which
  has no `try/except` (`logitech_receiver/listener.py`, lines 158-160,
  `self.receiver.status.changed(True, reason='initialization')`). The thread
  `ReceiverListener:hidrawN` dies a second after Solaar starts. Solaar's window still looks
  normal, but no rule for that keyboard ever fires again.
- **Bolt receiver:** the push runs per notification inside a `try/except` (lines 174-178). The
  error is logged, that one push is lost, and the listener survives. Linking keeps working, which
  is why the bug stays hidden on a receiver: same Solaar version, same keyboard, different
  result.
- **Either link:** `solaar show` crashes, and so can Solaar's window when it shows the keyboard.

The fix is to stop Solaar from building the setting at all: put `backlight` into the device's
`_absent` list in `~/.config/solaar/config.yaml`, and make sure no `backlight:` key is present.
`_absent` stops `check_feature_settings()` in `settings_templates.py` (around line 1542) from
building the setting; but if the config also has a `backlight:` key, Solaar treats the setting as
"known present" and builds it anyway. A working config looks like this:

```yaml
- 1.1.11+dfsg-2                      # first line of the file
  _absent: [hi-res-scroll, ..., sidetone, equalizer, adc_power_management,
    backlight]
  _sensitive: {fn-swap: false, hires-scroll-mode: ignore, hires-smooth-invert: ignore, hires-smooth-resolution: ignore, multiplatform: false}
```

`_sensitive: {backlight: ignore}` is **not** enough. It only stops the write; `solaar show`
(`solaar/cli/show.py`, line 243) and the window still read the setting and crash. Stop Solaar
before editing, because it rewrites the file on exit. Keep the file's first line equal to the
running Solaar version, because a mismatch makes Solaar discard every `_absent` list. Solaar
1.1.19 or newer reads the setting correctly.

What `mx-setup.sh` does about it ("backlight guard"):

- It stops Solaar first, because Solaar rewrites `config.yaml` when it exits.
- It does nothing on Solaar 1.1.19 or newer, or when no connected device has BACKLIGHT2
  (`0x1982`) version 3 or higher.
- It backs up `config.yaml` to `config.yaml.bak-<timestamp>`.
- It adds `backlight` to that device's `_absent`, removes any `backlight:` key, and keeps the
  first-line version stamp at the running Solaar version.
- At the end it starts Solaar again.

After running it, `solaar show 2>&1 | grep -A3 Traceback` must print nothing.

**Fault 8 in detail (Bluetooth only, found 2026-11-02).** Each time the keyboard comes back to
this machine over Bluetooth, Solaar sets it up from scratch. On the MX Mechanical that is about
133 requests at ~45 ms each, so about 6 s; 78 of them read the key list for the `divert-keys`
setting. Solaar handles the keyboard's messages only after setup has finished. A CHANGE HOST
message that arrives during setup goes into a queue. The keyboard drops its link ~150–180 ms
later, so the next setup request fails, and the error escapes from the same unguarded start-up
call as fault 7 (`listener.py`, lines 158-160). The listener thread dies and the queued message
is never handled.

How it was proven: with `solaar -ddd`, the sequence was 1, then 3, then 1 again within about
5 s. Note that `-dd` shows only INFO lines; DEBUG lines need `-ddd`. The second press arrived at
10:33:44.538 as `r[11 FF 0900 02…]` in the middle of setup. `read failed` followed at
10:33:44.720, then a Traceback through `listener.py` line 160, and no rule ran. A press made
after the keyboard had been here for a while worked every time.

- **In practice:** after coming back to a Bluetooth-only machine, wait a few seconds before
  switching away.
- **Behind a receiver:** the listener belongs to the receiver, which stays connected, so this
  should not happen there. Not tested.
- **Upstream:** reported as [Solaar #3367](https://github.com/pwr-Solaar/Solaar/issues/3367),
  with a suggested fix: catch the error and still deliver the queue. Solaar 1.1.20's
  `listener.py` still has the unguarded call (line 145), so upgrading would not help.
- **Not fixed locally.** Fixing it here would mean patching Solaar's own files, and a package
  update would undo that without warning.
- **If the wait gets annoying, two options:**
  - Add `divert-keys` to the keyboard's `_absent`. That cuts setup to about 2.5 s; this setup
    needs no diverted keys.
  - Patch `listener.py` as in the issue. That removes the window completely.

**Fault 9 in detail (found 2026-11-10).** With `keychron-host-announce`, a desktop shortcut runs
`mx-push-mouse` a moment before the Keychron drops its Bluetooth link. `mx-push-mouse` scans the
HID devices through Solaar 1.1.11, and Solaar's `find_paired_node` (`hidapi/udev.py`) crashes
with `AttributeError: 'NoneType' object has no attribute 'get'` on the Keychron's node, which is
being removed at that moment. The old `mx-push-mouse` swallowed the error and reported
`mouse not found`. The current one repeats a failed scan up to 8 times, 0.3 s apart, and logs
the last scan error if it still gives up. A clean scan without the mouse is not repeated: the
mouse is simply not here. Simulated key combos (`xdotool`) never show this, because the keyboard
stays connected; only a real switch does.

### Fault 3 in detail — it is the subtle one

Each device stores a host table (`HOSTS INFO` 0x1815): status, name length and name per slot.
Options+ maps *"the keyboard is leaving for host N"* onto a slot of the **mouse** by matching
those names, so the two tables must agree. A Bolt receiver stamps its own name into the slot of
whichever device it re-pairs, producing:

```
keyboard host 0:  nameLen=22  'Logitech Bolt receiver'   <- re-stamped on EVERY reconnect
mouse    host 0:  nameLen=7   'linux-a'                  <- stable
```

The other slot still matched, so switching *to* the other machine kept working and only the
return broke — a very confusing asymmetry. **`solaar show` hides this**: `get_host_names()`
rewrites the current host's name to `socket.gethostname()` as a side effect of reading it, so it
always displays a corrected value regardless of what is stored. Read 0x1815 directly (as
`mx-discover` does). Solaar corrects the name only when it *builds* the change-host setting,
i.e. once per device per Solaar run — never per reconnect. Hence the keeper daemon.

Do **not** instead point the mouse at the receiver's name: Solaar will rewrite the current
host's name to the system hostname at the next login and break the match again.

**If fault 3 comes back, first check that the keeper is still alive**:
`systemctl --user status mx-hostname-keeper`. It runs as a systemd user service with
`Restart=always`. Before 2026-10-16 it was a one-shot autostart entry, and it died when a resume
from suspend re-enumerated the receiver mid-scan: Solaar's `find_paired_node` raised
`AttributeError`, which the main loop did not catch. The current version logs such errors and
rescans, and systemd restarts it if anything else kills it. Look for a traceback at the end of
`~/.cache/mx-hostname-keeper.log`.

**If the keeper is alive but fault 3 is back after a suspend, that is fault 5.** The receiver
reports device connects only while its `wireless` notification flag is set. A suspend clears
that flag (seen 2026-10-04, s2idle), and Solaar 1.1.11 sets it only at startup. The keeper then
waited for notifications that never came, for three days, without logging a single error. The
current keeper checks the flag every 60 s, re-arms it, and repairs any names it missed. The log
line `connection notifications were off (flags 0x…) - re-enabled` shows the fix at work. The
full investigation is in [`2026-10-07-pc-to-linux-mouse-stays.md`](2026-10-07-pc-to-linux-mouse-stays.md).

**Faults 3 and 5 are receiver-specific.** The keeper only watches receivers. On a machine
paired over Bluetooth it would find no receiver and rescan every 5 s, logging Solaar's
enumeration warnings each time (~6 MB/day), so the installer starts it only when the devices are
reached through a receiver. Over Bluetooth no name re-stamping has been seen: after several round
trips between two Linux machines, `mx-discover` on the Bluetooth one showed identical names on
keyboard and mouse in all three slots. If the current slot's name on the keyboard ever differs
from the mouse's, a Bluetooth variant of the keeper is needed.

---

## 7. Install

```sh
chmod +x mx-setup.sh
./mx-setup.sh --dry-run --prefix /tmp/mx   # inspect: writes only under /tmp/mx
./mx-setup.sh                              # do it: follow to every other paired slot
./mx-setup.sh --target linux-a             # or: only to the named slot(s); repeatable
```

Keyboard and mouse must both be on this machine while it runs. It reads the keyboard's host
table: the **current** slot is this machine, and every other slot with `status=1` becomes a
target. `--target` takes the host name **as stored in the devices** (the `name=` field from
`mx-discover`), which is not necessarily the machine's real hostname.

It then writes the three helpers (`mx-discover`, `mx-push-mouse`, `mx-hostname-keeper`) to
`~/.local/bin` with the discovered unit IDs and the full slot-name map baked in, and writes
**one Solaar rule per target slot**, because Solaar's `Execute` action cannot pass the matched
host byte on to the command. It backs up any existing `rules.yaml` first. Finally it installs
the keeper as a systemd user service with its output appended to
`~/.cache/mx-hostname-keeper.log`, falling back to XDG autostart without systemd.

On Solaar older than 1.1.19 it also applies the fault 7 fix (section 6). **At the end it starts
Solaar again**, so the new rules are live immediately. In a `--dry-run` it touches neither Solaar
nor the real config. It writes a patched copy under the prefix instead.

The helpers find the devices behind a receiver or connected directly over Bluetooth. Both paths
have run for real on 2026-11-02 (a dry run behind a receiver, a full install over Bluetooth).
Two fixes came out of the Bluetooth run:

- A keyboard on Bluetooth reports kind 0, which Solaar 1.1.11 shows as `?`. The scripts
  therefore ask the device for its kind.
- A directly connected device has no unit ID until it has answered a ping. `mx-push-mouse`
  therefore pings it first.

It does not pair devices and does not touch the other machines. **Re-run it whenever a slot is
paired or re-paired**, or the new slot has no rule (fault 6).

**Updating only `mx-push-mouse`.** The full installer needs the MX keyboard on this machine and
restarts Solaar. If only `mx-push-mouse` changed (as with the fault 9 retry), you can instead
take its heredoc from `mx-setup.sh` (between `<<'PUSH_EOF'` and `PUSH_EOF`), replace
`@MOUSE_ID@` and `@HOST_NAMES@` with the values in your installed copy, and install it over
`~/.local/bin/mx-push-mouse`. Diff against the old file first: the only differences should be
the code changes.

After it finishes: **restart Solaar**, then test. Press each target's channel key, bring both
devices back by hand (the target machine may not be set up yet), and watch
`~/.cache/mx-push-mouse.log`. One `pushed mouse to host N (name)` line per key press is the
proof. A popup is not proof; popups are off by default (`NOTIFY = False` in `mx-push-mouse`).

---

## 8. Distro and desktop differences

Four things vary between systems. Only the first two usually bite.

### 8.1 Autostart — depends on your *desktop*, not your distribution

Both Solaar and the keeper daemon must start on login.

- **Desktops that implement XDG autostart** — GNOME, KDE, Cinnamon, XFCE, MATE, Budgie — read
  `/etc/xdg/autostart/solaar.desktop` and `~/.config/autostart/`. Nothing to do; Solaar starts
  itself and the installer's fallback entry works.
- **Bare Wayland compositors** — Hyprland, sway, river, niri — implement **no** XDG autostart, so
  neither directory is read and **Solaar will not start at all**. Since the rule engine lives in
  the Solaar process, the linking is simply dead until you fix this. Use the compositor's own
  mechanism:
  ```
  exec-once = solaar --window=hide
  exec-once = ~/.local/bin/mx-hostname-keeper
  ```
  or a systemd user service for each. The installer prefers a **systemd user service** for the
  keeper precisely because it is desktop-independent, but Solaar wants a graphical session and is
  better started by the compositor.
- If your session runs through `uwsm`, start both under it so they inherit the session
  environment.

### 8.2 Solaar version and its Python API

The helpers import Solaar's internals, and that API has drifted. Debian, Ubuntu and Mint ship
older Solaar (1.1.x); Arch and Fedora ship newer, where `Receiver.open()` has been replaced by a
factory in the 1.2 series. **Run the API check in section 3 before installing.** The HID++
concepts and function numbers never change — only the Python wrappers around them do.

Solaar's library also lives in different places: site-packages on Arch and Fedora,
`/usr/share/solaar/lib` on Debian and derivatives. The scripts try a plain import first and fall
back to the Debian path, so this is already handled.

### 8.3 Notifications

`notify-send` needs a running notification daemon — one is present on full desktops, but on a
bare compositor you need mako, dunst or similar. Without one the switching still works and you
just lose the feedback, so **never read a missing popup as a failed switch**; check
`~/.cache/mx-push-mouse.log` instead.

### 8.4 Init system

Without systemd the installer falls back to an XDG autostart entry automatically, which is fine
on any desktop from 8.1's first group.

### 8.5 Arch and Omarchy in particular

Everything above applies; concretely, the deltas from the reference machine are:

| | Reference (Mint/Cinnamon) | Arch / Omarchy |
|---|---|---|
| Install | `apt install solaar` | `pacman -S solaar` |
| Solaar autostart | automatic via XDG | **manual** — Omarchy runs Hyprland; add `exec-once` |
| Keeper autostart | XDG entry or systemd unit | systemd user unit (installer default) |
| Solaar version | 1.1.11 | newer — run the API check in section 3 |
| Library path | `/usr/share/solaar/lib` | site-packages — handled by the import shim |
| Notifications | Cinnamon's daemon | mako (Omarchy ships one) |

The Omarchy-specific trap is 8.1: everything installs cleanly, `mx-discover` works, the rule file
is correct — and nothing happens on login, because Solaar itself was never started. Check
`pgrep -x solaar` first when debugging on a compositor-only system.

**Wayland vs X11** makes no difference anywhere: this never touches input events, only the HID++
control channel.

---

## 9. Diagnostics that actually work

**Passive wire capture.** hidraw broadcasts input reports to every open file descriptor, so you
can watch the receiver without disturbing Solaar (use the node `mx-discover` marks):

```sh
python3 - /dev/hidraw3 <<'EOF'
import os, select, sys, time
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
t0 = time.time()
while time.time() - t0 < 180:
    if select.select([fd], [], [], 1.0)[0]:
        d = os.read(fd, 64)
        if d:
            print('%8.3f %s' % (time.time() - t0, d.hex(' ')), flush=True)
EOF
```

Host→device **writes do not appear** — only the device's reply. So *no traffic from device N* is
the signature of a command that was never sent, which is how you prove a failure belongs to the
other machine rather than to this one.

Decoding, with the frames that matter:

| Frame | Meaning |
|---|---|
| `11 01 09 00 00 01` | device 1, feature index 9 (`CHANGE HOST`), moving to host index 1 |
| `10 02 41 10 42 …` | device 2 connection notification; `0x40` set in the first data byte = link down |
| `10 01 41 10 01 …` | device 1 arrived (bit clear) |
| `11 02 0b 18 00` | mouse's reply to `setCurrentHost`; low nibble `8` = software id 8 = Solaar (`base.py:404`) |

**Full rule tracing.** Restart Solaar as `solaar -dd --window=hide > /tmp/solaar.log 2>&1`.
`Set action: [...]` means a write was attempted; a `paired offline` line for the mouse ~600 ms
later confirms it actually left. Stop Solaar with `pkill -x solaar`. Do **not**
`pkill -f "solaar -dd"` from inside an agent shell — the pattern matches your own shell's command
line and kills your session.

**Logs.** `~/.cache/mx-push-mouse.log` and `~/.cache/mx-hostname-keeper.log`. The keeper writes a
line only when it really changed a name, so a busy log means your receiver re-stamps on every
reconnect (fault 3) and the daemon is earning its keep. A `mouse did not answer` line in the push
log is usually **not** a fault — it means the mouse was not on this machine, i.e. already on the
other host.

---

## 10. The other machine (Windows / Logi Options+)

- **Both** devices must be present in Options+. The keyboard is the trigger — it emits the
  notification; the mouse only ever receives. Enabling the mouse alone gives Options+ nothing to
  react to.
- The linking toggle lives on the **keyboard's** page, under Easy-Switch.
- `logioptionsplus_agent.exe` is headless by design. **No tray icon is normal** and is not a
  symptom; check Task Manager → Details instead. Launch the window from the Start menu.
- If linking stops after a re-pairing on the Linux side, suspect fault 3 before touching
  anything in Options+, and check the host tables with `mx-discover`.
- With a third host, Options+ must also follow to that slot. It matches slots by the names in
  the host tables, so the new slot's name must be identical on keyboard and mouse.
- How to turn on the Options+ debug log and where it keeps its cached host tables is in
  [`2026-10-07-pc-to-linux-mouse-stays.md`](2026-10-07-pc-to-linux-mouse-stays.md), section 7.

---

## 11. Three or more hosts

Every MX device has three Easy-Switch slots, so up to three computers. The rule from section 1
generalises directly: **whichever machine the keyboard is leaving moves the mouse.** That is the
only machine that can still reach the mouse at that moment. Each host therefore needs linking
software that covers every *other* slot:

```
             key 2 pressed                            key 3 pressed
 linux-a (1) ────────────▶ slot 2       linux-a (1) ────────────▶ linux-b (3)
   rule "index 1"                          rule "index 2"

 linux-b (3) ────────────▶ linux-a (1)  linux-b (3) ────────────▶ slot 2
   rule "index 0"                          rule "index 1"

 slot 2 machine ─────────▶ 1 or 3: its own Options+ / own copy of this setup
```

| Keyboard leaves → goes to | Who moves the mouse | Rule / mechanism |
|---|---|---|
| 1 → 2 | `linux-a` | Solaar rule, `TestBytes [1,2,1,1]` → `mx-push-mouse 1` |
| 1 → 3 | `linux-a` | Solaar rule, `TestBytes [1,2,2,2]` → `mx-push-mouse 2` |
| 3 → 1 | `linux-b` | Solaar rule, `TestBytes [1,2,0,0]` → `mx-push-mouse 0` (verified 2026-11-02) |
| 3 → 2 | `linux-b` | Solaar rule, `TestBytes [1,2,1,1]` → `mx-push-mouse 1` (installed, not tested: nothing on slot 2) |
| 2 → 1, 2 → 3 | the slot-2 machine | Options+ (Windows) or this setup (Linux) |

Consequences worth knowing:

- **A machine that is asleep or off cannot push.** If you press key 1 while `linux-b` is
  suspended, the keyboard leaves but nothing moves the mouse. Use the mouse's own button.
- **The linking is per-machine, so a half-set-up rotation is lopsided rather than broken.**
  Before `linux-b` had its own install, 1 → 3 worked and 3 → 1 did not.
- **Two Linux machines need no name matching.** `mx-push-mouse` addresses the target by slot
  index, never by name. Host-table names matter only to Options+, which is why the keeper
  matters most on machines that a Windows host switches *to*.
- **Pair the same machine on the same number on both devices.** The index the keyboard reports
  is passed straight to the mouse, so if `linux-b` were slot 3 on the keyboard but slot 2 on the
  mouse, the mouse would follow to the wrong computer. `mx-discover` shows both tables side by
  side; the names should line up row by row.

---

## 12. Other keyboards

`mx-push-mouse <index>` does not care what triggered it. Any keyboard that can tell the computer
it is leaving where it goes can drive it from a desktop shortcut instead of a Solaar rule. The
`keychron-host-announce` project does this for a Keychron V6 Max with custom firmware: before
leaving, the keyboard sends Ctrl+Alt+Shift+F13/F14/F15, and a Cinnamon shortcut runs
`mx-push-mouse 0/1/2`. Solaar rules for an MX keyboard can stay installed alongside and do no
harm.
