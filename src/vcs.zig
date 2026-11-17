const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const VcsKind = enum {
    auto,
    git,
    hg,
    custom,
    live,

    pub fn badge(self: VcsKind) []const u8 {
        return switch (self) {
            .auto => "AUTO",
            .git => "GIT",
            .hg => "HG",
            .custom => "PIPE",
            .live => "LIVE",
        };
    }
};

pub const Action = enum(u8) {
    add = 'A',
    modify = 'M',
    delete = 'D',

    pub fn fromChar(ch: u8) ?Action {
        return switch (std.ascii.toUpper(ch)) {
            'A' => .add,
            'M', 'C', 'R', 'T', 'U' => .modify,
            'D' => .delete,
            else => null,
        };
    }
};

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Event = struct {
    timestamp: f64,
    author: []const u8,
    action: Action,
    path: []const u8,
    commit_hash: []const u8 = "",
    commit_msg: []const u8 = "",
    custom_color: ?Rgb = null,
};

pub const RepoInfo = struct {
    kind: VcsKind,
    root_path: []u8,
    name: []u8,

    pub fn deinit(self: *RepoInfo, gpa: Allocator) void {
        gpa.free(self.root_path);
        gpa.free(self.name);
    }
};

extern "c" fn access(pathname: [*:0]const u8, mode: c_int) c_int;
extern "c" fn realpath(path: [*:0]const u8, resolved_path: ?[*]u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

const F_OK: c_int = 0;

fn pathExists(sub: []const u8) bool {
    if (sub.len >= 4096) return false;
    var buf: [4096]u8 = undefined;
    @memcpy(buf[0..sub.len], sub);
    buf[sub.len] = 0;
    return access(@ptrCast(&buf), F_OK) == 0;
}

pub fn resolveRealPath(gpa: Allocator, raw_path: []const u8) ![]u8 {
    if (raw_path.len >= 4096) return error.NameTooLong;
    var c_in: [4096]u8 = undefined;
    @memcpy(c_in[0..raw_path.len], raw_path);
    c_in[raw_path.len] = 0;

    const resolved = realpath(@ptrCast(&c_in), null) orelse {
        return gpa.dupe(u8, raw_path);
    };
    defer free(@ptrCast(@constCast(resolved)));
    return gpa.dupe(u8, std.mem.span(resolved));
}

pub fn detectRepo(gpa: Allocator, target_path: []const u8, requested: VcsKind) !RepoInfo {
    const abs_start = try resolveRealPath(gpa, target_path);
    errdefer gpa.free(abs_start);

    if (requested == .git or requested == .hg or requested == .live or requested == .custom) {
        const base = std.fs.path.basename(abs_start);
        const name = try gpa.dupe(u8, if (base.len > 0) base else "root");
        return .{
            .kind = requested,
            .root_path = abs_start,
            .name = name,
        };
    }

    var cur: []const u8 = abs_start;
    while (true) {
        var probe_buf: [4096]u8 = undefined;
        if (std.fmt.bufPrint(&probe_buf, "{s}/.git", .{cur})) |git_path| {
            if (pathExists(git_path)) {
                const root_copy = try gpa.dupe(u8, cur);
                gpa.free(abs_start);
                const base = std.fs.path.basename(root_copy);
                return .{
                    .kind = .git,
                    .root_path = root_copy,
                    .name = try gpa.dupe(u8, if (base.len > 0) base else "git-repo"),
                };
            }
        } else |_| {}

        if (std.fmt.bufPrint(&probe_buf, "{s}/.hg", .{cur})) |hg_path| {
            if (pathExists(hg_path)) {
                const root_copy = try gpa.dupe(u8, cur);
                gpa.free(abs_start);
                const base = std.fs.path.basename(root_copy);
                return .{
                    .kind = .hg,
                    .root_path = root_copy,
                    .name = try gpa.dupe(u8, if (base.len > 0) base else "hg-repo"),
                };
            }
        } else |_| {}

        const parent = std.fs.path.dirname(cur) orelse break;
        if (std.mem.eql(u8, parent, cur)) break;
        cur = parent;
    }

    gpa.free(abs_start);
    return error.NoRepositoryFound;
}

fn normalizeRelPath(arena: Allocator, raw: []const u8) ![]const u8 {
    var trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        trimmed = trimmed[1 .. trimmed.len - 1];
        var out: std.ArrayList(u8) = .empty;
        var i: usize = 0;
        while (i < trimmed.len) : (i += 1) {
            if (trimmed[i] == '\\' and i + 1 < trimmed.len) {
                i += 1;
                switch (trimmed[i]) {
                    'n' => try out.append(arena, '\n'),
                    't' => try out.append(arena, '\t'),
                    '\\', '"' => try out.append(arena, trimmed[i]),
                    '0'...'7' => {
                        var val: u8 = trimmed[i] - '0';
                        var k: usize = 0;
                        while (k < 2 and i + 1 < trimmed.len and trimmed[i + 1] >= '0' and trimmed[i + 1] <= '7') : (k += 1) {
                            i += 1;
                            val = val *% 8 +% (trimmed[i] - '0');
                        }
                        try out.append(arena, val);
                    },
                    else => try out.append(arena, trimmed[i]),
                }
            } else {
                try out.append(arena, trimmed[i]);
            }
        }
        trimmed = out.items;
    }
    while (trimmed.len > 0 and trimmed[0] == '/') {
        trimmed = trimmed[1..];
    }
    if (std.mem.startsWith(u8, trimmed, "./")) {
        trimmed = trimmed[2..];
    }
    return arena.dupe(u8, trimmed);
}

