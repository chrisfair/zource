const std = @import("std");
const vcs = @import("vcs.zig");
const Allocator = std.mem.Allocator;
const Rgb = vcs.Rgb;

pub const ViewMode = enum {
    tree_2d,
    bubbles_3d,

    pub fn toggle(self: ViewMode) ViewMode {
        return switch (self) {
            .tree_2d => .bubbles_3d,
            .bubbles_3d => .tree_2d,
        };
    }

    pub fn label(self: ViewMode) []const u8 {
        return switch (self) {
            .tree_2d => "2D TREE",
            .bubbles_3d => "3D BUBBLES",
        };
    }
};

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub fn lenSq(a: Vec2) f32 {
        return a.x * a.x + a.y * a.y;
    }
    pub fn len(a: Vec2) f32 {
        return @sqrt(a.lenSq());
    }
};

pub const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub fn lenSq(a: Vec3) f32 {
        return a.dot(a);
    }
    pub fn len(a: Vec3) f32 {
        return @sqrt(a.lenSq());
    }
    pub fn normalizeOr(a: Vec3, fallback: Vec3) Vec3 {
        const l = a.len();
        if (l < 1e-5) return fallback;
        return a.scale(1.0 / l);
    }
    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return .{
            .x = a.x + (b.x - a.x) * t,
            .y = a.y + (b.y - a.y) * t,
            .z = a.z + (b.z - a.z) * t,
        };
    }
};

pub const DirNode = struct {
    parent: ?usize,
    name: []const u8,
    full_path: []const u8,
    depth: u16,
    child_dirs: std.ArrayList(usize) = .empty,
    files: std.ArrayList(usize) = .empty,
    alive_files: u32 = 0,
    subtree_files: u32 = 0,
    angle_hint: f32 = 0,
    orbit_unit: Vec3 = .{ .x = 0, .y = 1, .z = 0 },
    pos2: Vec2 = .{},
    vel2: Vec2 = .{},
    pos3: Vec3 = .{},
    vel3: Vec3 = .{},
    bubble_radius: f32 = 22.0,
    heat: f32 = 0,
    tint: Rgb = .{ .r = 90, .g = 155, .b = 235 },
};

pub const FileNode = struct {
    dir_idx: usize,
    name: []const u8,
    full_path: []const u8,
    color: Rgb,
    alive: bool = false,
    alpha: f32 = 0,
    heat: f32 = 0,
    seed: u32,
    local_unit3: Vec3,
    pos2: Vec2 = .{},
    pos3: Vec3 = .{},
    radius: f32 = 4.5,
};

pub const AuthorNode = struct {
    name: []const u8,
    color: Rgb,
    pos2: Vec2 = .{},
    pos3: Vec3 = .{},
    target2: Vec2 = .{},
    target3: Vec3 = .{},
    energy: f32 = 0,
    touches: u32 = 0,
};

pub const ActionBeam = struct {
    author_idx: usize,
    file_idx: usize,
    color: Rgb,
    ttl: f32,
    max_ttl: f32,
};

pub const Particle = struct {
    pos2: Vec2,
    vel2: Vec2,
    pos3: Vec3,
    vel3: Vec3,
    color: Rgb,
    ttl: f32,
    max_ttl: f32,
    size: f32,
};

pub const Camera = struct {
    yaw: f32 = 0.45,
    pitch: f32 = 0.32,
    zoom: f32 = 1.0,
    pan_x: f32 = 0,
    pan_y: f32 = 0,
    auto_orbit: bool = true,
    orbit_speed: f32 = 0.26,

    pub fn project3D(self: Camera, p: Vec3, width: f32, height: f32) struct { x: f32, y: f32, depth: f32, scale: f32, visible: bool } {
        const cy = @cos(self.yaw);
        const sy = @sin(self.yaw);
        const cp = @cos(self.pitch);
        const sp = @sin(self.pitch);

        const rx = p.x * cy + p.z * sy;
        const rz0 = -p.x * sy + p.z * cy;
        const ry = p.y * cp - rz0 * sp;
        const rz = p.y * sp + rz0 * cp;

        const cam_dist: f32 = 520.0 / @max(0.18, self.zoom);
        const z_cam = rz + cam_dist;
        if (z_cam < 24.0) {
            return .{ .x = 0, .y = 0, .depth = z_cam, .scale = 0, .visible = false };
        }
        const fov = @min(width, height) * 0.92;
        const persp = fov / z_cam;
        return .{
            .x = width * 0.5 + self.pan_x + rx * persp,
            .y = height * 0.5 + self.pan_y - ry * persp,
            .depth = z_cam,
            .scale = persp,
            .visible = true,
        };
    }

    pub fn project2D(self: Camera, p: Vec2, width: f32, height: f32) struct { x: f32, y: f32, scale: f32 } {
        const s = self.zoom * (@min(width, height) / 680.0);
        return .{
            .x = width * 0.5 + self.pan_x + p.x * s,
            .y = height * 0.5 + self.pan_y + p.y * s,
            .scale = s,
        };
    }
};

