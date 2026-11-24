# doment — product spec

**Date:** 2026-11-24
**Status:** approved by the owner on 2026-11-24
**Research:** docs/dforge/research/2026-11-24-game-streaming.md, 2026-11-24-remote-support.md, 2026-11-24-remote-coding.md,
2026-11-24-streaming-pipeline.md (all sourced; items they mark "Unverified" stay unverified here)

## 1. Problem

The owner works on a laptop but wants the power of a desktop PC: for coding, for design and animation work (Photoshop,
After Effects), and for games. Today that takes several tools, each with a gap the research documents:

- **Parsec** connects easily but needs its cloud and an account, puts 4:4:4 colour, multi-monitor and extra virtual
  displays behind a subscription, and has no Linux host.
- **Sunshine with Moonlight** is free but has no NAT traversal (internet use needs port forwarding or a VPN), a fragile
  setup, capture failures at UAC and lock screens, and in 2026 put its Windows gamepad driver behind a paid licence.
- **TeamViewer, AnyDesk, RustDesk and ScreenConnect** cover unattended support but are slower, carry licence friction, and
  have a long record of security incidents caused by account takeover, unsigned configuration, trusted file transfer and
  test certificates.
- **No remote-desktop product offers a text terminal channel.** Developers running several terminals and AI coding agents
  add tmux, SSH and a separate agent manager, and on a Windows host those sessions die when the connection drops.
- **Wake-on-LAN** exists in most products but fails silently and only works with a helper on the same network.

doment is one self-hosted product that covers all of it: a low-latency stream good enough for text, colour work and games,
persistent remote terminals with a dashboard, unattended access, and remote power-on, with no vendor cloud.

## 2. Users and their top tasks

The first user is the owner, on the owner's own machines and those of people the owner supports.

1. **Use the PC from the laptop** for everyday desktop work, design and animation: sharp text, accurate colour, the
   laptop's own resolution and refresh rate, correct shortcuts, clipboard and files.
2. **Code remotely**: several terminals and AI coding agent sessions on one or more machines that keep running when the
   laptop disconnects, with one dashboard that shows which session needs attention.
3. **Play games remotely** at high frame rate with controllers, at home and over the internet.
4. **Manage the homelab**: see which machines are on, asleep or off; power them on; reach headless machines.
5. **Support other people's PCs** unattended: login screen, UAC prompts, file transfer, reboot and reconnect (release 1.1).

## 3. Success measures

The owner approved these numbers with the spec on 2026-11-24; changing one is a spec change. Latency and frame delivery
are measured by the harness built in M1; the sharpness measurement is added to it in M9; SM8 is a build check and SM9 is
an owner sign-off. SM6 and the transport share of the latency budget are first proven on Linux (M2 to M4); every measure
that involves pixels is measured from M7 on the owner's Windows hardware.

- **SM1 Wired LAN.** 1440p at 120 Hz from an NVIDIA host to an Intel, an AMD and an NVIDIA client: added latency from
  host frame capture to client present is at most 16 ms at p50 and 33 ms at p99, and at least 99% of frames arrive on
  time over a 30-minute session.
- **SM2 Wi-Fi 6 LAN.** Same session: at most 20 ms at p50 and 45 ms at p99.
- **SM3 Internet.** On a direct path, added latency is at most 16 ms at p50 above the one-way network delay; a relayed
  session states its extra delay in the client.
- **SM4 Sharpness.** In desktop mode the coloured small-text test image is reproduced with a per-pixel error of at most
  2 in 255 within 0.5 seconds of the screen going still, on Intel, AMD and NVIDIA clients.
- **SM5 Connecting.** From choosing a paired device to the first frame takes at most 2 seconds on the LAN and 4 seconds
  over the internet; choosing a sleeping device wakes it and connects in one action.
- **SM6 Terminals.** A terminal session survives 24 hours with no client attached; reattaching shows the current screen
  within 1 second.
- **SM7 Gaming.** With a stream active the host game's frame rate is at least 95% of its rate without doment; a
  controller with rumble works in an XInput game.
- **SM8 First-party.** No code ships outside doment, darkraise-framework, .NET, operating-system APIs and GPU-driver
  interfaces except the entries of the exception register; every executable is published with NativeAOT.
- **SM9 Daily driver.** The owner uses doment as the only remote tool for 14 consecutive days.

## 4. Non-goals

Chosen by the owner in the discovery interview:

- **Enterprise fleet features**: mass deployment through MSI or Group Policy, technician role hierarchies, SIEM export,
  compliance session recording. A per-device permission list and a local audit log are in scope.

Proposed by this spec and approved by the owner with it on 2026-11-24:

- Circumventing protected content (DRM video stays black) or anti-cheat systems that reject injected input.
- Phones and tablets as hosts (they are clients only).
- Renting or provisioning cloud machines.

Not non-goals, and not on the roadmap yet (the owner left them possible): a doment-run hosted service with accounts and
billing, a browser client, and shared sessions with guests. Each would enter as a new milestone.

## 5. Constraints

- **Stack:** C# on .NET 10, every executable published with NativeAOT, built on darkraise-framework (core library and
  Win32UI). Reusable, product-neutral pieces go into the framework.
- **Build order (owner decision):** everything that can be built and verified on the Linux development machine comes
  first (M1 to M6): the portable core, the transport, the server, NAT traversal, the terminal service with a Linux
  headless agent, wake, and the portable media and input logic. Work that needs a Windows machine (capture, encoders,
  the service, the Win32UI desktop app) starts at M7.
- **Platform order:** for screen streaming, Windows is the first host and client. The Linux headless agent (terminals,
  wake helper, relay node) is part of 1.0 because it is built in the Linux phase. Then Android, Linux desktop and Steam
  Deck, macOS and iOS clients, and macOS and Linux desktop hosts. The portable core compiles for all of them from M1.
- **Windows floor:** Windows 11 x64 for host and client in 1.0. The framework is designed and tested on
  Windows 11, and Windows 10 is past its end of support.
- **Third-party rule:** first-party by default. A third-party component is allowed only as a named exception approved in
  this spec, with a reason, an interface around it and a replacement plan (section 11). GPU encoder interfaces (NVENC,
  Quick Sync) ship inside the installed GPU driver, are not redistributed, and count as platform APIs.
- **Drivers:** version 1.0 uses existing signed open-source drivers for the virtual display and the virtual gamepad;
  first-party drivers come in M17. No microphone passthrough before M17. Drivers are C or C++, outside the C# rule.
- **Self-hosted:** no doment-run cloud. The owner runs the server. LAN, direct-address and VPN connections work with no
  server at all.
