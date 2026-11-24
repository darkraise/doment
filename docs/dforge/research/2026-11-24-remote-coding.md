# Remote terminals, remote development and AI-agent session managers: competitor research

Date of research: 2026-11-24. Track: remote terminal and remote development tools, and how developers experience remote work.
Convention: `[Sn]` is the source URL in the list at the end. "Inference" marks my own reasoning. "Unverified" means I could not confirm it from a primary source. Many AI-agent tools change monthly; versions and dates are as seen on 2026-11-24.

## 0. Summary

- The market has already converged on the product shape: a daemon on the user's machine, an encrypted relay, a phone app, a session list with states (working, needs input, done), and a worktree per agent. Paseo, Happy, Nimbalyst, cmux and Claude Code itself (Remote Control plus agent view) are the main examples (section 5).
- None of them is a remote-desktop product. None offers pixels and a native terminal channel to the same Windows host, and most are macOS-first (section 8).
- The largest unsolved problem is reliability of reconnecting and re-listing sessions. Claude Code Remote Control has many closed-as-stale reports of dropped, delisted, or unrecoverable sessions (section 5.2).
- On Windows, the host terminal service has hard constraints: ConPTY quirks, process-tree cleanup, Session 0 isolation, and sessions killed when the SSH connection ends (section 7).
- Pixel streaming is disliked for text because of 4:2:0 chroma, keyboard mapping, and scaling. Developers say they prefer RDP for text, which sends more of the desktop as structured data (section 6).

## 1. Session persistence and multiplexing (tmux, Zellij, WezTerm, screen, lightweight tools)

Capabilities and what makes sessions survive:
- tmux, screen and Zellij run a server process that owns the PTYs. A client disconnect only detaches the client. This is why they remain the standard answer for "my process must survive". Even Cursor staff and Windows Terminal threads point users to tmux for this [S42, S64a].
- Zed's RFC states the root cause plainly: when the UI owns the PTY master, closing it sends SIGHUP to the shell. Their proposed design is a one-process-per-terminal daemon holding a headless terminal emulator (alacritty_terminal) that sends a serialized screen snapshot on reattach, then SIGWINCH to the foreground process group so full-screen apps redraw [S32]. Design idea worth copying: state snapshot instead of raw byte replay.
- shpool keeps an in-memory render of the terminal for redraw on reattach but passes raw output through, so native scrollback and copy/paste still work; one client per session. zmx keeps state and scrollback server-side using ghostty-vt. dtach and abduco only pass raw bytes [S63]. Details of dtach/abduco redraw were not confirmed.
- WezTerm offers unix, SSH and TLS multiplexer domains. TLS domains bootstrap over SSH then reconnect automatically with a certificate [S31a]. WSL2 cannot use the unix-domain path (no AF_UNIX interop) [S31a].

Documented pain points:
- Key-binding conflicts: Zellij's defaults collide with editors (Ctrl+O is Zellij session mode and vim jump-forward). Zellij 0.41 added an "unlock-first" preset [S30a]. A tracked issue shows Zellij's Ctrl+B intercepting Claude Code's Ctrl+B background-task key [S30b].
- Clipboard: tmux copy to the local clipboard relies on OSC 52, `set-clipboard`, a terminfo `Ms` capability and terminal support; nested tmux needs it on every layer; VTE terminals print garbage [S29]. tmux 3.3 turned `allow-passthrough` off by default, which breaks tools that wrap OSC 52 in a DCS passthrough envelope [S66a, S66b].
- Rendering of full-screen TUIs inside tmux: Claude Code reports of flicker with no synchronized output, duplicated scrollback on resize, and ghost input boxes in tmux panes [S64b]. Anthropic ships a flicker-free mode (`CLAUDE_CODE_NO_FLICKER=1`) as the documented mitigation [S64c].
- Double terminal emulation and scrollback confusion are cited by Zed users as the reason they dislike tmux/zellij inside their editor [S32].
- WezTerm: SSH-domain connections corrupt when the remote shell rc prints output; one user reports an SSH domain only worked if a unix-domain daemon already ran on the host [S31b].
- No native Windows tmux. psmux (Rust, MIT, ConPTY-based, reads `.tmux.conf`) fills this; about 3.9k GitHub stars [S62]. Claude Code has an open request for agent-team support via psmux [S76].

Design ideas to copy: server-side VT state with snapshot on attach; keep native scrollback in the client where possible; make the client a thin viewer so the server survives UI crashes and updates.

## 2. Latency-tolerant remote terminals (mosh, Eternal Terminal, successors)