pub fn parseGitLogOutput(arena: Allocator, raw_log: []const u8, events: *std.ArrayList(Event)) !void {
    var cur_ts: f64 = 0;
    var cur_author: []const u8 = "unknown";
    var cur_hash: []const u8 = "";
    var cur_msg: []const u8 = "";

    var lines = std.mem.splitScalar(u8, raw_log, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "COMMIT\x00")) {
            var parts = std.mem.splitScalar(u8, line["COMMIT\x00".len..], 0);
            const ts_str = parts.next() orelse "0";
            const author_str = parts.next() orelse "unknown";
            const hash_str = parts.next() orelse "";
            const msg_str = parts.next() orelse "";

            cur_ts = std.fmt.parseFloat(f64, ts_str) catch 0;
            cur_author = try arena.dupe(u8, if (author_str.len > 0) author_str else "unknown");
            cur_hash = try arena.dupe(u8, hash_str);
            cur_msg = try arena.dupe(u8, msg_str);
            continue;
        }

        if (line[0] == ':') {
            const tab_idx = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
            if (tab_idx == 0 or tab_idx + 1 >= line.len) continue;
            const meta = line[0..tab_idx];
            const last_space = std.mem.lastIndexOfScalar(u8, meta, ' ') orelse continue;
            if (last_space + 1 >= meta.len) continue;
            const status_tok = meta[last_space + 1 ..];
            const action = Action.fromChar(status_tok[0]) orelse continue;

            var rest_path = line[tab_idx + 1 ..];
            if (std.mem.indexOfScalar(u8, rest_path, '\t')) |second_tab| {
                rest_path = rest_path[second_tab + 1 ..];
            }
            const clean_path = try normalizeRelPath(arena, rest_path);
            if (clean_path.len == 0) continue;

            try events.append(arena, .{
                .timestamp = cur_ts,
                .author = cur_author,
                .action = action,
                .path = clean_path,
                .commit_hash = cur_hash,
                .commit_msg = cur_msg,
            });
        }
    }
}

