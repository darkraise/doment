# Competitor research: game-streaming and low-latency desktop streaming

Research date: 2026-11-24. Track: game-streaming products. Source tags `[Sn]` are listed at the end.

Method and limits:
- Reddit (r/cloudygamer, r/MoonlightStreaming, r/ParsecGaming, r/SteamDeck) could not be fetched (blocked for the tooling). Community evidence below comes from GitHub issue trackers, Hacker News, Steam forums and vendor docs. Reddit posts are cited only where a GitHub issue links to them.
- Parsec support pages (support.parsec.app) returned HTTP 403 to direct fetch. Parsec doc claims come from search-engine excerpts of those pages and from parsec.app/unity.com pages that did load; they are tagged "(excerpt)".
- Latency numbers: no independent benchmark was found. Vendor or blog numbers are labelled as such and not relied on.
- "Unverified" = could not confirm from a primary source.

---

## 1. Parsec

**Ownership and status.** Unity agreed to acquire Parsec for about USD 320M in Aug 2021 [S1][S2]. The product is now hosted on unity.com under Unity trademarks [S3]. Parsec shut down its Arcade feature in 2023 [S2]. I found no official 2026 statement on roadmap, divestiture or layoffs. Third-party layoff and "uncertain future" claims came from a competitor's marketing page and a WARN-notice aggregator that does not clearly tie the notices to Parsec: Unverified.

**Architecture** (excerpts of [S4]):
- Four parts: client, host, a Parsec-hosted signalling WebSocket/API gateway (TCP 443), and a Parsec-hosted STUN server (UDP 3478). Both sides learn their public address from STUN, exchange it through the API, then try a direct peer-to-peer UDP connection.
- UPnP or UDP hole punching is the default path. Peer-to-peer ports are random unless set statically.
- Account login is mandatory on both host and client. An HN user on 2026-11-10 complained that Parsec "requires internet access to its cloud services for authentication, session discovery, and connection setup" [S5].
- A relay exists only on the Enterprise tier ("high-performance relay", on-premises "Parsec Relay server") [S6][S4]. Personal users with symmetric NAT or CGNAT get no vendor relay per these docs. Unverified whether a free-tier relay fallback exists.

**Protocol and codec.**
- BUD: Parsec's own UDP protocol with TCP-like reliability and a custom congestion controller, DTLS 1.2 via OpenSSL, near-real-time sharing of network metrics with the encoder, no video buffers, priority order latency then frame rate then quality [S7]. The post (undated, from the pre-Unity era) says the design assumes under 50 ms ping and 30 Mb/s, admits it is too conservative for high-latency users, and does not mention FEC. It describes H.264; H.265 is listed as supported in the feature matrix (excerpt) [S8]. AV1: Unverified.
- Hardware encoder required on host; software fallback shows a red warning; RX 6400 and RX 6500 XT cannot host (excerpt) [S9].

**Platforms.** Host: Windows 10+ and macOS 10.15+ only [S6]. Linux can only be a client; Parsec's own article says Linux hosting is unsupported "at this time" (excerpt) [S10]. Clients: Windows, macOS, Linux, Android, Raspberry Pi per [S2]; iOS and web clients: Unverified.

**Licence and pricing** [S6]:

| Plan | Price | Notable |
|---|---|---|
| Personal | free | non-commercial; no multi-monitor, no 4:4:4, no privacy mode; 60 FPS desktop capture |
| Warp | USD 8.33/mo annual, 9.99 monthly | up to 3 monitors, 4:4:4, privacy mode, Wacom pressure/tilt; still non-commercial |
| Teams | USD 30 annual, 35 monthly per user | commercial use, SSO, team computer management, audit logs (7 days), guest access USD 25 per invitation |
| Enterprise | USD 45/user, annual only | high-performance relay, SCIM, full audit logs, API |

