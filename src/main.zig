const std = @import("std");
const vcs = @import("vcs.zig");
const sim_mod = @import("sim.zig");
const raster = @import("raster.zig");
const terminal = @import("terminal.zig");
const wayland = @import("wayland.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Config = struct {
    target_path: []const u8 = ".",
    path_explicit: bool = false,
    vcs_kind: vcs.VcsKind = .auto,
    custom_log_path: ?[]const u8 = null,
    live_watch: bool = false,

    use_wayland: bool = false,
    wayland_strict: bool = false,
    protocol: terminal.Protocol = .auto,
    view_mode: sim_mod.ViewMode = .bubbles_3d,

    output_ppm: ?[]const u8 = null,
    max_frames: usize = 0,
    width: u32 = 1280,
    height: u32 = 720,
    size_explicit: bool = false,
    fps: u32 = 30,

    seconds_per_day: f64 = 1.0,
    max_commits: usize = 0,
    loop_playback: bool = false,
    auto_skip_idle: bool = true,
    auto_orbit: bool = true,
    show_labels: bool = true,
    enable_bloom: bool = true,
    stop_at_end: bool = false,
    show_help: bool = false,
};

fn parseSizeArg(s: []const u8) ?struct { w: u32, h: u32 } {
    const sep = std.mem.indexOfAny(u8, s, "xX") orelse return null;
    const w = std.fmt.parseInt(u32, s[0..sep], 10) catch return null;
    const h = std.fmt.parseInt(u32, s[sep + 1 ..], 10) catch return null;
    if (w < 64 or h < 64 or w > 7680 or h > 4320) return null;
    return .{ .w = w, .h = h };
}