pub fn parseHgLogOutput(arena: Allocator, raw_log: []const u8, events: *std.ArrayList(Event)) !void {
    var cur_ts: f64 = 0;
    var cur_author: []const u8 = "unknown";
    var cur_hash: []const u8 = "";
    var cur_msg: []const u8 = "";

    var lines = std.mem.splitScalar(u8, raw_log, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "COMMIT\x00")) {
            var parts = std.mem.splitScalar(u8, line["COMMIT\x00".len..], 0);
            const ts_raw = std.mem.trim(u8, parts.next() orelse "0", " \t");
            const author_raw = std.mem.trim(u8, parts.next() orelse "unknown", " \t");
            const hash_raw = std.mem.trim(u8, parts.next() orelse "", " \t");
            const msg_raw = std.mem.trim(u8, parts.next() orelse "", " \t");

            var ts_tok = std.mem.tokenizeScalar(u8, ts_raw, ' ');
            const first_num = ts_tok.next() orelse "0";
            cur_ts = std.fmt.parseFloat(f64, first_num) catch 0;
            cur_author = try arena.dupe(u8, if (author_raw.len > 0) author_raw else "unknown");
            cur_hash = try arena.dupe(u8, hash_raw);
            cur_msg = try arena.dupe(u8, msg_raw);
            continue;
        }

        if (line.len >= 3 and line[1] == '\t') {
            const action = Action.fromChar(line[0]) orelse continue;
            const clean_path = try normalizeRelPath(arena, line[2..]);
            if (clean_path.len == 0) continue;

            try events.append(arena, .{
                .timestamp = cur_ts,
                .author = cur_author,
                .action = action,
                .path = clean_path,
                .commit_hash = cur_hash,
                .commit_msg = cur_msg,
            });
        }
    }
}

pub fn parseHexColor(hex_raw: []const u8) ?Rgb {
    var s = std.mem.trim(u8, hex_raw, " \t\r\n");
    if (s.len > 0 and s[0] == '#') s = s[1..];
    if (s.len != 6) return null;
    const r = std.fmt.parseInt(u8, s[0..2], 16) catch return null;
    const g = std.fmt.parseInt(u8, s[2..4], 16) catch return null;
    const b = std.fmt.parseInt(u8, s[4..6], 16) catch return null;
    return .{ .r = r, .g = g, .b = b };
}

pub fn parseCustomLogLine(arena: Allocator, raw_line: []const u8) !?Event {
    const line = std.mem.trim(u8, raw_line, " \t\r\n");
    if (line.len == 0 or line[0] == '#') return null;

    var parts = std.mem.splitScalar(u8, line, '|');
    const ts_str = parts.next() orelse return null;
    const author_str = parts.next() orelse return null;
    const type_str = parts.next() orelse return null;
    const path_str = parts.next() orelse return null;
    const color_opt = parts.next();

    const ts = std.fmt.parseFloat(f64, std.mem.trim(u8, ts_str, " \t")) catch return null;
    const trimmed_type = std.mem.trim(u8, type_str, " \t");
    if (trimmed_type.len == 0) return null;
    const action = Action.fromChar(trimmed_type[0]) orelse return null;

    const clean_path = try normalizeRelPath(arena, path_str);
    if (clean_path.len == 0) return null;

    const clean_author = std.mem.trim(u8, author_str, " \t");

    return Event{
        .timestamp = ts,
        .author = try arena.dupe(u8, if (clean_author.len > 0) clean_author else "unknown"),
        .action = action,
        .path = clean_path,
        .custom_color = if (color_opt) |c| parseHexColor(c) else null,
    };
}

pub fn parseCustomLogBuffer(arena: Allocator, raw_log: []const u8, events: *std.ArrayList(Event)) !void {
    var lines = std.mem.splitScalar(u8, raw_log, '\n');
    while (lines.next()) |line| {
        if (try parseCustomLogLine(arena, line)) |ev| {
            try events.append(arena, ev);
        }
    }
}

