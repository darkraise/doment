# Remote-support and unattended-access competitors (research dated 2026-11-24)

Scope: TeamViewer, AnyDesk, RustDesk, Splashtop, ConnectWise ScreenConnect (deep); Chrome Remote Desktop, MeshCentral, Microsoft RDP/Quick Assist/Windows App, NoMachine, DWService, Zoho Assist, HelpWire, Remotely/ControlR (light).
Citations are `[S#]` keys resolved in the source list at the end. "Unverified" means I could not confirm it from a primary or credible source. Prices are volatile and mostly come from third-party aggregators; treat as indicative as of 2026-11.

Method limits: Reddit (r/sysadmin, r/msp, r/rustdesk, r/homelab) could not be fetched (tool blocked), and web search returned no Reddit threads. Complaint evidence therefore comes from vendor community forums, GitHub issues/discussions, Microsoft Q&A and review aggregators. Competitor-authored pages (Splashtop, RustDesk, HelpWire, TSplus) are marked as marketing where used. Several advisory/CVE IDs for 2026 were read through summarising fetches; verify IDs on NVD before citing externally.

## 1. Per-product findings

### 1.1 TeamViewer
- Architecture: account-based; devices addressed by ID; outbound-only, tries TCP/UDP 5938, then 443, then 80; direct peer-to-peer when possible, otherwise via `router*.teamviewer.com` relays; no self-hosting of the connectivity platform [S7]. (Hole-punching internals not documented in the KB I read: Unverified.)
- Licence/pricing: subscription per licensed user plus "channels" (concurrent sessions). Reported list prices (Nov 2026): Remote Access about $24.90/mo (1 user, 3 devices), Business $50.90, Premium $120.90 (older listings $112.90), Corporate $245.90 (older $229.90); MSI mass deployment only in Corporate; mobile-device support is a paid add-on [S13]. Free tier is personal use only; "commercial use" is detected automatically [S6].
- Unattended access: "Easy Access" (device assigned to the account, no per-device password); account protected by Trusted Devices and optional 2FA; allowlist/blocklist by account or ID [S10]. Session recording and connection reports exist [S10]; per-feature detail Unverified.
- Prompts: remote user sees a small dialog after access is granted [S11].
- Black screen / privacy: "Black Screen" hides remote content and disables remote input, requires "Start TeamViewer with System", and depends on monitor-driver hardware support [S9].
- UAC: UAC prompts cannot be driven in a normal session; documented workaround is Windows Authentication with an admin account [S8]. Users report the remote screen still goes black at UAC on some hosts, including domain-joined PCs, even with admin credentials and with UAC registry changes [S8b].
- Wake-on-LAN: see section 2.
- Recent security record: 2025-2026 bulletins are frequent (about 20 bulletins in 2025-2026), including TV-2026-1007 "Bypass of 2FA for connections via Unattended Access in TeamViewer for macOS" (fixed in 15.80) and TV-2026-1003 "Access control vulnerability in Full and Host clients" [S2][S3].
- Not verified for TeamViewer: multi-monitor, remote printing, chat, safe-mode reboot and reconnect details, clipboard behaviour, RDP/multi-user session handling.

### 1.2 AnyDesk
- Architecture: ID-based clients; closed source; cloud by default with an On-Premises appliance on higher tiers [S21]. Proprietary DeskRT codec (vendor claims 60 fps, under 16 ms: unverified marketing) [S21]. Direct vs relay selection rules are not documented in sources I found (Unverified).
- Licence/pricing: free for personal use only (3 managed devices); paid Solo/Standard/Advanced/Ultimate. Competitor trackers report a January 2026 increase (Solo $14.90 to $28.90, Standard $22.90 to $49.90, Advanced to $111.90) while another tracker lists Solo about $23 and Advanced about $90; sources conflict and are competitor-authored [S18]. Licence requires full-year upfront payment [S18].
- Unattended access: off by default; enabled by setting a password under Security; optional 2FA; "Interactive Access" can be set to never show incoming requests so only password-authenticated connections are accepted; ACL by ID/alias via custom client keys `ad.security.acl_enabled` and `ad.security.acl_list`; per-profile permissions under Settings > Security > Permissions (AnyDesk 7+) [S17].
- UAC/secure desktop: only the installed client with the AnyDesk Service can interact with UAC and admin software; portable clients show a blank screen with a crossed-out cursor until the remote user acts; "Request elevation" and "Transmit authentication data" exist; elevation does not make a standard user an admin [S16]. Login/lock-screen handling is not described on that page (Unverified).
- Commercial-use detection: AnyDesk publishes no detection threshold; users report false positives and a whitelist-request route (competitor-authored sources) [S19].
- Security record: 2024 breach (section 3.2); 2025-2026 local privilege escalation via unquoted service path (CVE-2025-34499) and link-following DoS bugs in "Send support information" and screen recording (ZDI-26-400/401) [S20]; a Cloud Security Alliance note reports a public Linux root exploit in Oct 2026 with no CVE at the time [S20].
- Not verified: privacy mode, session recording, remote printing, safe-mode reboot, multi-monitor specifics.

