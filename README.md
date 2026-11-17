# zource

`zource` is a repository history and live working-tree visualizer written in Zig. Inspired by Gource, it runs natively inside modern graphics-capable terminals—even over SSH on headless machines with no X11 or Wayland libraries installed—while also supporting hardware-accelerated native Wayland windows when `-w` / `--wayland` is passed.

## Capabilities

- **Terminal Graphics Protocols (Default)**:
  - **Kitty & Ghostty (`--protocol kitty`)**: Streams 24-bit RGB frames compressed with zlib (`f=24,o=z`) over the Kitty Graphics Protocol (`\x1b_G...`), wrapped in DEC Mode 2026 synchronized output (`?2026h` / `?2026l`), Kitty Keyboard Protocol (`\x1b[>1u`), and SGR mouse tracking (`?1002h` / `?1006h`). Auto-detected both locally via environment and over remote SSH via non-blocking APC graphics query on `/dev/tty`.
  - **Foot (`--protocol sixel`)**: Encodes ordered-dithered 216-color Sixel bands with RLE compression inside DEC Mode 2026 synchronized frames. Auto-detected via `TERM=foot*` or VT DA1 capability attribute `4` over SSH.
  - **Plain TTY Fallback (`--protocol ansi`)**: Renders 24-bit ANSI truecolor UTF-8 half-blocks (`▀`) when neither Kitty graphics nor Sixel is available.
- **Dual 3D Rotating Bubbles & 2D Radial Tree**:
  - **3D Rotating Bubbles (`--3d`, default)**: Directories form translucent 3D Fresnel glass spheres arranged on Fibonacci orbital shells around parent directories, enclosing lit 3D file orbs and flying contributor orbs that fire additive commit beams. Works identically inside Kitty, Ghostty, Foot, Wayland, and headless PPM export.
  - **2D Radial Tree (`--2d`)**: Classic force-relaxed Gource radial directory graph. Switch live between 2D and 3D at any time with `Tab` (`2` / `3` / `v`).
- **Optional Native Wayland Window (`-w` / `--wayland`)**:
  - Loads `libwayland-client.so.0`, `libwayland-egl.so.1`, `libEGL.so.1`, and `libGLESv2.so.2` at runtime via `std.DynLib` (`dlopen`), compiling GLES ray-impostor 3D sphere & Fresnel shell shaders on the GPU (or falling back to `wl_shm` `memfd_create` buffers if EGL/GLES is absent). Zero Wayland or OpenGL libraries are linked at build time, so a single binary runs on bare headless servers.
- **Input & Output Modes**:
  - **Git (`.git`)** and **Mercurial (`.hg`)**: Auto-detected upward from the target directory (`--git` / `--hg` to force).
  - **Gource Custom Log Pipe (`--log <file|->`)**: Reads `timestamp|author|A/M/D|path[|RRGGBB]` from a file or live `stdin` stream while keeping keyboard/mouse controls active on `/dev/tty`.
  - **Live Working-Tree Watch (`--live`)**: Uses Linux `inotify` across directory trees to animate file creates, edits, and deletes as they happen.
  - **Headless FFmpeg / PPM Export (`--output-ppm <file|->`)**: Streams binary `P6` PPM frames with no terminal or display server required.

## Build

Requires Zig `0.17.0` (no external C headers or package dependencies required):

```bash
zig build -Doptimize=ReleaseFast
zig build test
```

The binary is placed at `zig-out/bin/zource`.

## Usage Examples

```bash
# Visualize the current Git or Mercurial repo in Ghostty, Kitty, or Foot (3D bubbles by default)
./zig-out/bin/zource

# Visualize another repository starting in 2D radial tree mode at 0.5s per day
./zig-out/bin/zource --2d -s 0.5 ~/Projects/cheatdetectorplugin

# Open a hardware-accelerated native Wayland window
./zig-out/bin/zource --wayland ~/Projects/whalehouse

# Force Foot Sixel or Kitty protocol explicitly
./zig-out/bin/zource --protocol sixel
./zig-out/bin/zource --protocol kitty

# Watch live edits in a working directory via inotify
./zig-out/bin/zource --live .

# Stream Gource custom pipe logs from stdin
cat events.log | ./zig-out/bin/zource --log -

# Render a 60fps 1080p MP4 video on a headless server with ffmpeg
./zig-out/bin/zource --size 1920x1080 --fps 60 --max-frames 600 --output-ppm - . \
  | ffmpeg -y -f image2pipe -vcodec ppm -r 60 -i - -c:v libx264 -pix_fmt yuv420p repo.mp4
```

## Controls

| Input | Action |
| :--- | :--- |
| `Space` | Play / Pause timeline |
| `Tab`, `V`, `2`, `3` | Smoothly morph between 2D Radial Tree and 3D Rotating Bubbles |
| `Left-drag` or `WASD` / `Arrows` | Orbit 3D camera (`yaw` / `pitch`) |
| `Right-drag` | Pan camera |
| `Scroll wheel` or `Z` / `X` | Zoom in / out |
| `+` / `-` (or `]` / `[`) | Speed up / slow down simulation (`seconds-per-day`) |
| `,` / `.` | Seek backward / forward 5% |
| `O` | Toggle automatic 3D camera orbit |
| `L` / `B` | Toggle labels / radial glow bloom |
| `R` | Restart from first commit |
| `Q` or `Esc` | Quit |
