#!/usr/bin/env bash
# Install MX Easy-Switch linking helpers. See docs/setup.md for the why.
#
#   ./mx-setup.sh [--target NAME]... [--dry-run] [--prefix DIR]
#
# Run it with the keyboard and mouse both on THIS machine.
# By default the mouse is made to follow the keyboard to EVERY other paired
# slot. --target NAME (repeatable) limits that to the named slots; NAME is the
# host name as stored in the devices (the name= field from mx-discover).
# --dry-run  write nothing outside --prefix and skip service installation
# --prefix   install root; default $HOME
set -euo pipefail

TARGETS=()
DRY_RUN=0
PREFIX="$HOME"

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGETS+=("$2"); shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --prefix)  PREFIX="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BIN="$PREFIX/.local/bin"
mkdir -p "$BIN" "$PREFIX/.cache"

# ---------------------------------------------------------------- mx-discover
cat > "$BIN/mx-discover" <<'DISCOVER_EOF'
#!/usr/bin/env python3
"""Print everything needed to configure MX Easy-Switch linking on this machine.

Read-only: it never writes to a device. Deliberately avoids Solaar's
get_host_names(), which rewrites the current host's name as a side effect of
reading it, so the host tables printed here are what is really stored.
Covers devices behind a receiver (Bolt / Unifying) and devices connected
directly (Bluetooth).
"""
import glob
import os
import socket
import subprocess
import sys

# Solaar's python packages live in site-packages on Arch, but under
# /usr/share/solaar/lib on Debian/Ubuntu/Mint.
try:
    from logitech_receiver import base
except ImportError:
    for candidate in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
        if os.path.isdir(candidate):
            sys.path.insert(0, candidate)
            break
    from logitech_receiver import base

from logitech_receiver import Receiver
from logitech_receiver.device import Device
from logitech_receiver import hidpp20 as h20
from logitech_receiver.hidpp20 import FEATURE


def host_table(dev):
    state = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x00)
    if not state:
        return None, []
    current, rows = state[3], []
    for host in range(state[2]):
        info = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x10, host)
        if not info:
            continue
        length, name, remaining = info[4], '', info[4]
        while remaining > 0:
            piece = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x30, host, length - remaining)
            if not piece:
                break
            name += piece[2:2 + min(remaining, 14)].decode(errors='replace')
            remaining = max(0, remaining - 14)
        rows.append((host, info[1], length, name))
    return current, rows


def show(dev, indent='  '):
    alive = dev.ping()
    # get_kind, not dev.kind: Solaar 1.1.11 shows a Bluetooth keyboard as '?' (kind 0 is falsy)
    kind = h20.get_kind(dev) if alive else None
    print('%sdevice %-3s %-18s kind=%-9s unitId=%s serial=%s%s'
          % (indent, dev.number, dev.name, '?' if kind is None else kind, dev.unitId, dev.serial,
             '' if alive else '   [not responding - on another channel]'))
    if not alive:
        return
    current, rows = host_table(dev)
    for host, status, length, name in rows:
        print('%s    host %d (index) = slot %d: status=%d nameLen=%-3d name=%r%s'
              % (indent, host, host + 1, status, length, name,
                 '   <- current' if host == current else ''))


print('hostname   : %s' % socket.gethostname().partition('.')[0])
print('solaar lib : %s' % os.path.dirname(base.__file__))
try:
    print('solaar ver : %s' % subprocess.run(['solaar', '--version'], capture_output=True,
                                             text=True, timeout=15).stdout.strip())
except Exception:
    print('solaar ver : unknown')

infos = list(base.receivers_and_devices())
receiver_paths = {i.path for i in infos if not getattr(i, 'isDevice', False)}
print('\nhidraw nodes owned by Logitech (046d); receiver HID++ nodes are marked:')
for node in sorted(glob.glob('/sys/class/hidraw/hidraw*')):
    try:
        uevent = open(os.path.join(node, 'device/uevent')).read()
    except OSError:
        continue
    hid_id = [l for l in uevent.splitlines() if l.startswith('HID_ID=')]
    hid_name = [l for l in uevent.splitlines() if l.startswith('HID_NAME=')]
    if hid_id and '046D' in hid_id[0].upper():
        dev = '/dev/' + os.path.basename(node)
        print('  %-16s %-28s %-11s %s' % (dev, hid_name[0][9:] if hid_name else '?',
                                          'rw' if os.access(dev, os.R_OK | os.W_OK) else 'NO ACCESS',
                                          '<- HID++ node' if dev in receiver_paths else ''))