pub fn loadGitHistory(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    repo_path: []const u8,
    max_commits: usize,
    events: *std.ArrayList(Event),
) !void {
    var max_buf: [64]u8 = undefined;
    var argv_list: [8][]const u8 = undefined;
    var argc: usize = 0;
    argv_list[argc] = "git";
    argc += 1;
    argv_list[argc] = "-C";
    argc += 1;
    argv_list[argc] = repo_path;
    argc += 1;
    argv_list[argc] = "log";
    argc += 1;
    argv_list[argc] = "--reverse";
    argc += 1;
    argv_list[argc] = "--raw";
    argc += 1;
    argv_list[argc] = "--no-renames";
    argc += 1;
    argv_list[argc] = "--pretty=format:COMMIT%x00%ct%x00%an%x00%h%x00%s";
    argc += 1;

    var argv_with_limit: [9][]const u8 = undefined;
    const final_argv: []const []const u8 = if (max_commits > 0) blk: {
        @memcpy(argv_with_limit[0..argc], argv_list[0..argc]);
        argv_with_limit[argc] = try std.fmt.bufPrint(&max_buf, "--max-count={d}", .{max_commits});
        break :blk argv_with_limit[0 .. argc + 1];
    } else argv_list[0..argc];

    const res = try std.process.run(gpa, io, .{
        .argv = final_argv,
    });
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    if (!res.term.success()) {
        return error.GitLogFailed;
    }
    try parseGitLogOutput(arena, res.stdout, events);
}

pub fn loadHgHistory(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    repo_path: []const u8,
    max_commits: usize,
    events: *std.ArrayList(Event),
) !void {
    const revset = if (max_commits > 0) blk: {
        var rbuf: [64]u8 = undefined;
        const s = try std.fmt.bufPrint(&rbuf, "last(0:tip, {d})", .{max_commits});
        break :blk try gpa.dupe(u8, s);
    } else try gpa.dupe(u8, "0:tip");
    defer gpa.free(revset);

    const template = "COMMIT\\x00{date|hgdate}\\x00{person(author)}\\x00{short(node)}\\x00{firstline(desc)}\\n{file_adds % 'A\\t{file}\\n'}{file_mods % 'M\\t{file}\\n'}{file_dels % 'D\\t{file}\\n'}\\n";

    const argv = [_][]const u8{
        "hg",
        "--repository",
        repo_path,
        "log",
        "-r",
        revset,
        "--template",
        template,
    };

    const res = try std.process.run(gpa, io, .{
        .argv = &argv,
    });
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    if (!res.term.success()) {
        return error.HgLogFailed;
    }
    try parseHgLogOutput(arena, res.stdout, events);
}

pub fn loadCustomLogFile(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    file_path: []const u8,
    events: *std.ArrayList(Event),
) !void {
    const file = try Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    const len = try file.length(io);
    const buf = try gpa.alloc(u8, @intCast(len));
    defer gpa.free(buf);

    var offset: usize = 0;
    while (offset < buf.len) {
        var slices = [_][]u8{buf[offset..]};
        const n = try file.readPositional(io, &slices, offset);
        if (n == 0) break;
        offset += n;
    }
    try parseCustomLogBuffer(arena, buf[0..offset], events);
}

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};
const POLLIN: c_short = 0x0001;
const POLLHUP: c_short = 0x0010;
extern "c" fn poll(fds: [*]PollFd, nfds: c_ulong, timeout: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;

pub const PipeStream = struct {
    fd: c_int,
    eof: bool = false,
    line_buf: [8192]u8 = undefined,
    line_len: usize = 0,

    pub fn init(fd: c_int) PipeStream {
        return .{ .fd = fd };
    }

    pub fn pollEvents(self: *PipeStream, arena: Allocator, out: *std.ArrayList(Event)) !void {
        if (self.eof) return;

        var budget: usize = 256;
        while (budget > 0) : (budget -= 1) {
            var pfd = [1]PollFd{.{ .fd = self.fd, .events = POLLIN, .revents = 0 }};
            const rc = poll(&pfd, 1, 0);
            if (rc <= 0) break;

            if ((pfd[0].revents & (POLLIN | POLLHUP)) == 0) break;

            var chunk: [2048]u8 = undefined;
            const n = read(self.fd, &chunk, chunk.len);
            if (n <= 0) {
                if (self.line_len > 0) {
                    if (try parseCustomLogLine(arena, self.line_buf[0..self.line_len])) |ev| {
                        try out.append(arena, ev);
                    }
                    self.line_len = 0;
                }
                self.eof = true;
                break;
            }

            const slice = chunk[0..@intCast(n)];
            for (slice) |b| {
                if (b == '\n') {
                    if (try parseCustomLogLine(arena, self.line_buf[0..self.line_len])) |ev| {
                        try out.append(arena, ev);
                    }
                    self.line_len = 0;
                } else if (self.line_len < self.line_buf.len) {
                    self.line_buf[self.line_len] = b;
                    self.line_len += 1;
                }
            }
        }
    }
};

extern "c" fn inotify_init1(flags: c_int) c_int;
extern "c" fn inotify_add_watch(fd: c_int, pathname: [*:0]const u8, mask: u32) c_int;

const DIR = opaque {};
const Dirent = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]u8,
};
extern "c" fn opendir(name: [*:0]const u8) ?*DIR;
extern "c" fn readdir(dirp: *DIR) ?*Dirent;
extern "c" fn closedir(dirp: *DIR) c_int;