fn parseCliArgs(args: std.process.Args) !Config {
    var cfg = Config{};
    var it = std.process.Args.Iterator.init(args);
    _ = it.skip(); // argv[0]

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            cfg.show_help = true;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--wayland")) {
            cfg.use_wayland = true;
        } else if (std.mem.eql(u8, arg, "--wayland-only")) {
            cfg.use_wayland = true;
            cfg.wayland_strict = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--terminal")) {
            cfg.use_wayland = false;
        } else if (std.mem.eql(u8, arg, "--2d")) {
            cfg.view_mode = .tree_2d;
        } else if (std.mem.eql(u8, arg, "--3d")) {
            cfg.view_mode = .bubbles_3d;
        } else if (std.mem.eql(u8, arg, "--live")) {
            cfg.live_watch = true;
            cfg.vcs_kind = .live;
        } else if (std.mem.eql(u8, arg, "--git")) {
            cfg.vcs_kind = .git;
        } else if (std.mem.eql(u8, arg, "--hg") or std.mem.eql(u8, arg, "--mercurial")) {
            cfg.vcs_kind = .hg;
        } else if (std.mem.eql(u8, arg, "--loop")) {
            cfg.loop_playback = true;
        } else if (std.mem.eql(u8, arg, "--stop-at-end")) {
            cfg.stop_at_end = true;
        } else if (std.mem.eql(u8, arg, "--no-auto-skip")) {
            cfg.auto_skip_idle = false;
        } else if (std.mem.eql(u8, arg, "--no-orbit")) {
            cfg.auto_orbit = false;
        } else if (std.mem.eql(u8, arg, "--no-labels")) {
            cfg.show_labels = false;
        } else if (std.mem.eql(u8, arg, "--no-bloom")) {
            cfg.enable_bloom = false;
        } else if (std.mem.eql(u8, arg, "--protocol") or std.mem.eql(u8, arg, "-p")) {
            const val = it.next() orelse return error.MissingArgValue;
            if (std.ascii.eqlIgnoreCase(val, "auto")) {
                cfg.protocol = .auto;
            } else if (std.ascii.eqlIgnoreCase(val, "kitty") or std.ascii.eqlIgnoreCase(val, "ghostty")) {
                cfg.protocol = .kitty;
            } else if (std.ascii.eqlIgnoreCase(val, "sixel") or std.ascii.eqlIgnoreCase(val, "foot")) {
                cfg.protocol = .sixel;
            } else if (std.ascii.eqlIgnoreCase(val, "ansi") or std.ascii.eqlIgnoreCase(val, "halfblock")) {
                cfg.protocol = .ansi;
            } else {
                return error.InvalidProtocol;
            }
        } else if (std.mem.eql(u8, arg, "--vcs")) {
            const val = it.next() orelse return error.MissingArgValue;
            if (std.ascii.eqlIgnoreCase(val, "auto")) {
                cfg.vcs_kind = .auto;
            } else if (std.ascii.eqlIgnoreCase(val, "git")) {
                cfg.vcs_kind = .git;
            } else if (std.ascii.eqlIgnoreCase(val, "hg") or std.ascii.eqlIgnoreCase(val, "mercurial")) {
                cfg.vcs_kind = .hg;
            } else if (std.ascii.eqlIgnoreCase(val, "custom")) {
                cfg.vcs_kind = .custom;
            } else if (std.ascii.eqlIgnoreCase(val, "live")) {
                cfg.vcs_kind = .live;
                cfg.live_watch = true;
            } else {
                return error.InvalidVcs;
            }
        } else if (std.mem.eql(u8, arg, "--log")) {
            const val = it.next() orelse return error.MissingArgValue;
            cfg.custom_log_path = val;
            cfg.vcs_kind = .custom;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output-ppm")) {
            cfg.output_ppm = it.next() orelse return error.MissingArgValue;
        } else if (std.mem.eql(u8, arg, "--max-frames")) {
            const val = it.next() orelse return error.MissingArgValue;
            cfg.max_frames = std.fmt.parseInt(usize, val, 10) catch return error.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--fps")) {
            const val = it.next() orelse return error.MissingArgValue;
            cfg.fps = @max(1, @min(144, std.fmt.parseInt(u32, val, 10) catch return error.InvalidNumber));
        } else if (std.mem.eql(u8, arg, "--size")) {
            const val = it.next() orelse return error.MissingArgValue;
            const sz = parseSizeArg(val) orelse return error.InvalidSize;
            cfg.width = sz.w;
            cfg.height = sz.h;
            cfg.size_explicit = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--seconds-per-day")) {
            const val = it.next() orelse return error.MissingArgValue;
            cfg.seconds_per_day = @max(0.02, std.fmt.parseFloat(f64, val) catch return error.InvalidNumber);
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--max-commits")) {
            const val = it.next() orelse return error.MissingArgValue;
            cfg.max_commits = std.fmt.parseInt(usize, val, 10) catch return error.InvalidNumber;
        } else if (arg.len > 0 and arg[0] == '-' and !std.mem.eql(u8, arg, "-")) {
            return error.UnknownFlag;
        } else {
            if (std.mem.eql(u8, arg, "-")) {
                cfg.custom_log_path = "-";
                cfg.vcs_kind = .custom;
            } else {
                cfg.target_path = arg;
                cfg.path_explicit = true;
            }
        }
    }
    return cfg;
}

