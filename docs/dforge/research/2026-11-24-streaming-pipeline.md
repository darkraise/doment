# Streaming pipeline engineering reference: capture → encode → transport → decode → present

Date: 2026-11-24. Scope: Windows-first host and client in C# with NativeAOT, using OS APIs and GPU-driver interfaces rather than third-party libraries. Labels: **Inference** means my reasoning, not a reported fact. **Unverified** means I could not confirm it from a primary source in this pass.

Headline decisions (Inference, argued below):
- Capture with Desktop Duplication from a SYSTEM agent in the console session; keep Windows.Graphics.Capture for window capture.
- Encode through the vendor SDKs (NVENC, AMF, VPL), which ship inside the drivers. Make D3D12 Video Encode the vendor-neutral path and Media Foundation the last resort.
- Run your own UDP protocol: FEC plus reference-frame invalidation, a delay-based rate controller, and packet pacing. Use QUIC only for non-real-time channels.
- Two drivers are unavoidable for full parity: a virtual display (IddCx, user-mode) and a virtual gamepad. Virtual audio devices are a third, optional one.

## 1. Screen capture on Windows

**Desktop Duplication (DD), `IDXGIOutput1::DuplicateOutput` / `IDXGIOutput5::DuplicateOutput1`.** This is the default in every serious product.
- It returns a GPU texture per output, plus dirty and move rectangles. The pointer comes separately: position every frame, shape through `GetFramePointerShape`, and only when the hardware overlays it rather than drawing it into the image ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)).
- `DuplicateOutput` always converts to BGRA8 ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)). `DuplicateOutput1` takes a list of formats, so you can receive FP16 or R10G10B10A2 for HDR and skip the conversion cost ([MS](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1)).
- Limits: four duplicating processes per session, one duplication per output per process ([MS](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutput1-duplicateoutput)).
- Errors you must handle:
  - `E_ACCESSDENIED` on the secure desktop unless you run as LocalSystem.
  - `DXGI_ERROR_UNSUPPORTED` on desktop switches and mode changes. Wait for `EVENT_SYSTEM_DESKTOPSWITCH` or `WM_DISPLAYCHANGE`, then recreate.
  - `DXGI_ERROR_SESSION_DISCONNECTED`.

  ([MS](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutput1-duplicateoutput))