const DT_DIR: u8 = 4;
const DT_REG: u8 = 8;
const DT_UNKNOWN: u8 = 0;

const IN_NONBLOCK: c_int = 0o4000;
const IN_CLOEXEC: c_int = 0o2000000;
const IN_MODIFY: u32 = 0x00000002;
const IN_CLOSE_WRITE: u32 = 0x00000008;
const IN_MOVED_FROM: u32 = 0x00000040;
const IN_MOVED_TO: u32 = 0x00000080;
const IN_CREATE: u32 = 0x00000100;
const IN_DELETE: u32 = 0x00000200;
const IN_ISDIR: u32 = 0x40000000;

const InotifyEventHdr = extern struct {
    wd: c_int,
    mask: u32,
    cookie: u32,
    len: u32,
};

fn isIgnoredDirName(name: []const u8) bool {
    return std.mem.eql(u8, name, ".") or
        std.mem.eql(u8, name, "..") or
        std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".hg") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-cache") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "node_modules") or
        std.mem.eql(u8, name, "target");
}

pub fn nowEpochSeconds() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) * 1e-9;
}

pub const LiveWatcher = struct {
    gpa: Allocator,
    fd: c_int,
    root_path: []u8,
    user_name: []u8,
    wd_to_rel: std.AutoHashMapUnmanaged(c_int, []u8) = .empty,

    pub fn init(
        gpa: Allocator,
        arena: Allocator,
        root_path: []const u8,
        user_name: []const u8,
        initial_events: *std.ArrayList(Event),
    ) !LiveWatcher {
        const fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (fd < 0) return error.InotifyInitFailed;

        var self = LiveWatcher{
            .gpa = gpa,
            .fd = fd,
            .root_path = try gpa.dupe(u8, root_path),
            .user_name = try gpa.dupe(u8, if (user_name.len > 0) user_name else "live"),
        };
        errdefer self.deinit();

        const start_ts = nowEpochSeconds();
        try self.scanAndWatchDir(arena, "", start_ts, initial_events, 0);
        return self;
    }

    pub fn deinit(self: *LiveWatcher) void {
        var it = self.wd_to_rel.valueIterator();
        while (it.next()) |rel_ptr| {
            self.gpa.free(rel_ptr.*);
        }
        self.wd_to_rel.deinit(self.gpa);
        if (self.fd >= 0) {
            _ = close(self.fd);
            self.fd = -1;
        }
        self.gpa.free(self.root_path);
        self.gpa.free(self.user_name);
    }

    fn scanAndWatchDir(
        self: *LiveWatcher,
        arena: Allocator,
        rel_dir: []const u8,
        ts: f64,
        initial_events: ?*std.ArrayList(Event),
        depth: usize,
    ) !void {
        if (depth > 16) return;

        var full_buf: [4096]u8 = undefined;
        const full_slice = if (rel_dir.len == 0)
            try std.fmt.bufPrint(&full_buf, "{s}", .{self.root_path})
        else
            try std.fmt.bufPrint(&full_buf, "{s}/{s}", .{ self.root_path, rel_dir });

        if (full_slice.len + 1 >= full_buf.len) return;
        full_buf[full_slice.len] = 0;
        const full_z: [*:0]const u8 = @ptrCast(full_buf[0..full_slice.len :0]);

        const mask = IN_CREATE | IN_DELETE | IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO;
        const wd = inotify_add_watch(self.fd, full_z, mask);
        if (wd >= 0 and !self.wd_to_rel.contains(wd)) {
            const dup_rel = try self.gpa.dupe(u8, rel_dir);
            self.wd_to_rel.put(self.gpa, wd, dup_rel) catch {
                self.gpa.free(dup_rel);
            };
        }

        const dir_handle = opendir(full_z) orelse return;
        defer _ = closedir(dir_handle);

        while (readdir(dir_handle)) |ent| {
            const name_z: [*:0]const u8 = @ptrCast(&ent.d_name);
            const name = std.mem.span(name_z);
            if (isIgnoredDirName(name)) continue;

            var child_rel_buf: [4096]u8 = undefined;
            const child_rel = if (rel_dir.len == 0)
                std.fmt.bufPrint(&child_rel_buf, "{s}", .{name}) catch continue
            else
                std.fmt.bufPrint(&child_rel_buf, "{s}/{s}", .{ rel_dir, name }) catch continue;

            if (ent.d_type == DT_DIR) {
                try self.scanAndWatchDir(arena, child_rel, ts, initial_events, depth + 1);
            } else if (ent.d_type == DT_REG or ent.d_type == DT_UNKNOWN) {
                if (initial_events) |ev_list| {
                    if (ev_list.items.len < 6000) {
                        try ev_list.append(arena, .{
                            .timestamp = ts,
                            .author = try arena.dupe(u8, self.user_name),
                            .action = .add,
                            .path = try arena.dupe(u8, child_rel),
                            .commit_msg = "working tree",
                        });
                    }
                }
            }
        }
    }

    pub fn pollEvents(self: *LiveWatcher, arena: Allocator, out: *std.ArrayList(Event)) !void {
        var raw_buf: [8192]u8 align(@alignOf(InotifyEventHdr)) = undefined;
        while (true) {
            const n = read(self.fd, &raw_buf, raw_buf.len);
            if (n <= 0) break;

            const total: usize = @intCast(n);
            var pos: usize = 0;
            const now_ts = nowEpochSeconds();

            while (pos + @sizeOf(InotifyEventHdr) <= total) {
                const hdr: *const InotifyEventHdr = @ptrCast(@alignCast(&raw_buf[pos]));
                const step = @sizeOf(InotifyEventHdr) + @as(usize, hdr.len);
                if (pos + step > total) break;

                if (hdr.len > 0) {
                    const name_bytes = raw_buf[pos + @sizeOf(InotifyEventHdr) .. pos + step];
                    const nul_idx = std.mem.indexOfScalar(u8, name_bytes, 0) orelse name_bytes.len;
                    const name = name_bytes[0..nul_idx];

                    if (name.len > 0 and !isIgnoredDirName(name) and !std.mem.endsWith(u8, name, ".swp") and !std.mem.endsWith(u8, name, "~")) {
                        const rel_dir = self.wd_to_rel.get(hdr.wd) orelse "";
                        var rel_path_buf: [4096]u8 = undefined;
                        const rel_path = if (rel_dir.len == 0)
                            std.fmt.bufPrint(&rel_path_buf, "{s}", .{name}) catch ""
                        else
                            std.fmt.bufPrint(&rel_path_buf, "{s}/{s}", .{ rel_dir, name }) catch "";

                        if (rel_path.len > 0) {
                            if ((hdr.mask & IN_ISDIR) != 0) {
                                if ((hdr.mask & (IN_CREATE | IN_MOVED_TO)) != 0) {
                                    self.scanAndWatchDir(arena, rel_path, now_ts, out, 1) catch {};
                                }
                            } else {
                                const action_opt: ?Action = if ((hdr.mask & (IN_DELETE | IN_MOVED_FROM)) != 0)
                                    .delete
                                else if ((hdr.mask & (IN_CREATE | IN_MOVED_TO)) != 0)
                                    .add
                                else if ((hdr.mask & (IN_CLOSE_WRITE | IN_MODIFY)) != 0)
                                    .modify
                                else
                                    null;

                                if (action_opt) |act| {
                                    try out.append(arena, .{
                                        .timestamp = now_ts,
                                        .author = try arena.dupe(u8, self.user_name),
                                        .action = act,
                                        .path = try arena.dupe(u8, rel_path),
                                        .commit_msg = "live edit",
                                    });
                                }
                            }
                        }
                    }
                }
                pos += step;
            }
        }
    }
};