for info in infos:
    try:
        if getattr(info, 'isDevice', False):
            dev = Device.open(info)
            if not dev:
                continue
            print('\ndirect     : %s  (bus 0x%04x - Bluetooth if 0x0005)' % (info.path, info.bus_id or 0))
            try:
                show(dev)
            finally:
                dev.close()
        else:
            rcv = Receiver.open(info)
            if not rcv:
                continue
            print('\nreceiver   : %s  (%s)' % (info.path, getattr(rcv, 'name', '?')))
            try:
                for dev in rcv:
                    show(dev)
            finally:
                rcv.close()
    except Exception as e:
        print('\ncannot open %s: %r' % (info.path, e))
DISCOVER_EOF
chmod +x "$BIN/mx-discover"
echo "wrote $BIN/mx-discover"

# ------------------------------------------------- discover devices and slots
echo
echo "Discovering devices ..."
eval "$(python3 - "${TARGETS[@]}" <<'PY'
import os, sys
try:
    from logitech_receiver import base
except ImportError:
    for p in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
        if os.path.isdir(p):
            sys.path.insert(0, p); break
    from logitech_receiver import base
from logitech_receiver import Receiver
from logitech_receiver.device import Device
from logitech_receiver import hidpp20 as h20
from logitech_receiver.hidpp20 import FEATURE

wanted = sys.argv[1:]


def host_table(dev):
    """{index: (status, name)} plus the current index, read straight from 0x1815."""
    state = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x00)
    if not state:
        return None, {}
    out = {}
    for host in range(state[2]):
        info = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x10, host)
        if not info:
            continue
        length, name, rem = info[4], '', info[4]
        while rem > 0:
            piece = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x30, host, length - rem)
            if not piece:
                break
            name += piece[2:2 + min(rem, 14)].decode(errors='replace')
            rem = max(0, rem - 14)
        out[host] = (info[1], name)
    return state[3], out


def all_devices():
    for info in base.receivers_and_devices():
        try:
            if getattr(info, 'isDevice', False):
                dev = Device.open(info)
                if dev:
                    try:
                        yield dev
                    finally:
                        dev.close()
            else:
                rcv = Receiver.open(info)
                if rcv:
                    try:
                        yield from rcv
                    finally:
                        rcv.close()
        except Exception:
            continue


kb = mouse = current = None
table = {}
via_receiver = False
for dev in all_devices():
    if not dev.ping():
        continue
    # Ask the device (DEVICE_NAME 0x0005) rather than reading dev.kind: Solaar 1.1.11
    # drops HID++ 2.0 kind 0 (= keyboard) as falsy, so a keyboard on Bluetooth shows '?'.
    kind = h20.get_kind(dev)
    if kind == 'keyboard' and kb is None:
        kb = dev.unitId or dev.serial
        current, table = host_table(dev)
        via_receiver |= dev.receiver is not None
    elif kind == 'mouse' and mouse is None:
        mouse = dev.unitId or dev.serial
        via_receiver |= dev.receiver is not None


def fail(msg):
    sys.stderr.write('ERROR: ' + msg + '\n')
    print('exit 1')
    sys.exit(0)


if not kb or not mouse:
    fail('need one keyboard and one mouse online on this machine.\n'
         '       Put both on this machine\'s channel, move the mouse, and retry.')
if current is None:
    fail('the keyboard did not report its host table (HOSTS INFO 0x1815).')

if wanted:
    by_name = {name: i for i, (status, name) in table.items()}
    missing = [w for w in wanted if w not in by_name]
    if missing:
        fail('no host slot named %s on the keyboard. Run mx-discover and use the\n'
             '       names it prints.' % ', '.join(repr(m) for m in missing))
    targets = sorted(by_name[w] for w in wanted)
else:
    targets = sorted(i for i, (status, name) in table.items() if status and i != current)
targets = [t for t in targets if t != current]
if not targets:
    fail('no other paired slot on the keyboard - nothing to link to.')

