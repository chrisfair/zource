const std = @import("std");
const raster = @import("raster.zig");
const Allocator = std.mem.Allocator;
const Framebuffer = raster.Framebuffer;

pub const Protocol = enum {
    auto,
    kitty,
    sixel,
    ansi,

    pub fn name(self: Protocol) []const u8 {
        return switch (self) {
            .auto => "auto",
            .kitty => "kitty",
            .sixel => "sixel",
            .ansi => "ansi",
        };
    }
};

pub const InputEvent = union(enum) {
    quit,
    toggle_pause,
    toggle_view_mode,
    set_2d,
    set_3d,
    toggle_auto_orbit,
    toggle_labels,
    toggle_bloom,
    speed_up,
    speed_down,
    seek_forward,
    seek_backward,
    restart,
    orbit: struct { dyaw: f32, dpitch: f32 },
    pan: struct { dx: f32, dy: f32 },
    zoom: f32,
};

const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const Termios = extern struct {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [32]u8,
    c_ispeed: u32,
    c_ospeed: u32,
};

const TIOCGWINSZ: c_ulong = 0x5413;
const TCSANOW: c_int = 0;
const ICANON: u32 = 0o0000002;
const ECHO: u32 = 0o0000010;
const ISIG: u32 = 0o0000001;
const IXON: u32 = 0o0002000;
const ICRNL: u32 = 0o0000400;
const VMIN: usize = 6;
const VTIME: usize = 5;
const POLLIN: c_short = 0x0001;
const O_RDWR: c_int = 0o2;
const O_NOCTTY: c_int = 0o400;

extern "c" fn open(pathname: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
extern "c" fn poll(fds: [*]PollFd, nfds: c_ulong, timeout: c_int) c_int;
extern "c" fn tcgetattr(fd: c_int, termios_p: *Termios) c_int;
extern "c" fn tcsetattr(fd: c_int, optional_actions: c_int, termios_p: *const Termios) c_int;
extern "c" fn isatty(fd: c_int) c_int;

pub fn isFdTty(fd: c_int) bool {
    return isatty(fd) != 0;
}

fn writeAllFd(fd: c_int, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = write(fd, bytes[off..].ptr, bytes.len - off);
        if (n <= 0) return error.TerminalWriteFailed;
        off += @intCast(n);
    }
}

pub var g_signal_quit: std.atomic.Value(bool) = .init(false);

fn handleSignal(_: std.posix.SIG) callconv(.c) void {
    g_signal_quit.store(true, .release);
}

pub fn installSignalHandlers() void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(.INT, &act, null);
    std.posix.sigaction(.TERM, &act, null);
}