test "parse git raw log output" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const sample =
        "COMMIT\x001700000100\x00Alice\x00a1b2c3d\x00Initial scaffold\n" ++
        ":000000 100644 0000000 1111111 A\tsrc/main.zig\n" ++
        ":000000 100644 0000000 2222222 A\tREADME.md\n" ++
        "\n" ++
        "COMMIT\x001700003700\x00Bob\x00e4f5a6b\x00Update main and remove readme\n" ++
        ":100644 100644 1111111 3333333 M\tsrc/main.zig\n" ++
        ":100644 000000 2222222 0000000 D\tREADME.md\n";

    var events: std.ArrayList(Event) = .empty;
    try parseGitLogOutput(arena, sample, &events);

    try std.testing.expectEqual(@as(usize, 4), events.items.len);
    try std.testing.expectEqualStrings("Alice", events.items[0].author);
    try std.testing.expectEqual(Action.add, events.items[0].action);
    try std.testing.expectEqualStrings("src/main.zig", events.items[0].path);
    try std.testing.expectEqualStrings("a1b2c3d", events.items[0].commit_hash);

    try std.testing.expectEqualStrings("Bob", events.items[2].author);
    try std.testing.expectEqual(Action.modify, events.items[2].action);
    try std.testing.expectEqual(Action.delete, events.items[3].action);
}

