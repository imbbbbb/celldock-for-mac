[English](README.md) · [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Resources/app_icon.png" width="128" height="128" alt="CellDock icon">
</p>

<h1 align="center">CellDock Modes</h1>

<p align="center">
  Use cellular network, SMS, and calls on your Mac — and move the same module freely
  between your Mac, an iPhone/iPad, and DJI hardware.
</p>

---

> ### About this project
>
> This is a personal derivative of [**celldock/celldock-for-mac**](https://github.com/celldock/celldock-for-mac).
>
> The original project did nearly all of the work — cellular takeover, SMS, calls and
> recording, the SOCKS5 proxy, eSIM management, multi-module scheduling. All of that is
> the original authors'. This fork only addresses one class of problem I ran into while
> using it: **the one-way rewrite of the module's USB identity.**
>
> Sincere thanks to the original authors for their open-source work. Without that
> foundation this fork could not exist.
>
> This fork was built for personal use under the upstream [non-commercial license](LICENSE).
> It is **not** official. Please report problems here rather than bothering the upstream
> maintainers.

## Why this fork exists

During setup, the original project rewrites the DJI QDC507 module's factory USB identity
**once, irreversibly**:

```
factory    2CA3:4006   USBCFG = 1,1,1,1,1,0,0
           ↓  one-way rewrite, no way back
rewritten  2C7C:0125   USBCFG = 1,1,1,1,1,1,1
```

That rewrite is necessary on a Mac, but it has two consequences:

1. **The trailing `audio=1` makes the module enumerate as a USB sound card.** Plug the
   module into an iPhone or iPad and iOS treats it as an external audio device,
   **hijacking system audio output** — when all I want on a mobile device is cellular data.
2. **Once the VID/PID changes, DJI's own DJOneHub can no longer find the module.** There is
   no path back to the drone.

The problem isn't the hardware. It's that the software treated a *conversion* as a terminal
state rather than as one of several switchable states. This fork turns it into three
reversible modes.

## What this fork changes

### 1. Three reversible modes (the core change)

| Mode | USB identity | USBCFG | Purpose |
| --- | --- | --- | --- |
| **Mac Full** | `2C7C:0125` | `1,1,1,1,1,1,1` | Data + SMS + calls + recording |
| **iPhone / iPad Data-Only** | `2C7C:0125` | `1,1,1,1,1,1,0` | Cellular data only — **no sound card enumerated**, iOS audio untouched |
| **DJI Stock** | `2CA3:4006` | `1,1,1,1,1,0,0` | Factory identity restored, recognized by DJOneHub |

You can move between all three in any direction — it is no longer a one-way trip. Field
order is `diag, nmea, AT, modem, rmnet, ADB, audio`; `usbnet` is 1 in all three modes.

### 2. Write safety

Getting a USB config write wrong can make the module vanish from the system, so this part
has several layers of protection:

- **A failed read-back makes the restart unreachable.** The commit step (`AT+CFUN=1,1`)
  accepts only a credential object produced by the verification stage. "Restarted without
  a matching read-back" is **unrepresentable at compile time**, not guarded by a runtime
  `if`.
- **A dropped link after the write is no longer treated as failure.** After USBCFG is
  written the module may immediately re-enumerate and the AT port disappears — at which
  point the write has quite possibly **already succeeded**. Rewriting would be dangerous.
  The transaction now enters an `indeterminate` state: read only, never write, wait for
  re-enumeration and read back the real state before deciding.
- **Whitelist validation.** The target must match one of the three rows above exactly;
  no runtime assembly of config strings. Parsing USBCFG requires exactly 7 fields.
- **A no-op target is skipped** rather than written again.
- **Snapshots are keyed by IMEI** (stable across modes) instead of the VID/PID, which changes.

### 3. Recovery and diagnostics page

A new page reachable in *any* state — including the `degraded` case where USBCFG is
unrecognized but the AT port still answers. The original project locks the module out of
the setup screen in that situation, with no way to recover.

It shows current USB identity, full USBCFG, usbnet, firmware revision, IMEI, ADB and UAC
status, recent configuration snapshots with their write/read-back results, and the mode
switch log. Actions: switch to any mode, **restore the last verified configuration**, and
export a diagnostic report.

### 4. Firmware capability no longer trusts the device's self-report

Testing showed the module's capability advertisement is **not trustworthy**:

```
AT+QPCMV=?    → +QPCMV: (0,1),(0-2)     ← claims support
AT+QPCMV?     → ERROR                    ← actually unusable
AT+QPCMV=0    → ERROR
```

Media backend selection is therefore driven by a **verified-firmware table**. Firmware not
in the table is conservatively refused rather than probed, instead of believing what
`AT+QPCMV=?` says.

### 5. Upstream defects fixed

- **The microphone and Contacts permission prompts never appeared.** The Hardened Runtime
  entitlements `com.apple.security.device.audio-input` and
  `.personal-information.addressbook` were missing, so the system denied the request
  outright — it never reached the user at all. Entitlements added.
- **Modules with `audio=0` were locked out of the setup screen** and could not enter the
  app (the direct cause of point 3 above).
- **The app built by `script/build_and_run.sh` was killed by dyld on launch** — it never
  embedded `Sparkle.framework`, which the binary's rpath points at. The same script's
  helper plist path and codesign identifier were also still the pre-rename `app.mavo.*`,
  and it never copied the Sounds and svg resources.
- **`tools/qdc507_iokit_tool.c` did not compile** — it still called the renamed
  `mavo_modem_*` API, leaving no standalone AT rescue tool when a module misbehaves.
  Fixed, and added to the test script so it cannot silently rot again.

### 6. Other additions

- **Module labels.** User-defined names keyed by IMEI, so you can tell modules apart when
  running more than one.
- **Right-click to delete an SMS conversation**, matching the call log's interaction.
- **AT console fixes**: text in the input field can be drag-selected, a "Copy All" button
  was added, and the focus ring no longer lingers after switching to another page.
- **Sparkle automatic updates disabled.** The official feed serves builds without these
  changes, and installing one would overwrite them. The update section now clearly reads
  as disabled instead of leaving dead controls in place.
- **`scripts/make_dmg.sh`** — one command produces an installable DMG.

### Verification status

Verified on real hardware: a QDC507 module running firmware
`QDC507GLEFM21_01.001.01.007`. Detection of all three modes, entering the app in each,
repeated reversible switching, and DJOneHub re-recognizing the module in DJI Stock mode
were all confirmed on-device.

**Configurations outside the three modes are repairable too**, confirmed on hardware: a
module reporting `2CA3:4006,1,1,1,1,1,0,1` — the DJI factory identity with USB audio
enabled — was restored by switching to any mode. A switch writes the complete target
USBCFG, and no flag from the source enters that write, so any module whose USB identity is
a known QDC507 and whose AT port answers can be repaired — even from a configuration that
has never been verified.

The write-failure branches (read-back mismatch, dropped link) are covered by unit tests;
they were not reproduced by inducing real faults. Multi-module concurrency is untested —
I only have one module.

## Installation

No prebuilt releases are published here. Build it yourself:

```bash
git clone https://github.com/imbbbbb/celldock-for-mac.git
cd celldock-for-mac
./scripts/make_dmg.sh          # produces outputs/CellDock-<version>-arm64.dmg
```

Requires macOS 14+ and the Xcode command line tools.

> **On signing**: without an Apple Developer certificate on your machine the resulting DMG
> is ad-hoc signed. It installs fine locally, but once that DMG travels over the network
> macOS will report the app as **"damaged"** — the file is intact; this is just the standard
> prompt for quarantined unsigned software, worded in a way that sends people looking for a
> corrupted download. The workaround is included inside the DMG: right-click → Open in
> Finder, or `xattr -dr com.apple.quarantine "/Applications/CellDock Modes.app"`.

---

Everything below describes the upstream project and is unchanged by this fork.

## Features

### Multi-Module & Cellular Network

- Discovers and monitors multiple supported USB cellular modules at the same time.
- Choose a separate module for calls and for data; only one module serves as the system's
  cellular-first egress at a time.
- Set each module to **Cellular First**, **Keep Connected**, or **Off**. Modules kept
  connected remain usable by bound SOCKS5 proxies but are not used as macOS's default
  network egress.
- Enabling automatically gives cellular priority over Wi-Fi.
- Disabling restores the previous network order without affecting SMS or incoming calls.
- Each module remembers its cellular switch state; reconnecting a module restores its
  previous choice.
- Bounded automatic recovery when the ECM link, DHCP, or module restart misbehaves.
- Live display of carrier, network mode, signal strength, IP address, and connection stage.
- Optional real-time download/upload speeds in the menu bar (fixed width, two lines),
  off by default.

### SOCKS5 Proxy

- Create a separate SOCKS5 proxy per module so apps or LAN devices can select a specific
  cellular egress.
- Listen on localhost only or on the LAN; ports are auto-assigned from `1080` and can be
  changed.
- Supports no-auth and username/password authentication; LAN listeners require authentication.
- Each proxy starts and stops independently and reports connection count and status such as
  module offline, cellular off, link down, or port in use.
- Proxies bind to a stable module identity and re-resolve the network interface after the
  module is reinserted. Auth passwords are stored in the macOS Keychain.

> A LAN proxy exposes the cellular egress to other devices on the same network. Use a
> strong password and make sure your firewall and network are trustworthy.

### SMS

- Receive SMS in the background with macOS notifications.
- View full threads by conversation; copy text, reply, or compose new messages.
- Send Chinese text and long (concatenated) messages.
- Auto-detects verification codes; click to copy and mark as read.
- Messages are tagged with their source module; choose which available module sends each
  message.
- Deleted messages no longer appear in CellDock; if a message is still stored on the module,
  CellDock also tries to clear it.
- Optionally auto-delete verification-code messages 30 minutes after they are read.

### Calls & Recording

- Dial, answer, reject, mute, and hang up.
- Incoming calls show a notification and floating window with Answer and Decline buttons.
- In-call keypad for navigating automated phone menus.
- Use your Mac's microphone and speakers for calls.
- Keeps recent and missed calls, noting which module was used.
- Manual and user-confirmed automatic recording captures both parties and saves as M4A.
- The recording library offers waveforms, playback, seeking, speed control, volume, rename,
  export, and Reveal in Finder.

> Before recording a call, get consent from all participants and follow local laws.

### SIM, eSIM & Contacts

- View SIM status, ICCID, IMSI, own number, carrier, network mode, and signal information.
- Configure per module whether it accepts incoming calls; operations that require a module
  restart are clearly flagged.
- Auto-detects physical SIM and eUICC.
- On supported eUICCs, view the EID and profiles; download, enable, disable, rename, or
  delete eSIM profiles.
- Reads the macOS Contacts database to match names on SMS and calls.
- Create, edit, delete contacts and manage contact groups in CellDock.

### Menu Bar, Sound & Interface

- Hot-plug modules without restarting the app.
- The menu bar icon shows calls, missed calls, unread SMS, the current data module, or
  callable-module status.
- The menu bar panel lists unread SMS and missed calls per module and automatically hides
  empty sections.
- Customizable SMS sound and ringtone; defaults are `bleeps.wav` and `ring.mp3`.
- Simplified Chinese, English, 日本語, and Français, switchable instantly in Settings.
- Follows system, light, and dark themes.
- Presentation privacy mode hides contacts, numbers, message bodies, verification codes,
  and recording titles.
- Open a standard main window; closing it keeps the app running in the menu bar.
- Optionally hide the menu bar icon when no module is connected.
- Optionally launch at login, off by default.
- ~~Built-in stable and beta update channels~~ — disabled in this fork, see above.

## Screenshots

<p align="center">
  <sub>Click to view full size</sub>
</p>

| SMS | Calls |
| :---: | :---: |
| <a href="screenshot/1. sms.png"><img src="screenshot/1. sms.png" width="320" alt="SMS"></a> | <a href="screenshot/2. call.png"><img src="screenshot/2. call.png" width="320" alt="Calls"></a> |

| In-Call | In-Call |
| :---: | :---: |
| <a href="screenshot/2.1 calling.png"><img src="screenshot/2.1 calling.png" width="320" alt="In-Call"></a> | <a href="screenshot/2.2 calling.png"><img src="screenshot/2.2 calling.png" width="320" alt="In-Call"></a> |

| Recordings | Proxy |
| :---: | :---: |
| <a href="screenshot/3.records.png"><img src="screenshot/3.records.png" width="320" alt="Recordings"></a> | <a href="screenshot/4. proxy.png"><img src="screenshot/4. proxy.png" width="320" alt="Proxy"></a> |

| Device | Settings |
| :---: | :---: |
| <a href="screenshot/5. device.png"><img src="screenshot/5. device.png" width="320" alt="Device"></a> | <a href="screenshot/6. settings.png"><img src="screenshot/6. settings.png" width="320" alt="Settings"></a> |

> These screenshots come from the upstream project and do not yet show the mode switching
> and recovery pages added here.

## Acknowledgments

- [**celldock/celldock-for-mac**](https://github.com/celldock/celldock-for-mac) — the direct
  upstream. The whole application architecture, cellular takeover, the SMS and call paths,
  eSIM management, and the SOCKS5 proxy are the original authors' work. This fork's share is
  small; the overwhelming majority of the credit is theirs.
- [**moluncn/mavo**](https://github.com/moluncn/mavo) — upstream drew on mavo for its
  interface and feature design, and that thanks is passed along here too.

## Disclaimer

- This fork is a personal derivative built for my own use. It is **not official** and has
  not been reviewed or endorsed by the upstream authors. Report issues here, not upstream.
- **Switching module modes rewrites the module's USB configuration and restarts it.**
  Despite the layers of protection described above, rewriting firmware configuration
  carries inherent risk. Use it only if you understand what it does; the author accepts no
  responsibility for module damage or malfunction.
- CellDock is provided "as is", without any express or implied warranty. The author makes
  no guarantees about its suitability or performance for any particular purpose.
- The app modifies macOS network configuration (for example, making cellular the priority
  egress and installing a network helper), which may affect existing network connections.
  Make sure you understand these features before use.
- The availability of cellular data, SMS, calls, and eSIM features depends on module
  firmware, SIM card, carrier, and local network conditions. The author does not guarantee
  their availability or performance in every environment.
- Sharing a cellular connection to LAN devices through the SOCKS5 proxy exposes that egress
  to other devices on the same network. Assess the security risks yourself and configure
  authentication properly.
- Get consent from call participants before recording and follow local laws; also follow
  your carrier's terms of service when using features such as connection sharing.
- The author is not liable for any direct or indirect loss caused by using or being unable
  to use this software.

## License

Inherits the upstream [non-commercial license](LICENSE): free to use, modify, and distribute
for personal and non-commercial purposes. **Any form of commercial use is prohibited**;
commercial use requires separate written authorization from the **original authors** — this
fork has no standing to grant it. Third-party components and their licenses are listed in
[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