fn printUsage(io: Io) !void {
    var buf: [2048]u8 = undefined;
    var fw = Io.File.Writer.init(.stdout(), io, &buf);
    const w = &fw.interface;
    try w.writeAll(
        \\zource - 2D/3D repository history & live edit visualizer for Kitty, Ghostty, Foot, and Wayland
        \\
        \\Usage:
        \\  zource [options] [repo_or_dir_or_-]
        \\
        \\Display & View Modes:
        \\  -t, --terminal            Render in terminal (default: auto-detects Kitty/Ghostty, Foot Sixel, or ANSI)
        \\  -w, --wayland             Open a native Wayland window (runtime dlopen of EGL/GLESv2 or wl_shm fallback)
        \\  -p, --protocol <mode>     Terminal graphics protocol: auto | kitty | sixel | ansi
        \\  --3d                      Start in 3D rotating bubble cluster mode (default)
        \\  --2d                      Start in classic 2D Gource radial tree mode
        \\  --size <WxH>              Pixel resolution cap in terminal, or window/PPM dimensions (e.g. 1280x720)
        \\  --fps <N>                 Target frame rate (default: 30 in terminal/PPM, 60 in Wayland)
        \\
        \\Input & Export Sources:
        \\  --vcs <auto|git|hg|live>  Force VCS backend (auto-detects .git and .hg upward)
        \\  --hg, --mercurial         Force Mercurial history mode
        \\  --log <file|->            Read Gource custom log format: timestamp|author|A/M/D|path[|RRGGBB]
        \\  --live                    Watch directory edits live via Linux inotify
        \\  -o, --output-ppm <file|-> Render headless P6 PPM stream for ffmpeg (works with zero TTY/Wayland)
        \\  --max-frames <N>          Stop after rendering N frames (useful with --output-ppm or CI smoke runs)
        \\  --stop-at-end             Exit automatically once commit playback finishes
        \\
        \\Playback & Appearance:
        \\  -s, --seconds-per-day <F> Simulation speed in seconds per repository day (default: 1.0)
        \\  -n, --max-commits <N>     Limit history to the most recent N commits/changesets
        \\  --loop                    Restart from commit 1 when history finishes
        \\  --no-auto-skip            Do not fast-forward idle multi-day gaps
        \\  --no-orbit                Disable automatic 3D camera rotation on startup
        \\  --no-labels               Hide in-scene directory and author labels
        \\  --no-bloom                Disable radial sphere glow halos
        \\
        \\Interactive Controls (Wayland & Terminal):
        \\  Space         Play / Pause               Tab / V / 2 / 3  Switch 2D Tree <-> 3D Bubbles
        \\  + / -         Adjust playback speed      , / .            Seek backward / forward 5%
        \\  Drag / Arrows Orbit 3D bubble camera     Scroll / Z / X   Zoom in / out
        \\  O             Toggle auto-orbit          L / B            Toggle labels / bloom
        \\  R             Restart playback           Q / Esc          Quit
        \\
    );
    try w.flush();
}

fn applyInputEvents(sim: *sim_mod.Simulation, events: []const terminal.InputEvent) !bool {
    for (events) |ev| {
        switch (ev) {
            .quit => return true,
            .toggle_pause => sim.paused = !sim.paused,
            .toggle_view_mode => sim.view_mode = sim.view_mode.toggle(),
            .set_2d => sim.view_mode = .tree_2d,
            .set_3d => sim.view_mode = .bubbles_3d,
            .toggle_auto_orbit => sim.camera.auto_orbit = !sim.camera.auto_orbit,
            .toggle_labels => sim.show_labels = !sim.show_labels,
            .toggle_bloom => sim.enable_bloom = !sim.enable_bloom,
            .speed_up => sim.seconds_per_day = @max(0.02, sim.seconds_per_day * 0.72),
            .speed_down => sim.seconds_per_day = @min(120.0, sim.seconds_per_day * 1.38),
            .seek_forward => try sim.seekRelative(0.05),
            .seek_backward => try sim.seekRelative(-0.05),
            .restart => try sim.restart(),
            .orbit => |o| {
                sim.camera.yaw = @mod(sim.camera.yaw + o.dyaw, std.math.tau);
                sim.camera.pitch = std.math.clamp(sim.camera.pitch + o.dpitch, -1.42, 1.42);
            },
            .pan => |p| {
                sim.camera.pan_x += p.dx;
                sim.camera.pan_y += p.dy;
            },
            .zoom => |z| {
                sim.camera.zoom = std.math.clamp(sim.camera.zoom * z, 0.22, 6.0);
            },
        }
    }
    return false;
}