fn hashString(s: []const u8) u32 {
    var h: u32 = 2166136261;
    for (s) |b| {
        h ^= b;
        h *%= 16777619;
    }
    return h;
}

fn hslToRgb(h_deg: f32, s: f32, l: f32) Rgb {
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const hp = @mod(h_deg / 60.0, 6.0);
    const x = c * (1.0 - @abs(@mod(hp, 2.0) - 1.0));
    var r1: f32 = 0;
    var g1: f32 = 0;
    var b1: f32 = 0;
    if (hp < 1.0) {
        r1 = c;
        g1 = x;
    } else if (hp < 2.0) {
        r1 = x;
        g1 = c;
    } else if (hp < 3.0) {
        g1 = c;
        b1 = x;
    } else if (hp < 4.0) {
        g1 = x;
        b1 = c;
    } else if (hp < 5.0) {
        r1 = x;
        b1 = c;
    } else {
        r1 = c;
        b1 = x;
    }
    const m = l - c * 0.5;
    return .{
        .r = @intFromFloat(std.math.clamp((r1 + m) * 255.0, 0.0, 255.0)),
        .g = @intFromFloat(std.math.clamp((g1 + m) * 255.0, 0.0, 255.0)),
        .b = @intFromFloat(std.math.clamp((b1 + m) * 255.0, 0.0, 255.0)),
    };
}

pub fn colorForPath(path: []const u8, override_color: ?Rgb) Rgb {
    if (override_color) |c| return c;
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.');
    const ext = if (dot) |idx| base[idx + 1 ..] else base;

    if (std.ascii.eqlIgnoreCase(ext, "zig")) return .{ .r = 247, .g = 164, .b = 29 };
    if (std.ascii.eqlIgnoreCase(ext, "rs")) return .{ .r = 232, .g = 104, .b = 60 };
    if (std.ascii.eqlIgnoreCase(ext, "c") or std.ascii.eqlIgnoreCase(ext, "h")) return .{ .r = 76, .g = 194, .b = 255 };
    if (std.ascii.eqlIgnoreCase(ext, "cpp") or std.ascii.eqlIgnoreCase(ext, "hpp") or std.ascii.eqlIgnoreCase(ext, "cc")) return .{ .r = 108, .g = 142, .b = 255 };
    if (std.ascii.eqlIgnoreCase(ext, "ts") or std.ascii.eqlIgnoreCase(ext, "tsx")) return .{ .r = 56, .g = 166, .b = 255 };
    if (std.ascii.eqlIgnoreCase(ext, "js") or std.ascii.eqlIgnoreCase(ext, "mjs")) return .{ .r = 245, .g = 208, .b = 51 };
    if (std.ascii.eqlIgnoreCase(ext, "vue") or std.ascii.eqlIgnoreCase(ext, "svelte")) return .{ .r = 66, .g = 211, .b = 146 };
    if (std.ascii.eqlIgnoreCase(ext, "py")) return .{ .r = 82, .g = 152, .b = 255 };
    if (std.ascii.eqlIgnoreCase(ext, "go")) return .{ .r = 45, .g = 212, .b = 228 };
    if (std.ascii.eqlIgnoreCase(ext, "md") or std.ascii.eqlIgnoreCase(ext, "txt")) return .{ .r = 192, .g = 168, .b = 250 };
    if (std.ascii.eqlIgnoreCase(ext, "json") or std.ascii.eqlIgnoreCase(ext, "toml") or std.ascii.eqlIgnoreCase(ext, "zon") or std.ascii.eqlIgnoreCase(ext, "yaml") or std.ascii.eqlIgnoreCase(ext, "yml")) return .{ .r = 110, .g = 231, .b = 183 };
    if (std.ascii.eqlIgnoreCase(ext, "sh") or std.ascii.eqlIgnoreCase(ext, "Makefile")) return .{ .r = 251, .g = 146, .b = 160 };

    const h = hashString(ext);
    const hue = @as(f32, @floatFromInt(h % 360));
    return hslToRgb(hue, 0.78, 0.62);
}