- **Direct first:** client and host connect directly whenever possible; the relay or a VPN is used only when a direct
  path fails, and the user always sees which path is active.
- **Reference hardware:** NVIDIA and Intel GPUs and GPU-less virtual machines as hosts; Intel, AMD and NVIDIA laptops
  as clients. Target picture: 1440p at 120 Hz.
- **First focus:** once the Windows stream and the desktop app exist (M7, M8), desktop work with coding and gaming must
  both become excellent in the same milestone (M9).

## 6. Requirements

Each requirement is a statement a test or a demonstration can check, and belongs to exactly one epic (the bold line above it). The owner approved the numbers in the success measures and requirements with this spec on 2026-11-24.

### M1 Foundations

**Architecture decisions**

- **R1** The process model (system service, per-session agent, client, self-hosted server, shared portable core) and the module boundaries are recorded, with one named interface per platform seam: capture, video encode, video decode, presentation, audio capture, audio playback, input injection, virtual display, virtual gamepad, pseudo-terminal.
- **R2** The build order is recorded: which projects are portable and built first on Linux and which are Windows-bound; Windows-bound code is reached only through the platform seams, and every seam has a simulated implementation used by tests.
- **R3** How doment consumes darkraise-framework is decided and recorded (package or project reference, version pinning), with the rule that reusable, product-neutral pieces are contributed to the framework and product logic stays in doment.
- **R4** A third-party exception register lists every component that is not doment code, darkraise-framework, .NET, an operating-system API or a GPU-driver interface, each with its reason, licence, the interface it sits behind and its replacement plan; the build fails on a dependency that is not listed.

**Repository, build and NativeAOT**

- **R5** One solution builds the portable core, the server, the Linux agent and the command-line client; each publishes with NativeAOT for linux-x64 with zero trim and AOT warnings.
- **R6** The portable core references no Windows-only API, enforced by compiling it for both linux-x64 and win-x64 on Linux.
- **R7** Formatting and analyzer rules match darkraise-framework conventions and are enforced by the build.

**CI for pushed branches**

- **R8** Every pushed branch is built and tested on CI on Linux, including the NativeAOT publish.

**Gates declared**

- **R9** docs/dforge/gates.md declares the gates every later milestone runs: build, tests, NativeAOT publish and the exception-register check, and marks the latency and sharpness measurements that need Windows hardware as applying from M7.

**Network test bench**

- **R10** A scripted test bench runs two or more doment processes on isolated networks with configurable delay, jitter, loss, rate limit and NAT behaviour, gives repeatable results, and runs in CI on this Linux machine.

**Walking skeleton**

- **R11** A Linux agent and the command-line client connect over UDP through the test bench, exchange control messages, and carry a synthetic frame stream end to end.

**Measurement harness**

- **R12** Every frame carries timestamps for each stage it passes (capture, encode, send, receive, decode, present); the harness reports p50 and p99 per stage and end to end without a camera, and writes a machine-readable report.
- **R13** The harness measures frame delivery (late, dropped and duplicated frames) over a timed run.


### M2 Secure sessions and media transport

**Device identity, pairing and encrypted sessions**

- **R14** Each device generates a key pair on first run; the private key is kept in operating-system key storage where the platform has one, otherwise in a file only the service account can read, and never leaves the device.
- **R15** Pairing mutually authenticates both devices with an out-of-band confirmation, and a short code cannot be guessed offline from a captured exchange.
- **R16** Every channel is end-to-end authenticated and encrypted with keys derived from the pinned device keys, using only .NET and operating-system cryptography.
- **R17** The host keeps a list of paired devices; revoking one ends its live sessions within 5 seconds.
- **R18** One policy decision point authorises every channel (video, input, audio, clipboard, files, terminal, power); a test enumerates all entry points against it.

**Media transport**

- **R19** Media travels over a first-party UDP protocol with packets of at most 1200 bytes, paced across the frame interval.
- **R20** Loss is recovered with forward error correction plus reference-frame invalidation or intra refresh requests, without full-keyframe storms; verified at 1% and 5% random loss and at burst loss.
- **R21** Congestion control changes the bitrate within 1 second of a capacity change, and a fixed-bitrate mode exists.
- **R22** Video is never buffered: under congestion, end-to-end latency stays bounded and frames are dropped instead.
- **R23** A reliable ordered control channel shares the session, and the session still works over TCP when UDP is blocked.
- **R24** Packets carry DSCP marking where the operating system permits it.

**Synthetic and recorded media sources**

- **R25** A synthetic frame source and a recorded-bitstream replay source produce the frame sizes and timing of 1440p 120 Hz desktop and game content, so transport is tested with no capture or encoding hardware.
- **R26** A verifying sink checks the integrity, order and timing of every received frame.

**Encoder control logic**

- **R27** Codec, profile and chroma format are negotiated from host and client capability sets, covering NVIDIA, Intel, AMD and software-only hosts and Intel, AMD and NVIDIA clients.
- **R28** Bitrate, frame-rate, resolution, keyframe and reference-invalidation requests flow from transport feedback to the encoder interface, verified against a simulated encoder.

**Statistics and diagnostics**

- **R29** Per-stage latency, frame rate, bitrate, loss, codec, chroma format and connection path are collected and exposed in machine-readable form.
- **R30** Every doment process writes structured logs and can export a diagnostic bundle.


### M3 Internet connectivity and self-hosted server

**Self-hosted server**

- **R31** The server is a single NativeAOT binary and a container image for linux-x64 that starts with one command and a configuration file; setup endpoints are disabled after first run.
- **R32** Devices enrol with the owner's server using a single-use expiring token, and the device list is the same on every client of the owner.
- **R33** The server never holds a device private key or any stream or terminal plaintext, and a compromised server cannot authorise a new device without confirmation from an already-trusted device.

**Direct-first NAT traversal**

- **R34** Connection follows a ladder (LAN, direct IPv6, mapped port through UPnP or PCP, UDP hole punching, relay), chosen automatically; a relayed session keeps trying to upgrade to a direct path.
- **R35** A direct path is achieved in every NAT test-bench case where one is theoretically possible: full cone, port restricted, symmetric on one side, double NAT, carrier-grade NAT.
- **R36** A device can be reached by IP address or host name with no server at all, including over Tailscale or WireGuard.

**Encrypted relay**

- **R37** The relay forwards end-to-end encrypted packets over UDP, with a TCP fallback on port 443.
- **R38** Every session reports its active path and the latency that path adds; the relay never activates without that report, and a setting forbids relaying.
- **R39** A relay health check exercises the real relay path, not a LAN shortcut.