pub const TerminalBackend = struct {
    gpa: Allocator,
    tty_fd: c_int,
    owns_tty_fd: bool,
    out_fd: c_int,
    orig_termios: ?Termios = null,
    protocol: Protocol,

    cols: u16 = 100,
    rows: u16 = 32,
    pixel_w: u32 = 960,
    pixel_h: u32 = 540,
    max_pixel_w: u32 = 960,
    max_pixel_h: u32 = 560,

    mouse_dragging: bool = false,
    last_mouse_col: i32 = 0,
    last_mouse_row: i32 = 0,
    mouse_btn: u8 = 0,

    out_buf: std.ArrayList(u8) = .empty,
    zlib_buf: []u8,
    flate_window: []u8,
    b64_buf: []u8,
    sixel_idx_row: []u8,
    palette_emitted: bool = false,

    pub fn init(
        gpa: Allocator,
        requested: Protocol,
        environ_map: *const std.process.Environ.Map,
        max_w: u32,
        max_h: u32,
    ) !TerminalBackend {
        var tty_fd = open("/dev/tty", O_RDWR | O_NOCTTY);
        var owns_fd = true;
        if (tty_fd < 0) {
            owns_fd = false;
            tty_fd = if (isFdTty(0)) 0 else 1;
        }
        errdefer if (owns_fd and tty_fd >= 0) {
            _ = close(tty_fd);
        };

        const out_fd: c_int = 1;

        var orig_tio: ?Termios = null;
        var tio: Termios = undefined;
        if (tcgetattr(tty_fd, &tio) == 0) {
            orig_tio = tio;
            var raw = tio;
            raw.c_lflag &= ~(ICANON | ECHO | ISIG);
            raw.c_iflag &= ~(IXON | ICRNL);
            raw.c_cc[VMIN] = 0;
            raw.c_cc[VTIME] = 0;
            _ = tcsetattr(tty_fd, TCSANOW, &raw);
        }

        const resolved_proto = if (requested != .auto)
            requested
        else
            detectProtocol(tty_fd, out_fd, environ_map);

        const flate_win = try gpa.alloc(u8, std.compress.flate.max_window_len * 2);
        errdefer gpa.free(flate_win);
        const zbuf = try gpa.alloc(u8, 4 * 1024 * 1024);
        errdefer gpa.free(zbuf);
        const b64 = try gpa.alloc(u8, 6 * 1024 * 1024);
        errdefer gpa.free(b64);
        const six_row = try gpa.alloc(u8, 4096);
        errdefer gpa.free(six_row);

        var self = TerminalBackend{
            .gpa = gpa,
            .tty_fd = tty_fd,
            .owns_tty_fd = owns_fd,
            .out_fd = out_fd,
            .orig_termios = orig_tio,
            .protocol = resolved_proto,
            .max_pixel_w = @max(160, max_w),
            .max_pixel_h = @max(120, max_h),
            .zlib_buf = zbuf,
            .flate_window = flate_win,
            .b64_buf = b64,
            .sixel_idx_row = six_row,
        };

        try self.enterAltScreen();
        self.refreshDimensions();
        return self;
    }

    pub fn deinit(self: *TerminalBackend) void {
        self.leaveAltScreen() catch {};
        if (self.orig_termios) |orig| {
            _ = tcsetattr(self.tty_fd, TCSANOW, &orig);
        }
        if (self.owns_tty_fd and self.tty_fd >= 0) {
            _ = close(self.tty_fd);
        }
        self.out_buf.deinit(self.gpa);
        self.gpa.free(self.sixel_idx_row);
        self.gpa.free(self.b64_buf);
        self.gpa.free(self.zlib_buf);
        self.gpa.free(self.flate_window);
    }

    fn detectProtocol(tty_fd: c_int, out_fd: c_int, env: *const std.process.Environ.Map) Protocol {
        const term = env.get("TERM") orelse "";
        const term_prog = env.get("TERM_PROGRAM") orelse "";

        if (env.get("KITTY_WINDOW_ID") != null or
            env.get("GHOSTTY_RESOURCES_DIR") != null or
            std.mem.indexOf(u8, term, "kitty") != null or
            std.mem.indexOf(u8, term, "ghostty") != null or
            std.ascii.eqlIgnoreCase(term_prog, "ghostty") or
            std.ascii.eqlIgnoreCase(term_prog, "WezTerm") or
            std.ascii.eqlIgnoreCase(term_prog, "kitty"))
        {
            return .kitty;
        }

        if (std.mem.startsWith(u8, term, "foot")) {
            return .sixel;
        }

        // Probe active terminal over the wire (works across SSH to headless machines with no X11/Wayland)
        if (isFdTty(tty_fd)) {
            const probe_seq = "\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[c";
            writeAllFd(out_fd, probe_seq) catch return .ansi;

            var reply_buf: [512]u8 = undefined;
            var reply_len: usize = 0;
            var wait_ms: c_int = 95;

            while (reply_len < reply_buf.len) {
                var pfd = [1]PollFd{.{ .fd = tty_fd, .events = POLLIN, .revents = 0 }};
                const rc = poll(&pfd, 1, wait_ms);
                if (rc <= 0 or (pfd[0].revents & POLLIN) == 0) break;
                const n = read(tty_fd, reply_buf[reply_len..].ptr, reply_buf.len - reply_len);
                if (n <= 0) break;
                reply_len += @intCast(n);
                wait_ms = 12;
                if (std.mem.indexOfScalar(u8, reply_buf[0..reply_len], 'c') != null) break;
            }

            const resp = reply_buf[0..reply_len];
            if (std.mem.indexOf(u8, resp, "_Gi=31;OK") != null or std.mem.indexOf(u8, resp, "_Gi=31;") != null) {
                return .kitty;
            }
            if (da1AdvertisesSixel(resp)) {
                return .sixel;
            }
        }

        return .ansi;
    }

    fn enterAltScreen(self: *TerminalBackend) !void {
        // Alt screen + clear + hide cursor + SGR mouse drag/wheel + Kitty keyboard protocol (disambiguate Esc/keys)
        try writeAllFd(self.out_fd, "\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l\x1b[?1002h\x1b[?1006h\x1b[>1u");
    }

    fn leaveAltScreen(self: *TerminalBackend) !void {
        if (self.protocol == .kitty) {
            try writeAllFd(self.out_fd, "\x1b_Ga=d,d=A,q=2\x1b\\");
        }
        try writeAllFd(self.out_fd, "\x1b[<u\x1b[?1002l\x1b[?1006l\x1b[?25h\x1b[?1049l");
    }

    pub fn refreshDimensions(self: *TerminalBackend) void {
        var ws: Winsize = .{ .ws_row = 0, .ws_col = 0, .ws_xpixel = 0, .ws_ypixel = 0 };
        if (ioctl(self.tty_fd, TIOCGWINSZ, &ws) == 0 and ws.ws_col > 0 and ws.ws_row > 0) {
            self.cols = ws.ws_col;
            self.rows = ws.ws_row;
            if (ws.ws_xpixel >= 120 and ws.ws_ypixel >= 80) {
                var pw: u32 = ws.ws_xpixel;
                var ph: u32 = ws.ws_ypixel;
                if (pw > self.max_pixel_w or ph > self.max_pixel_h) {
                    const sx = @as(f32, @floatFromInt(self.max_pixel_w)) / @as(f32, @floatFromInt(pw));
                    const sy = @as(f32, @floatFromInt(self.max_pixel_h)) / @as(f32, @floatFromInt(ph));
                    const s = @min(sx, sy);
                    pw = @max(160, @as(u32, @intFromFloat(@as(f32, @floatFromInt(pw)) * s)));
                    ph = @max(120, @as(u32, @intFromFloat(@as(f32, @floatFromInt(ph)) * s)));
                }
                // Align height to 6 pixels for clean Sixel band boundaries
                self.pixel_w = pw & ~@as(u32, 1);
                self.pixel_h = (ph / 6) * 6;
                return;
            }
        }

        if (self.protocol == .ansi) {
            self.pixel_w = @as(u32, self.cols);
            self.pixel_h = @as(u32, self.rows) * 2;
        } else {
            const est_w = @min(self.max_pixel_w, @as(u32, self.cols) * 10);
            const est_h = @min(self.max_pixel_h, @as(u32, self.rows) * 20);
            self.pixel_w = @max(240, est_w & ~@as(u32, 1));
            self.pixel_h = @max(180, (est_h / 6) * 6);
        }
    }

    pub fn present(self: *TerminalBackend, fb: *const Framebuffer) !void {
        switch (self.protocol) {
            .kitty, .auto => try self.presentKitty(fb),
            .sixel => try self.presentSixel(fb),
            .ansi => try self.presentAnsiHalfBlocks(fb),
        }
    }

    fn presentKitty(self: *TerminalBackend, fb: *const Framebuffer) !void {
        var fixed_z = std.Io.Writer.fixed(self.zlib_buf);
        var comp = try std.compress.flate.Compress.init(&fixed_z, self.flate_window, .zlib, .fastest);
        try comp.writer.writeAll(fb.rgb);
        try comp.finish();
        const compressed = fixed_z.buffered();

        const b64_len = std.base64.standard.Encoder.calcSize(compressed.len);
        if (b64_len > self.b64_buf.len) {
            self.b64_buf = try self.gpa.realloc(self.b64_buf, b64_len + 4096);
        }
        const encoded = std.base64.standard.Encoder.encode(self.b64_buf[0..b64_len], compressed);

        self.out_buf.clearRetainingCapacity();
        try self.out_buf.appendSlice(self.gpa, "\x1b[?2026h\x1b[H");

        const chunk_max: usize = 4096;
        var offset: usize = 0;
        var first = true;
        while (offset < encoded.len) {
            const end = @min(offset + chunk_max, encoded.len);
            const more: u8 = if (end < encoded.len) '1' else '0';
            const payload = encoded[offset..end];

            if (first) {
                var hdr_buf: [160]u8 = undefined;
                const hdr = try std.fmt.bufPrint(
                    &hdr_buf,
                    "\x1b_Ga=T,i=1,p=1,f=24,o=z,s={d},v={d},c={d},r={d},C=1,q=2,m={c};",
                    .{ fb.width, fb.height, self.cols, self.rows, more },
                );
                try self.out_buf.appendSlice(self.gpa, hdr);
                first = false;
            } else {
                const cont = [_]u8{ '\x1b', '_', 'G', 'm', '=', more, ';' };
                try self.out_buf.appendSlice(self.gpa, &cont);
            }
            try self.out_buf.appendSlice(self.gpa, payload);
            try self.out_buf.appendSlice(self.gpa, "\x1b\\");
            offset = end;
        }

        try self.out_buf.appendSlice(self.gpa, "\x1b[?2026l");
        try writeAllFd(self.out_fd, self.out_buf.items);
    }

    fn presentSixel(self: *TerminalBackend, fb: *const Framebuffer) !void {
        const w: usize = fb.width;
        const h: usize = fb.height;
        if (w * 6 > self.sixel_idx_row.len) {
            self.sixel_idx_row = try self.gpa.realloc(self.sixel_idx_row, w * 6);
        }

        self.out_buf.clearRetainingCapacity();
        var hdr_buf: [96]u8 = undefined;
        const hdr = try std.fmt.bufPrint(&hdr_buf, "\x1b[?2026h\x1b[H\x1bP0;1;0q\"1;1;{d};{d}", .{ w, h });
        try self.out_buf.appendSlice(self.gpa, hdr);

        // Emit 6x6x6 = 216 perceptual palette registers (0..215)
        for (0..6) |r6| {
            const rp = (r6 * 100) / 5;
            for (0..6) |g6| {
                const gp = (g6 * 100) / 5;
                for (0..6) |b6| {
                    const bp = (b6 * 100) / 5;
                    const idx = r6 * 36 + g6 * 6 + b6;
                    var pbuf: [32]u8 = undefined;
                    const ps = try std.fmt.bufPrint(&pbuf, "#{d};2;{d};{d};{d}", .{ idx, rp, gp, bp });
                    try self.out_buf.appendSlice(self.gpa, ps);
                }
            }
        }

        const bayer2x2 = [4]i32{ -6, 4, 6, -4 };

        var band_y: usize = 0;
        while (band_y < h) : (band_y += 6) {
            const rows_in_band = @min(@as(usize, 6), h - band_y);
            var used_colors: [216]bool = @splat(false);

            for (0..rows_in_band) |ry| {
                const y = band_y + ry;
                var src_off = y * w * 3;
                const dst_off = ry * w;
                for (0..w) |x| {
                    const dither = bayer2x2[((y & 1) << 1) | (x & 1)];
                    const r_d: u32 = @intCast(std.math.clamp(@as(i32, fb.rgb[src_off + 0]) + dither, 0, 255));
                    const g_d: u32 = @intCast(std.math.clamp(@as(i32, fb.rgb[src_off + 1]) + dither, 0, 255));
                    const b_d: u32 = @intCast(std.math.clamp(@as(i32, fb.rgb[src_off + 2]) + dither, 0, 255));

                    const r6 = (r_d * 5 + 127) / 255;
                    const g6 = (g_d * 5 + 127) / 255;
                    const b6 = (b_d * 5 + 127) / 255;
                    const c_idx: u8 = @intCast(r6 * 36 + g6 * 6 + b6);
                    self.sixel_idx_row[dst_off + x] = c_idx;
                    used_colors[c_idx] = true;
                    src_off += 3;
                }
            }

            var first_color_in_band = true;
            for (0..216) |c_idx| {
                if (!used_colors[c_idx]) continue;
                if (!first_color_in_band) {
                    try self.out_buf.append(self.gpa, '$');
                }
                first_color_in_band = false;

                var cbuf: [12]u8 = undefined;
                const cs = try std.fmt.bufPrint(&cbuf, "#{d}", .{c_idx});
                try self.out_buf.appendSlice(self.gpa, cs);

                var run_char: u8 = 0;
                var run_len: usize = 0;

                for (0..w) |x| {
                    var bits: u8 = 0;
                    for (0..rows_in_band) |ry| {
                        if (self.sixel_idx_row[ry * w + x] == @as(u8, @intCast(c_idx))) {
                            bits |= (@as(u8, 1) << @intCast(ry));
                        }
                    }
                    const ch: u8 = 63 + bits;
                    if (run_len == 0) {
                        run_char = ch;
                        run_len = 1;
                    } else if (ch == run_char) {
                        run_len += 1;
                    } else {
                        try appendSixelRun(self.gpa, &self.out_buf, run_char, run_len);
                        run_char = ch;
                        run_len = 1;
                    }
                }
                if (run_len > 0 and run_char != 63) {
                    try appendSixelRun(self.gpa, &self.out_buf, run_char, run_len);
                }
            }

            if (band_y + 6 < h) {
                try self.out_buf.append(self.gpa, '-');
            }
        }

        try self.out_buf.appendSlice(self.gpa, "\x1b\\\x1b[?2026l");
        try writeAllFd(self.out_fd, self.out_buf.items);
    }

    fn presentAnsiHalfBlocks(self: *TerminalBackend, fb: *const Framebuffer) !void {
        self.out_buf.clearRetainingCapacity();
        try self.out_buf.appendSlice(self.gpa, "\x1b[?2026h\x1b[H");

        const cols: usize = @min(@as(usize, self.cols), fb.width);
        const rows: usize = @min(@as(usize, self.rows), fb.height / 2);

        for (0..rows) |r| {
            const y_top = (r * 2 * fb.height) / (rows * 2);
            const y_bot = @min(fb.height - 1, y_top + 1);
            for (0..cols) |c| {
                const x = (c * fb.width) / cols;
                const top_idx = (y_top * fb.width + x) * 3;
                const bot_idx = (y_bot * fb.width + x) * 3;
                var cell_buf: [48]u8 = undefined;
                const s = try std.fmt.bufPrint(
                    &cell_buf,
                    "\x1b[38;2;{d};{d};{d};48;2;{d};{d};{d}m▀",
                    .{
                        fb.rgb[top_idx + 0], fb.rgb[top_idx + 1], fb.rgb[top_idx + 2],
                        fb.rgb[bot_idx + 0], fb.rgb[bot_idx + 1], fb.rgb[bot_idx + 2],
                    },
                );
                try self.out_buf.appendSlice(self.gpa, s);
            }
            if (r + 1 < rows) {
                try self.out_buf.appendSlice(self.gpa, "\x1b[0m\r\n");
            }
        }
        try self.out_buf.appendSlice(self.gpa, "\x1b[0m\x1b[?2026l");
        try writeAllFd(self.out_fd, self.out_buf.items);
    }

    pub fn pollInput(self: *TerminalBackend, out: *std.ArrayList(InputEvent)) !void {
        if (g_signal_quit.load(.acquire)) {
            try out.append(self.gpa, .quit);
            return;
        }

        var pfd = [1]PollFd{.{ .fd = self.tty_fd, .events = POLLIN, .revents = 0 }};
        while (poll(&pfd, 1, 0) > 0 and (pfd[0].revents & POLLIN) != 0) {
            var buf: [256]u8 = undefined;
            const n = read(self.tty_fd, &buf, buf.len);
            if (n <= 0) break;
            try self.parseInputBytes(buf[0..@intCast(n)], out);
        }
    }

    pub fn parseInputBytes(self: *TerminalBackend, bytes: []const u8, out: *std.ArrayList(InputEvent)) !void {
        var i: usize = 0;
        while (i < bytes.len) {
            const b = bytes[i];
            if (b == 0x03 or b == 0x04) {
                try out.append(self.gpa, .quit);
                i += 1;
                continue;
            }
            if (b == 0x1b) {
                if (i + 1 >= bytes.len) {
                    try out.append(self.gpa, .quit);
                    break;
                }
                if (bytes[i + 1] == '[') {
                    // CSI sequence
                    var end = i + 2;
                    while (end < bytes.len and !(bytes[end] >= 0x40 and bytes[end] <= 0x7E)) : (end += 1) {}
                    if (end >= bytes.len) break;
                    const final = bytes[end];
                    const params = bytes[i + 2 .. end];
                    try self.handleCsi(params, final, out);
                    i = end + 1;
                    continue;
                } else if (bytes[i + 1] == '_') {
                    // Ignore any APC response
                    var end = i + 2;
                    while (end + 1 < bytes.len and !(bytes[end] == 0x1b and bytes[end + 1] == '\\')) : (end += 1) {}
                    i = @min(bytes.len, end + 2);
                    continue;
                } else {
                    i += 2;
                    continue;
                }
            }

            try mapAsciiKey(self.gpa, b, out);
            i += 1;
        }
    }

    fn handleCsi(self: *TerminalBackend, params: []const u8, final: u8, out: *std.ArrayList(InputEvent)) !void {
        // SGR mouse: \x1b[<btn;col;rowM or m
        if (params.len > 0 and params[0] == '<' and (final == 'M' or final == 'm')) {
            var it = std.mem.splitScalar(u8, params[1..], ';');
            const btn_code = std.fmt.parseInt(u32, it.next() orelse return, 10) catch return;
            const col = std.fmt.parseInt(i32, it.next() orelse return, 10) catch return;
            const row = std.fmt.parseInt(i32, it.next() orelse return, 10) catch return;

            if (btn_code == 64 and final == 'M') {
                try out.append(self.gpa, .{ .zoom = 1.12 });
                return;
            }
            if (btn_code == 65 and final == 'M') {
                try out.append(self.gpa, .{ .zoom = 1.0 / 1.12 });
                return;
            }

            const is_motion = (btn_code & 32) != 0;
            const base_btn: u8 = @intCast(btn_code & 0x3);

            if (final == 'm') {
                self.mouse_dragging = false;
                return;
            }
            if (!is_motion and (base_btn == 0 or base_btn == 2)) {
                self.mouse_dragging = true;
                self.mouse_btn = base_btn;
                self.last_mouse_col = col;
                self.last_mouse_row = row;
                return;
            }
            if (is_motion and self.mouse_dragging) {
                const dc = col - self.last_mouse_col;
                const dr = row - self.last_mouse_row;
                self.last_mouse_col = col;
                self.last_mouse_row = row;
                if (dc != 0 or dr != 0) {
                    if (self.mouse_btn == 2) {
                        try out.append(self.gpa, .{ .pan = .{
                            .dx = @as(f32, @floatFromInt(dc)) * 8.0,
                            .dy = @as(f32, @floatFromInt(dr)) * 14.0,
                        } });
                    } else {
                        try out.append(self.gpa, .{ .orbit = .{
                            .dyaw = @as(f32, @floatFromInt(dc)) * 0.035,
                            .dpitch = @as(f32, @floatFromInt(dr)) * 0.045,
                        } });
                    }
                }
            }
            return;
        }

        // Kitty keyboard protocol CSI <codepoint>[;<modifiers>] u
        if (final == 'u') {
            var it = std.mem.splitScalar(u8, params, ';');
            const cp = std.fmt.parseInt(u32, it.next() orelse return, 10) catch return;
            if (cp == 27) {
                try out.append(self.gpa, .quit);
            } else if (cp == 9) {
                try out.append(self.gpa, .toggle_view_mode);
            } else if (cp < 128) {
                try mapAsciiKey(self.gpa, @intCast(cp), out);
            }
            return;
        }

        switch (final) {
            'A' => try out.append(self.gpa, .{ .orbit = .{ .dyaw = 0, .dpitch = -0.08 } }),
            'B' => try out.append(self.gpa, .{ .orbit = .{ .dyaw = 0, .dpitch = 0.08 } }),
            'C' => try out.append(self.gpa, .{ .orbit = .{ .dyaw = 0.09, .dpitch = 0 } }),
            'D' => try out.append(self.gpa, .{ .orbit = .{ .dyaw = -0.09, .dpitch = 0 } }),
            'Z' => try out.append(self.gpa, .toggle_view_mode),
            else => {},
        }
    }
};