pub fn colorForAuthor(name: []const u8) Rgb {
    const h = hashString(name);
    const hue = @as(f32, @floatFromInt((h *% 73) % 360));
    return hslToRgb(hue, 0.85, 0.68);
}

fn fibonacciDirection(index: usize, total: usize, seed: u32) Vec3 {
    const n = @as(f32, @floatFromInt(@max(total, 1)));
    const i = @as(f32, @floatFromInt(index)) + 0.5;
    const golden_angle: f32 = 2.39996323;
    const phase = @as(f32, @floatFromInt(seed % 1024)) * 0.0061359;
    const y = 1.0 - (2.0 * i) / n;
    const r = @sqrt(@max(0.0, 1.0 - y * y));
    const theta = golden_angle * i + phase;
    return .{
        .x = @cos(theta) * r,
        .y = y,
        .z = @sin(theta) * r,
    };
}

pub fn formatTimestampUtc(epoch_sec_f: f64, out: *[20]u8) []const u8 {
    const secs: i64 = @intFromFloat(@max(0.0, epoch_sec_f));
    const days_total = @divFloor(secs, 86400);
    const rem_sec = @mod(secs, 86400);
    const hour: u32 = @intCast(@divFloor(rem_sec, 3600));
    const minute: u32 = @intCast(@divFloor(@mod(rem_sec, 3600), 60));

    // Civil-from-days (Howard Hinnant)
    const z = days_total + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: u64 = @intCast(z - era * 146097);
    const yoe: u64 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    var y: i64 = @as(i64, @intCast(yoe)) + era * 400;
    const doy: u64 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp: u64 = (5 * doy + 2) / 153;
    const d: u32 = @intCast(doy - (153 * mp + 2) / 5 + 1);
    const m: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    if (m <= 2) y += 1;

    const year_clamped: u32 = @intCast(std.math.clamp(y, 1970, 9999));
    return std.fmt.bufPrint(out, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{
        year_clamped,
        m,
        d,
        hour,
        minute,
    }) catch "1970-01-01 00:00";
}

