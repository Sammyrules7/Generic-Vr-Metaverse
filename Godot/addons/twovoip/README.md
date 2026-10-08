# TwoVoip native extension

Vendored from [TwoVoip v6.6](https://github.com/goatchurchprime/two-voip-godot-4/releases/tag/v6.6),
commit `141db995f95ddb3b0677a54f2bb2901794e59b55` (MIT).
The upstream `TwoVoIP.zip` SHA-256 is
`e5a84a6e6bb14d6f734edf53d06bfb76e7835a31c0851d51de2421b2a91f8ad0`.
Only the GDExtension and its libraries are included; the demonstration scenes and
GDScript helper/UI layers are unnecessary for this project.

`Networking/voice_chat.gd` uses `TwovoipOpusEncoder` for mono 48 kHz, 20 ms,
24 kbit/s Opus with RNNoise, and `AudioStreamOpus` / `AudioStreamPlaybackOpus`
for native decoding and buffered positional playback. Godot's AudioServer captures
microphone frames directly. The existing worker performs sample-rate conversion,
noise suppression, gain, activity measurement, encoding, and packet decoding;
Godot's audio thread mixes the native playback ring. There is no PCM wire format,
GDScript sample conversion, or decoded-audio queue.

The archive supplies Windows x86_64, Linux x86_64, universal macOS/iOS,
Android arm32/arm64/x86_32/x86_64, and both threaded and non-threaded Web libraries.
It does **not** supply Linux ARM or Windows ARM libraries. Other architectures
need an upstream source build. Web exports require GDExtension support and matching
`web_dlink_*` templates; the project uses threaded Web, with COOP/COEP headers
already provided by the Cloudflare worker. Microphone permission requires HTTPS
(or localhost) and a user gesture. Android presets enable RECORD_AUDIO.

## Editor fix

The upstream v6.6 `get_current_chunk()` divides by zero when Godot's editor queries
the default properties of an uninitialized encoder. `editor-defaults.patch` adds
an initialization guard. The Linux editor library is rebuilt on Ubuntu 22.04 with this patch;
export-target libraries otherwise come from the checked upstream archive.
When using the editor on another OS, rebuild its library with the same patch.

To rebuild from a recursive checkout of the pinned upstream commit, apply
`editor-defaults.patch` and use the platform's upstream build toolchain:

```sh
git apply /path/to/this/addon/editor-defaults.patch
git apply /path/to/this/addon/build-cwd.patch
scons apply_patches
scons build_opus
scons build_rnnoise
scons -j4 platform=linux target=template_debug
```

The build-only `build-cwd.patch` restores the working directory after building
external libraries, including with the SCons version shipped in Ubuntu 22.04.
Run those targets sequentially because they change the process working directory.

Keep the upstream and bundled codec licenses alongside the binaries. Opus,
RNNoise, and SpeexDSP notices are included in their respective `*-LICENSE` files.