names = {i: (name or 'slot %d' % (i + 1)) for i, (status, name) in table.items()}
print('KEYBOARD_ID=%s' % kb)
print('MOUSE_ID=%s' % mouse)
print('SELF_INDEX=%d' % current)
print('VIA_RECEIVER=%d' % via_receiver)
print('TARGET_INDICES="%s"' % ' '.join(str(t) for t in targets))
print('HOST_NAMES_PY="%s"' % repr(names).replace('"', ''))
for t in targets:
    print('NAME_%d=%s' % (t, "'" + names[t].replace("'", '') + "'"))
PY
)"

echo "  keyboard unit ID : $KEYBOARD_ID"
echo "  mouse unit ID    : $MOUSE_ID"
echo "  this machine     : host index $SELF_INDEX (key labelled $((SELF_INDEX + 1)))"
echo "  connected via    : $([ "$VIA_RECEIVER" = 1 ] && echo receiver || echo 'Bluetooth only')"
for i in $TARGET_INDICES; do
  n="NAME_$i"
  echo "  follow to        : host index $i (key labelled $((i + 1))) = ${!n}"
done

# -------------------------------------------------------------- mx-push-mouse
cat > "$BIN/mx-push-mouse" <<'PUSH_EOF'
#!/usr/bin/env python3
"""Send the MX mouse to an Easy-Switch host, bypassing Solaar's device registry.

Called from the Solaar rules in ~/.config/solaar/rules.yaml when the MX keyboard
switches host, so the mouse follows it.

Why not Solaar's own `Set` action: `Set` resolves the target with Device.find(), which
silently skips any device Solaar has marked offline - a stale registry (after a
re-pairing) or a sleeping mouse both make it a no-op, and because `Set` never returns
False the rule's notification still fires, so it looks like it worked. Here we open the
receiver (or the Bluetooth device) ourselves and ping first, which both wakes the
mouse and sets the online flag that feature_request() requires.

Usage: mx-push-mouse <host-index>   # 0-based: the key labelled 1 is index 0
"""
import os
import subprocess
import sys
import time

try:
    from logitech_receiver import base
except ImportError:
    for _p in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
        if os.path.isdir(_p):
            sys.path.insert(0, _p)
            break
    from logitech_receiver import base
from logitech_receiver import Receiver
from logitech_receiver.device import Device
from logitech_receiver.hidpp20 import FEATURE

MOUSE = '@MOUSE_ID@'        # unit ID of the mouse, baked in at install time
HOST_NAMES = @HOST_NAMES@
PING_TRIES = 6              # a sleeping mouse needs a few before it answers
LOG = os.path.expanduser('~/.cache/mx-push-mouse.log')
NOTIFY = False              # True = desktop popup per switch; outcomes always go to LOG