pub const Simulation = struct {
    arena_state: std.heap.ArenaAllocator,
    gpa: Allocator,

    repo_name: []const u8,
    vcs_kind: vcs.VcsKind,
    streaming_mode: bool = false,

    events: std.ArrayList(vcs.Event) = .empty,
    next_event_idx: usize = 0,
    sim_time: f64 = 0,
    start_time: f64 = 0,
    end_time: f64 = 0,

    seconds_per_day: f64 = 1.0,
    auto_skip_idle: bool = true,
    paused: bool = false,
    loop_playback: bool = false,
    finished: bool = false,

    view_mode: ViewMode = .bubbles_3d,
    blend_3d: f32 = 1.0,
    show_labels: bool = true,
    enable_bloom: bool = true,
    camera: Camera = .{},

    dirs: std.ArrayList(DirNode) = .empty,
    dir_lookup: std.StringHashMapUnmanaged(usize) = .empty,

    files: std.ArrayList(FileNode) = .empty,
    file_lookup: std.StringHashMapUnmanaged(usize) = .empty,

    authors: std.ArrayList(AuthorNode) = .empty,
    author_lookup: std.StringHashMapUnmanaged(usize) = .empty,

    beams: std.ArrayList(ActionBeam) = .empty,
    particles: std.ArrayList(Particle) = .empty,

    active_file_count: u32 = 0,
    last_commit_hash: []const u8 = "",
    last_commit_msg: []const u8 = "",
    last_author: []const u8 = "",
    phase_clock: f32 = 0,

    pub fn init(gpa: Allocator, repo_name: []const u8, vcs_kind: vcs.VcsKind, view_mode: ViewMode) !Simulation {
        var sim = Simulation{
            .arena_state = std.heap.ArenaAllocator.init(gpa),
            .gpa = gpa,
            .repo_name = "",
            .vcs_kind = vcs_kind,
            .view_mode = view_mode,
            .blend_3d = if (view_mode == .bubbles_3d) 1.0 else 0.0,
        };
        const ar = sim.arena_state.allocator();
        sim.repo_name = try ar.dupe(u8, repo_name);
        try sim.resetGraph();
        return sim;
    }

    pub fn deinit(self: *Simulation) void {
        for (self.dirs.items) |*d| {
            d.child_dirs.deinit(self.gpa);
            d.files.deinit(self.gpa);
        }
        self.dirs.deinit(self.gpa);
        self.dir_lookup.deinit(self.gpa);
        self.files.deinit(self.gpa);
        self.file_lookup.deinit(self.gpa);
        self.authors.deinit(self.gpa);
        self.author_lookup.deinit(self.gpa);
        self.beams.deinit(self.gpa);
        self.particles.deinit(self.gpa);
        self.arena_state.deinit();
    }

    pub fn arena(self: *Simulation) Allocator {
        return self.arena_state.allocator();
    }

    fn resetGraph(self: *Simulation) !void {
        for (self.dirs.items) |*d| {
            d.child_dirs.deinit(self.gpa);
            d.files.deinit(self.gpa);
        }
        self.dirs.clearRetainingCapacity();
        self.dir_lookup.clearRetainingCapacity();
        self.files.clearRetainingCapacity();
        self.file_lookup.clearRetainingCapacity();
        self.authors.clearRetainingCapacity();
        self.author_lookup.clearRetainingCapacity();
        self.beams.clearRetainingCapacity();
        self.particles.clearRetainingCapacity();
        self.active_file_count = 0;
        self.last_commit_hash = "";
        self.last_commit_msg = "";
        self.last_author = "";

        try self.dirs.append(self.gpa, .{
            .parent = null,
            .name = self.repo_name,
            .full_path = "",
            .depth = 0,
            .bubble_radius = 28.0,
        });
        try self.dir_lookup.put(self.gpa, "", 0);
    }

    pub fn finalizeLoadedEvents(self: *Simulation) void {
        if (self.events.items.len == 0) {
            const now = vcs.nowEpochSeconds();
            self.start_time = now;
            self.end_time = now;
            self.sim_time = now;
            return;
        }
        std.mem.sort(vcs.Event, self.events.items, {}, struct {
            fn lessThan(_: void, a: vcs.Event, b: vcs.Event) bool {
                return a.timestamp < b.timestamp;
            }
        }.lessThan);

        self.start_time = self.events.items[0].timestamp;
        self.end_time = self.events.items[self.events.items.len - 1].timestamp;
        self.sim_time = self.start_time;
        self.next_event_idx = 0;
        self.finished = false;
    }

    pub fn restart(self: *Simulation) !void {
        try self.resetGraph();
        self.next_event_idx = 0;
        self.sim_time = self.start_time;
        self.finished = false;
    }

    pub fn seekRelative(self: *Simulation, delta_fraction: f64) !void {
        if (self.streaming_mode or self.events.items.len == 0) return;
        const span = @max(1.0, self.end_time - self.start_time);
        const target = std.math.clamp(self.sim_time + span * delta_fraction, self.start_time, self.end_time);
        if (target < self.sim_time) {
            try self.restart();
        }
        self.sim_time = target;
        while (self.next_event_idx < self.events.items.len and self.events.items[self.next_event_idx].timestamp <= self.sim_time) {
            try self.applyEvent(self.events.items[self.next_event_idx], false);
            self.next_event_idx += 1;
        }
        self.finished = false;
    }

    fn ensureDirChain(self: *Simulation, dir_path: []const u8) !usize {
        if (dir_path.len == 0 or std.mem.eql(u8, dir_path, ".")) return 0;
        if (self.dir_lookup.get(dir_path)) |idx| return idx;

        const parent_slice = std.fs.path.dirname(dir_path) orelse "";
        const parent_idx = try self.ensureDirChain(parent_slice);

        const a = self.arena();
        const full_dup = try a.dupe(u8, dir_path);
        const base_dup = try a.dupe(u8, std.fs.path.basename(dir_path));

        const new_idx = self.dirs.items.len;
        const sibling_slot = self.dirs.items[parent_idx].child_dirs.items.len;
        const seed = hashString(full_dup);
        const angle = @as(f32, @floatFromInt(seed % 6283)) * 0.001 + @as(f32, @floatFromInt(sibling_slot)) * 2.399963;
        const unit3 = fibonacciDirection(sibling_slot, sibling_slot + 6, seed);

        const parent_pos2 = self.dirs.items[parent_idx].pos2;
        const parent_pos3 = self.dirs.items[parent_idx].pos3;
        const parent_depth = self.dirs.items[parent_idx].depth;
        const spawn_dist: f32 = if (parent_idx == 0) 95.0 else 65.0;

        try self.dirs.append(self.gpa, .{
            .parent = parent_idx,
            .name = base_dup,
            .full_path = full_dup,
            .depth = parent_depth + 1,
            .angle_hint = angle,
            .orbit_unit = unit3,
            .pos2 = .{
                .x = parent_pos2.x + @cos(angle) * spawn_dist,
                .y = parent_pos2.y + @sin(angle) * spawn_dist,
            },
            .pos3 = parent_pos3.add(unit3.scale(spawn_dist)),
        });
        try self.dirs.items[parent_idx].child_dirs.append(self.gpa, new_idx);
        try self.dir_lookup.put(self.gpa, full_dup, new_idx);

        // Rebalance sibling orbital directions on parent
        const siblings = self.dirs.items[parent_idx].child_dirs.items;
        for (siblings, 0..) |sib_idx, k| {
            const sib_seed = hashString(self.dirs.items[sib_idx].full_path);
            self.dirs.items[sib_idx].orbit_unit = fibonacciDirection(k, siblings.len, sib_seed);
            self.dirs.items[sib_idx].angle_hint = self.dirs.items[parent_idx].angle_hint +
                (@as(f32, @floatFromInt(k)) - @as(f32, @floatFromInt(siblings.len)) * 0.5) * (std.math.tau / @as(f32, @floatFromInt(@max(siblings.len, 3))));
        }

        return new_idx;
    }

    fn ensureAuthor(self: *Simulation, raw_author: []const u8) !usize {
        if (self.author_lookup.get(raw_author)) |idx| return idx;
        const a = self.arena();
        const dup_name = try a.dupe(u8, raw_author);
        const idx = self.authors.items.len;
        const seed = hashString(dup_name);
        const ang = @as(f32, @floatFromInt(seed % 6283)) * 0.001;
        const unit = fibonacciDirection(idx, idx + 8, seed);

        try self.authors.append(self.gpa, .{
            .name = dup_name,
            .color = colorForAuthor(dup_name),
            .pos2 = .{ .x = @cos(ang) * 160.0, .y = @sin(ang) * 160.0 },
            .pos3 = unit.scale(190.0),
            .target2 = .{ .x = @cos(ang) * 120.0, .y = @sin(ang) * 120.0 },
            .target3 = unit.scale(150.0),
        });
        try self.author_lookup.put(self.gpa, dup_name, idx);
        return idx;
    }

    fn adjustSubtreeCounts(self: *Simulation, start_dir: usize, delta: i32) void {
        var cur_opt: ?usize = start_dir;
        while (cur_opt) |idx| {
            const cur = &self.dirs.items[idx];
            if (delta > 0) {
                cur.subtree_files +|= @intCast(delta);
            } else {
                const sub: u32 = @intCast(-delta);
                cur.subtree_files = if (cur.subtree_files > sub) cur.subtree_files - sub else 0;
            }
            cur_opt = cur.parent;
        }
    }

    fn spawnParticles(self: *Simulation, pos2: Vec2, pos3: Vec3, color: Rgb, count: usize, seed_base: u32) !void {
        if (self.particles.items.len > 900) return;
        for (0..count) |i| {
            const h = seed_base +% @as(u32, @intCast(i)) *% 2654435761;
            const ang = @as(f32, @floatFromInt(h % 6283)) * 0.001;
            const spd = 18.0 + @as(f32, @floatFromInt((h >> 8) % 45));
            const dir3 = fibonacciDirection(i, count, h);
            try self.particles.append(self.gpa, .{
                .pos2 = pos2,
                .vel2 = .{ .x = @cos(ang) * spd, .y = @sin(ang) * spd },
                .pos3 = pos3,
                .vel3 = dir3.scale(spd),
                .color = color,
                .ttl = 0.75,
                .max_ttl = 0.75,
                .size = 2.4,
            });
        }
    }

    pub fn applyEvent(self: *Simulation, ev: vcs.Event, spawn_fx: bool) !void {
        const dir_slice = std.fs.path.dirname(ev.path) orelse "";
        const dir_idx = try self.ensureDirChain(dir_slice);
        const author_idx = try self.ensureAuthor(ev.author);

        const file_idx = if (self.file_lookup.get(ev.path)) |existing| blk: {
            if (ev.custom_color) |cc| {
                self.files.items[existing].color = cc;
            }
            break :blk existing;
        } else blk: {
            const a = self.arena();
            const full_dup = try a.dupe(u8, ev.path);
            const name_dup = try a.dupe(u8, std.fs.path.basename(ev.path));
            const idx = self.files.items.len;
            const slot = self.dirs.items[dir_idx].files.items.len;
            const seed = hashString(full_dup);
            const unit3 = fibonacciDirection(slot, slot + 12, seed);
            const d_pos2 = self.dirs.items[dir_idx].pos2;
            const d_pos3 = self.dirs.items[dir_idx].pos3;

            try self.files.append(self.gpa, .{
                .dir_idx = dir_idx,
                .name = name_dup,
                .full_path = full_dup,
                .color = colorForPath(full_dup, ev.custom_color),
                .seed = seed,
                .local_unit3 = unit3,
                .pos2 = d_pos2,
                .pos3 = d_pos3,
            });
            try self.dirs.items[dir_idx].files.append(self.gpa, idx);
            try self.file_lookup.put(self.gpa, full_dup, idx);
            break :blk idx;
        };

        var file = &self.files.items[file_idx];
        switch (ev.action) {
            .add, .modify => {
                if (!file.alive) {
                    file.alive = true;
                    if (!spawn_fx) file.alpha = 1.0;
                    self.active_file_count += 1;
                    self.dirs.items[dir_idx].alive_files += 1;
                    self.adjustSubtreeCounts(dir_idx, 1);
                }
                file.heat = 1.0;
            },
            .delete => {
                if (file.alive) {
                    file.alive = false;
                    if (!spawn_fx) file.alpha = 0.0;
                    if (self.active_file_count > 0) self.active_file_count -= 1;
                    if (self.dirs.items[dir_idx].alive_files > 0) self.dirs.items[dir_idx].alive_files -= 1;
                    self.adjustSubtreeCounts(dir_idx, -1);
                }
                file.heat = 0.85;
            },
        }

        // Blend directory tint toward touched file color
        var dir = &self.dirs.items[dir_idx];
        dir.heat = 1.0;
        dir.tint = .{
            .r = @intCast((@as(u16, dir.tint.r) * 3 + file.color.r) / 4),
            .g = @intCast((@as(u16, dir.tint.g) * 3 + file.color.g) / 4),
            .b = @intCast((@as(u16, dir.tint.b) * 3 + file.color.b) / 4),
        };

        // Direct author orb toward this file cluster
        var author = &self.authors.items[author_idx];
        const offset_ang = @as(f32, @floatFromInt(author_idx)) * 1.7;
        author.target2 = .{
            .x = dir.pos2.x + @cos(offset_ang) * (dir.bubble_radius + 26.0),
            .y = dir.pos2.y + @sin(offset_ang) * (dir.bubble_radius + 26.0),
        };
        author.target3 = dir.pos3.add(author.pos3.sub(dir.pos3).normalizeOr(.{ .x = 0, .y = 1, .z = 0 }).scale(dir.bubble_radius + 34.0));
        author.energy = 1.0;
        author.touches +|= 1;

        if (ev.commit_hash.len > 0) self.last_commit_hash = ev.commit_hash;
        if (ev.commit_msg.len > 0) self.last_commit_msg = ev.commit_msg;
        self.last_author = author.name;

        if (spawn_fx) {
            if (self.beams.items.len < 96) {
                const beam_color: Rgb = switch (ev.action) {
                    .add => .{ .r = 80, .g = 245, .b = 155 },
                    .modify => file.color,
                    .delete => .{ .r = 255, .g = 92, .b = 92 },
                };
                try self.beams.append(self.gpa, .{
                    .author_idx = author_idx,
                    .file_idx = file_idx,
                    .color = beam_color,
                    .ttl = 0.55,
                    .max_ttl = 0.55,
                });
            }
            try self.spawnParticles(file.pos2, file.pos3, file.color, if (ev.action == .delete) 6 else 3, file.seed +% author.touches);
        }
    }

    pub fn appendStreamEvents(self: *Simulation, incoming: []const vcs.Event) !void {
        if (incoming.len == 0) return;
        for (incoming) |ev| {
            try self.events.append(self.arena(), ev);
            self.sim_time = ev.timestamp;
            self.end_time = @max(self.end_time, ev.timestamp);
            if (self.start_time == 0) self.start_time = ev.timestamp;
            try self.applyEvent(ev, true);
            self.next_event_idx = self.events.items.len;
        }
    }

    pub fn step(self: *Simulation, raw_dt: f32) !void {
        const dt = std.math.clamp(raw_dt, 0.001, 0.08);
        self.phase_clock += dt;

        const target_blend: f32 = if (self.view_mode == .bubbles_3d) 1.0 else 0.0;
        self.blend_3d += (target_blend - self.blend_3d) * @min(1.0, dt * 6.5);

        if (self.camera.auto_orbit and self.blend_3d > 0.05) {
            self.camera.yaw = @mod(self.camera.yaw + self.camera.orbit_speed * dt, std.math.tau);
        }

        if (!self.paused and !self.streaming_mode and self.events.items.len > 0) {
            if (self.next_event_idx < self.events.items.len) {
                const days_per_sec = 1.0 / @max(0.02, self.seconds_per_day);
                const advance_sec = @as(f64, dt) * 86400.0 * days_per_sec;

                const next_ts = self.events.items[self.next_event_idx].timestamp;
                if (self.auto_skip_idle and next_ts - self.sim_time > advance_sec * 45.0) {
                    self.sim_time = next_ts - advance_sec * 2.0;
                } else {
                    self.sim_time += advance_sec;
                }

                var applied_this_frame: usize = 0;
                while (self.next_event_idx < self.events.items.len and
                    self.events.items[self.next_event_idx].timestamp <= self.sim_time and
                    applied_this_frame < 180)
                {
                    try self.applyEvent(self.events.items[self.next_event_idx], applied_this_frame < 24);
                    self.next_event_idx += 1;
                    applied_this_frame += 1;
                }
            } else if (self.loop_playback) {
                try self.restart();
            } else {
                self.finished = true;
            }
        }

        self.stepPhysics(dt);
    }

    fn stepPhysics(self: *Simulation, dt: f32) void {
        const dir_count = self.dirs.items.len;

        // 1. Update directory bubble sizes and heat decay
        for (self.dirs.items, 0..) |*d, idx| {
            const fcount: f32 = @floatFromInt(d.alive_files);
            const scount: f32 = @floatFromInt(d.subtree_files);
            const target_r: f32 = if (idx == 0)
                26.0 + @sqrt(fcount) * 4.2
            else
                14.0 + @sqrt(fcount) * 5.2 + @sqrt(scount) * 1.4;
            d.bubble_radius += (target_r - d.bubble_radius) * @min(1.0, dt * 6.0);
            d.heat = @max(0.0, d.heat - dt * 1.35);
        }

        // 2. Pin root at origin; relax child directories via hierarchical springs + repulsion
        if (dir_count > 0) {
            self.dirs.items[0].pos2 = .{};
            self.dirs.items[0].pos3 = .{};
        }

        for (1..dir_count) |i| {
            var d = &self.dirs.items[i];
            const p_idx = d.parent orelse 0;
            const parent = self.dirs.items[p_idx];

            const sibling_count: f32 = @floatFromInt(@max(parent.child_dirs.items.len, 1));
            const rest_dist_2d = parent.bubble_radius + d.bubble_radius + 46.0 + sibling_count * 4.0;
            const rest_dist_3d = parent.bubble_radius + d.bubble_radius + 42.0 + @sqrt(sibling_count) * 14.0;

            const desired2 = Vec2{
                .x = parent.pos2.x + @cos(d.angle_hint) * rest_dist_2d,
                .y = parent.pos2.y + @sin(d.angle_hint) * rest_dist_2d,
            };
            const desired3 = parent.pos3.add(d.orbit_unit.scale(rest_dist_3d));

            var force2 = desired2.sub(d.pos2).scale(6.5);
            var force3 = desired3.sub(d.pos3).scale(6.5);

            // Pairwise directory repulsion (capped window for large repos so O(N) stays fast)
            const window_start = if (i > 48) i - 48 else 1;
            const window_end = @min(dir_count, i + 48);
            for (window_start..window_end) |j| {
                if (i == j) continue;
                const other = self.dirs.items[j];

                const diff2 = d.pos2.sub(other.pos2);
                const min_sep2 = d.bubble_radius + other.bubble_radius + 24.0;
                const d2_sq = diff2.lenSq() + 1.0;
                if (d2_sq < min_sep2 * min_sep2) {
                    const dist2 = @sqrt(d2_sq);
                    const push2 = (min_sep2 - dist2) * 14.0 / dist2;
                    force2 = force2.add(diff2.scale(push2));
                }

                const diff3 = d.pos3.sub(other.pos3);
                const min_sep3 = d.bubble_radius + other.bubble_radius + 22.0;
                const d3_sq = diff3.lenSq() + 1.0;
                if (d3_sq < min_sep3 * min_sep3) {
                    const dist3 = @sqrt(d3_sq);
                    const push3 = (min_sep3 - dist3) * 15.0 / dist3;
                    force3 = force3.add(diff3.scale(push3));
                }
            }

            d.vel2 = d.vel2.add(force2.scale(dt)).scale(@exp(-4.5 * dt));
            d.pos2 = d.pos2.add(d.vel2.scale(dt));

            d.vel3 = d.vel3.add(force3.scale(dt)).scale(@exp(-4.5 * dt));
            d.pos3 = d.pos3.add(d.vel3.scale(dt));
        }

        // 3. Position file bubbles cleanly inside/around parent directory bubble
        for (self.dirs.items) |d| {
            var alive_rank: usize = 0;
            const total_alive = @max(d.alive_files, 1);
            for (d.files.items) |f_idx| {
                var f = &self.files.items[f_idx];
                if (f.alive) {
                    f.alpha = @min(1.0, f.alpha + dt * 3.8);
                } else {
                    f.alpha = @max(0.0, f.alpha - dt * 2.2);
                }
                f.heat = @max(0.0, f.heat - dt * 1.1);
                if (f.alpha <= 0.001) continue;

                const rank_f: f32 = @floatFromInt(alive_rank);
                if (f.alive) alive_rank += 1;

                // Golden-angle phyllotaxis disc in 2D
                const golden: f32 = 2.39996323;
                const r2 = 8.0 + 5.8 * @sqrt(rank_f + 0.5);
                const a2 = rank_f * golden + d.angle_hint;
                const target2 = Vec2{
                    .x = d.pos2.x + @cos(a2) * r2,
                    .y = d.pos2.y + @sin(a2) * r2,
                };

                // Fibonacci spherical shell + gentle local orbital spin in 3D
                const spin = self.phase_clock * 0.32 + @as(f32, @floatFromInt(f.seed % 100)) * 0.03;
                const u = fibonacciDirection(alive_rank, total_alive + 2, f.seed);
                const cs = @cos(spin);
                const sn = @sin(spin);
                const spun = Vec3{
                    .x = u.x * cs + u.z * sn,
                    .y = u.y,
                    .z = -u.x * sn + u.z * cs,
                };
                const shell_r = @max(6.0, d.bubble_radius * 0.72);
                const target3 = d.pos3.add(spun.scale(shell_r));

                const follow = @min(1.0, dt * 9.0);
                f.pos2 = .{
                    .x = f.pos2.x + (target2.x - f.pos2.x) * follow,
                    .y = f.pos2.y + (target2.y - f.pos2.y) * follow,
                };
                f.pos3 = Vec3.lerp(f.pos3, target3, follow);
                f.radius = 4.2 + f.heat * 2.4;
            }
        }

        // 4. Glide author orbs smoothly
        for (self.authors.items) |*a| {
            a.energy = @max(0.0, a.energy - dt * 0.35);
            const glide = @min(1.0, dt * 5.5);
            a.pos2 = .{
                .x = a.pos2.x + (a.target2.x - a.pos2.x) * glide,
                .y = a.pos2.y + (a.target2.y - a.pos2.y) * glide,
            };
            a.pos3 = Vec3.lerp(a.pos3, a.target3, glide);
        }

        // 5. Decay action beams & particles
        var bi: usize = 0;
        while (bi < self.beams.items.len) {
            self.beams.items[bi].ttl -= dt;
            if (self.beams.items[bi].ttl <= 0) {
                _ = self.beams.swapRemove(bi);
            } else {
                bi += 1;
            }
        }

        var pi: usize = 0;
        while (pi < self.particles.items.len) {
            var p = &self.particles.items[pi];
            p.ttl -= dt;
            if (p.ttl <= 0) {
                _ = self.particles.swapRemove(pi);
            } else {
                p.pos2 = p.pos2.add(p.vel2.scale(dt));
                p.pos3 = p.pos3.add(p.vel3.scale(dt));
                pi += 1;
            }
        }
    }
};