### 1.3 RustDesk
- Architecture: open-source client (AGPL-3.0-or-later per Wikipedia) with `hbbs` (ID/rendezvous) and `hbbr` (relay); tries hole punching, falls back to relay; WebSocket clients always use the relay; key pair in `id_ed25519.pub` encrypts connections; ports UDP 21116, TCP 21114-21119 [S27]. Direct-IP connections skip the relay, which confuses relay testing [S27b].
- Public server: controllers (rollout date not stated in the post) must log in via a third-party identity provider on the public server because of scam and botnet abuse; RustDesk admits this blocked some legitimate users [S23].
- Licence/pricing: client AGPL; community server AGPL with no user management; Server Pro is proprietary and paid (Individual about $9.90/mo for 20 devices; Basic about $19.90/mo for 10 users and 100 devices; add-ons per user, per device, per concurrent connection; figures differ by page) [S27]. Pro adds web console, 2FA, OIDC, LDAP, audit logs, address book, strategy, control roles [S27]. Community allegation that distributing Pro binaries violates AGPL is unresolved [S29]. Complaint: a four-person team needing concurrent access estimated $120/month [S29]. Developer-entity status is conflicting (Unverified) [S29].
- Provisioning: custom-client generator (Pro), `rustdesk.exe --config <string>`, server-config import/export; silent MSI install is not covered in the docs I read (Unverified; issue #212 "Windows installer silent install" exists, 34 comments) [S27][S28].
- Unattended access: permanent password plus TOTP 2FA with optional trusted-device bypass, IP allowlist and ID allowlist (v1.5.0), rate-limited, evaluated before password/2FA [S23]. The ID allowlist relies on client-reported IDs so a modified client can spoof it [S23].
- Windows specifics: virtual display and privacy mode relied on a custom Indirect Display driver; see 3.4. UAC elevation for the portable build was requested early (#70); "Send Ctrl+Alt+Del" (#1244) and privacy-mode failures (#5714, #14849 Privacy Mode 2 with auto-login) are long-running issues [S28].
- Wake-on-LAN: section 2.
- Recent vulnerabilities: ZDI-26-117 (CVE-2026-2490, Windows file-transfer link following); a March 2026 batch (CVE-2026-30783 to about -30798, clients through 1.4.5 and Server Pro through 1.7.5) covering authentication, certificate validation, URI config import; CVE-2026-57850 missing session-scope enforcement, fixed in 1.4.9 per references [S26]. Reports of exploitation: none seen by WA SOC as of its advisory [S26].
- Platform gaps: Wayland support was the most-commented issue (#56, 134 comments); clipboard failures on Wayland (#13338); macOS 15 black frames (#16402, opened 2026-09-30) [S28].

### 1.4 Splashtop
- Architecture: cloud accounts, a Streamer on the host, Business/Remote Support/Enterprise cloud plus an On-Prem Gateway edition (Gateway and Streamers must be on the same subnet for WoL) [S30].
- Pricing (indicative, third-party): Business Access Pro about $8.25 per user/mo (billed yearly, up to 10 computers); Performance about $13 per user/mo includes Android/IoT unattended; Remote Support SOS about $17-22 per technician/mo (sources disagree); Enterprise is quote-only [S31].
- Headless hosts: Splashtop documents black screens on headless Windows and a workaround of a virtual display capped at 720p [S30b].
- Security: Streamer for Windows local privilege escalation bugs in 2020 (CVE-2020-12431) and 2024 (CVE-2024-42050 installer temp-folder race fixed in 3.7.0.0; CVE-2024-42053 install-time file permissions, fixed after 3.6.0.0) [S31]. I found no 2025-2026 advisories (absence of results, not proof).
- Not verified: UAC/login-screen behaviour, privacy mode, recording, printing, mass deployment details, permission model.

### 1.5 ConnectWise ScreenConnect
- Architecture: self-hosted (on-premises) or ConnectWise cloud; relay server brokers sessions; extensions run .NET on the server as SYSTEM [S32a]. Guests join "support" sessions; "access" agents are persistent unattended agents.
- Licence: concurrent-technician licences for support (One about $30, Standard about $45-47, Premium about $53-55 per month, annual) plus agent-based licences for unattended Access, priced separately and with historic large increases (Splashtop-authored claim: up to 275% on Access tiers) [S32b][S18b].
- Headless/black screen: community requests for headless endpoint support (#2460) and reports of blank screens on Windows 10/11 (#922, #4360) [S32c]. RDP-session targeting problems on servers are documented for sibling product GoTo Resolve, not ScreenConnect (Unverified for ScreenConnect) [S32c].
- Wake-on-LAN: no documentation found (Unverified), see section 2.
- Security record: section 3.

### 1.6 Lighter coverage
- Chrome Remote Desktop: WebRTC transport, setup negotiated through Google services, STUN/TURN relay fallback; Windows host runs a SYSTEM daemon with a low-privilege network process; "curtain mode" is available via admin policy; admin needs TCP/UDP 443 and 3478 allowances [S34a]. No Wake-on-LAN (low-quality source; Unverified) [S34a]. UAC/login behaviour: Unverified.
- MeshCentral: Apache-2.0, self-hosted Node.js server, small C agent that dials back, server relays browser-to-agent websockets, device groups, per-group user permissions, MFA, SSO, optional Intel AMT out-of-band including agent-less AMT groups; actively maintained per aggregator (482 commits in 12 months, Aug 2026) [S34b]. Permission bit `MESHRIGHT_WAKEDEVICE` exists in `meshuser.js` [S34b2].
- Microsoft: RDP is session-based and depends on the Windows SKU; Quick Assist moved to a Store app and Microsoft recommends Intune Remote Help for governed support [S35]. Users report RDP lock-screen with no sign-in option for PIN/Microsoft accounts, and reconnects hanging after 24H2 [S35b]. Quick Assist abuse: section 3.7. Windows 11 Pro single interactive session is background knowledge, Unverified in this research.
- NoMachine: NX protocol, free (single incoming connection, no browser access) and paid editions; Wake-on-LAN since v7 in both editions; screen blanking of host display is Enterprise [S34c].
- DWService: free service, browser-only client, agent MPLv2 and server not open source, supports screen, files, shell; inbound-port model Unverified [S34d].
- Zoho Assist: free plan 1 technician plus 5 unattended computers; Wake-on-LAN listed in Standard by a GetApp listing only (Unverified); reboot/reconnect reliability questioned by a reviewer [S34e].
- HelpWire: free tool; reviews conflict on whether unattended access exists and on free-tier limits; no vendor terms found (Unverified) [S34f].
- Remotely: repository carries a "Looking for Maintainers" notice; its original author continues as MIT-licensed ControlR with a two-year Devolutions sponsorship [S34g]. Other 2025-2026 newcomers: HopToDesk and RustAdmin are RustDesk forks, unaffiliated [S29]. No other notable 2025-2026 open-source entrant verified.

## 2. Wake-on-LAN: how each does it and where it fails
Core constraint: a magic packet is a layer-2 broadcast, so something on the target's LAN must send it. Every product either (a) uses another online agent on that LAN as a sender, or (b) needs a public-IP router forwarding to the broadcast address.

| Product | Mechanism | Evidence |
|---|---|---|
| TeamViewer | (1) "Neighbour": another TeamViewer device on the same network, running 24/7 and starting with the OS, relays the wake request. (2) Public address: static IP or DDNS name; router must forward UDP (example UDP 9 to 192.168.1.255:9) and hold a static ARP entry for the target MAC. Macs wake only from sleep; Windows/Linux from sleep, hibernate, off if hardware allows. [S4] | Per KB |
| AnyDesk | Servers pick another online AnyDesk client on the target's network, which sends the packet. Settings: Disabled; Enabled (random local clients, default); Enabled only via listed AnyDesk IDs. Needs BIOS/UEFI WoL, NIC "Magic packet", Fast Startup off; supports S5, hybrid shutdown, sleep; Windows/Linux/macOS (macOS Intel only); Wi-Fi wake needs router support [S15] | Per vendor doc |
| Splashtop | Needs another Streamer on the target network that is awake; Auto or Manual choice of sender devices; Business article says Windows only; feature page says Windows from off/sleep/hibernate, Mac from sleep only; On-Prem needs Gateway on same subnet and Ethernet, laptops on AC [S30] | Docs conflict on Mac support |
| RustDesk | LAN-only; the client scans the LAN to record MAC addresses then sends a magic packet via the wol-rs crate; UI entry appears only for devices in "Discovered" in Flutter; maintainer: "Same local network required" (2022-11-16); a Dec 2025 prerequisites guide exists; no Pro/server-assisted wake [S24] | Maintainer-confirmed |
| ScreenConnect | No WoL documentation found (Unverified) | Search negative |
| MeshCentral | Community claim: MeshCentral tells other online devices in the group to send the wake request; not found in official docs; subnet restriction unconfirmed; AMT groups give out-of-band power control [S34b3] | Unverified |
| NoMachine | Client option "wake the server on the LAN if powered off" since v7; same on free and Enterprise [S34c] | Per KB |
| Chrome Remote Desktop | None found [S34a] | Low-quality source |
| Remote Utilities, LogMeIn (comparators) | Second always-on host on same LAN, wired only [S36] | Comparator |

What users report failing:
- TeamViewer: wake icon blinks and nothing happens; message "The device cannot be reached directly and no neighbor is available" despite BIOS/NIC settings; after a Host update wake showed "Device could not wake up"; support acknowledged a bug where no WoL packets were sent from any device including the web console, "fixed" then recurred ("works great for a few months and then stops"); works from phone/web but not desktop client; one thread titled "Wake on LAN failed because of no license" [S5].
- RustDesk: entry present but remote PC does not wake (2025-06); MAC addresses often unknown and IPs change; users want manual MAC entry and configurable port (2026-01); question whether self-hosted server can send packets unanswered (2026-11-08) [S24].
- AnyDesk: "no device found" when no peer is online; Windows Fast Startup is a recurrent cause; one commenter says AnyDesk's equivalent also stopped working and that paid AnyDesk can wake across networks (second-hand, Unverified) [S15][S24].
- Splashtop: network nodes between client and target can block ports; vendor ships a WoL Checking Tool [S30c].
- Cross-cutting causes: no online sender on the LAN (single-PC homes, overnight shutdowns of all PCs), VLAN/subnet separation, Wi-Fi targets, Fast Startup, BIOS/NIC settings, laptops on battery, router lacking directed-broadcast or static-ARP support, dynamic IP/MAC knowledge.

## 3. Security incidents and design lessons

### 3.1 TeamViewer account takeover wave (June 2016)
- Facts: victims reported takeover of PCs followed by PayPal/eBay/Amazon fraud; some said they had strong passwords and 2FA. TeamViewer denied a breach, blamed credential reuse from third-party leaks, and tied a 2016-06-01 outage to a DNS DoS [S12]. On 2016-06-03 it launched Trusted Devices (new-device approval by emailed link valid 24 hours) and Data Integrity (anomaly monitoring) [S12].
- Root cause: credential stuffing against accounts without mandatory second factor; whether 2FA accounts were also hit was never resolved publicly ("We don't know" per Tripwire) [S12].
- Lesson: an account is the key to every enrolled device; new-device approval and anomaly detection must exist before launch, and attack reports must be answered with evidence.

### 3.2 AnyDesk breach (disclosed 2024-02-02)
- Facts: production systems compromised; source code and private code-signing keys stolen (per BleepingComputer sources); AnyDesk said no tokens stolen, not ransomware; incident response with CrowdStrike; certificates revoked; new signing certificate in 8.0.8 (2024-01-29), old "philandro Software GmbH" cert to be revoked; web-portal passwords revoked; 4-day outage from 2024-01-29 [S14]. Root cause not disclosed [S14].
- Lesson: signing keys must live in HSMs separate from build infrastructure; design for fast certificate rotation and agent auto-update; publish root cause. Mass revocation breaks installed bases, so key-compromise recovery must be rehearsed.

### 3.3 ConnectWise ScreenConnect CVE-2024-1709 / 1708 (Feb 2024)
- Facts: 1709 (CVSS 10.0) authentication bypass; 1708 ZipSlip path traversal in extension unpacking (CVSS 8.4); on-prem 23.9.7 and earlier; fixed in 23.9.8; CISA KEV [S32a][S32d]. (Mandiant and IBM write the labels swapped; NVD labels are as above.)
- Root cause: the setup-wizard guard compared raw `Request.Path` to `"/SetupWizard.aspx"` at `OnBeginRequest`; `/SetupWizard.aspx/anything` bypassed it and re-ran setup on a configured instance, overwriting the user DB. Fix: check the resolved handler (`ISetupHandler`) after mapping [S32a]. Admin extensions run .NET as SYSTEM, so admin equals remote code execution [S32a].
- Lesson: authorisation must be by resolved identity, not string-matching URLs; setup endpoints must be physically disabled after first run; server-side extension execution as SYSTEM makes the server a single point of fleet compromise.

### 3.4 RustDesk 1.2.3 test root certificate (CVE-2024-25140, disputed)
- Facts: default Windows install put a WDK test certificate (code-signing EKU, valid to 2033) into Trusted Root; NVD scored 9.8 but marks it disputed [S26]. Installer script from the virtual-display driver project did this to sign the driver; maintainers said it was a Microsoft WDK certificate, then removed the driver (losing virtual display and privacy mode), later replaced it with usbmmidd_v2 signed by Microsoft (answer dated 2025-02-03) [S25].
- Lesson: never add a trust anchor to the machine root store; ship drivers with proper attestation/WHQL signing before features that depend on them; a privacy-mode/virtual-display feature depends on driver signing, so plan this early.

### 3.5 ScreenConnect 2025 incidents
- 2025: CVE-2025-3935 ViewState code injection (versions 25.2.3 and earlier; fixed in 2025.4 which removes ViewState); needs leaked ASP.NET machine keys; CISA KEV 2025-06-02 [S32e]. ConnectWise disclosed a suspected nation-state intrusion affecting a few cloud instances; a source said intrusion Aug 2024, discovered May 2025 (unconfirmed by BleepingComputer) [S32f]. ConnectWise rotated code-signing certificates for ScreenConnect, Automate, RMM (on-prem deadline 2025-06-13), stating it was unrelated to the intrusion [S32g].
- Root cause of rotation: installer stored the callback URL/config in an unsigned region, so a validly signed client could be re-pointed; attackers reportedly embedded malicious config in legitimate signed clients, evading EDR [S32g].
- Lesson: cover agent-to-server configuration with the signature or embed it cryptographically; do not rely on a vendor signature as proof of safe behaviour; do not keep long-lived secrets (machine keys) where a platform-level compromise reveals them.

### 3.6 ScreenConnect 2026: CVE-2026-84869 and November campaign
- Facts: disclosed 2026-09-08 (CVSS 9.9), CISA KEV 2026-09-11, fixed in technician host clients 26.6.5; a guest in a session could trigger file-transfer actions that the technician's client processed without authorisation or confirmation, including running files; Huntress saw spraying from 2026-10-19 and a full technician-workstation compromise on 2026-11-12/13; a worm-like toolkit "SCKit" and a second wave on 2026-11-13 are reported; ConnectWise's 2026-11-11 advisory reports partner-account unauthorised access and rogue remote clients with initial access still under investigation [S32h].
- Root cause: the technician client trusted guest-originated file-transfer commands; server patches alone did not fix it [S32h].
- Lesson: treat the remote end as hostile in both directions; no auto-open/auto-run of transferred files; require explicit local consent per transfer on the controlling side; let admins remove file-transfer permission instantly by role; client auto-update must reach technician consoles, not only servers.

### 3.7 Abuse by scammers and ransomware actors; vendor countermeasures
- CISA AA23-025A (2023-01-25): legitimate RMM tools (ScreenConnect, AnyDesk) used in refund scams; portable executables bypass admin and software-control policies [S33a]. AA25-163A (2025-06): ransomware actors exploiting unpatched SimpleHelp [S33a].
- Microsoft (2024-05-15): Storm-1811 used vishing and Quick Assist (Ctrl+Windows+Q code entry) to install Qakbot, Cobalt Strike, ScreenConnect, NetSupport, then Black Basta; Microsoft added scam warnings, suspended tenants, recommended blocking or uninstalling Quick Assist and using Remote Help [S33b].
- RustDesk: Google Play unpublished 2023-09-03; public-server login for controllers; Android warning plus countdown; controlled-side IP/ID allowlists and TOTP; admits warnings are ignorable and that consent obtained by deception cannot be fixed by encryption [S23].
- TeamViewer: allowlist/blocklist by ID, on-screen indicator after access is granted, scam reporting form [S11]. AnyDesk: 2023 "Anti-Fraud Task Force" with scam baiters (Wikipedia-level source) [S20b].
- Lesson: the vendor cannot prevent consent obtained by deception; it can add friction at the moment of consent (who is asking, what they can do), make the controller identifiable, and give admins block/allowlist and "only accept from my org" controls.

### 3.8 Other incidents (context)
- TeamViewer 2024: initial access 2024-06-26 via a standard employee account; APT29 attribution; employee directory and encrypted passwords copied; no product environment or customer data affected; final update 2024-07-04 [S1]. Lesson: corporate identity compromise adjacent to a remote-access vendor is high impact; keep build/signing and corporate IT strictly separated and say so verifiably.
- TeamViewer 2026-07 macOS unattended-access 2FA bypass (CWE-288): a business-logic path let device-management users skip the connection 2FA step [S3]. Lesson: every access path (unattended, web console, API) must go through one policy decision point.

## 4. Recurring complaints and root causes
1. False "commercial use" flags. TeamViewer: sessions cut after about a minute then reconnect blocked; reset requires a specialist reply, forms unanswered for days or weeks; no false-positive dialog in v14 [S6]. AnyDesk: no published threshold, whitelist request route, a user reporting 3-4 uses a year flagged [S19]. Root cause: heuristic enforcement with no self-service appeal.
2. Price hikes and licence resentment. Competitor trackers cite TeamViewer and AnyDesk increases and a Premium tier at $120.90/mo with one concurrent connection [S13][S18]; ScreenConnect Access increases [S18b]; RustDesk Pro per-user/per-device charges criticised ($120/mo for four users) [S29]. Treat magnitude as unverified (marketing sources).
3. Connection time limits and unattended gating. TeamViewer free sessions limited; AnyDesk free sessions may time out [S6][S18]. Root cause: free-tier abuse control.
4. Sessions lost or blank at UAC/secure desktop. TeamViewer threads [S8]; AnyDesk portable client blanks the screen [S16]; RustDesk requests for UAC password entry and Ctrl+Alt+Del [S28]. Root cause: secure desktop is owned by SYSTEM; the helper process needs SYSTEM-level capture/injection or UIAccess; portable (non-service) installs cannot.
5. Black screen on headless or screen-off hosts. RustDesk #2166 (open since 2022-11-16, still reported 2026): host shown offline when monitor sleeps; maintainer blamed an overloaded $5/month server, a user showed it also happens self-hosted [S28]; RustDesk guide: no monitor means no framebuffer, use dummy plug or virtual display [S28b]; Splashtop 720p virtual-display workaround [S30b]; ScreenConnect headless request #2460 [S32c]; Zoho and TeamViewer threads with the same symptom [S34e]. Root cause: capture depends on an attached display; a virtual display driver is needed (and driver signing, see 3.4).
6. Keyboard layout and modifiers. RustDesk #7530 (Turkish Q, some keys swapped; TeamViewer and RDP did not); AltGr issues (#728); Map mode vs Translate mode changing remote layout; iOS AZERTY (#14104) [S28c]. Root cause: sending scancodes vs characters when local and remote layouts differ; AltGr arrives as Ctrl+Alt or Alt.
7. Clipboard failures: RustDesk Wayland-to-Wayland (#13338) [S28]. Other products: Unverified from this research.
8. Self-hosting pain. Relay not reachable ("Failed to connect to relay server"), key mismatch, two-NIC servers, WebSocket mode forcing relay, port list of 21114-21119 [S27]; testing on LAN bypasses relay [S27b]; open-source server lacks users, audit and web console [S27].
9. Slowness and relay dependence. Vendor claims only; no independent latency data collected (Unverified). RustDesk relay is mandatory when hole punching fails, so a self-host relay is the performance ceiling [S27].
10. Outages and sign-in friction. TeamViewer 2016-06-01 DNS DoS outage [S12]; AnyDesk 4-day login outage in Jan-Feb 2024 [S14]; RustDesk public-server login requirement blocked some users [S23]; RDP 24H2 login hangs and lock screens without sign-in option [S35b].
11. Wake-on-LAN unreliability: section 2.
12. Pro/enterprise features gated: TeamViewer MSI only in Corporate; RustDesk custom client Pro only [S13][S27].

## 5. What a new product should do differently (requirement candidates)
Each item cites the finding it traces to. "Checkable" means a test or inspection can pass/fail it.

Identity and enrolment
- R1. No trust anchor is ever added to the machine or user certificate store by the installer or driver. Check: install on a clean VM, diff root stores. (3.4)
- R2. Account sign-in requires 2FA by default for any account that can reach unattended devices; new-device approval and login-anomaly alerts ship at launch. Check: attempt login from a new device without 2FA and confirm refusal. (3.1, 3.8)
- R3. Unattended enrolment is bound to an org/account by a single-use or expiring token; the host rejects installs that lack a token. (3.7, 3.5)
- R4. One policy decision point authorises every access path (viewer, web console, API, CLI, address-book shortcut); an automated test enumerates all entry points against 2FA and allowlist rules. (3.8 macOS bypass)
- R5. Controller identity is cryptographic (per-device key signed by the account), not a client-reported ID; allowlists key on that identity. (RustDesk ID allowlist limit, 1.3)
- R6. Per-device policy supports: allow only my organisation's controllers, allowlist/blocklist, IP restriction, time windows, and "attended-only" mode. (3.7)

Consent and abuse resistance
- R7. Attended sessions show the controller's verified display name, organisation, and requested capabilities (view/control/file/clipboard/elevation) on the consent prompt; the first unfamiliar-controller connection shows a scam warning with a delay before Accept. (3.7)
- R8. A persistent on-screen indicator and one-click "end session" are shown for the whole session, including unattended sessions when a user is logged in; a policy can disable it for kiosks. (3.7 TeamViewer indicator)
- R9. Sessions that include screen sharing with an unsigned/portable "run once" client cannot be granted elevation without separate user confirmation. (3.7, 4.4)
- R10. Provide an enterprise switch "block all connections not from my organisation" that is enforceable by MSI/GPO. (3.7)

File transfer, clipboard, remote code surfaces
- R11. File transfers never auto-run, auto-open or write outside a designated folder on either side; transfers into the controller's machine require a local prompt; path traversal tests (ZipSlip, `..\`, reserved names, junctions) run in CI for both directions. (3.3, 3.6)
- R12. Capabilities (file transfer, clipboard, command execution, elevation, recording off) are separately grantable per role and per device and are revocable in effect within seconds for live sessions. (3.6)
- R13. No server-side plug-in mechanism that executes arbitrary code as SYSTEM in the relay/management tier; if extensions exist, they are sandboxed and signed. (3.3)
- R14. Setup and bootstrap endpoints are removed or disabled after first run, and authorisation uses resolved handler/identity, not URL strings; fuzz tests on path normalisation. (3.3)

Signing, update, supply chain
- R15. Signing keys live in an HSM or cloud signing service isolated from build servers; documented rotation runbook rehearsed annually; agent auto-update can replace trust roots without manual reinstall. (3.2, 3.5)
- R16. Agent installer embeds server address/tenant config inside the signed region or verifies a signed config blob at runtime; test: modify config bytes and confirm the agent refuses. (3.5)
- R17. Publish a root-cause statement within a defined period after any security incident; maintain a public advisory feed with CVE IDs and fixed versions. (3.2, 3.5)
- R18. Technician-side clients auto-update and report version to the server; the server can refuse connections from vulnerable consoles. (3.6)
- R19. Windows service and installer path hygiene: quoted service paths, ACL-hardened install directory and temp folders, no oplock-racy installers; check with a local privilege-escalation test suite. (AnyDesk CVE-2025-34499, Splashtop 2024 CVEs [S20][S31])

Windows session handling
- R20. Host runs as a SYSTEM service with a per-session helper; supports capture and input on the login screen, lock screen, UAC secure desktop, fast user switching, console and RDP sessions, and shows which session the technician is attached to. Check matrix: login, lock, UAC consent and credential prompt, Ctrl+Alt+Del, user switch, RDP session on server. (4.4, 4.5)
- R21. A "Send Ctrl+Alt+Del / unlock / sign in with credentials" action exists, with credential entry kept out of the screen stream and logged. (RustDesk #1244, 4.4)
- R22. Built-in virtual display for headless hosts with Microsoft-attested driver, and the device stays "online" when the monitor sleeps. Test: unplug monitor, lock, sleep display, reconnect. (4.5, 3.4)
- R23. Privacy mode (blank local screen, block local input) works without a custom unsigned driver, and degrades with a clear message when the GPU/driver does not allow it. (3.4, TeamViewer black screen limits [S9])
- R24. Reconnect after reboot, including safe mode with networking, and a service that starts before logon; restart and shutdown are first-class actions with confirmation policy. (Not verified for any competitor; treat as differentiator)
- R25. Multi-monitor selection, per-monitor capture, and DPI-correct input; keyboard layout handling sends scancodes with layout negotiation and has AltGr and dead-key tests for at least US, DE, FR (AZERTY), TR-Q, JP. (4.6)

Wake-on-LAN
- R26. Wake works through at least three paths, ordered by automatic fallback: (a) peer agent on the same L2 segment, (b) site gateway/appliance on the segment, (c) directed-broadcast through a router with documented settings. Admin console shows which senders exist per segment and warns when a target has none. (Section 2)
- R27. The server records each host's MAC, subnet, and last-seen sender candidates automatically; users do not type MAC addresses; an optional manual override exists. (RustDesk users asking for manual MAC/port, [S24])
- R28. Wake is observable: the console reports "no sender available", "packet sent by X", "device came up after N seconds", with a self-test tool ("WoL check") on the host. (TeamViewer/Splashtop failure reports, [S5][S30c])
- R29. Wake health is tested after every agent update (regression test: wake from S5 and from sleep on a lab matrix incl. Fast Startup on/off). (TeamViewer regression after Host update, [S5])
- R30. Consider out-of-band options for managed fleets (Intel AMT/vPro-style or smart plug/IPMI integrations); do not rely on them as the only path. (MeshCentral AMT, [S34b])

Audit, recording, governance
- R31. Immutable audit log of connections, capabilities used, file names and hashes, elevation requests, and permission changes, exportable to SIEM; optional session recording with retention policy. (Pro gating complaints, 4.12; CISA guidance [S33a])
- R32. Address book/device groups with role-based permissions, group-level policies, and bulk operations; included in the base paid tier. (4.12)
- R33. Mass deployment: signed MSI with silent install, enrolment token and policy as parameters, uninstall protection, and Intune/GPO guidance, in all paid tiers. (4.12, [S13])

Licensing and trust
- R34. Licence enforcement never silently terminates active sessions mid-use; flagging for non-commercial use is explainable, shows evidence, and has a self-service appeal that answers within a stated time. (4.1)
- R35. Price model predictable: published seat/concurrency rules, no mandatory annual prepayment surprises, price-change notice period of at least 90 days. (4.2, hypotheses to validate with customer research)
- R36. Self-hosting option documented with one command setup, relay health checks that test the relay path (not LAN shortcut), and parity of audit/user management with the hosted product. (4.8)
- R37. Product behaviour is testable offline: a connection-path diagnostic shows direct vs relay, round-trip time, and bandwidth, so "slow" complaints are diagnosable. (4.9)

## 6. Verification gaps (carry into the next research step)
- Not verified per product: session recording, remote printing, chat, multi-monitor, safe-mode reboot-and-reconnect, clipboard, and RDP/multi-user handling for TeamViewer, AnyDesk, Splashtop and ScreenConnect; login-screen handling for AnyDesk, Splashtop, ScreenConnect, Chrome Remote Desktop.
- ScreenConnect Wake-on-LAN, MeshCentral wake semantics, Chrome Remote Desktop UAC/login behaviour.
- All Reddit evidence (tool blocked). Independent latency or throughput benchmarks.
- Current official prices (only aggregator and competitor figures obtained).
- AnyDesk and TeamViewer connection architecture (hole punching/relay selection) in primary docs.
- RustDesk public-server login rollout date; RustDesk company status.

## 7. Source list
- S1 https://www.teamviewer.com/en/resources/trust-center/statement/ (2024 incident, final update 2024-07-04)
- S2 https://www.teamviewer.com/en/trust-center/security-bulletins/ (bulletin list; CVE IDs via summarising fetch)
- S3 https://www.teamviewer.com/en/resources/trust-center/security-bulletins/tv-2026-1007/
- S4 https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-remote/remote-control/wake-up-a-device-remotely
- S5 https://community.teamviewer.com/English/discussion/117022/remote-wake-on-lan-not-working ; https://community.teamviewer.com/English/discussion/110882/the-device-cannot-be-reached-directly-and-no-neighbor-is-available ; https://community.teamviewer.com/English/discussion/129246/wake-on-lan-failed-because-of-no-license ; https://community.teamviewer.com/English/discussion/comment/151225/
- S6 https://www.teamviewer.com/ams/global/support/knowledge-base/teamviewer-classic/licensing/personal-use/commercial-use-suspected/ ; https://community.teamviewer.com/English/discussion/113172/connection-blocked-after-timeout
- S7 https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-remote/troubleshooting/ports-used-by-teamviewer/
- S8 https://www.teamviewer.com/apac/global/support/knowledge-base/teamviewer-remote/remote-control/control-uac-during-a-teamviewer-session/ ; S8b https://community.teamviewer.com/English/discussion/143738/uac-prompts-blackout-remote-screen-on-specific-host-devices ; https://community.teamviewer.com/English/discussion/143708/uac-secure-desktop-lockout-persists-on-domain-joined-pcs-even-with-windows-authentication (title only read)
- S9 https://www.teamviewer.com/it/global/support/knowledge-base/teamviewer-remote/security/teamviewer-black-screen/
- S10 https://www.teamviewer.com/en/Insights/unattended-access-security/
- S11 https://www.teamviewer.com/it/global/support/knowledge-base/teamviewer-remote/security/teamviewer-and-scamming/
- S12 https://www.theregister.com/2016/06/01/teamviewer_mass_breach_report ; https://www.neowin.net/news/teamviewer-ratchets-up-account-security-with-trusted-devices-and-data-integrity-features/ ; https://www.tripwire.com/state-of-security/teamviewer-hack-pc-hijack
- S13 https://pricingsaas.com/companies/teamviewer ; https://capterra.com/p/194565/TeamViewer/pricing/ ; https://nerdbot.com/?p=312052
- S14 https://www.bleepingcomputer.com/news/security/anydesk-says-hackers-breached-its-production-servers-resets-passwords/
- S15 https://support.anydesk.com/docs/wake-on-lan.md
- S16 https://support.anydesk.com/docs/administrative-privileges-and-elevation-uac.md
- S17 https://support.anydesk.com/Unattended_Access ; https://support.anydesk.com/advanced-options
- S18 https://www.splashtop.com/blog/anydesk-price-increase (competitor) ; https://tsplus.net/anydesk-pricing (competitor) ; S18b https://www.splashtop.com/blog/connectwise-screenconnect-price-increase (competitor)
- S19 https://anydesk.com/en/commercial-use ; https://rustdesk.com/blog/anydesk-commercial-use-detected (competitor) ; https://www.anyviewer.com/how-to/anydesk-commercial-use-detected-2578.html
- S20 https://www.incibe.es/en/incibe-cert/early-warning/vulnerabilities/cve-2025-34499 ; https://zerodayinitiative.com/advisories/ZDI-26-401 ; https://zerodayinitiative.com/advisories/ZDI-26-400 ; https://labs.cloudsecurityalliance.org/wp-content/uploads/2026/10/CSA_research_note_anydesk_anypwn_silent_patch_exploit_20261011-csa-styled.pdf ; S20b https://wikipedia.com/wiki/AnyDesk
- S21 https://anydesk.com/on-premises ; https://anydesk.com/en/performance
- S23 https://rustdesk.com/blog/rustdesk-and-remote-access-scams
- S24 https://github.com/rustdesk/rustdesk/discussions/1249
- S25 https://github.com/rustdesk/rustdesk/discussions/6444
- S26 https://nvd.nist.gov/vuln/detail/CVE-2024-25140 ; https://zerodayinitiative.com/advisories/ZDI-26-117 ; https://soc.cyber.wa.gov.au/advisories/20260309001-Rustdesk-Vulnerabilities-and-POC/ ; https://nvd.nist.gov/vuln/detail/CVE-2026-57850
- S27 https://rustdesk.com/pricing ; https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/faq ; https://rustdesk.com/docs/en/self-host/client-configuration/ ; S27b https://rustdesk.com/docs/ja/self-host/rustdesk-server-pro/faq/ (relay error text) and https://dietpi.com/forum/t/rustdesk-new-installation-and-configuration/20299 (LAN bypasses relay)
- S28 https://github.com/rustdesk/rustdesk/issues/2166 ; https://github.com/rustdesk/rustdesk/issues?q=is%3Aissue+%22UAC%22+OR+%22lock+screen%22+OR+%22login+screen%22+sort%3Acomments-desc ; https://github.com/rustdesk/rustdesk/issues?q=is%3Aissue+label%3Abug+sort%3Areactions-%2B1-desc ; S28b https://rustdesk.com/blog/rustdesk-connected-waiting-for-image ; S28c https://github.com/rustdesk/rustdesk/issues/7530
- S29 https://scribe.disroot.org/comment/7085887 ; https://github.com/rustdesk/rustdesk-server/discussions/297 ; https://en.wikipedia.org/wiki/RustDesk
- S30 https://support-splashtopbusiness.splashtop.com/hc/en-us/articles/49413740529307-Remote-Wake-Wake-on-LAN ; https://www.splashtop.com/features/remote-wake ; https://support-splashtoponprem.splashtop.com/hc/articles/214200606 ; S30b https://support-splashtopbusiness.splashtop.com/hc/en-us/articles/212724063-Display-Issues-or-Black-screen-when-I-establish-a-remote-session-to-a-headless-Windows-PC ; S30c https://support-splashtopbusiness.splashtop.com/hc/articles/360049281831-User-Guide-for-the-WoL-Checking-Tool
- S31 https://www.capterra.com/p/162972/Splashtop-Business-Access/pricing/ ; https://nvd.nist.gov/vuln/detail/CVE-2020-12431 ; https://tenable.com/cve/CVE-2024-42050 ; https://nvd.nist.gov/vuln/detail/CVE-2024-42053
- S32a https://www.huntress.com/blog/a-catastrophe-for-control-understanding-the-screenconnect-authentication-bypass ; S32b https://screenconnect.com/pricing ; S32c https://screenconnect.product.connectwise.com/communities/1/topics/2460-support-for-connecting-to-a-headless-endpoint-windows-computer-without-a-monitor-plugged-in ; https://screenconnect.product.connectwise.com/communities/1/topics/922-blank-screen-when-connecting-to-machines-running-windows-10 ; https://community.goto.com/discussion/317523/unattended-access-connecting-into-rdp-sessions-on-windows-server-instead-of-to-the-console ; S32d https://nvd.nist.gov/vuln/detail/cve-2024-1709 ; S32e https://nvd.nist.gov/vuln/detail/CVE-2025-3935 ; S32f https://www.bleepingcomputer.com/news/security/connectwise-breached-in-cyberattack-linked-to-nation-state-hackers/ ; S32g https://www.helpnetsecurity.com/2025/06/11/connectwise-is-rotating-code-signing-certificates-what-happened/ ; S32h https://www.huntress.com/blog/cve-2026-84869-screenconnect-technician-exploitation ; https://thehackernews.com/2026/11/connectwise-warns-screenconnect-attacks.html ; https://bleepingcomputer.com/news/security/active-screenconnect-attacks-breach-msps-impact-dozens-of-organizations
- S33a https://www.cisa.gov/ncas/alerts/aa23-025a ; https://www.cisa.gov/news-events/cybersecurity-advisories/aa25-163a ; S33b https://www.microsoft.com/en-us/security/blog/2024/05/15/threat-actors-misusing-quick-assist-in-social-engineering-attacks-leading-to-ransomware/
- S34a https://chromium.googlesource.com/chromium/src/+/f303bc03a281b55dbd066185f79daa61dd8ba8d1/remoting/GEMINI.md ; https://support.google.com/chrome/a/answer/16364503 ; https://support.google.com/chrome/a/answer/2799701 ; https://www.anyviewer.com/how-to/chrome-remote-desktop-limitations-2578.html (low quality)
- S34b https://docs.meshcentral.com/design/ ; https://github.com/Ylianst/MeshCentral ; https://ideaproof.io/open-source/project/meshcentral (aggregator) ; S34b2 https://raw.githubusercontent.com/Ylianst/MeshCentral/master/meshuser.js ; S34b3 https://www.github.com/Ylianst/MeshCentral/discussions/6054
- S34c https://kb.nomachine.com/?p=813 ; https://www.nomachine.com/nomachine-features
- S34d https://www.dwservice.net/en/home.html ; https://github.com/DWService-remote-access/
- S34e https://www.capterra.com/p/112011/Zoho-Assist/pricing/ ; https://help.zoho.com/portal/en/community/topic/unattended-access-black-screen
- S34f https://www.capterra.com/p/169762/HelpWire/reviews/
- S34g https://github.com/immense/Remotely ; https://devolutions.net/blog/devolutions-announces-a-major-2-year-sponsorship-of-controlr/
- S35 https://o365hq.com/md/blog/quick-assist-is-no-longer-available-as-a-built-in-app-for-windows-10-and-windows-11 (low authority) ; S35b https://learn.microsoft.com/en-us/answers/questions/2195042/lock-screen-via-microsoft-remote-desktop-shows-no ; https://learn.microsoft.com/en-us/answers/a/1952362
- S36 https://remoteutilities.com/support/docs/wake-on-lan ; https://support.logmein.com/resolve/help/how-to-wake-a-computer-in-sleep-mode-or-powered-off-using-wake-on-lan