A Japanese article claims a 28 Sep 2026 build raised the limit from 3 to 5 screens; Unverified (not on Parsec's pricing page).

**Gaming features.**
- Controllers: Windows host can present the pad as Xbox or DS4; uses the Parsec Virtual USB driver or ViGEm 1.17+ for the DS4 touchpad; rumble supported (excerpts) [S11]. Parsec troubleshooting repeatedly says input to elevated windows and some games needs "system permissions" and that running as administrator is not enough (excerpt) [S12].
- Virtual displays: Parsec Virtual Display Driver (VDD), Windows host only, up to 3 extra displays, only created for Parsec sessions (not persistent), no HDR on virtual displays; additional virtual displays need Warp/Teams, but "fallback to virtual display" (one display when none exists) is free (excerpts) [S13][S14]. Community forks of the open driver exceed the limit; unverified.
- Headless host: Parsec still says the GPU must "believe there is a physical monitor" and recommends an HDMI dummy plug or the VDD; USB display adapters and some docks are incompatible (excerpt) [S14].
- Multi-user couch co-op, mic passthrough, relative mouse, gyro, 120/240 Hz, VRR, frame-pacing controls, bitrate controls: Unverified for 2026 (not confirmable without the 403-blocked docs). Parsec's marketing says "up to 4K at 60 fps" [S3].
- Statistics overlay: Unverified.
- Wake-on-LAN: no Parsec WoL documentation found in several searches. Unverified.

**What users like.** HN: "There's nothing out there that comes close to Parsec's performance"; installation "like magic" [S15]. A 2022 HN comment finds Parsec over gigabit "very difficult to distinguish" from local and RDP "noticeably laggy" in comparison [S16].

**Documented pain points.**
- Cloud and account dependency (above) [S5]. Trustpilot reviewers cite repeated login problems and frequent re-authentication (search excerpt, individual reviews; low weight): Unverified beyond that.
- Paywall resentment and feature gating: 4:4:4, multi-monitor, extra virtual displays, privacy mode are behind a subscription; 4:4:4 was already a request on HN in 2021 ("may require payment") [S15]. Non-commercial licence means any business user must buy Teams at USD 30.
- Chroma subsampling hurts text; HN user: text "hard to read in VSCode" [S15].
- Software decoding on Macs "slams CPU" [S15].
- Elevated-window and UAC input requires system permissions [S12]; the UAC secure desktop is not capturable by normal-desktop capture in general (vendor-neutral explanation) [S17].
- No Linux host; Mac host needs manual Privacy and Security grants (review excerpt, low weight).
- Ownership uncertainty after the Unity deal was an immediate community worry in 2021 ("I hope this doesn't mean the end of Parsec as a standalone service") [S15].

---

## 2. Sunshine and Moonlight

**Architecture.** Accountless and self-hosted. Sunshine is the host (web UI at https://localhost:47990, base streaming port 47989) and Moonlight is the client; no vendor cloud, no relay, no built-in NAT traversal [S18][S19][S20]. The protocol is the NVIDIA GameStream protocol re-implemented (GameStream was NVIDIA's closed host) [S21]. Pairing: add the host in Moonlight, Moonlight shows a 4-digit PIN, enter it in the Sunshine web UI under PIN, name the device [S22]. Moonlight guide: pair on the home LAN first; iOS and tvOS must pair on the same network [S19]. Internet options in the official guide: UPnP (Sunshine setting), manual port forwarding, IPv6, or an overlay VPN (ZeroTier, Tailscale, Meshnet); Tailscale fails if only a DERP relay path is available [S19]. Ports TCP 47984/47989/48010, UDP 47998/47999/48000/48002/48010 [S19]. There is no browser client because GameStream needs raw TCP/UDP sockets [S21].

**Protocol and latency techniques** (from the Sunshine config reference [S20]): hardware encode (NVENC, QuickSync, AMF, VAAPI, VideoToolbox, Vulkan Video, software), forward error correction default 20% (`fec_percentage`), optional AES encryption (`lan_encryption_mode` default off, `wan_encryption_mode` default on-if-supported), `minimum_fps_target` for static content, `ping_timeout` 10 s. Windows capture methods include DXGI and Windows.Graphics.Capture (WGC) [S23]. Moonlight offers frame-pacing and V-Sync options per client [S24][S25]. Transport details beyond this (RTSP/RTP/ENet) are from background knowledge, not re-verified here.

**Platforms.** Host (current docs): Windows 11+, macOS 14.2+, Debian 13+, Fedora 43+, Ubuntu 22.04+, FreeBSD 15.1+ [S18]. Older Moonlight docs still say Windows 10 [S19]. Clients: Windows, macOS, Linux, Raspberry Pi 4/5, Android, iOS, tvOS, ChromeOS, Steam Link, community ports (Vita, Xbox, webOS, Switch/L4T) [S26][S21].

**Licence and pricing.** Sunshine and Moonlight are GPL-3.0 [S23][S26]. As of 2026 there is one paid element: the Windows Virtual HID Driver for gamepad creation (see 2.1).

**Gaming features.**
- Codecs: H.264, HEVC, AV1; YUV 4:4:4 only with Sunshine [S26]. HDR on Windows needs HEVC Main10 or AV1 10-bit GPU, an HDR display or EDID dummy, and the HDR option in the client [S27][S19].
- Controllers: up to 16 players, rumble, motion; emulated types Generic, DS4, DualSense, Switch Pro, Xbox 360/One/Series; macOS host gamepad support only appeared in a pre-release on 2026-11-23 [S18][S26][S28]. Motion and touchpad can be mapped to a DS4 (`motion_as_ds4`, `touchpad_as_ds4`) [S20].
- Relative mouse capture plus a "remote desktop mouse mode" where the host cursor follows the client cursor [S21]. Non-Shield Android handles mouse acceleration poorly; GameStream-era hosts changed host mouse settings [S21].
- Not passed through: flight sticks, wheels, gyro of arbitrary devices (FAQ suggests VirtualHere for USB) [S21].
- High refresh: 120 fps works but a macOS host was capped at 90 fps (open issue #2745) [S29].
- VRR: not in upstream. A community Moonlight fork adds VRR-aware pacing and needs V-Sync on and borderless window [S30].
- Mic passthrough: reported by a user as a Sunshine addition over GameStream [S31]; Unverified in current docs.
- Statistics overlay: present in Moonlight clients (background knowledge); Unverified this session.
- Multi-monitor: one display per stream; Windows `output_name`/`adapter_name` selects it [S20]. Windows capture is limited to the GPU that drives the display; eGPU/other GPU needs a dummy display attached to it [S23].
- Virtual displays: none built in upstream; use a dummy plug or a third-party virtual display driver [S23].
- Wake-on-LAN: sent by the Moonlight client as a magic packet; works on the LAN or over a VPN; not designed for internet use; docs say laptops and Wi-Fi hosts are unreliable, and WoL can stop working after long sleep [S32][S21]. Sunshine docs do not mention WoL [S23].

### 2.1 Paid Virtual HID Driver (Aug-Sep 2026) [S33][S34][S18]
- LizardByte introduced libvirtualhid and a Windows Virtual HID Driver. The licence is USD 14.99/year or USD 49.99 lifetime, up to 5 machines, and creating a gamepad needs an online licence check; the maintainer says a daily check exists to prevent refund abuse and abuse by cloud-gaming companies [S33][S34].
- Free paths remain: ViGEmBus fallback for Xbox 360 and DualShock 4, SendInput for keyboard and mouse. ViGEmBus is end-of-life and archived since 2023-11-02 [S35]. Sunshine stopped installing it automatically in the 2026-05 release [S28].
- Games that read Raw Input may ignore the SendInput fallback keyboard and mouse; the driver-backed keyboard and mouse need the licence [S18].
- Community reaction in the announcement thread: dislike of phone-home licensing and subscriptions, "upsell feel" of repeated notifications, antivirus or Windows trust warnings on the driver, a licence email that never arrived, one user considering a fork [S34].

### 2.2 Documented pain points (Sunshine and Moonlight)
- Windows service vs UAC and WGC: the Sunshine maintainer states the UAC prompt is visible only with the service and DXGI capture, not with WGC or "run as admin"; with WGC UAC is invisible and the stream freezes until it is resolved (issue 3487, closed with that guidance) [S36]. Apollo's maintainer says WGC cannot run from the service and Task Scheduler cannot handle UAC or lock-screen passwords [S37].
- HDR: blown-out colours sent to SDR clients when HDR is enabled in Windows but the HDR monitor or dummy plug disappears (issue 1853, reopened work as late as 2026-05) [S38]; the running Sunshine service made other apps' HDR washed out (issue 3500) [S38]; Moonlight macOS/Windows HDR brightness wrong in an open issue [S39].
- Frame rate side effects: a Vulkan game limited to half its frame cap whenever Sunshine was running (3703), DLSS frame generation versions halving streamed fps (3621), FreeSync on host halving capture fps (2499) [S29][S38]. A pull request notes stutter when moving the mouse that was fixed with a DwmFlush call [S40].
- GPU scheduling and VRAM: stream freezes with hardware-accelerated GPU scheduling (863) or near-full VRAM and does not recover without restarting Sunshine (1031) [S38]. NVIDIA vsync:fast stutter is in the official troubleshooting page [S41].
- Startup failures: "Unable to find display or encoder during startup" on Windows 11 24H2, recovered only by manually restarting Sunshine; the issue was closed by a stale bot after 90 days without a fix [S36].
- Antivirus: Defender flagged a pre-release as Wacatac trojan (3962); NSIS installer flags reduced, installer replaced by MSI in 2026 [S36][S28].
- Security cadence: 2026 saw a critical advisory in May, five advisories in a critical update on 6 Sep, and a high-severity Linux update on 15 Sep; an earlier issue titled "Elevation of Privileges Exploit" (998) concerned the SYSTEM service launching apps [S28][S29].
- Breaking releases: 2026 releases dropped NSIS installers, renamed portable packages, removed ViGEmBus web endpoints, required CSRF origin config for non-localhost web UI, and stopped auto-opening the web UI [S28].
- Permission denied launching apps from non-system drives because the service runs as SYSTEM [S41].
- Moonlight client problems: periodic macOS stutter since 2019 (issue 159, still open, 165 comments; maintainer traced a 100 ms `recvfrom` stall to the network or OS stack; users link it to AWDL, the interface behind AirDrop, and switch Wi-Fi channels) [S42]; Steam Deck OLED jitter that clears when a system menu is opened (open, attributed to Wi-Fi power management or SteamOS) [S43]; random mouse lag spikes on Windows traced to an SDL 2.0.9-2.0.10 bug [S44]; Steam Deck HDR took until Moonlight 6.0.0 in June 2024 and only works outside the desktop session [S45].
- Docs and setup friction: Moonlight docs (Windows 10/11) and Sunshine docs (Windows 11+) disagree on the host minimum; Sunshine's own docs have no Windows virtual display guidance and no WoL page [S23]; HN user: Sunshine and Moonlight "fantastic" for gaming but "janky" for remote desktop use [S5].

---

## 3. Sunshine forks and successors

**Apollo + Artemis (ClassicOldSong)** [S46]:
- GPL-3.0 fork of Sunshine. Adds built-in virtual display (SudoVDA driver) that matches client resolution, refresh rate and HDR, creates it at stream start and removes it when the app quits, fixed per-client display identity so Windows remembers layout; per-client permissions (launch apps, mouse, keyboard, view streams; first paired client gets all, later clients only view and list); clipboard sync; connect/disconnect commands; input-only mode; dual-GPU adapter selection; headless mode without dummy plug.
- Artemis (also called Moonlight Noir) is the client, Android only per the README; Windows/macOS/Linux builds are a community fork with dev builds (issue 937: 56 reactions, maintainer silent on a timeline, users complaining of no updates) [S46][S47].
- The README says Apollo and Artemis "will no longer be compatible with OG Sunshine and OG Moonlight eventually" and recommends removing other virtual display drivers [S46].
- Health: 11.7k stars, 348 open issues, last push 2026-05-21 (about six months before today, an inference of slowed activity); latest listed release v0.4.7-alpha.1 (August, year not shown, probably 2025). A release note warned the SudoVDA driver signature expires on 19 August, and the release signing key shows as expired [S48][S49].
- Pain points: stutter regression in 0.4.3 that users fixed by reverting to 0.3.7 and no root cause was found (issue 956, 78 comments); one user fixed it with half-rate vsync via NVIDIA Inspector, while the maintainer noted a 60 fps request creates a 60 Hz virtual display [S50]. HDR with the service fails to detect the GPU when WGC is on (issue 1147, open) and the thread moved users to Vibeshine [S37]. Virtual display creation fails on Optimus laptops even after reinstall (issue 1532, 2026-07) [S51]. Enabling HDR on virtual display caused washout (205) [S51]. Virtual display on Linux is unsupported (1161) [S46].

**Vibeshine / Vibepollo (Nonary)** [S52][S53]:
- Vibeshine is Sunshine-based; Vibepollo brings the same features to Apollo. Windows is primary, Linux host in beta (needs Linux 6.16+ and a hardware H.264 encoder), SteamOS experimental.
- Adds: bundled virtual display driver with SudoVDA kept as rollback, up to eight clients each with its own virtual screen, display-layout recovery after crashes or reboots, WGC capture that switches methods automatically including at the login screen and UAC, remote monitor and remote input sessions, game library sync (Playnite, Steam, Lutris), RTSS and NVIDIA frame-cap integration, Lossless Scaling and Smooth Motion support, scoped API tokens, WebRTC browser streaming (version 1.14.0), a bundled gamepad driver needing no ViGEmBus and no licence key (Xbox Series/One, DualSense, DS4, Switch Pro; optional wired-DualSense haptics), VRR-aware capture and the PyroWave codec (need Nonary's Moonlight fork) [S52][S53].
- Maintainer says about 99% of the code is AI-generated, upstream backports are unlikely, and it diverges from upstream by roughly 99,800 changed lines [S52][S53]. Licence type not stated in the README text I could read: Unverified.
- Risk signals: a single maintainer, AI-generated code at scale, a warning in Apollo's notes about forks that merge unfinished upstream PRs ("security risks") [S49]. No independent security review was found.

---

## 4. Steam Remote Play / Steam Link

- Architecture: Steam account required on both ends; direct LAN or Steam-relayed internet play; free, closed-source [S54]. Details of the connection model: Unverified (the Steam support page body did not load).
- Platforms: Steam Deck, Windows, macOS and Linux appear in the 2026 beta notes [S55][S56]; Steam Link on Android, iOS, tvOS and the full host matrix: Unverified.
- 2026 changes: Steam beta on 2026-07-29 added HDR streaming to the Steam Deck OLED as a client and AV1 under the experimental SteamRT3 client [S55]; on 2026-09-21 the beta added the Pyrowave codec for Remote Play. Pyrowave is intra-only wavelet, off by default, needs 5 to 10 times the bandwidth of normal codecs, a wired gigabit connection recommended, bitrate 100 to 500 Mbit/s, optional 4:4:4, automatic HDR, Windows and macOS beta, Linux behind SteamRT3, mobile "coming soon", and Valve says some setups may not benefit [S56]. Test figures such as about 10 ms total at 1080p60 came from a single secondary article and are Unverified [S57].
- Moonlight's README says Steam Link hardware builds cap at 1080p60 and 40 Mbps and lack HDR on original hardware [S26].
- Co-op: Remote Play Together lets a friend join without owning the game (secondary description) [S58]; the details of controller limits are Unverified.
- Wake-on-LAN: Unverified.
- Pain points: black screen or crash is most commonly fixed by turning off hardware encoding on the host, which moves load to the CPU and may be worse [S59]; stutter on a Deck client fixed by turning off hardware decoding or HEVC or low-latency networking [S59]; a Steam support article describes an NVIDIA driver bug that crashes or black-screens streaming from laptops unless Steam uses the integrated GPU [S59]. In 2022, ex-GameStream users measured Steam Link at roughly 80 to 110 ms more display latency than GameStream's 25 to 30 ms by camera (single-user measurement) [S21]. Valve itself signalled that users needed extra tools for the best in-home experience (headline only) [S60].

---

## 5. Defunct or discontinued

**NVIDIA GameStream.** NVIDIA told Shield owners in Dec 2022 that GameStream would end in mid-February 2023 and recommended Steam Link and GeForce NOW; the removal shipped in March 2023 [S61]. No reason was given [S61]. Moonlight users were told to move to Sunshine; GFE owners kept old installers and blocked updates [S21]. What users lost: the one-click host built into GeForce Experience, Shield TV as a turnkey client, and a protocol Moonlight was built on. Lesson: a closed host controlled by one vendor can vanish with weeks of notice; the open reimplementation (Sunshine) became the standard and added AMD/Intel hosts, AV1 and mic support [S21].

**Rainway.** A browser-client game streaming service with a Windows host; funded with USD 1.5M seed (2018) and USD 3.5M (2019); the Xbox One app was pulled from the Microsoft Store in Feb 2020 at Microsoft's request; the founder announced shutdown on 2022-10-26 [S62][S63]. The stated reason was not found: Unverified. Observation only: it depended on a vendor-run service and a closed client.

**AMD Link.** AMD announced in late 2023 that Link would lose support in a Q1 2024 Adrenalin release, saying it launched when few alternatives existed and now "there are many options"; AMD kept the AMF SDK for developers [S64]. A German report ties the removal to Adrenalin 24.1.1 [S64]. Users lost the only first-party Radeon streaming path and were pointed at Parsec and Moonlight.

Common thread: GPU-vendor streaming features were sidelines, ended by vendor strategy, and replaced by open or third-party tools.

---

## 6. Newer entrants and comparisons (brief)

- Valve Pyrowave and Vibepollo PyroWave: both adopted the same low-latency intra-frame GPU codec in 2026; both need wired gigabit or better [S56][S52]. This signals the LAN-only "ultra-low-latency, high-bitrate" mode is now a differentiator.
- RustDesk: open source remote desktop, versions 1.5.0 (2026-09-30), 1.5.1 (11-01), 1.5.3 (11-09); 1.5.1 notes DRM pacing and PipeWire latency fixes, hardware-encoder warm-up fixes and Intel QSV stall fixes; 1.5.0 added WebRTC support and HDR tone mapping; the release notes do not mention gaming [S65]. Self-hosting uses hbbs (rendezvous) and hbbr (relay) with UDP hole punching and relay fallback; web console, OIDC, LDAP and similar are Pro-only [S66]. The server licence claim from a Habr article is Unverified.
- Shadow PC (hosted PC): only low-quality secondary sources were found (tech-insider.org, which contradicts itself); a claimed July 2026 hour-capped "Lite" tier and USD 37.99 to 54.99 plans are Unverified [S67].
- Sunshine-based commercial wrappers: none found. Searches returned only SEO comparison pages. Unverified that none exist.
- Other open-source activity seen: Vibepollo's Linux host, Helios (Linux/Wayland virtual display on the Apollo base), community Artemis desktop builds [S46][S47].

---

## 7. Recurring complaints and root causes

| ID | Complaint | Root cause (evidence) | Seen in |
|---|---|---|---|
| C1 | Setup friction: pairing PIN, ports, web UI cert warnings, manual port forwarding, VPN needed for internet | No NAT traversal service in Sunshine; GameStream-derived protocol needs fixed ports and pairing on LAN first [S19][S22] | Sunshine, Moonlight |
| C2 | Cloud dependency and logins: auth, session discovery and connection need Parsec servers; re-authentication | Central signalling plus account model [S4][S5] | Parsec |
| C3 | Paywalls and licence resentment | Parsec 4:4:4, multi-monitor, extra VDD displays behind subscription; Sunshine paid gamepad driver with online licence check and nag notifications [S6][S33][S34] | Parsec, Sunshine |
| C4 | Black or frozen stream at UAC, lock screen, secure desktop | Secure desktop not capturable from the user session; WGC cannot run in the service; DXGI plus service is the working combination, but not for all games [S36][S37][S17] | all |
| C5 | Elevated apps ignore input | Windows input integrity (UIPI); host needs system-level permissions or UIAccess [S12][S17] | Parsec, Sunshine |
| C6 | Headless host needs dummy plug or a virtual display; drivers conflict; virtual display fails on Optimus laptops or after driver updates | GPU only outputs when it sees a display; third-party IDD drivers conflict and sign certificates expire [S14][S23][S51][S49] | all |
| C7 | HDR washout, wrong brightness, HDR breaks other apps | Windows HDR state vs dummy plug/virtual display; tone-mapping mismatch; service interferes [S38][S39][S51] | Sunshine, Apollo, Steam |
| C8 | Stutter and frame-pacing problems | Many causes: HAGS, VRAM, vsync modes, frame-cap interactions, Wi-Fi power management or AWDL, client vsync; no root cause in many threads [S38][S42][S43][S50] | all |
| C9 | Frame cap or fps halved while host streams | Capture hooks interact with exclusive-fullscreen, DLSS FG, FreeSync [S29][S38] | Sunshine |
| C10 | Regression churn: update breaks working setup, revert advised | Fast fork cadence, breaking changes, minimal regression testing [S28][S50][S34] | Sunshine, Apollo |
| C11 | Abandonment, stale issues, stale-bot closures, bus factor | Issue bots close unresolved bugs; Apollo and Artemis desktop lag; Vibepollo single-maintainer and AI-written code [S36][S47][S52] | Sunshine, Apollo, Vibepollo |
| C12 | Controller and input driver trouble | ViGEmBus EOL; Raw Input games need driver-backed keyboard and mouse; Parsec needs host-type setting [S18][S35][S11] | all |
| C13 | Mouse acceleration, pointer capture, keyboard layout (AltGr, Super key) | Client OS differences, SDL and Flatpak regressions, host layout mismatch [S21][S44][S68] | Moonlight |
| C14 | Wake-on-LAN unreliable off-LAN, on Wi-Fi, and after long sleep | WoL is link-local and NIC/BIOS dependent [S32] | Moonlight |
| C15 | Security exposure: SYSTEM service, web UI, port forwarding | Multiple 2026 advisories; CSRF added only in 2026; forking increases patch lag [S28][S49] | Sunshine, forks |
| C16 | Vendor discontinuation | GameStream, AMD Link, Rainway [S61][S64][S62] | defunct |
| C17 | Poor remote-desktop (non-game) behaviour of game-oriented streamers | Designed around fullscreen games and one display [S5] | Sunshine |

---

## 8. What a new product should do differently (requirement candidates)

Each item names the complaint (C) or strength (S) it traces to. All are testable.

**Connectivity and accounts**
- R1 (C1, C2, S1: Parsec "just works"): The host and client connect from a cold install in at most 3 user actions with no router changes on a typical home NAT; test on UPnP-off, double-NAT and CGNAT lab networks, success rate target stated and measured.
- R2 (C2, C16): LAN, direct IP and offline pairing work with no internet and no account; a vendor-service outage does not break an already-paired LAN session. Test by blocking all external hosts.
- R3 (C1): Provide a rendezvous and a relay fallback and surface to the user which path is active (direct, relayed) and the added latency; relay never silently activates.
- R4 (C1, C15): Pairing uses mutual authentication with out-of-band confirmation; device list with revoke; no web UI exposed beyond the LAN by default.
- R5 (C14): Wake-on-LAN from the client for a stored host MAC, a clear "not supported" diagnosis (Wi-Fi, no BIOS setting), and a relay "wake agent" option for off-LAN wake; document sleep-state limits. Test: wake from S3 after 24 h and 72 h sleep.

**Capture and session lifecycle**
- R6 (C4, C5): Stream the logon screen, lock screen, UAC secure desktop and Ctrl+Alt+Del path without a manual toggle, with input to elevated windows, via a service plus session helper design. Test matrix: lock, sign-out, UAC, fast user switching, RDP session stealing.
- R7 (C6): Ship a signed virtual display driver with per-client persistent identity, client-matched resolution, refresh rate and HDR, automatic creation and cleanup, and crash-safe restore of the physical layout; no dummy plug required. Test: Optimus laptop, headless desktop, driver update, reboot mid-session.
- R8 (C6): Driver certificate expiry monitored in CI and surfaced as a startup warning at least 60 days before expiry (Apollo note about expiring SudoVDA signature).
- R9 (C9, C8): Capture must not alter the frame rate of the game being captured: automated test with a Vulkan exclusive-fullscreen title, a DLSS frame-generation title and a FreeSync host; host game fps with the product running but idle must match fps without it within 2%, and streamed fps must match host fps.
- R10 (C6): Multi-GPU and hybrid laptops: capture and encode on whichever GPU drives the display, validated on at least one iGPU+dGPU laptop per release.

**Video, latency and pacing**
- R11 (S: BUD, Moonlight FEC): Congestion control reacts within 1 s, supports automatic bitrate and FEC, never buffers video, and exposes a real-time stats overlay (capture, encode, network, decode, present, dropped frames, jitter, path).
- R12 (C8): End-to-end latency budget published per stage and measured by an automated camera-less method (timestamped frames); regression gate in CI for p50 and p99.
- R13 (C8): Client frame pacing has at least a lowest-latency and a smoothest mode, VRR-aware presentation, and auto-detects client refresh mismatch. Test: 60 Hz stream on 144 Hz VRR display, 120 Hz stream on 120 Hz display.
- R14 (S: Sunshine): H.264, HEVC and AV1 with 10-bit HDR and 4:4:4 included in the free tier; Pyrowave-like high-bitrate LAN codec as an optional mode (S: Valve 2026 and Vibepollo).
- R15 (C7): HDR is negotiated per stream, restored on disconnect, and never leaks into other apps while no stream is running; SDR clients get correct tone-mapping when the host is HDR. Test: HDR toggled with display disconnected, with the service idle.
- R16: Static-content efficiency: no large bitrate excursions or frame-rate drops on idle or mostly static desktops (Sunshine issues 3419 and 3817, both reported on Linux/AMD) and a desktop-quality mode for text (4:4:4 or lossless-ish) so remote desktop use is not "janky" (C17).

**Input, audio and peripherals**
- R17 (C12): Gamepad passthrough for Xbox and DualSense types with rumble, gyro, touchpad and adaptive trigger/haptics, with no paid or phone-home dependency, and a signed driver that passes antivirus checks. Test: virus-scan the installer on every release.
- R18 (C12): Keyboard and mouse use hardware-level injection (Raw Input visible) without a licence check; test with a Raw-Input-only game.
- R19 (C13): Relative mouse and absolute mode switch automatically with pointer-lock state; mouse acceleration off option; layout-independent scancode forwarding plus text input (AltGr, IME, modifiers never stuck after focus loss). Test: stuck-modifier on alt-tab, German and Portuguese layouts.
- R20: Audio: capture without muting the host unless asked, virtual sink for headless hosts, microphone passthrough, and per-stream audio device selection (config options `virtual_sink`, `stream_audio` show the need).
- R21 (S: Apollo permissions, Parsec Teams): Per-client permissions (view, control, keyboard, mouse, launch apps, clipboard), couch co-op guest sessions with per-guest controller slots and revocation, and an audit log; clipboard sync as an explicit permission.

**Business model and trust**
- R22 (C3): Never gate core streaming quality features (4:4:4, HDR, multi-monitor, high refresh) behind a subscription that needs an online check to run on a LAN; if paid, licence checks must work offline for a grace period of at least 30 days and never degrade an active session.
- R23 (C3, C10): Publish pricing and the exact feature split before launch; no repeated nag notifications; refund and licence-email failure handling tested.
- R24 (C10, C15): Release channels with staged rollout and a one-click rollback to the previous version without losing config; breaking changes documented in release notes with migration steps (2026 Sunshine releases changed installers, packages, input backends in a few months).
- R25 (C11): Issues triaged within a stated window; no bot auto-closing of unreproduced bugs without maintainer comment; a public status page for any vendor services.
- R26 (C15): Third-party security review before launch, a vulnerability disclosure policy, signed installers, and a service that drops privileges for launched apps (issue 998, 2026 advisories).
- R27 (C16): If any hosted component is required, publish an open protocol spec or a self-host mode so an end-of-life notice cannot strand users (GameStream, AMD Link, Rainway).

**Platform**
- R28: Windows host first, with client parity targets documented and a Linux host on the roadmap; Parsec has none and Sunshine has one, and Linux hosts cause most of Sunshine's issue volume, so do not promise parity before the Windows host is solid.
- R29 (C13): Web or browser client (WebRTC) as a fallback client for locked-down machines; Moonlight has none and Vibepollo and RustDesk 1.5.0 are adding one [S21][S52][S65].

---

## 9. Not verified or not obtainable

- Parsec: current codec list, AV1, 240 Hz, relative mouse, mic, co-op, stats overlay, Wake-on-LAN, 5-screen claim, any 2026 roadmap or layoff facts (support docs 403; secondary claims conflict).
- Steam Remote Play: full host/client matrix, 4:4:4, WoL, internet relay model, Remote Play Together limits.
- Rainway: reason for shutdown. Shadow PC: any primary pricing or latency data. Sunshine-based commercial wrappers: none found.
- Sunshine stats overlay and exact transport stack: background knowledge only.
- Reddit complaint threads: not accessible; counts and sentiment from Reddit are absent from this report.
- The Sunshine repository redirect: github.com/LizardByte/Sunshine returned HTTP 301 to github.com/SunshineStream/Sunshine on 2026-11-24 (curl); I found no announcement explaining it.

---

## Sources

- [S1] https://unity.com/news/unity-enters-agreement-acquire-parsec (and https://www.businesswire.com/news/home/20210810005116/en)
- [S2] https://en.wikipedia.org/wiki/Parsec_(software)
- [S3] https://unity.com/products/parsec
- [S4] https://support.parsec.app/hc/en-us/articles/32361410290324-Components-and-Connection-Sequence and https://support.parsec.app/hc/en-us/articles/32381460716180-Parsec-Connectivity-Requirements (excerpts)
- [S5] https://news.ycombinator.com/item?id=50436127 (comment 2026-11-10)
- [S6] https://parsec.app/pricing
- [S7] https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007
- [S8] https://support.parsec.app/hc/en-us/articles/4407194154253-Feature-Matrix (excerpt)
- [S9] https://support.parsec.app/hc/en-us/articles/4425688194189 (excerpt)
- [S10] https://support.parsec.app/hc/en-us/articles/32381494397332-Parsec-App-for-Linux (excerpt)
- [S11] https://support.parsec.app/hc/en-us/articles/32381705301908-Setup-Gamepad and https://support.parsec.app/hc/en-us/articles/32381826078868-Controller-Isn-t-Working-in-the-Game (excerpts)
- [S12] https://support.parsec.app/hc/en-us/articles/32381827815188-Mouse-and-Keyboard-Isn-t-Working-Correctly-When-Connected (excerpt)
- [S13] https://support.parsec.app/hc/en-us/articles/32381733729044-Multiple-Monitors-and-Virtual-Displays and https://support.parsec.app/hc/en-us/sections/32361161093780-Virtual-Display-Driver-VDD (excerpts)
- [S14] https://support.parsec.app/hc/en-us/articles/32381854731156-Running-Parsec-On-A-Headless-Gaming-PC-Or-A-Server (excerpt)
- [S15] https://news.ycombinator.com/item?id=28135433
- [S16] https://news.ycombinator.com/item?id=32530122
- [S17] https://obsproject.com/forum/threads/dual-screen-uac-make-black-screen-in-primary-screen-source-on-obs-studio.84679 (secure-desktop explanation, vendor-neutral)
- [S18] https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2troubleshooting.html and https://docs.lizardbyte.dev/projects/sunshine/latest/
- [S19] https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- [S20] https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html
- [S21] https://github.com/moonlight-stream/moonlight-docs/wiki/Frequently-Asked-Questions and https://github.com/moonlight-stream/moonlight-qt/issues/918
- [S22] https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html
- [S23] same as S22 (capture, eGPU, HDR notes)
- [S24] https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting
- [S25] https://github.com/moonlight-stream/moonlight-android/issues/1541 (search excerpt, pacing options)
- [S26] https://github.com/moonlight-stream/moonlight-qt
- [S27] same as S22 (HDR on Windows)
- [S28] https://github.com/LizardByte/Sunshine/releases (redirects to SunshineStream/Sunshine)
- [S29] https://github.com/SunshineStream/Sunshine/issues/3703, /3621, /2499, /2745, /998, /3419, /3817
- [S30] https://newreleases.io/project/github/Nonary/moonlight-qt/release/v6.1.0-vrr5
- [S31] https://github.com/moonlight-stream/moonlight-qt/issues/918 (user comment)
- [S32] https://github.com/ReenigneArcher/moonlight-docs/wiki/WOL-(Wake-On-LAN)
- [S33] https://app.lizardbyte.dev/2026-08-16-introducing-libvirtualhid-and-virtual-hid-driver/
- [S34] https://github.com/orgs/LizardByte/discussions/1079
- [S35] https://docs.nefarius.at/projects/ViGEm/End-of-Life/
- [S36] https://github.com/SunshineStream/Sunshine/issues/3487, /3447, /3962
- [S37] https://github.com/ClassicOldSong/Apollo/issues/1147
- [S38] https://github.com/SunshineStream/Sunshine/issues/1853, /3500, /863, /1031
- [S39] https://github.com/moonlight-stream/moonlight-qt/issues/1508
- [S40] https://github.com/LizardByte/Sunshine/pull/164 (search excerpt, DwmFlush)
- [S41] https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2troubleshooting.html
- [S42] https://github.com/moonlight-stream/moonlight-qt/issues/159
- [S43] https://github.com/moonlight-stream/moonlight-qt/issues/1152
- [S44] https://github.com/moonlight-stream/moonlight-qt/issues/168
- [S45] https://github.com/moonlight-stream/moonlight-qt/issues/1117
- [S46] https://github.com/ClassicOldSong/Apollo
- [S47] https://github.com/ClassicOldSong/Apollo/issues/937
- [S48] GitHub API repo metadata for ClassicOldSong/Apollo, SunshineStream/Sunshine, moonlight-stream/moonlight-qt (queried 2026-11-24)
- [S49] https://github.com/ClassicOldSong/Apollo/releases
- [S50] https://github.com/ClassicOldSong/Apollo/issues/956
- [S51] https://github.com/ClassicOldSong/Apollo/issues/1532 and /205
- [S52] https://github.com/Nonary/Vibepollo
- [S53] https://newreleases.io/project/github/Nonary/Vibepollo/release/2.0.0 and https://signpath.org/projects/vibepollo (search excerpts)
- [S54] https://help.steampowered.com/faqs/view/0689-74B8-92AC-10F2 (body did not load)
- [S55] https://www.gamingonlinux.com/2026/07/steam-beta-adds-hdr-streaming-on-steam-deck-oled/
- [S56] https://www.gamingonlinux.com/2026/09/steam-beta-adds-experimental-new-pyrowave-video-codec-for-remote-play/
- [S57] https://borncity.com/news/steam-remote-play-valve-integriert-pyrowave-codec-fuer-ultra-latenz/ (AI-assisted article, low weight)
- [S58] https://store.steampowered.com/remoteplay (not loaded; description from secondary guides)
- [S59] Steam community threads: https://steamcommunity.com/groups/homestream/discussions/1/4290314417250545891 and https://help.steampowered.com/faqs/view/0689-74B8-92AC-10F2 (search excerpts)
- [S60] https://www.pcgamer.com/software/platforms/valve-puts-some-elbow-grease-into-steam-remote-play-maybe-one-day-you-wont-have-to-install-additional-tools-to-get-the-best-in-home-game-streaming-experience/ (headline only)
- [S61] https://9to5google.com/2023/03/29/shield-tv-gamestream-removal/ and https://wccftech.com/nvidia-shield-ends-gamestream-service-recommends-steam-link-plus-geforce-now-as-replacements/
- [S62] https://en.wikipedia.org/wiki/Rainway
- [S63] https://www.windowscentral.com/rainway-pc-game-streaming-app-pulled-microsoft-store
- [S64] https://www.amd.com/en/resources/support-articles/faqs/PA-325.html and https://www.tomshardware.com/pc-components/gpus/amd-is-ending-support-for-its-link-game-streaming-application-here-are-some-alternatives
- [S65] https://github.com/rustdesk/rustdesk/releases
- [S66] https://rustdesk.com/docs/en/self-host/
- [S67] https://tech-insider.org/shadow-pc-hour-caps-avoid-lockouts-2026/ (low reliability, not relied on)
- [S68] https://github.com/moonlight-stream/moonlight-qt/issues/1776 (Flatpak sdlcompat breaks Super key)