fn monotonicSeconds() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) * 1e-9;
}

fn sleepSeconds(sec: f64) void {
    if (sec <= 0.0002) return;
    const whole: isize = @intFromFloat(@floor(sec));
    const frac_ns: isize = @intFromFloat((sec - @floor(sec)) * 1e9);
    var req = std.c.timespec{ .sec = whole, .nsec = frac_ns };
    _ = std.c.nanosleep(&req, null);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var cfg = parseCliArgs(init.minimal.args) catch |err| {
        var ebuf: [512]u8 = undefined;
        var ew = Io.File.Writer.init(.stderr(), io, &ebuf);
        try ew.interface.print("zource: argument error ({s}). Try --help.\n", .{@errorName(err)});
        try ew.interface.flush();
        std.process.exit(2);
    };

    if (cfg.show_help) {
        try printUsage(io);
        return;
    }

    if (!cfg.path_explicit and cfg.custom_log_path == null and !cfg.live_watch and !terminal.isFdTty(0)) {
        cfg.custom_log_path = "-";
        cfg.vcs_kind = .custom;
    }

    var repo_info: ?vcs.RepoInfo = null;
    defer if (repo_info) |*ri| ri.deinit(gpa);

    var repo_name: []const u8 = "stream";
    var resolved_vcs = cfg.vcs_kind;
    var repo_root: []const u8 = cfg.target_path;

    if (cfg.vcs_kind != .custom) {
        repo_info = vcs.detectRepo(gpa, cfg.target_path, cfg.vcs_kind) catch |err| {
            var ebuf: [512]u8 = undefined;
            var ew = Io.File.Writer.init(.stderr(), io, &ebuf);
            try ew.interface.print(
                "zource: no .git or .hg repository found at '{s}' ({s}). Pass --live to watch a plain directory or --log <file|->.\n",
                .{ cfg.target_path, @errorName(err) },
            );
            try ew.interface.flush();
            std.process.exit(1);
        };
        repo_name = repo_info.?.name;
        resolved_vcs = repo_info.?.kind;
        repo_root = repo_info.?.root_path;
    } else if (cfg.custom_log_path) |lp| {
        repo_name = if (std.mem.eql(u8, lp, "-")) "stdin-pipe" else std.fs.path.basename(lp);
    }

    var sim = try sim_mod.Simulation.init(gpa, repo_name, resolved_vcs, cfg.view_mode);
    defer sim.deinit();
    sim.seconds_per_day = cfg.seconds_per_day;
    sim.loop_playback = cfg.loop_playback;
    sim.auto_skip_idle = cfg.auto_skip_idle;
    sim.camera.auto_orbit = cfg.auto_orbit;
    sim.show_labels = cfg.show_labels;
    sim.enable_bloom = cfg.enable_bloom;

    var pipe_stream: ?vcs.PipeStream = null;
    var live_watcher: ?vcs.LiveWatcher = null;
    defer if (live_watcher) |*lw| lw.deinit();

    switch (resolved_vcs) {
        .git => {
            vcs.loadGitHistory(gpa, sim.arena(), io, repo_root, cfg.max_commits, &sim.events) catch |err| {
                var ebuf: [512]u8 = undefined;
                var ew = Io.File.Writer.init(.stderr(), io, &ebuf);
                try ew.interface.print("zource: failed to read git history in '{s}' ({s})\n", .{ repo_root, @errorName(err) });
                try ew.interface.flush();
                std.process.exit(1);
            };
            sim.finalizeLoadedEvents();
        },
        .hg => {
            vcs.loadHgHistory(gpa, sim.arena(), io, repo_root, cfg.max_commits, &sim.events) catch |err| {
                var ebuf: [512]u8 = undefined;
                var ew = Io.File.Writer.init(.stderr(), io, &ebuf);
                try ew.interface.print("zource: failed to read Mercurial (hg) history in '{s}' ({s})\n", .{ repo_root, @errorName(err) });
                try ew.interface.flush();
                std.process.exit(1);
            };
            sim.finalizeLoadedEvents();
        },
        .custom => {
            const lp = cfg.custom_log_path orelse "-";
            if (std.mem.eql(u8, lp, "-")) {
                pipe_stream = vcs.PipeStream.init(0);
                var seed_batch: std.ArrayList(vcs.Event) = .empty;
                try pipe_stream.?.pollEvents(sim.arena(), &seed_batch);
                if (pipe_stream.?.eof) {
                    try sim.events.appendSlice(sim.arena(), seed_batch.items);
                    sim.finalizeLoadedEvents();
                    pipe_stream = null;
                } else {
                    sim.streaming_mode = true;
                    try sim.appendStreamEvents(seed_batch.items);
                }
            } else {
                try vcs.loadCustomLogFile(gpa, sim.arena(), io, lp, &sim.events);
                sim.finalizeLoadedEvents();
            }
        },
        .live => {
            const user_env = init.environ_map.get("USER") orelse "developer";
            var seed_events: std.ArrayList(vcs.Event) = .empty;
            live_watcher = try vcs.LiveWatcher.init(gpa, sim.arena(), repo_root, user_env, &seed_events);
            sim.streaming_mode = true;
            const now = vcs.nowEpochSeconds();
            sim.start_time = now;
            sim.end_time = now;
            sim.sim_time = now;
            for (seed_events.items) |ev| {
                try sim.applyEvent(ev, false);
            }
        },
        .auto => unreachable,
    }

    terminal.installSignalHandlers();

    if (cfg.output_ppm) |ppm_target| {
        const out_file = if (std.mem.eql(u8, ppm_target, "-"))
            Io.File.stdout()
        else
            try Io.Dir.cwd().createFile(io, ppm_target, .{});
        defer if (!std.mem.eql(u8, ppm_target, "-")) out_file.close(io);

        var out_buf: [65536]u8 = undefined;
        var fw = Io.File.Writer.init(out_file, io, &out_buf);
        var fb = try raster.Framebuffer.init(gpa, cfg.width, cfg.height);
        defer fb.deinit();

        const dt: f32 = 1.0 / @as(f32, @floatFromInt(cfg.fps));
        var frames_written: usize = 0;

        while (!terminal.g_signal_quit.load(.acquire)) {
            if (pipe_stream) |*ps| {
                var batch: std.ArrayList(vcs.Event) = .empty;
                try ps.pollEvents(sim.arena(), &batch);
                try sim.appendStreamEvents(batch.items);
            }
            try sim.step(dt);
            try fb.renderSimulation(&sim);
            try fb.writePpmFrame(&fw.interface);
            frames_written += 1;

            if (cfg.max_frames > 0 and frames_written >= cfg.max_frames) break;
            if (sim.finished and (cfg.stop_at_end or cfg.max_frames == 0)) break;
        }
        try fw.interface.flush();
        return;
    }

    var wl_win: ?*wayland.WaylandWindow = null;
    defer if (wl_win) |w| w.deinit();

    if (cfg.use_wayland) {
        const has_wl_env = init.environ_map.get("WAYLAND_DISPLAY") != null;
        if (has_wl_env) {
            var title_buf: [192]u8 = undefined;
            const win_title = std.fmt.bufPrint(&title_buf, "zource — {s} ({s})", .{ repo_name, resolved_vcs.badge() }) catch "zource";
            wl_win = wayland.WaylandWindow.init(gpa, cfg.width, cfg.height, win_title) catch |err| blk: {
                if (cfg.wayland_strict) return err;
                var ebuf: [256]u8 = undefined;
                var ew = Io.File.Writer.init(.stderr(), io, &ebuf);
                try ew.interface.print("zource: Wayland unavailable ({s}), falling back to terminal.\n", .{@errorName(err)});
                try ew.interface.flush();
                break :blk null;
            };
        } else if (cfg.wayland_strict) {
            return error.WaylandDisplayUnset;
        }
    }

    var input_events: std.ArrayList(terminal.InputEvent) = .empty;
    defer input_events.deinit(gpa);

    if (wl_win) |win| {
        const target_fps: u32 = if (cfg.fps == 30) 60 else cfg.fps;
        const frame_budget = 1.0 / @as(f64, @floatFromInt(target_fps));
        var fallback_fb = try raster.Framebuffer.init(gpa, win.width, win.height);
        defer fallback_fb.deinit();

        var prev_t = monotonicSeconds();
        var frame_idx: usize = 0;

        while (true) {
            const now_t = monotonicSeconds();
            const dt: f32 = @floatCast(@min(0.1, @max(0.001, now_t - prev_t)));
            prev_t = now_t;

            input_events.clearRetainingCapacity();
            try win.pollInput(&input_events);
            if (try applyInputEvents(&sim, input_events.items)) break;

            if (pipe_stream) |*ps| {
                var batch: std.ArrayList(vcs.Event) = .empty;
                try ps.pollEvents(sim.arena(), &batch);
                try sim.appendStreamEvents(batch.items);
            }
            if (live_watcher) |*lw| {
                var batch: std.ArrayList(vcs.Event) = .empty;
                try lw.pollEvents(sim.arena(), &batch);
                try sim.appendStreamEvents(batch.items);
            }

            try sim.step(dt);
            try win.renderAndPresent(&sim, &fallback_fb);
            frame_idx += 1;

            if (cfg.max_frames > 0 and frame_idx >= cfg.max_frames) break;
            if (cfg.stop_at_end and sim.finished) break;

            const elapsed = monotonicSeconds() - now_t;
            sleepSeconds(frame_budget - elapsed);
        }
        return;
    }

    const max_term_w: u32 = if (cfg.size_explicit) cfg.width else 960;
    const max_term_h: u32 = if (cfg.size_explicit) cfg.height else 560;
    var term = try terminal.TerminalBackend.init(gpa, cfg.protocol, init.environ_map, max_term_w, max_term_h);
    defer term.deinit();

    var fb = try raster.Framebuffer.init(gpa, term.pixel_w, term.pixel_h);
    defer fb.deinit();

    const frame_budget = 1.0 / @as(f64, @floatFromInt(cfg.fps));
    var prev_t = monotonicSeconds();
    var frame_idx: usize = 0;

    while (true) {
        const now_t = monotonicSeconds();
        const dt: f32 = @floatCast(@min(0.1, @max(0.001, now_t - prev_t)));
        prev_t = now_t;

        term.refreshDimensions();
        try fb.resize(term.pixel_w, term.pixel_h);

        input_events.clearRetainingCapacity();
        try term.pollInput(&input_events);
        if (try applyInputEvents(&sim, input_events.items)) break;

        if (pipe_stream) |*ps| {
            var batch: std.ArrayList(vcs.Event) = .empty;
            try ps.pollEvents(sim.arena(), &batch);
            try sim.appendStreamEvents(batch.items);
        }
        if (live_watcher) |*lw| {
            var batch: std.ArrayList(vcs.Event) = .empty;
            try lw.pollEvents(sim.arena(), &batch);
            try sim.appendStreamEvents(batch.items);
        }

        try sim.step(dt);
        try fb.renderSimulation(&sim);
        try term.present(&fb);
        frame_idx += 1;

        if (cfg.max_frames > 0 and frame_idx >= cfg.max_frames) break;
        if (cfg.stop_at_end and sim.finished) break;

        const elapsed = monotonicSeconds() - now_t;
        sleepSeconds(frame_budget - elapsed);
    }
}

test {
    _ = vcs;
    _ = sim_mod;
    _ = @import("font.zig");
    _ = @import("polyhedron.zig");
    _ = raster;
    _ = terminal;
    _ = wayland;
}