def log(msg):
    with open(LOG, 'a') as fh:
        fh.write('%s %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), msg))


def notify(text, urgent=False):
    if not NOTIFY:
        return
    cmd = ['notify-send', '-t', '4000']
    if urgent:
        cmd += ['-u', 'critical']
    subprocess.Popen(cmd + ['Easy-Switch', text])


# Solaar's udev scan (hidapi/udev.py, find_paired_node) walks every hidraw node and
# crashes with AttributeError on one that is being removed. That is exactly the case
# when a Bluetooth keyboard triggers this script on its way to another host (the
# Keychron host-announce shortcut): its HID node disappears while we scan. A failed
# scan is therefore repeated before giving up. Seen and fixed 2026-11-10.
SCAN_TRIES = 8
SCAN_DELAY = 0.3
scan_errors = []


def all_devices():
    """Every HID++ device reachable here: behind a receiver, or connected directly."""
    for info in base.receivers_and_devices():
        try:
            if getattr(info, 'isDevice', False):
                dev = Device.open(info)
                if dev:
                    try:
                        yield dev
                    finally:
                        dev.close()
            else:
                rcv = Receiver.open(info)
                if rcv:
                    try:
                        yield from rcv
                    finally:
                        rcv.close()
        except Exception as e:
            scan_errors.append('%s: %s' % (type(e).__name__, e))
            continue


def main():
    host = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    target = HOST_NAMES.get(host, 'host %d' % (host + 1))
    started = time.monotonic()

    for scan in range(SCAN_TRIES):
        if scan:
            time.sleep(SCAN_DELAY)
        result = push(host, target, started)
        if result is not None:
            return result
        if not scan_errors:
            break           # a clean scan without the mouse: retrying will not help

    log('mouse not found on any receiver or Bluetooth link%s - not switching'
        % (' (scan error: %s)' % scan_errors[-1] if scan_errors else ''))
    notify('mouse did NOT follow to %s (not found)' % target, urgent=True)
    return 1


def push(host, target, started):
    """Find the mouse and send it to host. None if it was not found in this scan."""
    del scan_errors[:]
    for dev in all_devices():
        # Behind a receiver the unit ID is known up front. Over Bluetooth Solaar marks the
        # device offline until it answers once, and unitId stays None until then.
        if dev.unitId is None:
            dev.ping()
        if MOUSE not in (dev.unitId, dev.serial):
            continue
        for attempt in range(PING_TRIES):
            if dev.ping():
                break
            time.sleep(0.25)
        else:
            # Not necessarily a fault: the mouse is most likely already on
            # another host, so it is not here to answer at all.
            log('mouse did not answer %d pings - not on this machine' % PING_TRIES)
            notify('mouse not reachable here - already on another host?')
            return 1
        dev.feature_request(FEATURE.CHANGE_HOST, 0x10, host, no_reply=True)
        log('pushed mouse to host %d (%s) after %d ping(s), %.0f ms'
            % (host, target, attempt + 1, (time.monotonic() - started) * 1000))
        notify('keyboard → %s, mouse following' % target)
        return 0
    return None


if __name__ == '__main__':
    sys.exit(main())
PUSH_EOF
python3 - "$BIN/mx-push-mouse" "$MOUSE_ID" "$HOST_NAMES_PY" <<'PY'
import sys
path, mouse, names = sys.argv[1:]
s = open(path).read().replace('@MOUSE_ID@', mouse).replace('@HOST_NAMES@', names)
open(path, 'w').write(s)
PY
chmod +x "$BIN/mx-push-mouse"
echo "wrote $BIN/mx-push-mouse"

# --------------------------------------------------------- mx-hostname-keeper
cat > "$BIN/mx-hostname-keeper" <<'KEEPER_EOF'
#!/usr/bin/env python3
"""Keep the Logitech devices' current-host name equal to this machine's hostname.

Why this exists: the Bolt receiver re-stamps 'Logitech Bolt receiver' into the MX
Mechanical's host-0 slot on every reconnect, while the MX Anywhere 3S keeps
this machine's name. Logi Options+ on a Windows host makes the mouse follow the keyboard
back to this machine by matching host names across the two devices' host tables
(HID++ feature 0x1815), so the mismatch silently breaks the return trip - the mouse
is never sent a switch command at all. Solaar only corrects the name when it first
builds the change-host setting (settings_templates.py:1098), i.e. once per device
per Solaar run, so nothing repairs it afterwards.

Watches the receiver's HID++ node for device-connect notifications and re-applies
the name each time. Verified 2026-09-09: aligned names -> mouse follows; after one
reconnect the name reverts and it stops.

Those notifications only arrive while the receiver's 'wireless' notification flag
is set. A suspend clears it (seen 2026-10-04, s2idle) and Solaar 1.1.11 sets it only
at startup, so the keeper went deaf for three days without a single error. It now
checks the flag once a minute, re-arms it, and repairs whatever it missed.
"""
import os
import select
import socket
import sys
import time

try:
    from logitech_receiver import base
except ImportError:
    for _p in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
        if os.path.isdir(_p):
            sys.path.insert(0, _p)
            break
    from logitech_receiver import base
from logitech_receiver import Receiver
from logitech_receiver import hidpp10 as h10
from logitech_receiver import hidpp20 as h20
from logitech_receiver.hidpp20 import FEATURE

HOSTNAME = socket.gethostname().partition('.')[0]
SETTLE = 1.5    # let the link settle before writing
RESCAN = 5.0    # wait before looking for the receiver again
CHECK = 60      # how often to verify connection notifications are still on


def log(msg):
    print('%s %s' % (time.strftime('%Y-%m-%d %H:%M:%S'), msg), flush=True)


def stored_host_name(dev):
    """The name as actually stored, bypassing Solaar's get_host_names auto-correct."""
    state = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x00)
    if not state:
        return None, None
    current = state[3]
    info = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x10, current)
    if not info:
        return current, None
    length = info[4]
    name, remaining = '', length
    while remaining > 0:
        piece = h20.feature_request(dev, FEATURE.HOSTS_INFO, 0x30, current, length - remaining)
        if not piece:
            break
        name += piece[2:2 + min(remaining, 14)].decode(errors='replace')
        remaining = max(0, remaining - 14)
    return current, name