**WAN adaptation**

- **R40** Congestion control holds the latency bound without collapse on emulated profiles: 20, 50 and 100 ms round trip, 1 to 5% loss, Wi-Fi jitter and cellular.
- **R41** A session survives the client changing network and resumes within 3 seconds.

**Low-latency audio codec**

- **R42** Audio is coded with a first-party low-latency codec (the CELT layer of Opus) at 5 to 10 ms frames and 64 to 256 kbit/s stereo with loss concealment; uncompressed audio remains an option on the LAN.
- **R43** The decoder passes the RFC 6716 test vectors for the modes it implements, and the codec lives where other darkraise apps can reuse it.

**Device presence**

- **R44** The device directory reports each device as online, asleep or off, or unreachable, with the last time it was seen, through the server and through LAN discovery.


### M4 Remote terminals on Linux

**Linux headless agent**

- **R45** The agent is a single NativeAOT binary for linux-x64 and linux-arm64 with a systemd unit, and connects outbound only.
- **R46** The agent serves as a relay node for its network when the owner enables it.

**Host terminal service**

- **R47** Terminal sessions live in the host process that owns the pseudo-terminal; closing, crashing or updating any client leaves the shell and its descendants running.
- **R48** Ending a session kills every descendant process, and detaching never does.
- **R49** Shells run as the configured user and never silently with higher privilege; a privileged session needs an explicit action on the host and is labelled.
- **R50** Shell profiles define the command, arguments, environment and working directory, with defaults for the host's installed shells.

**Terminal channel and persistence**

- **R51** Reattaching shows the current screen from a host-side snapshot in one round trip, loads scrollback on demand, and keeps the session's identifier.
- **R52** A session stays listed for as long as its host process lives; clients reconnect without user action after a 24-hour outage and after host sleep and wake.
- **R53** The terminal channel works over every connection path including the relay, and without starting video.

**Terminal state model**

- **R54** A portable terminal model parses the VT and xterm behaviour the conformance list needs (24-bit colour, mouse modes, bracketed paste, alternate screen, wide and combining Unicode, synchronized output) and holds the screen and scrollback, with no dependence on any UI.
- **R55** Output split in the middle of a UTF-8 character or an escape sequence is handled correctly, and the parser is fuzzed.
- **R56** The model passes a conformance suite built from bash, vim, tmux and Claude Code output.

**Command-line terminal client**

- **R57** A command-line client lists sessions across devices, attaches to one from any terminal with keys, mouse and resize passed through unchanged, and starts a new session on a chosen host, directory and profile.

**Session inventory and states**

- **R58** The inventory lists every terminal on every device with the states working, needs input, needs approval, idle, done, failed and host offline.
- **R59** Each entry carries host, working directory, git branch, title, last activity and the pending question.
- **R60** A named workspace records a set of sessions across hosts and reopens them in one action.
- **R61** The inventory is available in machine-readable form through the command-line client and to graphical clients through the same interface.

**Coding agent awareness**

- **R62** Claude Code session state comes from its hook events within 3 seconds; other tools use output heuristics labelled as lower confidence.
- **R63** A pending permission request can be approved or denied without opening the terminal, and stays pending across client disconnects.
- **R64** An attention event names the session, the host and what is asked; it is withdrawn when handled on another device and suppressed while the user is active in that session.
- **R65** An optional git worktree per session is off by default, and deleting a session never discards uncommitted changes.


### M5 Wake and power

**Wake-on-LAN**