- Rotation is the caller's job ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)).
- DD delivers a frame only when the screen changes and accumulates updates between calls, so call frequency shapes latency ([MS Q&A](https://docs.microsoft.com/answers/questions/459716/desktop-duplication-api-skip-frame-issue-and-slown.html)).

**Windows.Graphics.Capture (WGC).**
- Available from Windows 10 1803. `IsCursorCaptureEnabled` arrived in 2004. `IsBorderRequired`, `MinUpdateInterval`, `DirtyRegionMode` and `IncludeSecondaryWindows` exist on newer builds ([MS](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession)); exact minimum builds Unverified.
- Sunshine marks WGC beta and "not compatible with the Sunshine service" ([Sunshine config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- Users report WGC capping at about 50 fps on 144 Hz content, and a Windows 11 24H2 regression affecting DD ([robmikh/Win32CaptureSample#82](https://github.com/robmikh/Win32CaptureSample/issues/82)).
- Use WGC for single-window capture and as a fallback. It cannot run headless or from a service (Inference).

**GDI and mirror drivers.** Windows 8 disabled XDDM mirror drivers in favour of DD ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)). GDI `BitBlt` goes through the CPU. A forum post claims Steam's default path is "Desktop BitBlt RGB + libyuv + NVENC HEVC" (Unverified, [Steam forum](https://steamcommunity.com/discussions/forum/1/3758852882958515471)). NvFBC appears as a Sunshine capture option, but on Linux only per its platform notes ([Sunshine config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)). NvFBC on Windows is not an option for a new product (Inference).

**What products use.**
- Parsec: DD, frames stay in video memory and go straight to the encoder ([Parsec blog](https://parsec.app/blog/description-of-parsec-technology-b2738dcc3842)).
- Sunshine: `ddx` by default, `wgc` as beta ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- RustDesk: DXGI with a GDI fallback (Unverified).
- Chrome Remote Desktop (CRD): the WebRTC desktop capturer (Unverified which backend).

**Sessions and desktops.**
- The UAC prompt, the lock screen and the login screen all render on the Winlogon secure desktop. Only a SYSTEM process in the *console session* can open it.
- The capture thread must follow the input desktop: `OpenInputDesktop` + `SetThreadDesktop`, comparing `UOI_NAME`. RustDesk does this, crediting TigerVNC ([rustdesk windows.cc](https://github.com/rustdesk/rustdesk/blob/master/src/platform/windows.cc)), and Sunshine has the same helper ([Sunshine misc.cpp](https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp)).
- Session 0, where services run, has no interactive desktop, so the service has to spawn an agent (see §8).
- Fast user switching changes the console session. Catch `WTS_CONSOLE_CONNECT` and relaunch the agent, as Sunshine does ([sunshinesvc.cpp](https://github.com/LizardByte/Sunshine/blob/master/tools/sunshinesvc.cpp)).
- When someone RDPs into the host, the console session is disconnected and DD returns `SESSION_DISCONNECTED`. Treat that as a "host in use" state (Inference).

**Exclusive fullscreen and VRR.**
- Mode changes by fullscreen games invalidate the duplication, so recreate it. `DuplicateOutput1` hands you the game's native back-buffer format ([MS](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1)).
- With VRR the host frame cadence is irregular. Timestamp each frame and encode on arrival; don't resample to a fixed clock (Inference).
- A second active display can force composed rather than independent flip on the physical monitor ([Blur Busters](https://forums.blurbusters.com/viewtopic.php?p=123497)).

**HDR and wide colour.**
- Capture FP16 (scRGB, linear) through `DuplicateOutput1`. Convert in a shader to BT.2020 PQ in P010 for HEVC Main10 or AV1 10-bit, and send the mastering metadata (Inference).
- Sunshine advertises HEVC Main10 and AV1 10-bit and has HDR workarounds for virtual displays (`dd_hdr_option`, `dd_wa_hdr_toggle_delay`) ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).

**Cursor.** Send the cursor shape and position as metadata and draw it on the client; the local cursor then feels instant. Composite it into the video only for recordings (Inference; DD exposes shape and position separately ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api))). With WGC, set `IsCursorCaptureEnabled=false` and read `GetCursorInfo` yourself.

**Protected content.** Windows marked `WDA_EXCLUDEFROMCAPTURE`, and hardware-DRM video, capture as black ([MS SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)). Don't work around it.

**Hybrid-GPU laptops.**
- DD fails with `DXGI_ERROR_UNSUPPORTED` when the D3D device sits on the discrete GPU but the output belongs to the integrated one. Microsoft says to run on the GPU that owns the output, usually the integrated one ([MS KB](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/error-when-dda-capable-app-is-against-gpu), [freemancw](https://www.freemancw.com/2020/11/desktop-duplication-on-hybrid-graphics-systems/)).
- Sunshine warns that `adapter_name` is not a reliable indicator of physical wiring ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- Design: capture on the adapter that owns the output. Then either encode on that same GPU (QSV/AMF on the integrated GPU) or copy across adapters through a shared NT-handle texture. The cross-adapter copy goes through system memory and costs milliseconds at 4K (Inference).

**Headless hosts.**
- A dummy HDMI/DP plug (an EDID emulator) needs no software.
- An Indirect Display Driver (IDD) is a UMDF driver built on IddCx. It runs in session 0, has no kernel component, and can do a hardware cursor and protected content ([MS](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview)); there is a sample in [Windows-driver-samples](https://github.com/Microsoft/Windows-driver-samples/tree/main/video/IndirectDisplay).
- Products that ship one:
  - Parsec VDD: IddCx 1.4, Windows 10 19H2+, no HDR, choice of GPU since 0.45 ([Parsec](https://support.parsec.app/hc/en-us/articles/4422939339789-Overview-Prerequisites-and-Installation)).
  - Apollo's SudoVDA: created per stream, automatic resolution and frame-rate match to the client, a fixed identity per client, HDR ([Apollo](https://github.com/ClassicOldSong/Apollo)).
  - The community Virtual Display Driver: IddCx 1.10 with HDR, signed through SignPath ([VDD](https://github.com/lizardbyte/virtual-display-driver)).
- Signing: Microsoft states that user-mode drivers don't need a Microsoft signature on Windows 10, but attestation signing covers them ([MS code-signing reqs](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-reqs)). Budget for attestation signing through Partner Center to avoid install prompts (Inference).
- The IDD's frames can also be consumed directly inside the driver and passed to the agent as shared textures. That is more work, and capturing the IDD's output with DD is simpler (Inference).

## 2. Video encoding without third-party libraries

**Option A: the vendor SDKs, called directly.** Parsec does this "without wrappers" ([blog](https://parsec.app/blog/description-of-parsec-technology-b2738dcc3842)). Sunshine ships a standalone NVENC encoder with reference-frame invalidation (RFI) ([docs](https://docs.lizardbyte.dev/projects/sunshine/latest/classnvenc_1_1nvenc__base.html)).
- **NVENC.**
  - The runtime library is installed with the NVIDIA display driver ([NVENC guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html)). On x64 it is `nvEncodeAPI64.dll` (the guide names `nvEncodeAPI.dll`). The headers are MIT-licensed ([nv-codec-headers](https://github.com/FFmpeg/nv-codec-headers)), so you translate them to C# and redistribute nothing.
  - Low-latency recipe: P1–P4 presets with low-latency or ultra-low-latency CBR tuning, no B-frames, no lookahead, infinite GOP. Add intra refresh ("period may be small like 30 for a highly error prone network"), `NvEncInvalidateRefFrames` keyed by input timestamp, and long-term references (LTR), which don't work with B-frames ([guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html)).
  - Asynchronous mode exists only on Windows 10+ under WDDM (same source).
  - Sunshine's NVENC lessons ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)):
    - Two-pass at quarter resolution avoids "bitrate overshoot and subsequent packet loss".
    - Relaxing the VBV acts as low-latency VBR.
    - Real-time GPU priority under Hardware-Accelerated GPU Scheduling (HAGS) can freeze the stream.
    - The adaptive P-state "doesn't work well with low latency streaming".
    - CAVLC costs about 10% more bitrate than CABAC.
  - GeForce cards allow 12 concurrent sessions ([matrix](https://developer.nvidia.com/video-encode-decode-support-matrix)).
- **AMD AMF.**
  - The headers are MIT ([AMF repo](https://github.com/GPUOpen-LibrariesAndSDKs/AMF)). `amfrt64.dll` ships with the Adrenalin driver (Inference; the AMF docs don't say).
  - Usage presets: `ULTRA_LOW_LATENCY` and `LOWLATENCY_MODE`. Rate control defaults to latency-constrained VBR, and the default ultra-low-latency VBV is 735 kbit. There are intra-refresh macroblocks per slot, slices per frame, and LTR, but LTR excludes B-frames and, when user-controlled, intra refresh ([AMF encode API](https://github.com/GPUOpen-LibrariesAndSDKs/AMF/blob/master/amf/doc/AMF_Video_Encode_API.md)).
  - Sunshine's experience: "vbr_latency generally works best, but some bitrate overshoots may still occur"; preanalysis adds latency ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- **Intel oneVPL/QSV.**
  - The runtime ships in the driver: `libmfx64-gen.dll` for Xe, `libmfxhw64.dll` for the legacy Media SDK. It is found through the adapter's DriverStore folder ([VPL session spec](https://intel.github.io/libvpl/latest/programming_guide/VPL_prg_session.html)).
  - The usual dispatcher (libvpl, MIT) is third-party code, but the search order is specified, so a C# dispatcher is small (Inference). Intel's encoder MFT is the alternative.
  - Sunshine notes that old Intel GPUs support only low-power H.264 (`qsv_slow_hevc`) ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).

**Option B: D3D12 Video Encode.** It is OS-native and vendor-neutral.
- H.264 and HEVC from Windows 11; AV1 from Windows 11 24H2 with WDDM 3.2 ([MS](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/video-encoding-d3d12)).
- Rate control modes: CQP, CBR, VBR, QVBR, with VBV capacity and initial fullness.
- Row-based intra refresh.
- Dynamic rate-control, resolution, GOP and subregion changes, each a capability flag.
- Slice or subregion modes, plus subregion notification for sending before the frame finishes.
- The host app controls headers and reference management, so first-party RFI and LTR are possible ([spec](https://microsoft.github.io/DirectX-Specs/d3d/D3D12_Video_Encoding_H264_HEVC.html), [index](https://microsoft.github.io/DirectX-Specs/d3d/D3D12VideoEncoding.html)).
- Base input is 4:2:0 NV12/P010, with a separate HEVC 4:2:2/4:4:4 extension (same index).
- Risks: driver maturity and quality parity with the native SDKs (Unverified). DD and WGC give D3D11 textures, so you need D3D11↔D3D12 shared resources and fences (Inference).

**Option C: Media Foundation (MF) hardware encoder MFTs (Media Foundation transforms).**
- These are vendor-written and installed by the drivers. They must be asynchronous (`METransformNeedInput` and `METransformHaveOutput` events) and support dynamic format changes ([MS hardware MFTs](https://learn.microsoft.com/en-us/windows/win32/medfound/hardware-mfts)).
- Certified encoders must implement rate control, quality, mean and max bitrate, buffer size, GOP, QP and ForceKeyFrame. LTR, slice control, max reference frames, temporal layers, CABAC and low-latency mode are *optional*. There is no intra-refresh or RFI property ([MS H.264 encoder](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-encoder)).
- Vendor quirks are real: NVIDIA's MFT latency rises when the frame rate is capped ([NVIDIA forum](https://forums.developer.nvidia.com/t/nvenc-h-264-encoder-mft-latency-increases-when-framerate-is-limited/63930)).
- Use MF as the universal fallback, not the primary path (Inference).

**Support matrix.**
- NVENC: H.264 from Maxwell; HEVC from Pascal (NVIDIA lists some Maxwell GM206 parts too); AV1 encode from Ada; 4:2:2 from Blackwell; H.264/HEVC 4:4:4 broadly; AV1 decode from Ampere ([NVIDIA matrix](https://developer.nvidia.com/video-encode-decode-support-matrix)).
- AMD: AV1 encode on RDNA3 (RX 7000) ([Tom's Hardware](https://www.tomshardware.com/news/next-amd-video-engine-may-lack-av1)). No 4:4:4 encode (Inference).
- Intel: AV1 encode on Arc; HEVC 4:4:4 8/10-bit encode on 11th/12th gen and Arc ([Intel VPL HW reference](https://www.intel.com/content/www/us/en/docs/onevpl/developer-reference-media-intel-hardware/current/overview.html)).
- No vendor encodes AV1 4:4:4 ([LizardByte discussion](https://github.com/orgs/LizardByte/discussions/220)).
- Sunshine's 4:4:4 is experimental and Windows-host-only; client decode support is the bottleneck (same).

**Software fallback under a no-third-party rule.**
- The inbox Microsoft H.264 MFT (`mfh264enc.dll`) does Baseline, Main and High and CBR. Its low-latency mode encodes slices in parallel on CPU threads ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-encoder)). CPU cost at 1080p60 is Unverified, and N editions need the Media Feature Pack (Unverified).
- An intra-only GPU-compute wavelet codec is a realistic first-party alternative for LAN. Valve now ships PyroWave in Steam Remote Play beta: GPU encode and decode, 100–500 Mbit/s, YUV 4:4:4 and HDR, MIT-licensed, written in Vulkan compute ([GamingOnLinux](https://www.gamingonlinux.com/2026/09/steam-beta-adds-experimental-new-pyrowave-video-codec-for-remote-play/page=1/), [author's blog](https://themaister.net/blog/2025/06/16/i-designed-my-own-ridiculously-fast-game-streaming-video-codec-pyrowave/)). Porting the idea to D3D11/D3D12 compute is feasible (Inference).
- Over WAN there is no first-party software H.264 short of writing an encoder (Inference).

**Licensing.**
- H.264 (Via LA): the first 100,000 units a year are $0, then $0.20 per unit, with enterprise caps ([Via LA](https://www.via-la.com/licensing-programs/avc-h-264/)).
- HEVC has several pools (Access Advance; Via LA, now VCL Advance) plus independent licensors ([Via LA HEVC](https://www.via-la.com/licensing-programs/hevc-vvc/)).
- AV1 is royalty-free from AOMedia, but Sisvel runs a claimed patent pool (secondary source: [Fora Soft](https://www.forasoft.com/learn/video-encoding/articles/codec-comparison-table)).
- Whether an application owes royalties when it only *invokes* codecs that the OS or GPU vendor already licensed is Unverified. Get counsel. Moonlight and Sunshine ship without visible licences (Inference).

## 3. Decoding and presentation on the client

**Media Foundation decoders.**
- The inbox H.264 MFT (`msmpeg2vdec.dll`) supports DXVA2/D3D11 and low-latency mode from Windows 8. It goes up to level 5.1 and 4096×2304, **4:2:0 only**.
- **DXVA is used only for Main-compatible streams.** Baseline needs `constrained_set1_flag=1`, otherwise decoding silently falls back to software ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-decoder)).
- A documented HEVC decoder MFT exists ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/h-265---hevc-video-decoder)). On consumer Windows it typically depends on the Store "HEVC Video Extensions", and AV1 on the "AV1 Video Extension" (Unverified).

**Direct D3D11VA (`ID3D11VideoDecoder`) or D3D12 Video Decode.**
- This has no Store dependency and gives the lowest latency. The cost: you parse SPS/PPS/slice headers (or AV1 OBUs), fill the DXVA picture parameters and manage the decoded picture buffer yourself. That is what FFmpeg's hardware acceleration does for Moonlight.
- Inference: a few thousand lines per codec, and the largest first-party item on the client.

**Moonlight.**
- FFmpeg hardware decode, with the D3D11 renderer preferred on Windows 10+ ([v6.0.0 notes](https://github.com/moonlight-stream/moonlight-qt/releases/tag/v6.0.0)).
- Its pacer: a time-critical vsync thread (DXGI vblank source); at most 3 queued frames; drops the oldest frame; keeps the queue at 1 frame when the stream runs slower than the display, and lets it grow to 3 under jitter when stream fps ≥ display. It wakes 3 ms before vsync (`TIMER_SLACK_MS`) and keeps a frame alive one extra render so the GPU never reads a reused surface ([pacer.cpp](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp)).

**Parsec.** Hardware decode into NV12 that stays in VRAM, a pixel shader for NV12→RGB, D3D11 flip-sequential, and vsync on by default with frames dropped when the host runs faster. It claims encode plus decode under 10 ms ([blog](https://parsec.app/blog/description-of-parsec-technology-b2738dcc3842)).

**Swap chain for lowest latency.**
- Use the flip model (`FLIP_DISCARD`) ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model), [DirectX blog](https://devblogs.microsoft.com/directx/dxgi-flip-model/)).
- Use a waitable swap chain with `SetMaximumFrameLatency(1)` and wait on the object before rendering ([MS](https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains)).
- `ALLOW_TEARING` plus `Present(0, DXGI_PRESENT_ALLOW_TEARING)` gives VRR and tearing in windowed and borderless mode ([MS](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/variable-refresh-rate-displays)).
- Independent flip gets down to 1 frame of latency ([DirectX blog](https://devblogs.microsoft.com/directx/dxgi-flip-model/)). Developers report a requested latency of 1 behaving like 2 ([gamedev.net](https://www.gamedev.net/forums/topic/686507-windows-10-dx12-low-latency-tearing-free-rendering/5335807/)).
- Offer two modes: "lowest latency" (present on arrival, with tearing or VRR) and "smooth" (a Moonlight-style vblank pacer). HDR: P010 into an FP16 or 10-bit swap chain with `DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020` and metadata (Inference).
- Colour conversion: either the D3D11 video processor or your own shader. The shader gives exact BT.709/BT.2020 range control (Inference).

**Jitter buffers.** Parsec runs "no buffers of any kind on video" ([BUD blog](https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007)). Video uses at most a 0–1 frame display queue. Audio needs a small adaptive jitter buffer, roughly 10–40 ms (Inference).

## 4. Transport

**GameStream / Moonlight + Sunshine.**
- RTSP setup over TCP. Video goes over RTP/UDP with Reed-Solomon FEC per frame block. Parity = data × `fecPercentage`, Sunshine's default is 20%, and a frame can span several blocks ([RtpVideoQueue.c](https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/RtpVideoQueue.c), [config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- Unrecoverable loss → `notifyFrameLost` → an RFI range, otherwise an IDR request. "Speculative RFI" fires as soon as missing packets exceed the parity budget (same).
- The control channel is ENet with AES-GCM from 7.1.431. It sends loss stats every 50 ms and a ping every 100 ms, and reports a poor connection at 30% immediate loss or 15% loss twice in a row ([ControlStream.c](https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/ControlStream.c)).
- Video encryption is optional per LAN and WAN (`lan_encryption_mode=0` and `wan_encryption_mode=1` by default) ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- Bitrate is user-fixed. I found no congestion-control or bitrate-adaptation logic (Inference from these sources).

**Parsec BUD ("Better User Datagrams").**
- UDP with "basic reliability semantics like TCP" and a "highly tuned and custom congestion control" that must "detect a congestion event before it starts" because video is unbuffered. Parsec admits it is "too conservative for people with higher latencies" ([BUD blog](https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007)).
- DTLS 1.2 via OpenSSL (same blog). Parsec claims 97% NAT-traversal success ([technology](https://parsec.app/technology)). Its slides cite TCP congestion control and missing loss/RTT metrics as the reasons for a custom protocol ([slides](https://www.slideshare.net/BenjyBoxer/building-a-udp-protocol-for-cloud-gaming)).

**WebRTC (used by CRD).**
- DTLS-SRTP ([RFC 5764](https://www.rfc-editor.org/rfc/rfc5764)).
- NACK/RTX ([RFC 4588](https://www.rfc-editor.org/rfc/rfc4588)), FlexFEC ([RFC 8627](https://www.rfc-editor.org/rfc/rfc8627)), and PLI/FIR keyframe requests.
- Google Congestion Control (GCC) ([draft-ietf-rmcat-gcc-02](https://datatracker.ietf.org/doc/html/draft-ietf-rmcat-gcc-02)) with transport-wide feedback ([draft-holmer](https://datatracker.ietf.org/doc/html/draft-holmer-rmcat-transport-wide-cc-extensions-01), [RFC 8888](https://www.rfc-editor.org/rfc/rfc8888)).
- CRD's host is a WebRTC PeerConnection with an AV1 encoder in `remoting/codec` ([chromium](https://chromium.googlesource.com/chromium/src/+/master/remoting/protocol/webrtc_transport.h), [AV1 encoder](https://chromium.googlesource.com/chromium/src.git/+/main/remoting/codec/webrtc_video_encoder_av1.cc)).

**RustDesk.** TCP through the rendezvous and relay servers, with concurrent TCP and UDP hole punching ([secondary](https://deepwiki.com/rustdesk/rustdesk/2.4-nat-traversal-and-relay)). Its UI strings now mention a "direct WebRTC connection" with relay fallback ([lang](https://github.com/rustdesk/rustdesk/blob/master/src/lang/pl.rs)). Use of KCP is Unverified.

**Steam Remote Play.** UDP on 27031/27036 and TCP on 27036/27037. A lost video frame is skipped rather than retransmitted ([Valve FAQ](https://help.steampowered.com/en/faqs/view/3E3D-BE6B-787D-A5D2)).

**QUIC.**
- Datagrams are [RFC 9221](https://www.rfc-editor.org/rfc/rfc9221). RTP-over-QUIC is still an Experimental draft (-14) ([datatracker](https://datatracker.ietf.org/doc/draft-ietf-avtcore-rtp-over-quic/)).
- QUIC's congestion controller (Cubic or BBR in MsQuic) governs datagrams and is not built for real-time video.
- The `System.Net.Quic` API documents only streams, not datagrams (Inference from [MS overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/quic/quic-overview)). So use QUIC for control, clipboard and files, not media.

**Loss recovery** (Inference, consistent with the sources above):
- Retransmission (NACK) only when RTT is well under one frame interval (a LAN).
- Otherwise adaptive FEC per frame plus RFI or LTR, so a loss doesn't trigger an IDR.
- Intra refresh instead of periodic IDRs, to avoid size spikes.
- An IDR is the last resort, rate-limited.

**Congestion control and adaptive bitrate.**
- Options: GCC (delay gradient plus loss); SCReAM ([RFC 8298](https://www.rfc-editor.org/rfc/rfc8298)); SCReAMv2, a 2026 WG draft with L4S support ([draft -01](https://datatracker.ietf.org/doc/draft-ietf-ccwg-rfc8298bis-screamv2/)); NADA ([RFC 8698](https://www.rfc-editor.org/rfc/rfc8698)). Requirements are in [RFC 8836](https://www.rfc-editor.org/rfc/rfc8836).
- Known failure modes (Inference from operating experience and the GCC analysis in [Carlucci et al.](https://dl.acm.org/doi/10.1145/2910017.2910605)):
  - Wi-Fi aggregation and contention add delay noise, which causes false backoffs.
  - Cellular deep buffers (bufferbloat) hide congestion until delay explodes.
  - Delay-based control starves against Cubic TCP flows.
  - Ramp-up after a backoff is slow.
- Design: a delay-gradient controller with loss fallback and fast IDR-free bitrate change, plus a user "fixed bitrate" mode, which is what Moonlight users rely on (Inference).

**MTU and pacing.**
- Keep UDP payload ≤ about 1200 bytes, the QUIC minimum and the WebRTC practice ([RFC 9000 §14](https://www.rfc-editor.org/rfc/rfc9000#section-14)), so VPNs and PPPoE never fragment. Set Don't-Fragment, and optionally probe with DPLPMTUD ([RFC 8899](https://www.rfc-editor.org/rfc/rfc8899)).
- Pace each frame's packets over part of the frame interval instead of a line-rate burst, which overflows shallow Wi-Fi and router queues (Inference).
- Sunshine uses UDP segmentation offload (USO, `UDP_SEND_MSG_SIZE`, Windows 10 20H1 SDK) for batched sends ([misc.cpp](https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp)). Batching trades directly against pacing.

**DSCP and QoS marking on Windows.**
- Sunshine's comment: "Windows doesn't support any concept of traffic priority without DSCP tagging". It calls qWAVE `QOSAddSocketToFlow` with `QOSTrafficTypeAudioVideo` (video), `QOSTrafficTypeVoice` (audio) and `QOS_NON_ADAPTIVE_FLOW`, connecting the socket temporarily for it ([misc.cpp](https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp)).
- Arbitrary DSCP through `QOSSetOutgoingDSCPValue` requires Administrators or Network Configuration Operators ([MS](https://learn.microsoft.com/en-us/windows/win32/api/qos2/nf-qos2-qossetflow)).
- Value: Wi-Fi WMM maps DSCP to access categories in the home; on the internet it is usually bleached (Inference).

**.NET options.**
- `System.Net.Sockets.Socket` UDP with preallocated `SocketAddress` and buffers is enough. Disable `SIO_UDP_CONNRESET`, otherwise an ICMP port-unreachable surfaces as a receive error ([MS Winsock IOCTLs](https://learn.microsoft.com/en-us/windows/win32/winsock/winsock-ioctls)).
- `System.Net.Quic` uses MsQuic. On Windows `msquic.dll` "is distributed as part of the .NET runtime", and Windows 11 or Server 2022+ is required ([MS](https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/quic/quic-overview)).
- Under NativeAOT, `msquic.dll` is a native file next to your executable, loaded by full path ([dotnet/runtime#109963](https://github.com/dotnet/runtime/pull/109963)). So it *is* a bundled native DLL, though Microsoft-built.
- .NET 10 disables HTTP/3 by default under PublishAot ([MS](https://learn.microsoft.com/en-us/dotnet/core/compatibility/networking/10.0/http3-disabled-with-publishtrimmed)).

## 5. Connectivity and security

**NAT traversal.**
- Ladder: UPnP-IGD, NAT-PMP or PCP port mapping ([RFC 6886](https://www.rfc-editor.org/rfc/rfc6886), [RFC 6887](https://www.rfc-editor.org/rfc/rfc6887)) → STUN/ICE hole punching ([RFC 8489](https://www.rfc-editor.org/rfc/rfc8489), [RFC 8445](https://www.rfc-editor.org/rfc/rfc8445)) → relay ([TURN, RFC 8656](https://www.rfc-editor.org/rfc/rfc8656), or a custom relay).
- "Hard" NATs, with a mapping per destination, break plain STUN. Port probing (256 ports on the hard side × 1024 probes) gives about 98% when only one side is hard. Two hard NATs are impractical. Carrier-grade NAT blocks port mapping. IPv6 still needs firewall hole punching ([Tailscale](https://tailscale.com/blog/how-nat-traversal-works)).
- Parsec: UPnP first, then STUN hole punching, with an on-prem "High Performance Relay" for Teams ([Parsec](https://support.parsec.app/hc/en-us/articles/32361410290324-Components-and-Connection-Sequence)).
- RustDesk: hbbs handles rendezvous on 21115/21116, hbbr relays on 21117 ([docs](https://rustdesk.com/docs/en/self-host/)).
- Steam: Valve's Steam Datagram Relay exists for games ([Valve](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)). Whether Remote Play uses it is Unverified.
- CRD: WebRTC ICE with TURN relays, signalling over Google's FTL messaging ([chromium](https://chromium.googlesource.com/chromium/src.git/+/main/remoting/protocol/ice_transport_channel.cc)).

**Relay share.** The most-cited figure is about 22% of WebRTC calls needing TURN (callstats.io, 2016) ([webrtcHacks](https://webrtchacks.com/usage-stats/)). Other claims run 15–30%, Tailscale reports direct paths ">90%", and Parsec claims 97%. Budget 10–20% of internet sessions relayed at video bitrates (Inference).

**LAN discovery.** Windows 10+ has native DNS-SD/mDNS: `DnsServiceBrowse` / `DnsServiceRegister` ([MS](https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse); [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762)/[6763](https://www.rfc-editor.org/rfc/rfc6763)). A UDP broadcast probe is the fallback.

**Pairing models and weaknesses.**
- GameStream PIN pairing:
  - The AES-128 key is SHA-256 (or SHA-1) of salt plus a 4-digit PIN, with no iterated key derivation.
  - The pairing stages use AES-ECB over plain HTTP before the certificate is pinned, so a recorded pairing allows an offline PIN brute-force (Inference). The SHA-1 path can be forced by a downgrade ([nvpairingmanager.cpp](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/backend/nvpairingmanager.cpp)).
  - Sunshine CVEs: [CVE-2024-45407](https://nvd.nist.gov/vuln/detail/CVE-2024-45407) and [CVE-2024-51738](https://nvd.nist.gov/vuln/detail/CVE-2024-51738).
- RustDesk ID + password: NaCl box/secretbox. The login proof SHA256(SHA256(pw+salt)+challenge) uses salt and challenge chosen by the server, so a rogue server can recover the password offline ([CVE-2026-30789](https://cveawg.mitre.org/api/cve/CVE-2026-30789)).
- Parsec: account-brokered. Its docs variously say DTLS 1.2 with AES-128 or AES-GCM-128 ([security](https://parsec.app/security)); which is current is Unverified.
- Recommended design (Inference):
  - Per-device long-term keys, with TLS 1.3 or DTLS through SChannel and pinned certificates, or a Noise-style handshake.
  - Pairing through a PAKE (SPAKE2 or CPace) over a short code, or out-of-band fingerprint confirmation.
  - Accounts only as a rendezvous directory, never holding session keys. Per-device permissions as in Apollo ([Apollo](https://github.com/ClassicOldSong/Apollo)).

**Native crypto from .NET.**
- On Windows these use CNG with no extra library: AesGcm, ChaCha20Poly1305, ECDH and ECDSA on P-256, HKDF, SHA-2, and SslStream/SChannel (TLS 1.3 on Windows 11).
- .NET 10 adds ML-KEM and ML-DSA ([MS](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-10/libraries)).
- There is no Ed25519 type ([runtime#14741](https://github.com/dotnet/runtime/issues/14741)). X25519 appears in .NET 11 previews (GA status Unverified). CNG's `BCRYPT_ECC_CURVE_25519` is reachable through P/Invoke (Unverified in this pass).

## 6. Audio

**Capture.**
- WASAPI loopback (`AUDCLNT_STREAMFLAGS_LOOPBACK`) needs no driver ([MS](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)).
- Per-process include or exclude: `AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK`, Windows 10 build 20348+ ([MS](https://learn.microsoft.com/en-us/windows/win32/api/audioclientactivationparams/ne-audioclientactivationparams-audioclient_activation_type), [sample](https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/applicationloopbackaudio-sample/)).

**Host mute and microphone passthrough need virtual devices.**
- Sunshine's `virtual_sink` uses Steam Streaming Speakers, so it depends on Steam ([config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
- Parsec tells headless hosts to install VB-Cable ([Parsec](https://support.parsec.app/hc/en-us/articles/32381824873748-Unable-To-Hear-The-Game-You-re-Playing)) and does microphone passthrough through its own Virtual USB driver ≥0.2.5.0 ([Parsec](https://support.parsec.app/hc/en-us/articles/32380350695956-Use-your-Microphone-with-Parsec)).
- Windows has no inbox virtual audio API. A first-party device means a kernel audio driver (SysVAD sample, or ACX) with attestation signing ([SysVAD](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/sysvad-virtual-audio-device-driver-sample), [ACX](https://learn.microsoft.com/en-gb/windows-hardware/drivers/audio/acx-audio-class-extensions-overview)).
- Cheaper mute without a driver: capture with process loopback and mute the endpoint locally. This only works if the capture taps before the endpoint volume (Unverified; test it).

**Codec.**
- Moonlight negotiates 5 ms Opus packets ([SdpGenerator.c](https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/SdpGenerator.c)). Opus is BSD-licensed with royalty-free patent grants ([opus-codec.org](https://opus-codec.org/license/)), but it is a third-party library.
- Windows defines `MFAudioFormat_Opus` ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/audio-subtype-guids)) but ships no Opus encoder. An app-usable decoder MFT is Unverified; probe with `MFTEnumEx`.
- The MF AAC encoder is AAC-LC only, with no LD or ELD. It takes 16-bit 44.1 or 48 kHz input, bitrates of 96–192 kbps per channel pair, and 1024-sample frames (21.3 ms at 48 kHz) ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/aac-encoder)). Priming delay is about 2048 samples (Inference), so expect roughly 40–60 ms codec delay, against 5–10 ms for Opus.
- Raw PCM, 48 kHz/16-bit stereo, is 1.536 Mbit/s and fine on a LAN, but has no concealment (arithmetic).
- Concentus is a pure C# Opus port (BSD-style, no native DLL, about 40–50% of native speed) ([repo](https://github.com/lostromb/concentus)). It is third-party.
- Strict first-party option: write a CELT-only Opus codec from [RFC 6716](https://www.rfc-editor.org/rfc/rfc6716). It stays wire-compatible and fits game and desktop audio (Inference).

## 7. Input injection

**SendInput.**
- Subject to UIPI (User Interface Privilege Isolation): it can't inject into higher-integrity windows, and it fails *silently*. It doesn't reset key state, so you release stuck modifiers yourself ([MS](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)).
- To reach elevated windows, run the injector as SYSTEM in the session (or set uiAccess). To reach the secure desktop, use a SYSTEM agent bound to the Winlogon desktop (§8).
- Relative moves pass through pointer speed and acceleration ([MS MOUSEINPUT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-mouseinput)). Use absolute coordinates (`MOUSEEVENTF_ABSOLUTE|VIRTUALDESK`) for desktop work and relative for games, toggled by the client's pointer-capture state.
- Anti-cheat may reject events flagged as injected (Inference).

**Keyboard.** Inject scancodes (`KEYEVENTF_SCANCODE`) for games, because they are independent of the host layout. Use Unicode (`KEYEVENTF_UNICODE`) for text when the client and host layouts differ (Inference). On the client, capture Win, Alt-Tab and similar with a low-level keyboard hook while focused, and use Raw Input plus `ClipCursor` for relative mouse (Inference).

**Touch and pen.** `CreateSyntheticPointerDevice` and `InjectSyntheticPointerInput` on Windows 10 1809+ ([MS](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-createsyntheticpointerdevice)).

**Virtual gamepads.**
- ViGEmBus was retired and archived on 2023-11-02, with no successor ([Nefarius](https://docs.nefarius.at/projects/ViGEm/End-of-Life/)). Sunshine still requires it ([issue #4193](https://github.com/LizardByte/Sunshine/issues/4193)), and Apollo relies on it too.
- Parsec ships its own signed "Virtual USB Adapter" (Xbox, DS4, DualSense) ([Parsec](https://support.parsec.app/hc/en-us/articles/32381705301908-Setup-Gamepad)). What Steam uses is Unverified.
- `InputInjector.InjectGamepadInput` needs the restricted `inputInjectionBrokered` capability, which means a packaged app ([MS](https://learn.microsoft.com/en-us/uwp/api/windows.ui.input.preview.injection.inputinjector)). Whether XInput games see it is Unverified; likely they only reach Windows.Gaming.Input (Inference).
- Conclusion (Inference): no driverless XInput option exists. Plan a signed driver: either a UMDF/VHF HID gamepad (enough for DirectInput, SDL and HID games) or XUSB emulation for XInput.

**Clipboard and files.**
- Sunshine has only a client-to-host paste shortcut ([issue #1539](https://github.com/LizardByte/Sunshine/issues/1539)). Apollo lists clipboard sync. RustDesk has clipboard and file channels, with 2026 authorization CVEs (Unverified detail).
- Design (Inference): separate channels on the control connection, each with explicit per-device permission.

## 8. Windows service architecture for unattended access

**Pattern.** A LocalSystem service watches `WTSGetActiveConsoleSessionId` and `SERVICE_CONTROL_SESSIONCHANGE` ([MS](https://learn.microsoft.com/en-us/windows/win32/termserv/wm-wtssession-change)). It launches an agent *as SYSTEM in the console session*.
- Sunshine duplicates its own token, sets `TokenSessionId`, and calls `CreateProcessAsUserW` on `winsta0\default` inside a kill-on-close job. It relaunches the agent on crash or `WTS_CONSOLE_CONNECT` ([sunshinesvc.cpp](https://github.com/LizardByte/Sunshine/blob/master/tools/sunshinesvc.cpp)).
- RustDesk borrows `winlogon.exe`'s token for SYSTEM, and `explorer.exe`'s for "as user" launches ([windows.cc](https://github.com/rustdesk/rustdesk/blob/master/src/platform/windows.cc)).
- The agent's capture and input threads follow the input desktop (§1). User apps launch with `WTSQueryUserToken`, which needs SE_TCB ([MS](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtsqueryusertoken)).
- Parsec's service exists specifically for admin apps, UAC and the login screen ([Parsec](https://support.parsec.app/hc/en-us/articles/32381334155412-Why-Is-Parsec-Running-in-the-Background-on-Startup)).
- Best-practice privilege split: CRD runs a SYSTEM daemon, a desktop process as SYSTEM in the session, and a **network process as LOCAL_SERVICE at low integrity** ([chromium](https://chromium.googlesource.com/chromium/src/+/f303bc03a281b55dbd066185f79daa61dd8ba8d1/remoting/GEMINI.md)). Parse untrusted packets outside SYSTEM (Inference).

**Ctrl+Alt+Del.** `SendSAS` from a service, with the `SoftwareSASGeneration` policy ([MS](https://learn.microsoft.com/en-us/windows/win32/api/sas/nf-sas-sendsas)). RustDesk sets that policy at install ([CustomActions.cpp](https://github.com/rustdesk/rustdesk/blob/master/res/msi/CustomActions/CustomActions.cpp)).

**Reboot and logoff.** The service starts at boot, and the agent captures the login screen, so no auto-logon is required. A "restart into safe mode with networking" feature needs the service registered under `SafeBoot\Network` (Inference).

**Auto-update** (Inference; no primary source found for these products): the service downloads, verifies the Authenticode signature, the pinned publisher and your own signature through CNG, swaps versioned directories and restarts the agent. The user-session agent never writes to the install directory.

**Signing and reputation.**
- Since 2024, EV certificates no longer grant instant SmartScreen reputation. Reputation builds per file hash, so every release starts at zero ([MS](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)).
- Azure Artifact Signing (formerly Trusted Signing) issues no EV certificates and gives no instant reputation ([FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq)).
- Smart App Control blocks unsigned DLLs one by one ([MS](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview)). Sign every PE file.
- Remote-access tools are classified as "RemoteAdmin" or riskware ([Kaspersky](https://threats.kaspersky.com/en/threat/RemoteAdmin.Win32.RustDesk.df)), and fake installers of them circulate ([Malwarebytes](https://www.malwarebytes.com/blog/threat-intel/2026/01/how-real-software-downloads-can-hide-remote-backdoors)). Plan for vendor submissions, visible consent, and an on-host session indicator.

## 9. Wake-on-LAN and remote power-on

**Magic packet.** 6×`0xFF` followed by the MAC address repeated 16 times (102 bytes), over UDP to port 9 or 7, with no acknowledgement. Moonlight sends it to ports 9 and 47009 plus the GameStream ports, to known unicast addresses *and* the broadcast address of every local NIC ([nvcomputer.cpp](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/backend/nvcomputer.cpp)). RustDesk sends WoL only to peers on the LAN ([lan.rs](https://github.com/rustdesk/rustdesk/blob/master/src/lan.rs)).

**Why it doesn't cross the internet.** The sleeping host's ARP entry expires, and routers must not forward directed broadcasts by default ([RFC 2644](https://www.rfc-editor.org/rfc/rfc2644)). Workable designs:
- A peer agent on the same LAN (another host, a phone, a NAS or a Raspberry Pi) that your rendezvous server tells to send the broadcast. This is the robust choice.
- The router's own WoL feature.
- Static ARP plus a port forward, which is fragile.

**What breaks it.**
- Fast Startup (hybrid S4) is the default "shutdown", and Windows *disarms* the NIC for WoL in that transition. Microsoft says to disable Fast Startup when wake-from-off is needed ([MS](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/wake-on-lan-feature)).
- Modern Standby wakes on WoL patterns only in *connected* standby ([HP](https://support.hp.com/au-en/document/c08395618), [MS Surface](https://learn.microsoft.com/en-us/surface/wake-on-lan-for-surface-devices)).
- Wi-Fi WoWLAN is unreliable, so treat Wi-Fi hosts as not wakeable (Inference).
- BIOS ErP/Deep Sleep and Energy-Efficient Ethernet are commonly blamed (Unverified). Only port A of multiport adapters wakes ([Intel](https://www.intel.com/content/www/us/en/support/articles/000005793/ethernet-products.html)).
- Sleep (S3) is the most reliable wake source, then hibernate (S4), then soft-off (S5), which depends on the firmware.

**Alternatives.**
- Intel AMT/vPro gives out-of-band power and KVM. From CSME 16.1 it is TLS-only ([Intel](https://www.intel.com/content/dam/support/us/en/documents/technologies/adl-non-tls-update-support-guidance.pdf)).
- IPMI/BMC on servers.
- A smart plug plus BIOS "power on after AC loss" (Inference).

**After power-on.**
- A BitLocker TPM+PIN stops at the pre-boot screen. Network Unlock needs a domain, WDS and wired DHCP ([MS](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/network-unlock)). TPM-only BitLocker boots unattended.
- Automatic Restart Sign-On (ARSO) restores the session only after restarts, and CIS benchmarks recommend disabling it ([MS](https://learn.microsoft.com/en-us/windows-server/security/windows-authentication/winlogon-automatic-restart-sign-on-arso)).
- The service-plus-Winlogon-capture design makes auto-logon unnecessary.

## 10. NativeAOT / C# specifics

**Garbage collector.**
- A collection suspends all managed threads. Make the steady state allocation-free:
  - Preallocated pinned buffers (`GC.AllocateArray(pinned:true)`), structs and `Span`.
  - Object pools.
  - No LINQ, closures, boxing or `async` state machines on the frame path.
  - Verify with `GC.GetAllocatedBytesForCurrentThread` (Inference).
- `GCLatencyMode.SustainedLowLatency` suppresses foreground gen-2 collections ([MS](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/latency)). Use `TryStartNoGCRegion` only for short windows.

**COM.** Built-in COM interop generates IL stubs at runtime and is incompatible with NativeAOT. Use `[GeneratedComInterface]`/`[GeneratedComClass]` (.NET 8+), which supports IUnknown-based interfaces only, through `StrategyBasedComWrappers` ([MS](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/comwrappers-source-generation)). That covers DXGI, D3D11/12, MF and WASAPI.

**Hot paths.**
- For per-frame calls (ID3D11DeviceContext, NVENC's function table from `NvEncodeAPICreateInstance`), call raw vtable or function-table pointers through `delegate* unmanaged[Stdcall]`. This avoids wrapper overhead (Inference).
- Callbacks: `[UnmanagedCallersOnly]` static methods. Prefer event handles (WASAPI event mode, MF async events, the waitable swap chain) over callbacks.

**WinRT (WGC).** Use the Microsoft CsWinRT projection, which is AOT-capable (Unverified version requirements), or hand-written IInspectable vtables.

**Threads and timers.**
- Dedicated OS threads, not the ThreadPool, one per stage. MMCSS through `AvSetMmThreadCharacteristics("Games"|"Pro Audio")` ([MS](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)).
- Sunshine raises the process to HIGH_PRIORITY_CLASS, enables DWM MMCSS, requests 0.5 ms timer resolution through `NtSetTimerResolution` (falling back to `timeBeginPeriod(1)`), and sleeps on `CREATE_WAITABLE_TIMER_HIGH_RESOLUTION` timers ([misc.cpp](https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp)).
- Since Windows 10 2004, `timeBeginPeriod` is per-process. On Windows 11, an occluded, minimized or invisible window-owning process gets no guaranteed raised resolution ([MS](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod)). A host agent with no visible window must not rely on `Sleep(1)`: wait on events and high-resolution timers, and opt out of EcoQoS through `SetProcessInformation` (Inference).

**Trimming.** Use the JSON source generator and avoid reflection. .NET 10 disables HTTP/3 under PublishAot ([MS](https://learn.microsoft.com/en-us/dotnet/core/compatibility/networking/10.0/http3-disabled-with-publishtrimmed)).

## 11. Native building blocks on other platforms (for clean seams)

- **macOS:**
  - Capture: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).
  - Encode and decode: [VideoToolbox](https://developer.apple.com/documentation/videotoolbox), whose low-latency rate control is described in [WWDC21](https://developer.apple.com/videos/play/wwdc2021/10158/).
  - Input: CGEvent, which needs the Accessibility permission.
  - Audio: Core Audio taps for per-process capture (Unverified version).
  - Virtual displays: only through private API (Unverified).
- **Linux:**
  - Capture: xdg-desktop-portal ScreenCast plus PipeWire on Wayland; KMS capture needs `cap_sys_admin` ([Sunshine config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
  - Encode: VA-API, or Vulkan Video, which Moonlight 6 uses for decode ([notes](https://github.com/moonlight-stream/moonlight-qt/releases/tag/v6.0.0)).
  - Input: `uinput` covers keyboard, mouse *and gamepads* without a custom driver (Inference). Sunshine emulates DualSense on Linux only ([discussion](https://github.com/orgs/LizardByte/discussions/652)).
- **Android:** MediaProjection for capture, MediaCodec (`KEY_LOW_LATENCY` decoding) and AAudio ([MediaCodec](https://developer.android.com/reference/android/media/MediaCodec)).
- **iOS:** client only. VideoToolbox decode, and ReplayKit for limited capture.
- **NativeAOT targets:** see [MS](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/).
- **Seams** (Inference):
  - `ICaptureSource`: a GPU texture plus timestamp, dirty rectangles, cursor and HDR metadata.
  - `IVideoEncoder`: access units, plus `InvalidateRefs(range)`, `ForceIntra()` and `SetBitrate()`.
  - `IVideoDecoder` and `IPresenter`: separate, so pacing can be swapped.
  - `ITransport`: datagram channels plus reliable channels.
  - `IInputInjector`, `IGamepadBackend`, `IAudioCapture`/`IAudioRender`, and `ISessionBroker` (service and session plumbing).

## (a) Component map

| Component | Others use | OS-native option on Windows | Unavoidable third-party / must write first-party |
|---|---|---|---|
| Capture | DD (Parsec, Sunshine), WGC (Sunshine beta) | DD + `DuplicateOutput1`; WGC | Desktop-following SYSTEM agent (first-party) |
| Headless display | Parsec VDD, SudoVDA, VDD, dummy plug | none built in | **IddCx UMDF driver (first-party, signed)** or a dummy plug |
| HW encode | NVENC/AMF/QSV direct (Parsec, Sunshine); FFmpeg (RustDesk hwcodec) | Driver DLLs (nvEncodeAPI64, amfrt64, libmfx64-gen); D3D12 Video Encode; MF MFTs | C# header translations and a VPL dispatcher (first-party) |
| SW encode fallback | x264 / libvpx (Sunshine, RustDesk) | MS H.264 MFT | Optional GPU wavelet codec (PyroWave-style) |
| Decode | FFmpeg D3D11VA (Moonlight) | MF decoders (Store extensions for HEVC/AV1); D3D11VA/D3D12 decode | **Bitstream parsers + DXVA parameter filling (first-party)** |
| Present | SDL + D3D11 (Moonlight), D3D11 (Parsec) | DXGI flip model, waitable swap chain, tearing | Pacer (first-party) |
| Media transport + FEC | RTP + Reed-Solomon (GameStream), BUD, WebRTC | Winsock UDP, USO, qWAVE | **Protocol, Reed-Solomon FEC, congestion control (first-party)** |
| Control/file channels | ENet (Moonlight), TCP (RustDesk) | TCP + SslStream; System.Net.Quic (Win11+, bundles msquic.dll) | — |
| Crypto | OpenSSL (Parsec DTLS), libsodium (RustDesk) | CNG via .NET (AES-GCM, ECDH P-256, HKDF, TLS) | PAKE / Noise handshake code (first-party) |
| NAT traversal / relay | STUN + UPnP + relays (Parsec), hbbs/hbbr (RustDesk), TURN (CRD) | none client-side; UPnP through the COM `NATUPnP` API (Unverified) | **STUN/ICE logic, rendezvous and relay servers (first-party)** |
| LAN discovery | mDNS (Moonlight/Sunshine) | `DnsServiceBrowse/Register` | — |
| Audio capture | WASAPI loopback | WASAPI loopback / process loopback | — |
| Audio codec | Opus (Moonlight, Parsec) | MF AAC-LC (high latency), PCM | **Opus/CELT (first-party port) or accept libopus** |
| Virtual speaker / mic | Steam Streaming Speakers, VB-Cable, Parsec USB | none | **Kernel audio driver (first-party, signed)** if needed |
| Keyboard/mouse | SendInput | SendInput, SendSAS | — |
| Touch/pen | — | Synthetic pointer API | — |
| Gamepad | ViGEmBus (Sunshine, Apollo), Parsec vUSB | none for XInput | **Virtual gamepad driver (first-party, signed)** |
| Service/session | SYSTEM service + agent | SCM, WTS APIs, CreateProcessAsUser | — |
| WoL | LAN broadcast (Moonlight, RustDesk) | UDP broadcast | Peer-agent relay design (first-party) |

## (b) The 15 pitfalls most likely to hurt a new entrant

1. **Black screen or dead input at UAC, lock or login.** Fix: a SYSTEM agent in the console session that re-binds to the input desktop and recreates DD. RustDesk, Sunshine and Parsec all do this ([windows.cc](https://github.com/rustdesk/rustdesk/blob/master/src/platform/windows.cc), [Parsec](https://support.parsec.app/hc/en-us/articles/32381334155412-Why-Is-Parsec-Running-in-the-Background-on-Startup)).
2. **IDR storms after packet loss**, where large keyframes cause more loss. Fix: FEC plus reference invalidation, speculative RFI, LTR and intra refresh ([RtpVideoQueue.c](https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/RtpVideoQueue.c), [NVENC guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html)).
3. **Encoder bitrate overshoot turning into burst loss.** Fix: CBR with about a one-frame VBV, two-pass at quarter resolution, and guard rails per vendor ([Sunshine config](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)).
4. **Line-rate packet bursts on Wi-Fi.** Fix: pace packets within each frame interval and keep packets ≤1200 bytes (Inference; WebRTC's paced sender).
5. **Rate control that is too timid or too greedy** on Wi-Fi and cellular. Fix: a delay-gradient controller tuned for unbuffered video plus a user fixed-bitrate mode. Parsec admits its controller is too conservative at high RTT ([BUD blog](https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007)).
6. **Headless hosts with no monitor.** Fix: a per-session virtual display that matches the client's resolution and refresh (Parsec VDD, SudoVDA) ([Apollo](https://github.com/ClassicOldSong/Apollo)).
7. **DD failing on hybrid-GPU laptops.** Fix: capture on the GPU that owns the output and choose the encoder GPU deliberately ([MS KB](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/error-when-dda-capable-app-is-against-gpu)).
8. **Client presentation queueing adding 1–3 frames.** Fix: waitable flip-model swap chain with latency 1 and tearing allowed, or Moonlight's vblank pacer with a 3-frame cap ([pacer.cpp](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp)).
9. **Decoder availability traps.** The MF H.264 decoder silently uses software for non-Main-compatible Baseline streams ([MS](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-decoder)), HEVC/AV1 depend on Store extensions, and 4:4:4 decode is rare. Fix: emit High profile, decode with D3D11VA directly, and negotiate codecs from the client's capabilities.
10. **NAT traversal failures and relay cost.** Fix: a UPnP → STUN punching → relay ladder, budgeting 10–20% relayed sessions ([Tailscale](https://tailscale.com/blog/how-nat-traversal-works), [Parsec](https://parsec.app/technology)).
11. **Weak pairing and authentication crypto.** Moonlight's PIN pairing, Sunshine's 2024 CVEs and RustDesk's CVE-2026-30789 are the examples. Fix: a PAKE or Noise handshake with pinned device keys ([CVE-2026-30789](https://cveawg.mitre.org/api/cve/CVE-2026-30789)).
12. **Virtual gamepad dependency.** ViGEmBus is end-of-life. Fix: Parsec ships its own signed driver ([Parsec](https://support.parsec.app/hc/en-us/articles/32381705301908-Setup-Gamepad)). Budget driver work and signing early.
13. **Antivirus, SmartScreen and Smart App Control friction, and scam abuse.** Fix: sign every binary, build reputation, show consent UI and a host indicator. RustDesk added warnings and login requirements on its public servers ([MS](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)).
14. **.NET hiccups.** GC pauses, Windows 11 timer throttling for windowless agents, and ThreadPool jitter. Fix: allocation-free hot paths, dedicated MMCSS threads, and high-resolution waitable timers, Sunshine-style ([misc.cpp](https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp), [MS](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod)).
15. **"Wake my PC" not working.** Fast Startup disarms WoL, Wi-Fi hosts can't be woken, and broadcasts don't route. Fix: a LAN peer agent sends the broadcast on request, plus in-app checks for Fast Startup and the NIC settings ([MS](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/wake-on-lan-feature), [nvcomputer.cpp](https://github.com/moonlight-stream/moonlight-qt/blob/master/app/backend/nvcomputer.cpp)).

## Sources (primary, grouped)

- **Microsoft capture and display:** https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api · https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutput1-duplicateoutput · https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1 · https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession · https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/error-when-dda-capable-app-is-against-gpu · https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview · https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-reqs
- **Microsoft media:** https://learn.microsoft.com/en-us/windows/win32/medfound/hardware-mfts · https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-encoder · https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-decoder · https://learn.microsoft.com/en-us/windows/win32/medfound/aac-encoder · https://learn.microsoft.com/en-us/windows-hardware/drivers/display/video-encoding-d3d12 · https://microsoft.github.io/DirectX-Specs/d3d/D3D12_Video_Encoding_H264_HEVC.html
- **Microsoft presentation, timing and network:** https://devblogs.microsoft.com/directx/dxgi-flip-model/ · https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/variable-refresh-rate-displays · https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod · https://learn.microsoft.com/en-us/windows/win32/api/qos2/nf-qos2-qossetflow · https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/quic/quic-overview · https://learn.microsoft.com/en-us/dotnet/standard/native-interop/comwrappers-source-generation · https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/latency · https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse
- **GPU vendors:** https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvenc-video-encoder-api-prog-guide/index.html · https://developer.nvidia.com/video-encode-decode-support-matrix · https://github.com/GPUOpen-LibrariesAndSDKs/AMF/blob/master/amf/doc/AMF_Video_Encode_API.md · https://intel.github.io/libvpl/latest/programming_guide/VPL_prg_session.html · https://www.intel.com/content/www/us/en/docs/onevpl/developer-reference-media-intel-hardware/current/overview.html
- **Sunshine / Moonlight / Apollo:** https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html · https://raw.githubusercontent.com/LizardByte/Sunshine/master/src/platform/windows/misc.cpp · https://github.com/LizardByte/Sunshine/blob/master/tools/sunshinesvc.cpp · https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/RtpVideoQueue.c · https://github.com/moonlight-stream/moonlight-common-c/blob/master/src/ControlStream.c · https://github.com/moonlight-stream/moonlight-qt/blob/master/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp · https://github.com/moonlight-stream/moonlight-qt/blob/master/app/backend/nvpairingmanager.cpp · https://github.com/ClassicOldSong/Apollo
- **Parsec:** https://parsec.app/blog/description-of-parsec-technology-b2738dcc3842 · https://parsec.app/blog/a-networking-protocol-built-for-the-lowest-latency-interactive-game-streaming-1fd5a03a6007 · https://parsec.app/technology · https://support.parsec.app/hc/en-us/articles/32361410290324-Components-and-Connection-Sequence
- **RustDesk:** https://github.com/rustdesk/rustdesk/blob/master/src/platform/windows.cc · https://github.com/rustdesk/rustdesk/blob/master/src/lan.rs · https://cveawg.mitre.org/api/cve/CVE-2026-30789
- **Steam and CRD:** https://help.steampowered.com/en/faqs/view/3E3D-BE6B-787D-A5D2 · https://www.gamingonlinux.com/2026/09/steam-beta-adds-experimental-new-pyrowave-video-codec-for-remote-play/page=1/ · https://themaister.net/blog/2025/06/16/i-designed-my-own-ridiculously-fast-game-streaming-video-codec-pyrowave/ · https://chromium.googlesource.com/chromium/src/+/master/remoting/protocol/webrtc_transport.h
- **IETF:** https://datatracker.ietf.org/doc/html/draft-ietf-rmcat-gcc-02 · https://www.rfc-editor.org/rfc/rfc8298 · https://datatracker.ietf.org/doc/draft-ietf-ccwg-rfc8298bis-screamv2/ · https://www.rfc-editor.org/rfc/rfc8698 · https://www.rfc-editor.org/rfc/rfc8888 · https://www.rfc-editor.org/rfc/rfc9221 · https://datatracker.ietf.org/doc/draft-ietf-avtcore-rtp-over-quic/ · https://www.rfc-editor.org/rfc/rfc8445 · https://www.rfc-editor.org/rfc/rfc2644
- **Other:** https://tailscale.com/blog/how-nat-traversal-works · https://docs.nefarius.at/projects/ViGEm/End-of-Life/ · https://www.via-la.com/licensing-programs/avc-h-264/ · https://opus-codec.org/license/ · https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/wake-on-lan-feature · https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