fn mapAsciiKey(gpa: Allocator, b: u8, out: *std.ArrayList(InputEvent)) !void {
    switch (b) {
        'q', 'Q' => try out.append(gpa, .quit),
        ' ' => try out.append(gpa, .toggle_pause),
        '\t', 'v', 'V' => try out.append(gpa, .toggle_view_mode),
        '2' => try out.append(gpa, .set_2d),
        '3' => try out.append(gpa, .set_3d),
        'o', 'O' => try out.append(gpa, .toggle_auto_orbit),
        'l', 'L' => try out.append(gpa, .toggle_labels),
        'b', 'B' => try out.append(gpa, .toggle_bloom),
        '+', '=', ']' => try out.append(gpa, .speed_up),
        '-', '_', '[' => try out.append(gpa, .speed_down),
        '.', '>' => try out.append(gpa, .seek_forward),
        ',', '<' => try out.append(gpa, .seek_backward),
        'r', 'R' => try out.append(gpa, .restart),
        'w', 'W' => try out.append(gpa, .{ .orbit = .{ .dyaw = 0, .dpitch = -0.08 } }),
        's', 'S' => try out.append(gpa, .{ .orbit = .{ .dyaw = 0, .dpitch = 0.08 } }),
        'a', 'A' => try out.append(gpa, .{ .orbit = .{ .dyaw = -0.09, .dpitch = 0 } }),
        'd', 'D' => try out.append(gpa, .{ .orbit = .{ .dyaw = 0.09, .dpitch = 0 } }),
        'z' => try out.append(gpa, .{ .zoom = 1.12 }),
        'x' => try out.append(gpa, .{ .zoom = 1.0 / 1.12 }),
        else => {},
    }
}