- **R66** A client on the same LAN wakes a device directly; the device's MAC address and subnet are recorded automatically at pairing, with a manual override.
- **R67** From outside the LAN, any online doment host, a Linux agent or the self-hosted server on the target's network segment sends the wake packet on an authenticated request, with ordered fallback between helpers.
- **R68** Wake is observable: 'no helper available', 'packet sent by X', 'device came online after N seconds', and a timeout with a diagnosis.
- **R69** A Linux host self-check reports wake readiness (the network adapter's wake setting, wired or Wi-Fi) and what to change.

**Power actions and wake-then-connect**

- **R70** Sleep, restart and shut down are client actions with confirmation on Linux hosts, and a restart reconnects automatically.
- **R71** Connecting to a sleeping or powered-off device wakes it and connects when it is up, as one action in the client logic.


### M6 Portable media and session logic

**Video bitstream parsers**

- **R72** First-party parsers extract from H.264, HEVC and AV1 streams everything hardware decode needs (parameter sets, slice or frame headers, reference lists), verified on conformance streams.
- **R73** Every parser is fuzzed and rejects malformed input without crashing or over-reading.

**Frame pacing logic**

- **R74** The pacing logic offers a lowest-latency mode and a smoothest mode and handles a display refresh different from the stream rate, verified against simulated clocks and refresh timings.

**Input protocol and key mapping**

- **R75** Keys travel as scancodes with a Unicode text path, and modifier state is tracked so that no modifier stays pressed after focus loss or disconnect.
- **R76** The key mapping between client and host platforms is a documented, user-editable table with test data for US, US-International, German, French AZERTY, Vietnamese Telex and Japanese layouts.
- **R77** The protocol carries absolute and relative mouse movement, pen with pressure and tilt, touch, and up to 4 controllers with rumble returned and plugging during a session.

**Clipboard and file transfer protocol**

- **R78** The clipboard channel carries text, images and file lists both ways as a per-device permission that can be turned off.
- **R79** File transfer resumes after interruption, writes only to the chosen folder, never opens or runs a file, and needs confirmation on the receiving side.
- **R80** Path traversal, reserved names and link tricks are rejected in both directions by an automated suite that covers Windows and Linux path rules.

**Display and cursor signalling**

- **R81** The protocol carries cursor shape and position as metadata, the host monitor list, and the negotiation of resolution, refresh rate, scale and HDR metadata, including changes during a session.


### M7 Windows host and stream

**Windows build and CI**

- **R82** The Windows host service, agent and client publish with NativeAOT for win-x64 with zero trim and AOT warnings, and a Windows CI runner builds and tests every pushed branch.

**Host service and session agent**

- **R83** A service running as SYSTEM starts at boot, launches the agent into the active console session, follows session changes (logon, logoff, fast user switching) and restarts the agent after a crash.
- **R84** Video and input continue without user action across the lock screen, UAC consent and credential prompts and the logon screen, and the client can send Ctrl+Alt+Del.
- **R85** The installed service has quoted paths and access-control-hardened program and data directories, and no installer or driver step adds a certificate to any trust store.
- **R86** When a Remote Desktop session takes the console, the client shows a 'host in use by another session' state instead of a black screen.

**Screen capture**

- **R87** Capture uses Desktop Duplication, follows the input desktop and recovers from mode changes, fullscreen switches and device loss without dropping the session.
- **R88** On hybrid-GPU laptops capture runs on the adapter that owns the display and the encoder GPU is chosen deliberately; validated on one integrated-plus-discrete laptop.
- **R89** The cursor is captured as shape and position and drawn by the client; a composited-cursor option exists.
- **R90** A static desktop uses under 200 kbit/s and the encoded frame rate follows the content; no bitrate spike when motion resumes.

**Hardware and fallback encoders**

- **R91** NVIDIA hosts encode through the NVENC driver interface with first-party bindings: H.264, HEVC and AV1 where the GPU supports them, in low-latency configuration with reference-frame invalidation.
- **R92** Intel hosts encode through the Quick Sync (oneVPL) driver interface with first-party bindings, with the same codec and low-latency coverage.
- **R93** Hosts with any other hardware encoder (including AMD) and hosts with no GPU encode through Media Foundation, with the software path's resolution and frame-rate ceiling measured and stated.
- **R94** Per-frame size stays within 10% of the target so bursts do not cause loss, and bitrate, frame rate and resolution change during a session without reconnecting.

**Win32UI video surface control**

- **R95** A control hosts a Direct3D 11 flip-model swap chain inside a Win32UI window, with framework overlays drawn above it and correct behaviour on resize, DPI change and fullscreen; contributed to darkraise-framework.

**Client decode and presentation**

- **R96** The client decodes H.264, HEVC and AV1 through Direct3D 11 video decode on Intel, AMD and NVIDIA GPUs, using the first-party parsers.
- **R97** Presentation uses a waitable flip-model swap chain that queues at most one frame and is aware of tearing and variable refresh, driven by the pacing logic.
- **R98** Windowed and borderless-fullscreen views offer 1:1, integer and fit scaling, with 1:1 or integer chosen by default when sizes allow.

**Audio on Windows**

- **R99** Host playback is captured through WASAPI loopback at 48 kHz stereo without changing the host's default audio device.
- **R100** End-to-end audio latency on the LAN is at most 40 ms and audio stays within 30 ms of the video.
- **R101** The owner can choose whether the host's speakers stay audible during a session; where muting is impossible without a driver the client says so.

**Keyboard and mouse input**

- **R102** Keys are injected on the host independent of its layout, absolute mouse positioning is used for desktop work, and input reaches elevated windows.
- **R103** While the client has focus it captures operating-system shortcuts (Win, Alt+Tab, Alt+F4 and similar), with a toggle and a documented release chord.

**Windows terminal host**

- **R104** The Windows host service owns terminal sessions through the pseudo-console with the same persistence behaviour as the Linux agent, and every session's process tree is in a job object.
- **R105** Shells run in the interactive user's token, not as SYSTEM; an elevated session needs an explicit action on the host and is labelled as elevated.
- **R106** Profiles cover PowerShell, cmd and a WSL distribution, and WSL stays alive while one of its sessions exists.
- **R107** Pseudo-console teardown and resize behave correctly on supported Windows builds, proven by the conformance suite run against PowerShell, cmd, WSL, vim and Claude Code.

**Windows wake readiness and power**

- **R108** A Windows host self-check reports wake readiness (Fast Startup, the network adapter's magic-packet setting, wired or Wi-Fi, supported sleep states) and what to change.
- **R109** Sleep, hibernate, restart and shut down work on Windows hosts; after a wake or boot the host is reachable at the logon screen before anyone signs in, and the BitLocker pre-boot PIN case is detected and stated as a limit.


### M8 Windows desktop app

**Client shell**

- **R110** The client lists paired devices with their presence, discovers hosts on the LAN, adds a host by address, and connects to a paired device in at most 3 actions.
- **R111** After a network interruption the session resumes automatically within 3 seconds of the network returning, with no stuck keys.
- **R112** An in-session toolbar switches monitor and mode and disconnects, and a live overlay shows the collected statistics and the active connection path with its added latency.

**Host settings and pairing UI**

- **R113** The host shows the pairing confirmation, the paired-device list with revoke, per-device permissions and its settings.

**Terminal emulator control**

- **R114** A Win32UI terminal control renders the terminal state model, with native scrollback, selection, copy and paste, search, font and zoom, and passes Shift+Enter, Escape and Ctrl+Space to the application unchanged; contributed to darkraise-framework.
- **R115** Local processing from keystroke to drawn glyph takes at most 5 ms, and heavy output does not block the user interface.

**Terminal manager dashboard**

- **R116** A dashboard shows the session inventory with its states and entry details, opens terminals from several hosts in tabs, splits or a grid, reopens workspaces, and starts new sessions.
- **R117** Pending permission requests are approved or denied from the dashboard, and attention events appear as Windows notifications that open the session.

**Text and pixels together**

- **R118** From a terminal the user opens the pixel view of the same host in one action, and returns, on the same authenticated connection.

**Wake and power UI**

- **R119** Wake, sleep, hibernate, restart and shut down are available per device with confirmation, wake progress is shown step by step, and Connect on a sleeping device wakes it and connects.


### M9 Desktop and gaming excellence

**Text-sharp and colour-accurate video**

- **R120** The harness measures text sharpness on a test image of coloured 8 to 12 pixel text.
- **R121** A desktop mode streams full-chroma (4:4:4) video through hardware HEVC 4:4:4 where the host encoder and client decoder support it.
- **R122** Clients without hardware 4:4:4 decode (AMD) reach the same sharpness measure through an alternative technique chosen in this epic.
- **R123** SDR colour is reproduced with a colour difference of at most 2 (Delta E 2000) on a test chart, with range and matrix signalled correctly; 10-bit is used where both ends support it.
- **R124** When the picture stops changing it converges to visually lossless within 0.5 seconds.

**Virtual display and resolution matching**

- **R125** A virtual display is created per session at the client's resolution, refresh rate and scale through the named driver exception, removed on disconnect, and the physical layout is restored after a crash or reboot mid-session.
- **R126** A headless host streams with no monitor and no dummy plug.
- **R127** The user picks which host monitor to view, switches during a session, and can show several host monitors in separate client windows.
- **R128** Resizing the client window renegotiates the stream resolution, and host scaling follows the client's DPI.
- **R129** The driver sits behind doment's virtual-display interface, and doment still streams the physical monitor when the driver is absent.

**Keyboard fidelity**

- **R130** Dead keys, AltGr and input-method composition pass a test suite on Windows with US, US-International, German, French AZERTY, Vietnamese Telex and Japanese layouts.

**Clipboard and file transfer**

- **R131** Text, images and files copy both ways through the Windows clipboard, and files transfer by drag-and-drop or a picker, using the protocol's permission and confirmation rules.

**Pen and touch**

- **R132** Pen input from the client reaches the host with pressure and tilt (pressure works in Photoshop), and touch gestures reach the host as touch.

**Game controllers**

- **R133** Controllers connected to the client appear on the host as Xbox controllers visible to XInput games through the named driver exception, with rumble returned to the client; Xbox and PlayStation controller types map correctly.
- **R134** The driver sits behind doment's virtual-gamepad interface, and doment runs without it (no controllers) when it is absent.

**Game mouse and keyboard**

- **R135** The mouse switches to relative movement when the host application hides or locks the pointer, and back, with no added acceleration.
- **R136** A game that reads Raw Input only receives keyboard and mouse input correctly.

**HDR**

- **R137** An HDR session is negotiated per connection in 10-bit HEVC or AV1; SDR clients receive correct tone mapping from an HDR host; the host's HDR state is restored on disconnect and never changes while no session runs.

**Frame pacing and game performance**

- **R138** With a stream active the host game's frame rate is at least 95% of its rate without doment, and an idle doment costs under 2%.
- **R139** Capture keeps working with exclusive-fullscreen games, a variable-refresh host display and frame generation, and the streamed frame rate matches the host's up to 120.
- **R140** Presentation on a variable-refresh client is even, and a 60 Hz stream on a 120 or 144 Hz display paces evenly.
- **R141** Desktop, Game and Balanced presets set chroma, bitrate and pacing, selectable per session and switchable live.


### M10 Hardening

**Security review**

- **R142** A threat model is written, and an independent review covers pairing, session cryptography, the service privilege boundary, the server and file transfer; every finding is fixed or ruled by the owner.
- **R143** Every parser of network input has completed a full fuzzing campaign (transport, control, video bitstream, terminal escape sequences), and the file-transfer path suite runs on every build.

**Performance budget**

- **R144** Success measures SM1 to SM3 are met on the reference hardware list (NVIDIA and Intel hosts; Intel, AMD and NVIDIA clients); an 8-hour session shows no latency drift, no memory growth and no garbage-collection allocations on the steady-state media path.

**Reliability matrix**

- **R145** A reconnect matrix passes: network loss of 10 seconds, 10 minutes and overnight; host sleep and wake; client sleep and wake; service restart; with no stuck keys, no lost terminal sessions and the display layout restored.

**Errors and observability**

- **R146** Every failure the user can meet (black screen, each rung of the connection ladder, encoder or driver absence) states its cause and the next step.

**Documentation**

- **R147** A user guide, a server self-hosting guide, the protocol description and architecture notes are complete.


### M11 Release 1.0

**Installers and update**

- **R148** Installers exist for the Windows host and client and packages for the server and Linux agent; updating keeps configuration and pairings, and one action rolls back to the previous version.

**Versioning, changelog and runbook**

- **R149** The protocol is versioned so that a host and a client one minor version apart interoperate; a changelog and a runbook for the server exist.

**Daily-driver acceptance**

- **R150** The owner uses doment as the only remote tool for 14 consecutive days (desktop work, coding terminals, gaming, wake); every blocker found is fixed or ruled.


### M12 Unattended support

**Enrolment of supported PCs**

- **R151** A supported PC's host install is bound to the owner's server by a single-use expiring token carried in a signed configuration blob; the host refuses a tampered or missing blob.
- **R152** Only the owner's paired controller devices can open an unattended session, with an optional second confirmation on the controller.

**Permissions, consent and audit**

- **R153** Capabilities (view, control, clipboard, files, terminal, power, elevation) are granted per device and revoked in effect within 5 seconds for live sessions.
- **R154** In attended mode the local user sees who is asking and which capabilities are requested, and accepts or refuses; unattended mode is switched on per device by a local administrator.
- **R155** A persistent on-screen indicator and a one-click 'end session' are shown to the local user during every session.
- **R156** The host keeps a local audit log of connections, capabilities used, transferred file names and hashes, and elevation, readable by the owner.

**Support session tools**

- **R157** Reboot and reconnect works, including into safe mode with networking.
- **R158** On a host with several signed-in users the technician chooses the session (console or a Remote Desktop session) and sees which one is attached.
- **R159** Privacy mode blanks the local screen and blocks local input without an unsigned driver, and says clearly where it is unsupported.
- **R160** Supported devices can be grouped, tagged, annotated and searched in the device list.

**Code signing**

- **R161** Every binary and installer is signed with a key held in a hardware token or signing service separate from the build machine; a rotation procedure is written and rehearsed.


### M13 Android client

**Mobile UI stack decision**

- **R162** The UI stack for mobile clients is decided and recorded against the NativeAOT and third-party rules, with any exception named.

**Android terminals and control**

- **R163** The Android client shows the dashboard, attaches to terminals with touch keyboard helpers, approves or denies requests and wakes devices.
- **R164** Notifications reach the phone without a doment-run cloud service.

**Android stream viewer**

- **R165** The Android client views a stream with hardware decode, touch-to-mouse input and controllers.


### M14 Linux client and Steam Deck

**Linux desktop client**

- **R166** The UI stack for the Linux client is decided and recorded against the NativeAOT and third-party rules.
- **R167** The Linux client decodes in hardware (VA-API or Vulkan Video), presents with low latency and captures input on Wayland and X11, with the terminal dashboard included.

**Steam Deck mode**

- **R168** On a Steam Deck the client is usable with the controller alone and passes the built-in controls, including gyro and trackpads.


### M15 Apple clients

**macOS client**

- **R169** The macOS client decodes with VideoToolbox, presents with Metal, maps Command to Control by the editable key table, and scales to Retina at an integer factor.

**iOS and iPadOS client**

- **R170** The iOS and iPadOS client offers the stream viewer, terminals, approvals and wake, and sends Apple Pencil pressure as pen input.


### M16 More host platforms

**macOS host**

- **R171** A Mac is a host: ScreenCaptureKit capture, VideoToolbox encode, input injection with the permission flows explained in the app, and terminals.

**Linux desktop host**

- **R172** A Linux desktop is a host: PipeWire portal or KMS capture, VA-API or NVENC encode, and input injection, on Wayland and X11.


### M17 First-party drivers

**First-party virtual display driver**

- **R173** A doment virtual display driver replaces the exception, is attestation-signed with the owner's certificate, and doment warns at least 60 days before a signature expires.

**First-party virtual gamepad driver**

- **R174** A doment virtual gamepad driver replaces the exception and adds PlayStation controller emulation with gyro, touchpad and haptics.

**Virtual audio devices**

- **R175** A virtual audio driver provides microphone passthrough from client to host and silent-host streaming.

## 7. Epics

An epic is one spec, one or more plans, and can be demonstrated on its own.

| Milestone | Epic | Requirements |
|---|---|---|
| M1 | Architecture decisions | R1-R4 |
| M1 | Repository, build and NativeAOT | R5-R7 |
| M1 | CI for pushed branches | R8 |
| M1 | Gates declared | R9 |
| M1 | Network test bench | R10 |
| M1 | Walking skeleton | R11 |
| M1 | Measurement harness | R12-R13 |
| M2 | Device identity, pairing and encrypted sessions | R14-R18 |
| M2 | Media transport | R19-R24 |
| M2 | Synthetic and recorded media sources | R25-R26 |
| M2 | Encoder control logic | R27-R28 |
| M2 | Statistics and diagnostics | R29-R30 |
| M3 | Self-hosted server | R31-R33 |
| M3 | Direct-first NAT traversal | R34-R36 |
| M3 | Encrypted relay | R37-R39 |
| M3 | WAN adaptation | R40-R41 |
| M3 | Low-latency audio codec | R42-R43 |
| M3 | Device presence | R44 |
| M4 | Linux headless agent | R45-R46 |
| M4 | Host terminal service | R47-R50 |
| M4 | Terminal channel and persistence | R51-R53 |
| M4 | Terminal state model | R54-R56 |
| M4 | Command-line terminal client | R57 |
| M4 | Session inventory and states | R58-R61 |
| M4 | Coding agent awareness | R62-R65 |
| M5 | Wake-on-LAN | R66-R69 |
| M5 | Power actions and wake-then-connect | R70-R71 |
| M6 | Video bitstream parsers | R72-R73 |
| M6 | Frame pacing logic | R74 |
| M6 | Input protocol and key mapping | R75-R77 |
| M6 | Clipboard and file transfer protocol | R78-R80 |
| M6 | Display and cursor signalling | R81 |
| M7 | Windows build and CI | R82 |
| M7 | Host service and session agent | R83-R86 |
| M7 | Screen capture | R87-R90 |
| M7 | Hardware and fallback encoders | R91-R94 |
| M7 | Win32UI video surface control | R95 |
| M7 | Client decode and presentation | R96-R98 |
| M7 | Audio on Windows | R99-R101 |
| M7 | Keyboard and mouse input | R102-R103 |
| M7 | Windows terminal host | R104-R107 |
| M7 | Windows wake readiness and power | R108-R109 |
| M8 | Client shell | R110-R112 |
| M8 | Host settings and pairing UI | R113 |
| M8 | Terminal emulator control | R114-R115 |
| M8 | Terminal manager dashboard | R116-R117 |
| M8 | Text and pixels together | R118 |
| M8 | Wake and power UI | R119 |
| M9 | Text-sharp and colour-accurate video | R120-R124 |
| M9 | Virtual display and resolution matching | R125-R129 |
| M9 | Keyboard fidelity | R130 |
| M9 | Clipboard and file transfer | R131 |
| M9 | Pen and touch | R132 |
| M9 | Game controllers | R133-R134 |
| M9 | Game mouse and keyboard | R135-R136 |
| M9 | HDR | R137 |
| M9 | Frame pacing and game performance | R138-R141 |
| M10 | Security review | R142-R143 |
| M10 | Performance budget | R144 |
| M10 | Reliability matrix | R145 |
| M10 | Errors and observability | R146 |
| M10 | Documentation | R147 |
| M11 | Installers and update | R148 |
| M11 | Versioning, changelog and runbook | R149 |
| M11 | Daily-driver acceptance | R150 |
| M12 | Enrolment of supported PCs | R151-R152 |
| M12 | Permissions, consent and audit | R153-R156 |
| M12 | Support session tools | R157-R160 |
| M12 | Code signing | R161 |
| M13 | Mobile UI stack decision | R162 |
| M13 | Android terminals and control | R163-R164 |
| M13 | Android stream viewer | R165 |
| M14 | Linux desktop client | R166-R167 |
| M14 | Steam Deck mode | R168 |
| M15 | macOS client | R169 |
| M15 | iOS and iPadOS client | R170 |
| M16 | macOS host | R171 |
| M16 | Linux desktop host | R172 |
| M17 | First-party virtual display driver | R173 |
| M17 | First-party virtual gamepad driver | R174 |
| M17 | Virtual audio devices | R175 |

## 8. Milestones

Milestones M0 to M11 make release 1.0. M1 to M6 are built and verified on Linux; Windows-bound work starts at M7. Later milestones are 1.x releases in the order below.

| M | Name | Release | Exit criteria |
|---|---|---|---|
| M0 | Discovery | - | brief, users, non-goals and requirement list approved; competitor research recorded |
| M1 | Foundations | 1.0 | architecture and build order recorded; the portable core, server, Linux agent and command-line client publish with NativeAOT on Linux; a pushed branch builds and tests on CI; gates.md declared; the walking skeleton connects two Linux processes and the measurement harness reports its latency |
| M2 | Secure sessions and media transport | 1.0 | every M2 epic resolved; a synthetic stream with the frame sizes and timing of 1440p at 120 Hz crosses the test bench within the transport share of the latency budget at 0%, 1% and 5% loss; pairing, revocation and policy tests pass; gates green |
| M3 | Internet connectivity and self-hosted server | 1.0 | every M3 epic resolved; on the test bench two devices reach each other through the server on a direct path in every NAT case where one is possible and through the relay otherwise, with the active path reported; WAN adaptation profiles pass; gates green |
| M4 | Remote terminals on Linux | 1.0 | every M4 epic resolved; terminal sessions on a Linux machine survive 24 hours with no client attached and reattach within 1 second from the command-line client (SM6); session states are correct for plain shells and Claude Code sessions; the terminal conformance suite passes; gates green |
| M5 | Wake and power | 1.0 | every M5 epic resolved; a machine on the home network is woken from sleep and from soft-off by a request arriving from outside that network through the server or a Linux agent, with each step reported; gates green |
| M6 | Portable media and session logic | 1.0 | every M6 epic resolved; each parser passes its conformance streams and a fuzz run; the file-transfer path suite and the input mapping tests pass; all on Linux; gates green |
| M7 | Windows host and stream | 1.0 | every M7 epic resolved; a 1440p 120 Hz session on a wired LAN meets success measure SM1 from an NVIDIA host and from an Intel host; the stream and input continue across the lock screen, a UAC prompt and the logon screen; Windows CI green |
| M8 | Windows desktop app | 1.0 | every M8 epic resolved; from the app the owner pairs, connects to a device in at most 3 actions, works in terminals from the dashboard, and wakes and connects to a sleeping PC in one action (SM5, SM6 on Windows); gates green |
| M9 | Desktop and gaming excellence | 1.0 | every M9 epic resolved; sharpness measure SM4 passes on Intel, AMD and NVIDIA clients; the virtual display matches the laptop panel at 1440p 120 Hz; gaming measure SM7 passes; gates green |
| M10 | Hardening | 1.0 | security review complete with every finding fixed or ruled by the owner; performance budget met on the reference hardware; reliability matrix passes; documentation complete |
| M11 | Release 1.0 | 1.0 | installers and update with rollback work on the owner's machines; the server runbook exists; the 14-day daily-driver acceptance (SM9) is signed off |
| M12 | Unattended support | 1.1 | every M12 epic resolved; a PC outside the owner's home is enrolled with a token, reached unattended through the login screen and a UAC prompt, rebooted and reconnected; the permission, consent and audit checks pass; all binaries are signed |
| M13 | Android client | 1.2 | every M13 epic resolved; from an Android phone the owner sees the dashboard, answers an approval, wakes a PC and views a stream |
| M14 | Linux client and Steam Deck | 1.3 | every M14 epic resolved; a Linux desktop and a Steam Deck stream from the PC within the latency budget set in the epic |
| M15 | Apple clients | 1.4 | every M15 epic resolved; a MacBook and an iPhone or iPad stream from the PC and show the dashboard |
| M16 | More host platforms | 1.5 | every M16 epic resolved; a Mac and a Linux desktop are streamed and controlled from a Windows client |
| M17 | First-party drivers | 1.6 | every M17 epic resolved; both third-party driver exceptions are removed from the exception register |

## 9. Competitor mistakes and how doment avoids them

Each row is a documented failure from the research and the epic that answers it.

| Mistake seen in other products | Where | doment's answer (epic) |
|---|---|---|
| Black screen or dead input at UAC, lock and login screens, added late as a patch | Sunshine, AnyDesk portable, RustDesk | The Windows host is a SYSTEM service plus session agent from its first milestone (Host service and session agent) |
| Cloud account required; outages and logins block local use | Parsec, TeamViewer, AnyDesk | Self-hosted server; LAN and direct address work with no server (Self-hosted server, Direct-first NAT traversal) |
| No NAT traversal; port forwarding or VPN needed | Sunshine and Moonlight | Connection ladder that tries direct paths first (Direct-first NAT traversal) |
| Relay used silently, sessions feel slow with no explanation | RustDesk, TeamViewer | Active path and its added latency always shown (Encrypted relay) |
| Text blurred by 4:2:0 colour; 4:4:4 paywalled or experimental | Parsec, Sunshine | Full-chroma desktop mode, including clients without hardware 4:4:4 decode (Text-sharp and colour-accurate video) |
| Headless hosts need a dummy plug; virtual display drivers conflict or their signatures expire | all | Per-session virtual display behind an interface, layout restored after a crash (Virtual display and resolution matching), expiry warning (First-party virtual display driver) |
| Test certificate added to the trusted root store to load a driver | RustDesk | No trust anchor is ever added (Host service and session agent) |
| Gamepad support depends on an abandoned or paid driver | Sunshine, Apollo | Driver behind an interface now, first-party driver later (Game controllers, First-party virtual gamepad driver) |
| Stutter with no way to find the cause | all | Per-stage timestamps from M1 and a latency gate on real hardware from M7 (Measurement harness, Statistics and diagnostics) |
| Keyframe storms and bitrate overshoot after packet loss | GameStream lineage | Error correction with reference invalidation, bounded frame size (Media transport, Hardware and fallback encoders) |
| Wrong keys on non-US layouts, stuck modifiers | Moonlight, RustDesk | Scancode plus Unicode paths and a layout test suite (Keyboard and mouse input, Keyboard fidelity) |
| Weak pairing; client-reported identity; several access paths with different checks | Moonlight PIN, RustDesk, TeamViewer 2026 | Pinned device keys, guess-resistant pairing, one policy decision point (Device identity, pairing and encrypted sessions) |
| Technician's client ran files pushed by the remote side | ScreenConnect 2026 | Transfers never open or run, receiver confirms, path suite (Clipboard and file transfer protocol) |
| Agent configuration outside the signed part of the installer | ScreenConnect 2025 | Enrolment token inside a signed blob (Enrolment of supported PCs) |
| Signing keys stolen with the build systems | AnyDesk 2024 | Key in a hardware token or signing service apart from the build machine (Code signing) |
| Setup endpoint reachable after setup | ScreenConnect 2024 | Setup endpoints disabled after first run (Self-hosted server) |
| Terminal sessions vanish when the viewer disconnects; Windows shells die with the connection | Claude Code Remote Control, SSH on Windows | The host service owns the pseudo-console and the session list (Host terminal service, Terminal channel and persistence) |
| Agent managers are macOS-first, single-vendor, and get abandoned | Crystal, Vibe Kanban, Omnara | Linux and Windows hosts, plain shells and any agent, self-hosted (Session inventory and states, Coding agent awareness) |
| Notifications without context | several agent managers | Notification names the session, the host and the question (Coding agent awareness) |
| Wake-on-LAN fails silently; no helper on the LAN; unknown MAC address | TeamViewer, RustDesk, AnyDesk | Helper fallback, recorded MAC, every step reported, readiness self-check (Wake-on-LAN) |
| Updates break working setups with no way back | Sunshine and its forks | Update with one-action rollback, versioned protocol (Installers and update, Versioning, changelog and runbook) |

## 10. Architecture direction

Known so far; each open decision is settled inside its epic through dforge:selecting-approaches.

- **Processes.** A host service (SYSTEM) that owns terminal sessions and supervises a per-session agent; the agent
  captures, encodes, injects input and captures audio in the console session; a Win32UI client; a self-hosted server
  (directory, connection brokering, relay, wake helper). A shared portable core (net10.0) holds the protocol,
  cryptography, transport, error correction, congestion control, terminal state model and bitstream parsers.
- **Platform seams.** Capture, encode, decode, presentation, audio, input, virtual display, virtual gamepad and
  pseudo-terminal are interfaces in the core with a Windows implementation first, so later platforms add implementations
  and do not change the core.
- **Capture and encode.** Desktop Duplication in the agent, following the input desktop. Encoders are called through the
  vendor driver interfaces with first-party C# bindings; Media Foundation is the fallback.
- **Decode and present.** Direct3D 11 video decode with first-party bitstream parsing; a waitable flip-model swap chain
  hosted in a new Win32UI control.
- **Transport.** A first-party UDP protocol (no WebRTC, no MsQuic): paced packets, forward error correction,
  reference-frame invalidation, delay-based congestion control, and a reliable control channel with a TCP fallback.
- **Security.** Device key pairs pinned at pairing; a handshake built from .NET and operating-system cryptography; the
  server brokers and relays but cannot read or authorise.
- **Build order.** The portable core, server, Linux agent and command-line client are built and verified on Linux
  first, against simulated implementations of every platform seam. The Windows implementations and the Win32UI app are
  added from M7 without changing the core.
- **Terminals.** The host service owns the pseudo-console and keeps a headless terminal state for snapshots; clients
  render with a new Win32UI terminal control. Terminals are text, not pixels.
- **Real-time discipline.** Dedicated threads with multimedia scheduling, no allocations on the steady-state media path,
  high-resolution timers.
- **Framework contributions.** The video surface control, the terminal control and the audio codec go into
  darkraise-framework. The framework's own media programme is software-only and schedules Opus for its M11 and
  M12; doment needs a low-latency audio codec sooner, so the two plans must be reconciled in that epic.

Open decisions: the 4:4:4 technique for AMD clients; whether Direct3D 12 video encode is added as a vendor-neutral path
beside the NVENC and Quick Sync interfaces the requirements commit to; how doment references the framework; the UI stack for mobile, Linux and macOS clients (Win32UI is Windows-only).

## 11. Third-party exception register (initial)

| # | Component | Used for | Reason | Behind | Replacement |
|---|---|---|---|---|---|
| X1 | An existing signed open-source Indirect Display driver (candidate: the community Virtual Display Driver; licence and signature validity confirmed in the epic) | Virtual display | Windows has no built-in virtual display; a driver must be signed through Microsoft | Virtual-display interface | M17 first-party driver |
| X2 | ViGEmBus (archived in 2023, still signed and working) | Virtual gamepad | No driverless way exists for XInput games to see a controller | Virtual-gamepad interface | M17 first-party driver |

Nothing else is excepted. Adding an entry needs the owner's approval.

## 12. Risks

- **Size.** Eighteen milestones; 1.0 alone (M0 to M11) contains a video pipeline, a transport protocol, NAT traversal, a
  server, a terminal emulator and a terminal service. The roadmap orders the work so that each milestone is usable.
- **Late integration (consequence of the Linux-first build order).** Six milestones of transport, pacing and parser
  logic are finished before any real capture, encoder or decoder runs against them. Simulated and recorded sources reduce
  the risk but cannot remove it; M7 is where design errors in the seams surface, and it may send work back to M2 or M6.
- **Hardware-bound verification.** Capture, encoding and latency can only be tested on physical Windows machines with
  GPUs. From M7 the latency and sharpness gates run on the owner's machines.
- **Development machine.** It is a Linux container with no GPU; NativeAOT needs clang installed, and kernel network
  emulation is not available inside the container, so the M1 test bench must either emulate in user space or have the
  module loaded on the container host.
- **Driver exceptions.** ViGEmBus is abandoned and community driver signatures expire. Both sit behind interfaces, and
  doment must run without them.
- **4:4:4 on AMD clients** has no hardware decode. The alternative technique is unproven and is the riskiest part of M9.
- **First-party codecs and parsers.** Bitstream parsing for hardware decode, forward error correction and a CELT audio
  codec are each substantial and security-sensitive (they parse network input); each is fuzzed when built and again in M10.
- **Garbage collection on the real-time path** can cause frame-time spikes; the allocation-free rule is tested in M10.
- **Anti-cheat** in some games rejects injected input; those games will not work and doment will not work around it.
- **Unsigned binaries until M12.** On the owner's machines SmartScreen prompts are acceptable; installing on other
  people's PCs needs signing first, which is why signing is in M12.
- **Codec patents.** Whether an application that only calls operating-system and GPU codecs owes H.264 or HEVC
  royalties is unverified. It does not matter for private use and needs legal advice before any public release.
- **Research gaps.** Reddit could not be read by the research tools, and each research file lists items it could not
  verify (for example Parsec's current codec list and several 2026 CVE identifiers).
- **Requirements without a threshold.** The M0 audit found requirements whose wording has no pass threshold: "without
  collapse" (WAN adaptation), "no bitrate spike" (Screen capture), "presentation is even" (Frame pacing and game
  performance), "a full fuzzing campaign" (Security review), "every failure the user can meet" (Errors and
  observability), documentation "complete", and "usable with the controller alone" (Steam Deck mode). Each epic's own
  spec must set the threshold before its plan is written.
- **Accessibility.** Win32UI has no screen-reader support, so doment's Windows client has none either.

## 13. Discovery record

| Question | Owner's answer (2026-11-24) |
|---|---|
| Audience for the first release | The owner's own machines first, fully self-hosted, designed so a public release stays possible |
| Day-to-day uses | Remote coding, remote gaming, supporting other people's PCs, managing the homelab, and using the PC from the laptop for design and animation work (Photoshop, After Effects) |
| Client devices after Windows | Android, iPhone and iPad, MacBook, Linux desktop and Steam Deck |
| Host types beyond Windows | Linux headless agent, macOS host, Linux desktop streaming |
| Connectivity | Both the self-hosted server and VPN, server first; connect directly whenever possible, relay, server or VPN only when direct fails |
| What must be excellent first | Desktop work with coding, and gaming, both at the same time |
| Host GPUs | NVIDIA, Intel integrated or Arc, and GPU-less virtual machines and servers |
| Client GPUs | Intel integrated, AMD Radeon integrated, NVIDIA laptop GPU |
| Third-party rule | First-party, with listed exceptions |
| Most demanding picture | 1440p at 120 Hz |
| Non-goals | Enterprise fleet features |
| Release 1.0 | Windows daily driver: Windows host and client, desktop work, coding and gaming, self-hosted server, terminals and Wake-on-LAN |
| Drivers in 1.0 | Existing signed drivers first; first-party drivers later |
| Spec approval | Approved as drafted on 2026-11-24 ("approved, commit and start M1"), which covers the items the draft marked as proposals: the success-measure numbers, Windows 11 as the floor, the three additional non-goals, the first-party audio codec, and basic UAC and login-screen handling inside 1.0 |
| Build order | Defer the desktop app until after M6: build all the necessary code and logic on the Linux machine first, then build the desktop app on a Windows machine |