test "parse mercurial template log output" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const hg_sample =
        "COMMIT\x001700010000 21600\x00 Clara \x009f8e7d6c5b4a\x00Add renderer\n" ++
        "A\tsrc/raster.zig\n" ++
        "M\tbuild.zig\n" ++
        "D\told/legacy.c\n\n";

    var events: std.ArrayList(Event) = .empty;
    try parseHgLogOutput(arena, hg_sample, &events);

    try std.testing.expectEqual(@as(usize, 3), events.items.len);
    try std.testing.expectEqual(@as(f64, 1700010000), events.items[0].timestamp);
    try std.testing.expectEqualStrings("Clara", events.items[0].author);
    try std.testing.expectEqual(Action.add, events.items[0].action);
    try std.testing.expectEqualStrings("src/raster.zig", events.items[0].path);
    try std.testing.expectEqual(Action.modify, events.items[1].action);
    try std.testing.expectEqual(Action.delete, events.items[2].action);
}

test "parse gource custom pipe format with optional hex color" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const custom_sample =
        "# comment line\n" ++
        "1700020000|Dave|A|/src/wayland.zig|FF8800\n" ++
        "1700020050.5|Eve|M|src/terminal.zig\n";

    var events: std.ArrayList(Event) = .empty;
    try parseCustomLogBuffer(arena, custom_sample, &events);

    try std.testing.expectEqual(@as(usize, 2), events.items.len);
    try std.testing.expectEqualStrings("Dave", events.items[0].author);
    try std.testing.expectEqualStrings("src/wayland.zig", events.items[0].path);
    try std.testing.expectEqual(@as(u8, 0xFF), events.items[0].custom_color.?.r);
    try std.testing.expectEqual(@as(u8, 0x88), events.items[0].custom_color.?.g);
    try std.testing.expectEqual(@as(u8, 0x00), events.items[0].custom_color.?.b);
    try std.testing.expectEqual(@as( ?Rgb, null), events.items[1].custom_color);
}