test "simulation builds directory clusters, updates file counts, and formats UTC dates" {
    var sim = try Simulation.init(std.testing.allocator, "zource", .git, .bubbles_3d);
    defer sim.deinit();

    try sim.applyEvent(.{
        .timestamp = 1700000000,
        .author = "Christopher",
        .action = .add,
        .path = "src/core/engine.zig",
        .commit_hash = "1234abc",
        .commit_msg = "Add 3D bubble layout",
    }, true);
    try sim.applyEvent(.{
        .timestamp = 1700000100,
        .author = "Christopher",
        .action = .add,
        .path = "README.md",
    }, true);

    try std.testing.expectEqual(@as(u32, 2), sim.active_file_count);
    try std.testing.expectEqual(@as(usize, 3), sim.dirs.items.len); // root, src, src/core
    try std.testing.expectEqual(@as(usize, 1), sim.authors.items.len);

    try sim.step(0.016);

    try sim.applyEvent(.{
        .timestamp = 1700000200,
        .author = "Christopher",
        .action = .delete,
        .path = "README.md",
    }, false);
    try std.testing.expectEqual(@as(u32, 1), sim.active_file_count);

    var date_buf: [20]u8 = undefined;
    const formatted = formatTimestampUtc(1700000000, &date_buf);
    try std.testing.expectEqualStrings("2023-11-14 22:13", formatted);
}