def find_receiver():
    for info in base.receivers():
        try:
            rcv = Receiver.open(info)
        except Exception:
            continue
        if rcv:
            return info, rcv
    return None, None


def notifications_armed(rcv):
    """Make sure the receiver reports device connects. False if they had to be re-armed."""
    flags = h10.get_notification_flags(rcv)
    if flags is None or flags & h10.NOTIFICATION_FLAG.wireless:
        return True
    rcv.enable_connection_notifications()
    log('connection notifications were off (flags %#x) - re-enabled' % flags)
    return False


def fix_names():
    info, rcv = find_receiver()
    if not rcv:
        return
    try:
        notifications_armed(rcv)
        for dev in rcv:
            try:
                if not dev.ping():
                    continue
                host, name = stored_host_name(dev)
                if name is None or name == HOSTNAME:
                    continue
                ok = h20.set_host_name(dev, HOSTNAME)
                log('%s host %d: %r -> %r%s' % (dev.name, host, name, HOSTNAME, '' if ok else ' FAILED'))
            except Exception as e:
                log('device %s: %s' % (getattr(dev, 'number', '?'), e))
    finally:
        rcv.close()


def check(info):
    """Periodic: re-arm notifications after a suspend, and repair any connect missed meanwhile."""
    rcv = Receiver.open(info)   # not find_receiver(): enumerating spams the log every time
    if not rcv:
        return
    try:
        armed = notifications_armed(rcv)
    finally:
        rcv.close()
    if not armed:
        fix_names()