- mosh: UDP, roaming across networks, predictive local echo (including in vim), logs in over SSH, no daemon, no root. Limits stated by the project: no scrollback (only visible screen is synchronized), UDP ports 60000-61000 required, UTF-8 locale mandatory, no native Windows build, escape key Ctrl-^ awkward on some layouts [S24].
- Scrollback has been requested since 2011; the tracking issue was removed from the "mosh-future" milestone in 2023 and a user on 2026-09-27 reports it still does not work, with no maintainer reply [S25]. A maintainer said the gap is limited developer time, not philosophy (2020) [S25]. The latest release shown is 1.4.0 on "27 Oct"; the page omits the year (commonly 2022; year Unverified) [S26].
- Claude Code users report scrolling over mosh cycles through input history instead of conversation history [S67].
- Eternal Terminal: TCP, native scrollback, reconnect. v7.0.0 (07 Jul) added sessions that stay alive while the client is disconnected and Windows tunnelling; v7.1.0 (28 Oct) added a Windows build and test parity, named sessions, OpenSSH-style short flags, and a control socket; v7.1.1 on 29 Oct. The release page omits years, so I infer 2026 but did not verify [S27]. Earlier blog claims that ET was stalled at 1.4.0 are therefore out of date [S27].
- Successors are young and mostly unproven: koh (Rust, iroh/QUIC, predictive echo plus detach/reattach, no SSH server needed), morsh (QUIC, TLS 1.3, connection migration), tsshd (UDP, QUIC or KCP, local echo "Not Planned"), Osewa (QUIC or WebSocket after SSH key exchange, no local echo yet), RoSE (QUIC with wezterm's emulator, scrollback plus detach) [S28]. I did not confirm SSH3 or any widely adopted QUIC shell. Treat all as immature (2026).
- Common practice for phones: Termius or Blink with mosh over Tailscale, then reattach tmux; "mosh handles the link, tmux handles scrollback" [S70]. Blink's reviewers complain that mosh without tmux gives no scrollback and tmux mouse mode is off by default [S44b].

Design ideas to copy: roaming keyed on authenticated packets rather than IP; local prediction clearly marked (underline); network-independent session identity; keep scrollback client-side or server-replayed.

## 3. Remote development environments

- VS Code Remote-SSH / Tunnels: thin client plus a server installed on the host. Tunnels use Microsoft dev tunnels (outbound connection to Azure, no listener, SSH inside the tunnel), require a GitHub or Microsoft login, allow 10 tunnels per account, are "designed for one user or client at a time", can run as a service (`code tunnel service install`), and need acceptance of server licence terms [S34]. Remote-SSH failures are dominated by server install: install script written to and executed from a temp dir, timeouts, glibc incompatibility, and stale server processes; the official fix is "Kill VS Code Server on Host" [S35].
- Licence restriction: Microsoft's Remote-SSH extension works only in Microsoft builds of VS Code; Cursor and others had to ship their own remote extensions, and community open-remote-ssh is the workaround [S36]. code-server cannot use the Microsoft Marketplace and uses Open VSX [S38]. Takeaway (inference): do not depend on Microsoft's remote components in a product that is not VS Code.
- JetBrains: Gateway is slated for deprecation in favour of the Toolbox app, which adds a Toolbox Agent; with Gateway only Linux servers are supported, with Toolbox macOS and Windows hosts too (2026.1 docs). No end date found [S37].
- Zed: local UI, headless Zed server on the remote; one SSH ControlMaster per project multiplexes protocol, terminals and tasks; on drop it reconnects to the running daemon, else restores unsaved changes. Windows client works, Windows as host is not described. Remote terminals do not get persistence today and die like local ones (RFC) [S33, S32].
- Coder: control plane plus a workspace agent in each workspace; IDE connections use SSH, web terminals a WebSocket, all over one Tailnet connection via DERP or direct. Its new agents feature runs the agent loop on the control plane and shell execution in the workspace [S39]. A reconnecting-PTY detail was not confirmed.
- GitHub Codespaces: default idle timeout 30 minutes (configurable 5 minutes to 4 hours); reconnecting does not affect running processes, but visible terminal contents are not preserved across sessions [S40].

What fails (recurring): server install and version skew, reconnect that loses terminal state, extension host differences, licence limits, and a model that assumes an IDE rather than a terminal. Design ideas to copy: Zed's ControlMaster-style single multiplexed connection; Coder's one tunnel for all channels; VS Code Tunnels' outbound-only connection with no inbound port.

## 4. Terminal apps with sync or remote features

- Warp: Agent Management Panel and Oz web app list local and cloud agent runs with states Working, Blocked, Canceled, Failed, Success; the Runs page works on mobile; sessions can be shared. The page does not document push notifications or steering a running agent [S23]. Account login is required for the CLI (browser flow).
- Termius: vault is end-to-end encrypted with a key derived from the user's password (vendor claim). Reviewers say cloud sync and SFTP sit behind the paid tier; one user cites contracts that forbid storing credentials on third-party cloud (single anecdote) [S45].
- Blink Shell (iOS): mosh sessions that survive device reboot, `code` command for VS Code, paid tiers. Tessera is a newer iOS SSH/Mosh/tmux client with tmux windows as tabs (vendor listing) [S44a].
- Windows Terminal: session restore (since Preview 1.21) restores screen contents on startup, not live processes; requests for detach and reattach were closed as duplicates, and a user lost running scripts when the Store updated the app [S42]. No remote features.
- Tabby: Unverified (nothing found).
- ttyd, GoTTY, Wetty: no authentication by default (ttyd needs `-c`); no session management of their own; the common pattern is to run them against a named tmux session, with `-m 1` to avoid multi-tab resize fights; reconnect only restores the browser link, not the shell [S43].
- Tailscale SSH: identity from the tailnet instead of SSH keys, "check mode" re-authentication (12 hours by default). The server runs only on Linux and open-source macOS builds, not Windows. Restarting `tailscaled` ends active SSH sessions; port 22 only. Session recording is documented as beta on one page and deprecated (support ends August 2027) on another; conflicting, verify [S41].

Design ideas: identity-based access instead of key files; share the agent session as a link; one account-free path for self-hosters (Paseo advertises no forced login) [S15].

## 5. Managers for multiple AI coding-agent sessions

### 5.1 What exists (as of 2026-11-24)

- Claude Code Remote Control: continues a local session from claude.ai/code or the Claude mobile app; the host makes only outbound HTTPS calls, never opens inbound ports, and traffic routes through the Anthropic API over TLS. Server mode (`claude remote-control`) hosts up to 32 concurrent sessions (`--capacity`) with `--spawn worktree` for one git worktree each. Mobile push notifications for "actions required" and "Claude decides"; push is suppressed while the user is at the terminal. Permission prompts and questions stay open until answered. Limits: one remote session per interactive process outside server mode; server mode gives up after about 10 minutes of network outage and exits; other dialogs expire after 5 minutes [S1].
- Claude Code agent view (`claude agents`, research preview, announced 2026-05-11): one screen for background sessions with states Working, Needs input, Idle, Completed, Failed, Stopped; groups Pinned, Ready for review, Needs input, Working, Completed; peek and reply inline; attach, detach; `claude --bg`, `/bg`; a supervisor process keeps sessions alive after the terminal closes; unattended finished sessions stop after about an hour; sleep preserves sessions, shutdown stops them (sessions with progress in the last 48 hours show as failed and restart on attach); on macOS and Linux sessions stop if no new supervisor connects within about a minute; each session moves into its own git worktree on first edit; `claude agents --json` for scripts; notifications only while agent view is open. Windows support: the excerpt I read did not cover it (Unverified) [S2, S3].
- Claude Code hooks expose the status signals other tools can use: `Notification` types (`permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`, `agent_completed`), `Stop`, `StopFailure`, `PermissionRequest`, `SessionStart/End`, with `session_id`, `cwd`, `transcript_path` in the payload [S4]. A host-side agent can derive a status model from these (inference).
- cmux (manaflow-ai; macOS native, Swift/AppKit, libghostty): vertical tabs showing branch, PR status, ports, latest notification; attention via OSC 9/99/777 or `cmux notify` from agent hooks; blue ring on panes; scriptable browser; `cmux ssh`; iOS app in TestFlight beta; session restore does not restore live processes unless `cmux local-tmux` or `local-zellij` is used; GPL-3.0 with BSL for server parts [S8]. Launch motivation: Claude Code's notification text did not say which session needed attention [S9].
- Happy (slopus; MIT): CLI wrapper `happy claude` / `happy codex`, relay server with end-to-end encryption, native iOS and Android apps, push via APNs/FCM worker, share a session with a colleague [S10]. A troubleshooting guide (a third-party mirror) lists "sessions start but do not sync" fixed by restarting the daemon, and stale `daemon.lock` files [S11a]. An issue reports permission prompts becoming stuck when the mobile client drives a daemon session (seen via search, page not opened) [S11b].
- Omnara: began as a mobile and web dashboard that wrapped Claude Code with approvals and diff review (Show HN, about 295 points); its repository now describes a different product, a self-hostable agent platform with its own cloud (README, Apache-2.0). Treat the original wrapper as superseded [S12].
- Paseo (Apache-2.0, one maintainer): daemon runs headless on a laptop, VM or home lab; desktop, web, CLI and native mobile clients; optional end-to-end encrypted relay or Tailscale/SSH; worktrees; terminals and built-in browser; voice (local by default); MCP/CLI/SDK; many agents via ACP; macOS, Linux, Windows, iOS, Android claimed [S14, S15]. Closest to the product concept.
- Conductor (Melty Labs): macOS Apple Silicon app, Claude Code and Codex in worktrees, diff view, PR flow; Windows only a waitlist; paid Pro with cloud workspaces and mobile "coming soon" per a competitor's comparison page [S21].
- Crystal (Stravu) was deprecated in February 2026 for Nimbalyst (parallel worktree sessions, kanban, iOS app) [S18]. Vibe Kanban's company Bloop shut down on 2026-04-10; the project continues as community-maintained open source and the hosted services were wound down after 30 days [S13]. Superset, Emdash, Herdr, Orca are others; Emdash lists Windows and SSH remote dev; Superset's own pages disagree about Windows (Unverified) [S21b].
- claude-squad: tmux sessions plus worktrees in a terminal UI (Go). Native Windows fails because session creation uses a PTY library without ConPTY support (issue #275) [S22].
- herdr (Apache-2.0, Rust): a background server keeps terminals alive when the client or SSH connection drops; panes marked working, blocked or idle; local and saved SSH machines in one agent list; Windows in preview; its Windows keyboard routing needed fixes for Escape, Shift+Enter and Ctrl+Space [S16, S17].
- Warp's agent panel and Oz (section 4) are the commercial terminal vendor's version [S23].
- Tmux-based DIY: status line with blue working, orange blocked, green finished-unseen, notifications that retract when the pane is viewed [S20]; many small projects (Pitboss, ClaudePM, claws) exist, reported only via search snippets [S71].

### 5.2 What users complain about

- Reconnect and listing reliability (Claude Code Remote Control): session delisted 10-15 minutes after the viewing device disconnected while the host process was fine, with the session id rotating (Windows 11 host, 2026-07-14, closed "not planned" 2026-09-02) [S5]; connection dying overnight while the tmux-hosted process stayed alive (2026-02-26, closed stale) [S6]; automatic reconnection not working, sessions permanently losing sync, no way to delete dead sessions, sessions not surviving reboot (issues #34255, #34531, #36401 seen as GitHub links; reboot and delete issues seen as titles only) [S68].
- Cannot start a new session from the phone; auth expiry needs the host's screen; `git push` fails over SSH because credentials sit in the macOS Keychain [S7].
- "Which session needs me" lacks context: an alert saying "session 3 needs input" is not enough to answer from a phone; a session list row hides the work; reviewing coupled changes across sessions needs a combined diff; transcripts are trapped in each tool [S19, S9].
- Parallel agents: worktrees move conflicts to merge time; review bandwidth caps useful parallelism at roughly two to five sessions; setup cost in big monorepos; port collisions between dev servers (practitioner blogs, not surveys) [S72].
- Tool churn and viability: Crystal deprecated, Vibe Kanban's company closed, Omnara pivoted (2026). Open source plus local-first is the survivor pattern (inference) [S13, S18, S12].
- Platform: most orchestrators are macOS-only; Windows is waitlist, preview or beta [S21, S16, S22].
- Process hygiene: Windows reports of orphaned worktree agent processes holding directory locks, and `--tmux --worktree` creating worktrees where the agent never starts (seen as titles in search) [S73].

Design ideas worth copying: worktree per session created lazily on first edit (agent view); an explicit state machine with "ready for review" separate from "completed"; peek-and-reply without attaching; notification suppression when the user is present, with a presence file hook (Remote Control docs); alerts that retract when viewed; one-line model-written summaries per row; machine-readable `--json` state; end-to-end encrypted relay with an option to self-host.

## 6. Pixel remote desktop for coding (Parsec, RDP, Moonlight/Sunshine, RustDesk, Jump Desktop)

- Chroma subsampling: streaming codecs default to 4:2:0, which smears coloured text. Citrix HDX also defaults to 4:2:0 and documents 4:4:4 as a higher-bandwidth option [S47b]. Parsec has a "Prefer 4:4:4 Color" overlay setting (support article; I could not open it, so details such as GPU requirements are Unverified) [S46a]. A Sunshine commenter says Parsec's 4:4:4 relies on NVIDIA's encoder (user comment).
- Sunshine/Moonlight 4:4:4: requested since April 2023; maintainers listed blockers: no standard DXVA HEVC 4:4:4 decode profile, AMD has no 4:4:4 hardware decode, SDL cannot take 4:4:4 textures, no AV1 4:4:4 encode in current hardware; test PRs existed in 2024; I could not confirm they merged (no progress shown as of January 2025) [S47].
- RDP: default chroma is 4:2:0 for AVC; AVC 444 is enabled by group policy "Prioritize H.264/AVC 444 Graphics mode" plus "Configure image quality for RemoteFX Adaptive Graphics: High", and Microsoft says GPU acceleration is not required to change chroma [S48a]. Microsoft documents a "halo effect" for text with typical AVC and presents AVC 444 as the fix; Event ID 162 shows whether AVC 444 is in use (2016 blog) [S48b]. One user reported audio/video desync after enabling it (anecdote).
- Why developers prefer RDP for text: HN commenters say RDP degrades as lag on bad links, not as compression artefacts; it renders much of the desktop client-side with far less bandwidth; clipboard and peripherals integrate better. Counter-views: Sunshine/Moonlight is better for games and high refresh, and "not nearly as responsive for dev tasks" for one commenter [S49]. This is anecdote, not measurement.
- Keyboard: modifier mapping is the top complaint. Moonlight issue #980 (open since April 2023): users want Cmd/Option or Cmd/Ctrl swapped, system-wide macOS remaps affect the Mac itself, and Sunshine key-code swaps only partly work (Win+E, Win+D, Win+L still send Alt) [S51]. RustDesk's umbrella keyboard issue #4367 (open since May 2023, about 40 linked issues) lists missing ":" from Mac US to Windows Japanese layout, Escape/Caps swap on Hyprland sending both keys, Backspace failing in Terminal, sticky Fn, Wayland lacking translate mode; maintainers suggest "translate mode" for layouts and label it low priority [S50]. Jump Desktop converts Mac and Windows shortcuts automatically but Cmd+Tab and Mission Control stay local unless "macOS Shortcuts" passthrough is toggled; Parsec on macOS needs accessibility permission and immersive mode for Cmd+Tab [S52, S46b].
- Dead keys and IME: RDP clients on Android, iOS and web have unresolved dead-key and IME reports; the usual cause is Unicode versus scancode input mode, and the `IgnoreRemoteKeyboardLayout` registry value helps only sometimes [S53a]. I found no Parsec, Moonlight or Sunshine IME documentation (Unverified).
- Key repeat and typing latency: no authoritative source found; Unverified.
- HiDPI and resolution matching: the Windows App/Remote Desktop client on Mac shows a trade-off between sharp scaled rendering and blur when "Optimize for Retina" is off, and blur after window resizing; NoMachine forces pixel doubling; Jump Desktop users report blur when the window is near but not exactly the remote resolution [S53b, S53c].
- Clipboard: Sunshine/Moonlight pastes client-to-host via a shortcut but cannot copy host-to-client in one reported version [S54]; RDP is reported as better here [S49].
- Multi-monitor: no solid source collected; Unverified.

Takeaway (inference): a pixel product needs 4:4:4 or lossless text regions, per-key scancode plus Unicode input with an explicit layout negotiation, a documented modifier-mapping table, and exact-resolution/scale matching. A text channel sidesteps most of this for terminal work.

## 7. Windows-host specifics

ConPTY (pseudoconsole):
- API: `CreatePseudoConsole` with two synchronous pipes and size; attach via `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`; `ResizePseudoConsole`; `ClosePseudoConsole` terminates the whole attached process tree. Microsoft warns to service each pipe on its own thread because closing emits a final frame and can deadlock; handles given at creation must be closed in the host after process creation so broken pipes are detected [S55].
- Pitfalls from a third-party library write-up (not Microsoft): before Windows 11 24H2 (build 26100) output EOF does not arrive after child exit unless the pseudoconsole is released, and without it EOF takes about one second; builds with `ReleasePseudoConsole` do not wait on readers; closing the input pipe kills the child with 0xC000013A and loses unflushed output; output is a VT stream where chunks can split UTF-8 or escape sequences; a resize makes the host repaint and re-emit the screen; `PSEUDOCONSOLE_INHERIT_CURSOR` sends a cursor query and stalls input until answered; killing the root process leaves descendants, so use a job object, and the console host sits outside that job; non-inheritable handles are needed or EOF never comes [S56].
- Fidelity: ConPTY re-renders instead of passing bytes through. Passthrough mode is discussed upstream because entering and leaving it requires trashing the buffer (#1173) [S57c]; sixel and other DCS content are affected (Contour and Cygwin discussions, search results only) [S74]. Third-party notes say ConPTY may consume mouse mode DECSETs 1000/1002/1003/1006 so the app must re-send them (psmux note, unverified upstream) [S74].
- Input: win32-input-mode wraps keys; issue #15083 shows mouse events double-encoded in it (open; reported still present in 1.22 for X10 mouse and bracketed paste; SGR mouse works) and an app killed while in this mode can leave the shell affected [S57a].
- Resize: when the ConPTY buffer is smaller than existing output, enlarging the window overwrites output with the shorter buffer; `PSEUDOCONSOLE_RESIZE_QUIRK` expects the host terminal to reflow itself [S57b]. Claude Code has an open report of stale width after resize on Windows ConPTY and scrollback corruption on monitor change (search titles) [S74b].
- Windows key records: herdr found that reducing native key records to cross-platform key plus modifiers loses information, causing Escape, Shift+Enter and Ctrl+Space bugs; fix was forwarding the native record [S17].

OpenSSH Server on Windows [S58]:
- Default shell is cmd.exe unless the `DefaultShell` registry value is set; administrators use `%programdata%\ssh\administrators_authorized_keys` with strict ACLs; only password and publickey auth; no Entra ID auth; many sshd options are missing (no `AcceptEnv`, `KbdInteractiveAuthentication`, `X11Forwarding`, `PermitUserEnvironment`).
- Session lifetime: the sshd job object kills child processes when the session ends, same as POSIX; a Win32-OpenSSH maintainer suggests spawning via WMI `Win32_Process.Create` to escape the job (search result, not opened) [S59]. A Server 2019 report shows sshd and conhost processes left after logout (search result) [S59].
- Therefore SSH alone does not give persistence on Windows; this is why a host service that owns the PTY is needed (inference).

WSL: a WSL2 distro stops soon after its last terminal closes (about 15 seconds in one report), regardless of `vmIdleTimeout`, and tmux does not prevent it; `vmIdleTimeout=-1` regressions reported in 2.5.7+ [S60]. A host service must keep WSL alive or launch WSL terminals through a persistent process.

Service versus user session:
- Services run in Session 0 (non-interactive). To act inside a user's desktop session, a service gets the token with `WTSQueryUserToken` and uses `CreateProcessAsUser`; the process's session comes from the token [S61]. SE_TCB privilege is required (forum claim). Elevated tokens and the linked-token mechanism for UAC were not confirmed (Unverified). Inference: a terminal service run as a service can still launch shells as the logged-in user, but it cannot show GUI to a locked or logged-out desktop, and an elevated shell needs an explicit, user-visible decision.
- PowerShell remoting: not researched in depth (Unverified).
- Windows Terminal cannot detach; session restore only restores screen text [S42].

## 8. Product angle: closest tools and the gap

Closest, ranked by overlap with "remote desktop plus native terminal channel plus dashboard plus mobile":
1. Paseo: host daemon, encrypted relay, mobile, worktrees, terminals, multi-host, Windows claimed. Missing: pixel/desktop streaming, broad session persistence of arbitrary shells beyond its agents (Unverified), dashboard across many hosts (partly) [S14, S15].
2. Claude Code Remote Control plus agent view: first-party, but Claude Code only, list is per machine/account, reliability issues, no arbitrary terminals [S1, S2, S5].
3. herdr: persistent terminals, state detection, local plus SSH machines in one list, Windows preview; no mobile mentioned [S16].
4. Happy and Nimbalyst: phone clients for agents; not full terminal estate [S10, S18].
5. cmux: best attention UX in a terminal app; macOS only, no live process persistence without tmux, iOS beta [S8].
6. Warp/Oz: management panel across local and cloud; vendor-hosted [S23].
7. DIY: Tailscale or SSH plus mosh plus tmux plus Termius/Blink [S70]; works but is manual and weakest on Windows hosts (Tailscale SSH server unsupported on Windows [S41], tmux not native [S62]).
8. Remote desktop apps (Parsec, RDP, Jump, RustDesk): none ships a text terminal channel (inference; I found none).

Gaps none fills (inference from the above):
- One agent on a Windows host that offers both pixels and persistent ConPTY terminals under one identity, one relay, one session list.
- Cross-vendor, cross-host session inventory with uniform states, for arbitrary agents and plain shells, including Windows.
- Terminal sessions that survive client disconnect, sleep and client-app update, with recoverable listing (no delisting while the host process lives).
- Honest recovery model on host reboot (what resumes, what does not) displayed in the UI.
- Notifications with enough context to act (what is asked, which tool, diff summary) and approve or deny from the phone, without opening a full desktop.
- Seamless switching between text view and pixel view of the same machine (for GUI prompts such as UAC, browser logins, OAuth that need the host screen) [S7].
- First-class handling of Windows realities: ConPTY fidelity, process-tree cleanup, WSL keep-alive, elevation.

## 9. Recurring complaints and root causes

| Complaint | Root cause | Where |
|---|---|---|
| Session vanished or cannot reattach | Session identity tied to a live viewer or process; no server-side registry that outlives the transport | S5, S6, S68 |
| Process died with the UI | UI owns the PTY master | S32, S42 |
| No scrollback, odd scroll | State synchronisation instead of stream; or double emulation | S25, S32, S44b |
| Key-binding clashes | Multiplexer and app both claim the same chords | S30a, S30b |
| Clipboard broken over SSH or nesting | OSC 52 plus passthrough defaults, per-layer config | S29, S66 |
| TUI flicker/duplicate scrollback in multiplexers | Missing synchronized output; resize repaints | S64b |
| Blurry text in streams | 4:2:0 chroma, hardware 4:4:4 gaps | S47, S48 |
| Wrong modifiers and layouts | Key events sent as OS-specific codes without layout negotiation | S50, S51, S53a |
| Server install and skew failures | Thin client needs matching host binary and glibc | S35, S33 |
| Tool abandoned or pivoted | Hard monetisation; platform-first apps | S13, S18, S12 |
| Windows sessions die on disconnect | Job object, no detach primitive, ConPTY lifetimes | S59, S56 |
| Alert without context | Generic notification text | S9, S19 |

## 10. Gaps and opportunities

- Own the Windows host story that macOS-first tools skip (section 7 constraints are product moat if solved).
- Make "attention" a first-class object: needs-input, needs-approval, failed, ready-for-review, with context, deduplicated, retracted when handled, suppressed when the user is present [S1, S20, S9].
- Treat reconnection as the core feature, with tests and public SLOs, since competitors' reconnects are the loudest complaint [S5, S6].
- Combine channels: terminal first for text work, pixels when a GUI is needed, on one authenticated session.
- Offer a self-host path and local-first operation; abandonment risk is a buying criterion [S13].
- Do not rely on tmux or the Microsoft remote components as the foundation (licence and Windows availability) [S36, S62].

## 11. Requirement candidates

Each is checkable and traces to a finding.
Persistence and transport
- R1. Terminal sessions live in a host service that owns the PTY; closing, crashing or updating any client leaves the shell and its descendants running (S32, S42).
- R2. A session stays listed (state "offline viewer" or "idle") for as long as its host process lives; it is never delisted because a viewer disconnected, and its id does not change on reconnect (S5).
- R3. After a client reconnect, the user sees the full current screen from a server-side snapshot within one round trip, then scrollback on demand; a resize triggers a foreground-process redraw signal (S32, S63).
- R4. Reconnect after network loss up to at least 24 hours without user action, and after host sleep and wake; test with a 10-minute and an overnight outage (S1, S6).
- R5. Client scrollback and copy/paste use native client behaviour; no requirement to run tmux or screen inside the session (S25, S44b).
- R6. Optional local echo prediction with visible marking for high-latency links (S24).
- R7. Transport works with UDP blocked (fallback to TCP/WebSocket) and with outbound-only connections from the host (S24, S27, S1, S34).
Windows host
- R8. Pseudoconsole teardown follows the documented drain-and-release sequence on pre-26100 and 26100+ builds, with no deadlock when closing from the reader thread (S55, S56).
- R9. Every session's process tree is in a job object; ending a session kills all descendants, and detaching never does (S56, S59).
- R10. Output is decoded across chunk boundaries; test with split UTF-8 and split escape sequences (S56).
- R11. Resize never overwrites existing output; test shrinking and enlarging while output exceeds the buffer (S57b).
- R12. Mouse modes, bracketed paste and Shift+Enter, Escape, Ctrl+Space reach the app unchanged in a conformance suite run against PowerShell, cmd, WSL, vim, and Claude Code (S57a, S17).
- R13. The service launches shells in the interactive user's token (not SYSTEM) and states in the UI when a session runs elevated; elevation requires an explicit user action on the host (S61; elevation mechanism Unverified).
- R14. WSL terminals are kept alive while a session exists, or the UI states they may stop (S60).
- R15. Default shell is configurable per host; no dependence on `sshd` or the Microsoft OpenSSH job semantics (S58, S59).
Dashboard and status
- R16. A dashboard lists every terminal on every enrolled machine with at least these states: working, needs input, needs approval, idle, done, failed, offline host (S2, S23).
- R17. For Claude Code sessions, status derives from hook events (`Notification` types, `Stop`, `PermissionRequest`) and is updated within a few seconds; for other tools, from output heuristics, marked as lower confidence (S4, S16).
- R18. Each row shows host, working directory, branch, one-line summary, last activity time and pending question (S2, S8, S19).
- R19. Notification text states which session, which host, and what is asked; tapping opens that session (S9, S19).
- R20. A notification is retracted when the session is viewed or answered on any device, and is suppressed while the user is active at that host (S20, S1).
- R21. Approve or deny a permission request from the phone; the request stays pending until answered and survives a viewer disconnect (S1).
- R22. A session started from the phone (new terminal or agent in a chosen host and directory) works without touching the host (S7).
- R23. Worktree-per-session is available and off by default for plain shells; deleting a session never silently discards uncommitted changes (S2).
- R24. A combined diff view for selected sessions in the same repository (S19).
- R25. Machine-readable session state via CLI and local API (S2, S8).
Security and operations
- R26. Hosts connect outbound only; relay payloads are end-to-end encrypted and the relay cannot read terminal content; self-hosting the relay is supported (S1, S10, S15).
- R27. Auth does not depend on Microsoft remote components or on Tailscale SSH (S36, S41).
- R28. Each host action is audited (session start, attach, approve, elevate) and viewable by the owner (inference from S41 recording).
Channels
- R29. From a terminal session the user can switch to the pixel view of the same host in one action, and the reverse, keeping the same authenticated session (gap in section 8).
- R30. Clipboard works both ways between client and host in both channels (S49, S54).
Pixel channel
- R31. A text-optimised mode with 4:4:4 or lossless text regions; verifiable by a test image of coloured 8 to 12 px text (S47, S48a).
- R32. Keyboard mapping table documented per client OS and host OS (Cmd/Ctrl/Alt/Win), with a user-editable remap and a toggle for capturing OS shortcuts (S50, S51, S52).
- R33. Keys are sent as scancode plus resolved Unicode and the host layout is negotiated; dead keys and IME composition tested on US-International, German, French, Japanese (S53a).
- R34. Client window size matches host resolution exactly or the product renders at an integer scale factor; no fractional scaling blur on Retina and 4K (S53b, S53c).
- R35. Unverified areas needing measurement before commitment: typing latency target, key repeat behaviour, multi-monitor handling.

## Not verified

- Tabby features; PowerShell remoting; Parsec 4:4:4 requirements and IME behaviour; Windows support of agent view and Remote Control; SSH3 and any mainstream QUIC shell; mosh 1.4.0 and ET 7.x release years; typing latency, key repeat and multi-monitor complaints; dtach/abduco redraw; Coder reconnecting-PTY; linked-token elevation mechanics; Superset Windows status; Reddit threads (searches returned none from r/commandline, r/neovim, r/ClaudeAI; evidence here is GitHub issues, HN mirrors and blogs).
- `claudeissues.com` mirror URLs could not be fetched; I cite the GitHub issue numbers they mirror. Several issues were known from titles and snippets only (marked).

## Sources

S1 https://code.claude.com/docs/en/remote-control.md
S2 https://code.claude.com/docs/en/agent-view.md
S3 https://claude.com/blog/agent-view-in-claude-code
S4 https://code.claude.com/docs/en/hooks.md
S5 https://github.com/anthropics/claude-code/issues/77340
S6 https://github.com/anthropics/claude-code/issues/28914
S7 https://dev.to/shimo4228/claude-code-from-iphone-plugging-3-holes-in-remote-control-17cf
S8 https://raw.githubusercontent.com/manaflow-ai/cmux/HEAD/README.md
S9 https://cmux.com/blog/show-hn-launch
S10 https://raw.githubusercontent.com/slopus/happy/main/README.md
S11a https://www.mintlify.com/slopus/happy/guides/troubleshooting
S11b https://github.com/slopus/happy/issues/656
S12 https://github.com/omnara-ai/omnara
S13 https://vibekanban.com/blog/shutdown
S14 https://paseo.sh/alternatives/conductor
S15 https://paseo.sh/
S16 https://github.com/herdrdev/herdr
S17 https://github.com/herdrdev/herdr/discussions/1934
S18 https://nimbalyst.com/crystal
S19 https://dev.to/stravukarl/what-actually-breaks-when-you-run-5-claude-code-agents-in-parallel-1lbd
S20 https://www.joshmorony.com/effectively-manage-attention-across-multiple-coding-agents/
S21 https://www.morphllm.com/conductor-ai-coding
S21b https://superset.sh/compare/emdash-alternative
S22 https://github.com/smtg-ai/claude-squad/issues/275
S23 https://docs.warp.dev/agent-platform/cloud-agents/managing-cloud-agents/
S24 https://mosh.org/
S25 https://github.com/mobile-shell/mosh/issues/2
S26 https://github.com/mobile-shell/mosh/releases
S27 https://github.com/MisterTea/EternalTerminal/releases
S28 https://docs.rs/crate/koh/0.12.0 ; https://docs.rs/morsh ; https://trzsz.github.io/tsshd ; https://runtimewire.com/article/osewa-open-source-ssh-mosh-alternative-agent-terminals
S29 https://github.com/tmux/tmux/wiki/Clipboard
S30a https://zellij.dev/tutorials/colliding-keybindings/
S30b https://github.com/ncrmro/keystone/issues/350
S31a https://wezterm.org/multiplexing.html
S31b https://github.com/wez/wezterm/issues/1860
S32 https://github.com/zed-industries/zed/discussions/50584
S33 https://zed.dev/docs/remote-development
S34 https://code.visualstudio.com/docs/remote/tunnels
S35 https://code.visualstudio.com/docs/remote/troubleshooting
S36 https://forum.cursor.com/t/remote-ssh-is-only-supported-in-microsoft-versions-of-vs-code/23918
S37 https://www.jetbrains.com/help/toolbox-app/jetbrains-gateway-migrations-guide.html ; https://www.jetbrains.com/help/idea/2026.1/faq-about-remote-development.html
S38 https://coder.com/docs/code-server/FAQ
S39 https://coder.com/docs/v2.37/ai-coder/agents/architecture
S40 https://docs.github.com/en/codespaces/about-codespaces/understanding-the-codespace-lifecycle ; https://docs.github.com/en/codespaces/managing-codespaces-for-your-organization/restricting-the-idle-timeout-period
S41 https://tailscale.com/docs/features/tailscale-ssh
S42 https://github.com/microsoft/terminal/issues/6808 ; https://github.com/microsoft/terminal/releases/tag/v1.21.1272.0
S43 https://github.com/tsl0922/ttyd ; https://mrkaran.dev/posts/web-terminal-homelab/
S44a https://apps.apple.com/app/blink-shell/id1594898306
S44b https://jblevins.org/log/blink-shell
S45 https://makerstack.co/reviews/termius-review/
S46a https://support.parsec.app/hc/en-us/articles/32381785123860-Improve-Stream-Quality-and-Color-Accuracy
S46b https://support.parsec.app/hc/en-us/articles/32381778420372-Configure-Hotkeys
S47 https://github.com/orgs/LizardByte/discussions/220
S47b https://docs.citrix.com/us/en/citrix-virtual-apps-desktops/2203-ltsr/graphics/thinwire/colorspace.html
S48a https://learn.microsoft.com/en-us/azure/virtual-desktop/graphics-chroma-value-increase-4-4-4
S48b https://techcommunity.microsoft.com/t5/microsoft-security-and/remote-desktop-protocol-rdp-10-avc-h-264-improvements-in-windows/ba-p/249588
S49 https://hn.nuxt.dev/item/43436894
S50 https://github.com/rustdesk/rustdesk/issues/4367
S51 https://github.com/moonlight-stream/moonlight-qt/issues/980
S52 https://support.jumpdesktop.com/hc/en-us/community/posts/38495694603277/comments/40552862793101
S53a https://learn.microsoft.com/en-us/answers/questions/1688517/how-to-write-accents-(dead-keys)-using-android-rem
S53b https://techcommunity.microsoft.com/idea/azurevirtualdesktop/11-pixel-mapping-for-macos-client/3756227
S53c https://support.jumpdesktop.com/hc/en-us/community/posts/42257106470157/comments/42274095009165
S54 https://github.com/LizardByte/Sunshine/issues/1539
S55 https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session
S56 https://docs.rs/crate/conpty-oxide/0.1.2/source/docs/conpty-pitfalls.md
S57a https://github.com/microsoft/terminal/issues/15083
S57b https://github.com/microsoft/terminal/issues/16911
S57c https://github.com/microsoft/terminal/issues/1173
S58 https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration
S59 https://github.com/PowerShell/Win32-OpenSSH/issues/1642 ; https://github.com/PowerShell/Win32-OpenSSH/issues/1195
S60 https://github.com/microsoft/WSL/discussions/8659
S61 https://learn.microsoft.com/en-us/archive/blogs/winsdk/launching-an-interactive-process-from-windows-service-in-windows-vista-and-later
S62 https://github.com/marlocarlo/psmux
S63 https://github.com/shell-pool/shpool ; https://github.com/neurosnap/zmx
S64a https://forum.cursor.com/t/close-terminal-not-kill/148519
S64b https://github.com/anthropics/claude-code/issues/37283
S64c https://code.claude.com/docs/en/fullscreen.md
S66a https://github.com/anthropics/claude-code/issues/20974
S66b https://github.com/anomalyco/opencode/issues/25253
S67 https://github.com/anthropics/claude-code/issues/10010
S68 https://github.com/anthropics/claude-code/issues/34255 ; https://github.com/anthropics/claude-code/issues/34531 ; https://github.com/anthropics/claude-code/issues/36401
S70 https://johnoct.github.io/blog/2026/02/09/iphone-remote-coding-tailscale-tmux-terminus
S71 https://github.com/tholman/pitboss ; https://github.com/adilp/ClaudePM
S72 https://dev.to/jcamarate/claude-code-worktrees-parallel-agents-without-the-conflicts-3fnl ; https://blog.gitbutler.com/parallel-claude-code
S73 https://github.com/anthropics/claude-code/issues/68799 ; https://github.com/anthropics/claude-code/issues/27562 (titles only)
S74 https://sourceware.org/pipermail/cygwin/2020-April/244428.html ; https://docs.rs/crate/psmux/3.3.4/source/src/ssh_input.rs
S74b https://github.com/anthropics/claude-code/issues/80123 (title only)
S76 https://github.com/anthropics/claude-code/issues/34150
