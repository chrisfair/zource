# zource

`zource` visualizes Git and Mercurial commit history (or live directory edits) as an animated force-directed graph, written in Zig.

By default it renders inside graphics-capable terminals—Kitty, Ghostty, WezTerm, and Foot—including over SSH on headless Linux boxes where no X11 or Wayland libraries are installed. Passing `-w` (`--wayland`) dynamically opens `libwayland-client`, `libEGL`, and `libGLESv2` via `dlopen(3)` to run hardware-accelerated 3D sphere shaders in a native Wayland window (falling back to `wl_shm` shared-memory buffers if EGL/GLES is absent).

## Architecture & Protocols

Terminal rendering (`--protocol auto`) probes the active TTY when environment variables like `KITTY_WINDOW_ID`, `GHOSTTY_RESOURCES_DIR`, or `TERM=foot*` aren't forwarded over SSH:

| Protocol | Flag | Transport |
| :--- | :--- | :--- |
| Kitty / Ghostty | `--protocol kitty` | 24-bit RGB compressed with zlib (`\x1b_Ga=T,f=24,o=z...`) inside DEC Mode 2026 (`?2026h`/`?2026l`), Kitty keyboard (`\x1b[>1u`), and SGR mouse tracking. |
| Foot (Sixel) | `--protocol sixel` | 216-color ordered-dithered RLE Sixel bands (`\x1bP0;1;0q...`) inside DEC Mode 2026; auto-detected via `TERM=foot*` or VT DA1 attribute `4`. |
| Plain TTY | `--protocol ansi` | 24-bit ANSI truecolor UTF-8 half-block (`▀`) cells. |

Two layouts are available and can be toggled live with `Tab` (`2` / `3` / `v`):

1. `3D Rotating Bubbles` (`--3d`, default): Directories form nested translucent Fresnel spheres arranged on Fibonacci orbital shells around parent directories, enclosing lit 3D file orbs and contributor orbs firing commit beams.
2. `2D Radial Tree` (`--2d`): Force-relaxed radial directory tree with phyllotaxis file discs.

Input sources:
- Git (`.git`) and Mercurial (`.hg`) repositories, auto-detected upward from the target path (`--git` / `--hg` to force).
- Gource custom pipe logs (`--log <file|->` or piped `stdin`): `timestamp|author|A/M/D|path[|RRGGBB]`. Terminal input is read from `/dev/tty` so `stdin` stays free for event streams.
- Live working-tree watch (`--live`): Recursive Linux `inotify(7)` watches across directories.
- Headless video export (`--output-ppm <file|->`): Raw `P6` PPM frame stream requiring no TTY or display server.

## Installation

Arch Linux (AUR):

```bash
yay -S zource
```

Build from source (`mise.toml` pins Zig `0.17.0` and `Makefile` bootstraps `mise` if neither `zig` nor `mise` is installed):

```bash
make bootstrap
make test
make build
```

Or directly with Zig `0.17.0+`:

```bash
zig build -Doptimize=ReleaseFast
zig build test
```

## Usage

```bash
# 3D rotating bubbles in Ghostty, Kitty, or Foot
./zig-out/bin/zource

# Start in 2D radial tree mode at 0.5 seconds per repository day
./zig-out/bin/zource --2d -s 0.5 ~/src/repo

# Native Wayland window (EGL/GLES shaders or wl_shm fallback)
./zig-out/bin/zource --wayland ~/src/repo

# Force Sixel or Kitty protocol explicitly
./zig-out/bin/zource --protocol sixel
./zig-out/bin/zource --protocol kitty

# Watch live file edits via inotify
./zig-out/bin/zource --live .

# Stream Gource custom pipe logs from stdin
cat events.log | ./zig-out/bin/zource --log -

# Encode a 60fps 1080p MP4 on a headless box with ffmpeg
./zig-out/bin/zource --size 1920x1080 --fps 60 --stop-at-end --output-ppm - . \
  | ffmpeg -y -f image2pipe -vcodec ppm -r 60 -i - -c:v libx264 -pix_fmt yuv420p history.mp4
```

See `man -l ./man/zource.1` (or `man zource` once installed) for the full option list.

## Controls

| Input | Action |
| :--- | :--- |
| `Space` | Play / Pause timeline |
| `Tab`, `V`, `2`, `3` | Morph between 2D Radial Tree and 3D Rotating Bubbles |
| `Left-drag` or `WASD` / `Arrows` | Orbit camera (`yaw` / `pitch`) |
| `Right-drag` | Pan viewport |
| `Scroll wheel` or `Z` / `X` | Zoom in / out |
| `+` / `-` (or `]` / `[`) | Adjust simulation speed (`seconds-per-day`) |
| `,` / `.` | Seek backward / forward 5% |
| `O` | Toggle automatic 3D camera orbit |
| `L` / `B` | Toggle labels / radial glow halos |
| `R` | Restart from first commit |
| `Q` or `Esc` | Quit |

## License

GNU General Public License v3.0 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE).