def watch(info):
    fd = os.open(info.path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        while True:
            ready, _, _ = select.select([fd], [], [], CHECK)
            if not ready:
                check(info)
                continue
            try:
                data = os.read(fd, 64)
            except BlockingIOError:
                continue
            # 0x41 = device connection notification; bit 0x40 of the first data
            # byte means "link not established", so clear = the device just arrived
            if len(data) >= 5 and data[2] == 0x41 and not (data[4] & 0x40):
                time.sleep(SETTLE)
                fix_names()
    finally:
        os.close(fd)


def main():
    while True:
        info, rcv = find_receiver()
        if not rcv:
            time.sleep(RESCAN)
            continue
        rcv.close()
        log('watching %s' % info.path)
        try:
            fix_names()
            watch(info)
        except OSError as e:
            log('receiver gone: %s' % e)
        except Exception as e:
            # A resume can re-enumerate the receiver mid-scan; Solaar's udev lookup then
            # raises AttributeError, which killed the keeper silently on 2026-10-16.
            log('error, rescanning: %r' % e)
        time.sleep(RESCAN)


if __name__ == '__main__':
    main()
KEEPER_EOF
chmod +x "$BIN/mx-hostname-keeper"
echo "wrote $BIN/mx-hostname-keeper"

# --------------------------------------------------------------- solaar rules
RULES="$PREFIX/.config/solaar/rules.yaml"
mkdir -p "$(dirname "$RULES")"
if [ -f "$RULES" ]; then
  cp "$RULES" "$RULES.bak-$(date +%Y%m%d-%H%M%S)"
  echo "backed up existing rules.yaml"
fi
{
  cat <<RULES_HEAD
%YAML 1.3
# Easy-Switch device linking: when the keyboard switches host, send the mouse
# to the same host. Generated by mx-setup.sh on $(date +%F).
#
# Device is the keyboard's unit ID. TestBytes is range_test(start,end,min,max)
# over int.from_bytes(data[1:2]) - the 0-based target host index in the
# CHANGE HOST notification. One rule per target slot, because Execute cannot
# pass the matched byte on to the command.
#
# This machine is host index $SELF_INDEX (key $((SELF_INDEX + 1))). No rule for it: a switch TO
# this machine is seen by the machine the keyboard is leaving, not by this one.
#
# The push is done by mx-push-mouse rather than Solaar's own \`Set\` action:
# \`Set\` resolves the mouse through Device.find(), which skips any device Solaar
# has marked offline, so a stale registry or a sleeping mouse turns the rule
# into a silent no-op - and because \`Set\` never returns False, a notification
# action after it still fires and makes it look like it worked.
RULES_HEAD
  for i in $TARGET_INDICES; do
    n="NAME_$i"
    cat <<RULE
---
# key $((i + 1)) = host index $i = ${!n}
- Rule:
  - Feature: CHANGE HOST
  - Device: '$KEYBOARD_ID'
  - TestBytes: [1, 2, $i, $i]
  - Execute: ['$BIN/mx-push-mouse', '$i']
RULE
  done
  echo "..."
} > "$RULES"
echo "wrote $RULES"

# ---------------------------------------------- Solaar < 1.1.19 backlight guard
# Solaar 1.1.11 cannot parse BACKLIGHT2 (0x1982) version 3, which the MX Mechanical
# reports (firmware RBK 71.03): TypeError 'int' object is not subscriptable. The
# exception kills that device's listener thread at startup, so its CHANGE HOST
# notifications are never processed and no rule ever fires - silently. Listing
# `backlight` in the device's `_absent` list in config.yaml makes Solaar never build
# the setting at all (settings_templates.check_feature_settings). That is stronger
# than `_sensitive: {backlight: ignore}`, which only skips applying it at startup.
# Solaar rewrites config.yaml on exit, so it must not be running while we edit it.
CONF="$PREFIX/.config/solaar/config.yaml"
if [ "$DRY_RUN" != "1" ] && pgrep -x solaar >/dev/null; then
  pkill -x solaar        # -x, never -f: -f matches this shell's own command line
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x solaar >/dev/null || break; sleep 1; done
  echo "stopped Solaar (restarted at the end)"
fi
python3 - "$CONF" "$HOME/.config/solaar/config.yaml" <<'PY'
import os, re, shutil, sys, time
try:
    from logitech_receiver import base
except ImportError:
    for p in ('/usr/share/solaar/lib', '/usr/lib/solaar/lib'):
        if os.path.isdir(p):
            sys.path.insert(0, p); break
    from logitech_receiver import base
from logitech_receiver import Receiver
from logitech_receiver.device import Device
from logitech_receiver.hidpp20 import FEATURE
import yaml
try:
    from solaar import __version__ as VERSION
except Exception:
    VERSION = None

conf, real_conf = sys.argv[1:]
nums = tuple(int(x) for x in re.findall(r'\d+', VERSION or '')[:3])
if not VERSION or nums >= (1, 1, 19):
    print('backlight guard: Solaar %s - not needed' % VERSION)
    sys.exit(0)


def all_devices():
    for info in base.receivers_and_devices():
        try:
            if getattr(info, 'isDevice', False):
                dev = Device.open(info)
                if dev:
                    try:
                        yield dev
                    finally:
                        dev.close()
            else:
                rcv = Receiver.open(info)
                if rcv:
                    try:
                        yield from rcv
                    finally:
                        rcv.close()
        except Exception:
            continue


affected = []
for dev in all_devices():
    try:
        if not dev.ping() or not dev.features:
            continue
        version = dev.features.get_feature_version(FEATURE.BACKLIGHT2)
    except Exception:
        continue
    if version and version >= 3:
        affected.append({'_NAME': dev.name, '_wpid': dev.wpid, '_modelId': dev.modelId,
                         '_unitId': dev.unitId, '_serial': dev.serial})
if not affected:
    print('backlight guard: no online device with BACKLIGHT2 v3 - not needed')
    sys.exit(0)

# a dry run patches a copy of the real config, so the result can be inspected
if not os.path.exists(conf) and os.path.exists(real_conf) and os.path.abspath(conf) != os.path.abspath(real_conf):
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    shutil.copy(real_conf, conf)
data = None
if os.path.exists(conf):
    shutil.copy(conf, conf + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
    with open(conf) as fh:
        data = yaml.safe_load(fh)
if not data:
    data = [VERSION]
if data[0] != VERSION:
    # Solaar drops every _absent and _battery when the file was written by another
    # version (configuration._parse_config), which would drop ours too. Do the same
    # drop now and stamp the current version, so what we add survives the load.
    print('backlight guard: config.yaml was written by Solaar %s - refreshing as Solaar would' % data[0])
    data[0] = VERSION
    for entry in data[1:]:
        if isinstance(entry, dict):
            entry.pop('_absent', None)
            entry.pop('_battery', None)

for ident in affected:
    entry = next((e for e in data[1:] if isinstance(e, dict) and (
        (ident['_serial'] and e.get('_serial') == ident['_serial'])
        or (ident['_unitId'] and e.get('_modelId') == ident['_modelId'] and e.get('_unitId') == ident['_unitId']))), None)
    if entry is None:
        entry = {k: v for k, v in ident.items() if v}
        data.append(entry)
    absent = list(entry.get('_absent') or [])
    if 'backlight' not in absent:
        absent.append('backlight')
    entry['_absent'] = absent
    # a stored value overrides _absent ("known_present"), so it has to go
    entry.pop('backlight', None)
    print('backlight guard: %s (%s): backlight in _absent' % (ident['_NAME'], ident['_serial']))

with open(conf, 'w') as fh:
    yaml.dump(data, fh, default_flow_style=None, width=150)
print('wrote %s' % conf)
PY

# ------------------------------------------------------------------- autostart
# The keeper repairs names a receiver re-stamps (faults 3 and 5). Without a receiver it
# has nothing to watch, and its rescan loop logs Solaar's enumeration warnings every
# 5 s (~6 MB/day, measured on a Bluetooth-only machine), so it is installed only with one.
if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "Dry run: skipping service installation."
elif [ "$VIA_RECEIVER" != "1" ]; then
  if command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled mx-hostname-keeper >/dev/null 2>&1; then
    systemctl --user disable --now mx-hostname-keeper.service
    echo "disabled mx-hostname-keeper left from an earlier install"
  fi
  rm -f "$PREFIX/.config/autostart/mx-hostname-keeper.desktop"
  echo "devices on Bluetooth only: mx-hostname-keeper not started (it only serves a receiver;"
  echo "re-run this installer if you move the devices to a receiver)"
else
  if command -v systemctl >/dev/null 2>&1; then
    UNIT="$PREFIX/.config/systemd/user/mx-hostname-keeper.service"
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<'UNIT_EOF'
[Unit]
Description=Keep the MX devices' current-host name equal to this machine's hostname

[Service]
ExecStart=%h/.local/bin/mx-hostname-keeper
Restart=always
RestartSec=5
StandardOutput=append:%h/.cache/mx-hostname-keeper.log
StandardError=append:%h/.cache/mx-hostname-keeper.log

[Install]
WantedBy=default.target
UNIT_EOF
    systemctl --user daemon-reload
    systemctl --user enable --now mx-hostname-keeper.service
    echo "installed and started systemd user service mx-hostname-keeper"
  else
    DESKTOP="$PREFIX/.config/autostart/mx-hostname-keeper.desktop"
    mkdir -p "$(dirname "$DESKTOP")"
    cat > "$DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=MX host-name keeper
Exec=/bin/sh -c 'exec "\$HOME/.local/bin/mx-hostname-keeper" >> "\$HOME/.cache/mx-hostname-keeper.log" 2>&1'
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
    echo "installed XDG autostart entry (no systemd found)"
    nohup setsid "$BIN/mx-hostname-keeper" >> "$PREFIX/.cache/mx-hostname-keeper.log" 2>&1 &
  fi
fi

# ------------------------------------------------------------- restart Solaar
# Solaar does not pick up rules.yaml or config.yaml changes by itself.
if [ "$DRY_RUN" != "1" ]; then
  pkill -x solaar || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x solaar >/dev/null || break; sleep 1; done
  (setsid solaar --window=hide >/dev/null 2>&1 &)
  echo "started Solaar"
fi

cat <<DONE

Done. Next:

  1. Check that Solaar survives the keyboard - this must print nothing:
       solaar show 2>&1 | grep -A3 Traceback
     (the full listener check is in docs/setup.md, section 6, fault 7)
  2. On a Wayland compositor without XDG autostart (Hyprland/Omarchy), add to your config:
       exec-once = solaar --window=hide
  3. Press each channel key listed above and watch:
       tail -f ~/.cache/mx-push-mouse.log
  4. A Windows machine among the targets needs Logi Options+ for the way back - see docs/setup.md.
DONE
