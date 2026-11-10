# mx-easy-switch

Pressing an Easy-Switch channel key on a Logitech MX keyboard also moves the MX mouse to the
same computer, in both directions — Solaar rules on Linux, Logi Options+ on Windows. Works with
the devices behind a Logi Bolt receiver or paired directly over Bluetooth, and with up to three
computers.

- [`docs/setup.md`](docs/setup.md) — the full guide: why it works this way, the nine silent
  failure modes, distro differences, diagnostics, the Windows side, and three hosts. Read
  section 1 first.
- [`mx-setup.sh`](mx-setup.sh) — the Linux installer (`mx-discover`, `mx-push-mouse`,
  `mx-hostname-keeper`, one Solaar rule per other slot, autostart, Solaar backlight fix).
- [`docs/2026-10-07-pc-to-linux-mouse-stays.md`](docs/2026-10-07-pc-to-linux-mouse-stays.md) —
  a worked investigation of the subtlest failure (host names that no longer match), including how
  to read Logi Options+'s debug log.

Keyboard and mouse must both be on this machine while the installer runs:

```sh
./mx-setup.sh --dry-run --prefix /tmp/mx   # inspect: writes only under /tmp/mx
./mx-setup.sh                              # follow to every other paired slot
./mx-setup.sh --target OTHER-MACHINE-NAME  # or: only to the named slot(s); repeatable
```

Every computer in the rotation needs its own linking: this setup on Linux, Logi Options+ on
Windows or macOS. The computer the keyboard *leaves* is the one that moves the mouse.

`mx-push-mouse <slot>` also works on its own, so a non-Logitech keyboard can drive it. The
`keychron-host-announce` project does that for a Keychron V6 Max (guide, section 12).