pub fn appendSixelRun(gpa: Allocator, buf: *std.ArrayList(u8), ch: u8, count: usize) !void {
    if (count == 0) return;
    if (count <= 3) {
        for (0..count) |_| {
            try buf.append(gpa, ch);
        }
    } else {
        var rbuf: [24]u8 = undefined;
        const s = try std.fmt.bufPrint(&rbuf, "!{d}{c}", .{ count, ch });
        try buf.appendSlice(gpa, s);
    }
}

pub fn da1AdvertisesSixel(resp: []const u8) bool {
    const start = std.mem.indexOf(u8, resp, "\x1b[?") orelse return false;
    const tail = resp[start + 3 ..];
    const end = std.mem.indexOfScalar(u8, tail, 'c') orelse return false;
    var tok = std.mem.splitScalar(u8, tail[0..end], ';');
    while (tok.next()) |attr| {
        if (std.mem.eql(u8, attr, "4")) return true;
    }
    return false;
}

test "DA1 sixel attribute parser detects foot capability 4" {
    try std.testing.expect(da1AdvertisesSixel("\x1b[?62;4;22c"));
    try std.testing.expect(!da1AdvertisesSixel("\x1b[?62;22c"));
}

test "sixel RLE encoder compacts runs >= 4" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);

    try appendSixelRun(std.testing.allocator, &out, '~', 2);
    try appendSixelRun(std.testing.allocator, &out, '?', 12);
    try std.testing.expectEqualStrings("~~!12?", out.items);
}

test "kitty CSI-u keyboard and SGR mouse parser emits orbit and mode events" {
    var dummy = TerminalBackend{
        .gpa = std.testing.allocator,
        .tty_fd = -1,
        .owns_tty_fd = false,
        .out_fd = -1,
        .protocol = .kitty,
        .zlib_buf = &.{},
        .flate_window = &.{},
        .b64_buf = &.{},
        .sixel_idx_row = &.{},
    };

    var events: std.ArrayList(InputEvent) = .empty;
    defer events.deinit(std.testing.allocator);

    // Tab via Kitty CSI-u (\x1b[9;1u), press mouse at (10,10), drag to (15,12), release
    try dummy.parseInputBytes("\x1b[9;1u\x1b[<0;10;10M\x1b[<32;15;12M\x1b[<0;15;12m", &events);
    try std.testing.expectEqual(@as(usize, 2), events.items.len);
    try std.testing.expectEqual(InputEvent.toggle_view_mode, events.items[0]);
    try std.testing.expect(events.items[1] == .orbit);
}
