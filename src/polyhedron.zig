const std = @import("std");
const vcs = @import("vcs.zig");
const sim_mod = @import("sim.zig");

pub const Vec3 = sim_mod.Vec3;
pub const Rgb = vcs.Rgb;

pub const MIN_VERTS: u8 = 4;
pub const MAX_VERTS: u8 = 42;
pub const MAX_FACES: usize = 80;
pub const MAX_EDGES: usize = 120;

pub const PolyMesh = struct {
    verts: [MAX_VERTS]Vec3 = @splat(.{}),
    faces: [MAX_FACES][3]u8 = @splat(.{ 0, 0, 0 }),
    edges: [MAX_EDGES][2]u8 = @splat(.{ 0, 0 }),
    v_count: u8 = 0,
    f_count: u8 = 0,
    e_count: u8 = 0,

    fn addVert(self: *PolyMesh, v: Vec3) u8 {
        const idx = self.v_count;
        self.verts[idx] = v.normalizeOr(.{ .x = 0, .y = 1, .z = 0 });
        self.v_count += 1;
        return idx;
    }

    fn addEdge(self: *PolyMesh, a: u8, b: u8) void {
        const u = @min(a, b);
        const v = @max(a, b);
        var i: usize = 0;
        while (i < self.e_count) : (i += 1) {
            if (self.edges[i][0] == u and self.edges[i][1] == v) return;
        }
        if (self.e_count < MAX_EDGES) {
            self.edges[self.e_count] = .{ u, v };
            self.e_count += 1;
        }
    }

    fn addFace(self: *PolyMesh, a: u8, b: u8, c: u8) void {
        if (self.f_count >= MAX_FACES) return;
        const va = self.verts[a];
        const vb = self.verts[b];
        const vc = self.verts[c];
        const e1 = vb.sub(va);
        const e2 = vc.sub(va);
        const cross = Vec3{
            .x = e1.y * e2.z - e1.z * e2.y,
            .y = e1.z * e2.x - e1.x * e2.z,
            .z = e1.x * e2.y - e1.y * e2.x,
        };
        const centroid = Vec3{
            .x = va.x + vb.x + vc.x,
            .y = va.y + vb.y + vc.y,
            .z = va.z + vb.z + vc.z,
        };
        const dot_out = cross.x * centroid.x + cross.y * centroid.y + cross.z * centroid.z;
        if (dot_out >= 0.0) {
            self.faces[self.f_count] = .{ a, b, c };
        } else {
            self.faces[self.f_count] = .{ a, c, b };
        }
        self.f_count += 1;
        self.addEdge(a, b);
        self.addEdge(b, c);
        self.addEdge(c, a);
    }
};

pub const ProjectedFace = struct {
    p0: [2]f32,
    p1: [2]f32,
    p2: [2]f32,
    depth: f32,
    color: Rgb,
    alpha: f32,
    front: bool,
};

pub const ProjectedEdge = struct {
    p0: [2]f32,
    p1: [2]f32,
    alpha: f32,
    front: bool,
};

pub const ProjectedPoly = struct {
    faces: [MAX_FACES]ProjectedFace = undefined,
    face_count: usize = 0,
    edges: [MAX_EDGES]ProjectedEdge = undefined,
    edge_count: usize = 0,
};

pub fn vertexCountForFiles(file_count: u32) u8 {
    if (file_count <= MIN_VERTS) return MIN_VERTS;
    if (file_count >= MAX_VERTS) return MAX_VERTS;
    return @intCast(file_count);
}

var mesh_cache: [MAX_VERTS - MIN_VERTS + 1]PolyMesh = undefined;
var mesh_cache_ready: bool = false;

pub fn meshForFileCount(file_count: u32) *const PolyMesh {
    if (!mesh_cache_ready) {
        var v: u8 = MIN_VERTS;
        while (v <= MAX_VERTS) : (v += 1) {
            mesh_cache[v - MIN_VERTS] = buildMesh(v);
        }
        mesh_cache_ready = true;
    }
    const clamped = vertexCountForFiles(file_count);
    return &mesh_cache[clamped - MIN_VERTS];
}

pub fn buildMesh(v_target: u8) PolyMesh {
    const v = std.math.clamp(v_target, MIN_VERTS, MAX_VERTS);
    if (v == 4) return buildTetrahedron();
    if (v == 8) return buildSquareAntiprism();
    if (v == 12) return buildIcosahedron();
    return buildPolarRingPolyhedron(v);
}

fn buildTetrahedron() PolyMesh {
    var m = PolyMesh{};
    _ = m.addVert(.{ .x = 1.0, .y = 1.0, .z = 1.0 });
    _ = m.addVert(.{ .x = 1.0, .y = -1.0, .z = -1.0 });
    _ = m.addVert(.{ .x = -1.0, .y = 1.0, .z = -1.0 });
    _ = m.addVert(.{ .x = -1.0, .y = -1.0, .z = 1.0 });
    m.addFace(0, 1, 2);
    m.addFace(0, 2, 3);
    m.addFace(0, 3, 1);
    m.addFace(1, 3, 2);
    return m;
}

fn buildSquareAntiprism() PolyMesh {
    var m = PolyMesh{};
    const y_off: f32 = 0.56;
    const rad: f32 = @sqrt(1.0 - y_off * y_off);
    const pi: f32 = std.math.pi;
    for (0..4) |i| {
        const a = (@as(f32, @floatFromInt(i)) / 4.0) * 2.0 * pi;
        _ = m.addVert(.{ .x = @cos(a) * rad, .y = y_off, .z = @sin(a) * rad });
    }
    for (0..4) |i| {
        const a = ((@as(f32, @floatFromInt(i)) + 0.5) / 4.0) * 2.0 * pi;
        _ = m.addVert(.{ .x = @cos(a) * rad, .y = -y_off, .z = @sin(a) * rad });
    }
    // Top cap (2 triangles)
    m.addFace(0, 2, 1);
    m.addFace(0, 3, 2);
    // Side antiprism band (8 triangles)
    for (0..4) |i| {
        const i_next = (i + 1) % 4;
        const t0: u8 = @intCast(i);
        const t1: u8 = @intCast(i_next);
        const b0: u8 = @intCast(4 + i);
        const b1: u8 = @intCast(4 + i_next);
        m.addFace(t0, t1, b0);
        m.addFace(t1, b1, b0);
    }
    // Bottom cap (2 triangles)
    m.addFace(4, 5, 6);
    m.addFace(4, 6, 7);
    return m;
}

fn buildIcosahedron() PolyMesh {
    var m = PolyMesh{};
    const phi: f32 = 1.618033988749895;
    const raw = [12]Vec3{
        .{ .x = -1, .y = phi, .z = 0 },
        .{ .x = 1, .y = phi, .z = 0 },
        .{ .x = -1, .y = -phi, .z = 0 },
        .{ .x = 1, .y = -phi, .z = 0 },
        .{ .x = 0, .y = -1, .z = phi },
        .{ .x = 0, .y = 1, .z = phi },
        .{ .x = 0, .y = -1, .z = -phi },
        .{ .x = 0, .y = 1, .z = -phi },
        .{ .x = phi, .y = 0, .z = -1 },
        .{ .x = phi, .y = 0, .z = 1 },
        .{ .x = -phi, .y = 0, .z = -1 },
        .{ .x = -phi, .y = 0, .z = 1 },
    };
    for (raw) |p| _ = m.addVert(p);

    const tris = [20][3]u8{
        .{ 0, 11, 5 },  .{ 0, 5, 1 },  .{ 0, 1, 7 },   .{ 0, 7, 10 },  .{ 0, 10, 11 },
        .{ 1, 5, 9 },   .{ 5, 11, 4 }, .{ 11, 10, 2 }, .{ 10, 7, 6 },  .{ 7, 1, 8 },
        .{ 3, 9, 4 },   .{ 3, 4, 2 },  .{ 3, 2, 6 },   .{ 3, 6, 8 },   .{ 3, 8, 9 },
        .{ 4, 9, 5 },   .{ 2, 4, 11 }, .{ 6, 2, 10 },  .{ 8, 6, 7 },   .{ 9, 8, 1 },
    };
    for (tris) |f| m.addFace(f[0], f[1], f[2]);
    return m;
}

fn buildPolarRingPolyhedron(v_total: u8) PolyMesh {
    var m = PolyMesh{};
    const pi: f32 = std.math.pi;
    const rem: usize = @as(usize, v_total) - 2;
    const ring_count: usize = if (rem <= 5) 1 else if (rem <= 14) 2 else if (rem <= 26) 3 else 4;

    var ring_sizes: [4]usize = @splat(0);
    var weights: [4]f32 = @splat(0);
    var weight_sum: f32 = 0.0;
    for (0..ring_count) |r| {
        const theta = pi * (@as(f32, @floatFromInt(r + 1)) / @as(f32, @floatFromInt(ring_count + 1)));
        weights[r] = @sin(theta);
        weight_sum += weights[r];
    }

    var assigned: usize = 0;
    for (0..ring_count) |r| {
        const est = @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(rem)) * (weights[r] / weight_sum))));
        ring_sizes[r] = @max(3, est);
        assigned += ring_sizes[r];
    }
    while (assigned < rem) {
        var best_r: usize = 0;
        var best_deficit: f32 = -1e9;
        for (0..ring_count) |r| {
            const ideal = @as(f32, @floatFromInt(rem)) * (weights[r] / weight_sum);
            const deficit = ideal - @as(f32, @floatFromInt(ring_sizes[r]));
            if (deficit > best_deficit) {
                best_deficit = deficit;
                best_r = r;
            }
        }
        ring_sizes[best_r] += 1;
        assigned += 1;
    }
    while (assigned > rem) {
        var best_r: usize = 0;
        var best_surplus: f32 = -1e9;
        for (0..ring_count) |r| {
            if (ring_sizes[r] <= 3) continue;
            const ideal = @as(f32, @floatFromInt(rem)) * (weights[r] / weight_sum);
            const surplus = @as(f32, @floatFromInt(ring_sizes[r])) - ideal;
            if (surplus > best_surplus) {
                best_surplus = surplus;
                best_r = r;
            }
        }
        ring_sizes[best_r] -= 1;
        assigned -= 1;
    }

    const north_idx = m.addVert(.{ .x = 0, .y = 1, .z = 0 });
    var ring_starts: [4]u8 = @splat(0);

    for (0..ring_count) |r| {
        ring_starts[r] = m.v_count;
        const theta = pi * (@as(f32, @floatFromInt(r + 1)) / @as(f32, @floatFromInt(ring_count + 1)));
        const y = @cos(theta);
        const rad = @sin(theta);
        const k = ring_sizes[r];
        const phase: f32 = if ((r & 1) == 1) (pi / @as(f32, @floatFromInt(k))) else 0.0;
        for (0..k) |j| {
            const ang = phase + (@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(k))) * 2.0 * pi;
            _ = m.addVert(.{ .x = @cos(ang) * rad, .y = y, .z = @sin(ang) * rad });
        }
    }

    const south_idx = m.addVert(.{ .x = 0, .y = -1, .z = 0 });

    // North pole fan
    const k0 = ring_sizes[0];
    const s0 = ring_starts[0];
    for (0..k0) |j| {
        const a: u8 = @intCast(@as(usize, s0) + j);
        const b: u8 = @intCast(@as(usize, s0) + ((j + 1) % k0));
        m.addFace(north_idx, b, a);
    }

    // Staggered ring strips
    for (0..ring_count - 1) |r| {
        const ka = ring_sizes[r];
        const kb = ring_sizes[r + 1];
        const sa = ring_starts[r];
        const sb = ring_starts[r + 1];
        var ia: usize = 0;
        var ib: usize = 0;
        while (ia < ka or ib < kb) {
            const prog_a = (@as(f32, @floatFromInt(ia)) + 0.5) / @as(f32, @floatFromInt(ka));
            const prog_b = (@as(f32, @floatFromInt(ib)) + 0.5) / @as(f32, @floatFromInt(kb));
            const a0: u8 = @intCast(@as(usize, sa) + (ia % ka));
            const b0: u8 = @intCast(@as(usize, sb) + (ib % kb));
            if (ia < ka and (ib == kb or prog_a <= prog_b)) {
                const a1: u8 = @intCast(@as(usize, sa) + ((ia + 1) % ka));
                m.addFace(a0, a1, b0);
                ia += 1;
            } else {
                const b1: u8 = @intCast(@as(usize, sb) + ((ib + 1) % kb));
                m.addFace(a0, b1, b0);
                ib += 1;
            }
        }
    }

    // South pole fan
    const kl = ring_sizes[ring_count - 1];
    const sl = ring_starts[ring_count - 1];
    for (0..kl) |j| {
        const a: u8 = @intCast(@as(usize, sl) + j);
        const b: u8 = @intCast(@as(usize, sl) + ((j + 1) % kl));
        m.addFace(south_idx, a, b);
    }

    return m;
}

fn rgbToHsl(c: Rgb) struct { h: f32, s: f32, l: f32 } {
    const r = @as(f32, @floatFromInt(c.r)) / 255.0;
    const g = @as(f32, @floatFromInt(c.g)) / 255.0;
    const b = @as(f32, @floatFromInt(c.b)) / 255.0;
    const max_v = @max(r, @max(g, b));
    const min_v = @min(r, @min(g, b));
    const l = (max_v + min_v) * 0.5;
    const d = max_v - min_v;
    if (d < 0.0001) return .{ .h = 205.0, .s = 0.25, .l = l };
    const s = if (l > 0.5) d / (2.0 - max_v - min_v) else d / (max_v + min_v);
    var h: f32 = 0.0;
    if (max_v == r) {
        h = (g - b) / d + (if (g < b) @as(f32, 6.0) else @as(f32, 0.0));
    } else if (max_v == g) {
        h = (b - r) / d + 2.0;
    } else {
        h = (r - g) / d + 4.0;
    }
    return .{ .h = h * 60.0, .s = s, .l = l };
}

fn hslToRgb(h_deg: f32, s: f32, l: f32) Rgb {
    const h = @mod(h_deg, 360.0);
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const hp = h / 60.0;
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

/// Harmonized analogous facet color derived from the directory tint.
/// Shifts hue within a tasteful +/-32 degree analogous window with subtle saturation/lightness variation.
pub fn facetColor(base: Rgb, face_idx: usize, dir_seed: u32) Rgb {
    const hsl = rgbToHsl(base);
    const seed_f = @as(f32, @floatFromInt(dir_seed % 997)) * 0.001003;
    const fi = @as(f32, @floatFromInt(face_idx));
    const u = @mod(fi * 0.6180339887 + seed_f, 1.0);
    const v = @mod(fi * 0.3819660113 + seed_f * 1.7, 1.0);
    const hue_shift = (u * 2.0 - 1.0) * 32.0;
    const sat = std.math.clamp(hsl.s * (0.85 + v * 0.30), 0.28, 0.78);
    const light = std.math.clamp(hsl.l * (0.86 + (1.0 - v) * 0.24), 0.36, 0.74);
    return hslToRgb(hsl.h + hue_shift, sat, light);
}

pub fn projectPolyhedron(
    file_count: u32,
    cx: f32,
    cy: f32,
    radius: f32,
    base_color: Rgb,
    alpha_scale: f32,
    heat: f32,
    cam_yaw: f32,
    cam_pitch: f32,
    elapsed: f32,
    dir_seed: u32,
) ProjectedPoly {
    var out = ProjectedPoly{};
    if (radius < 2.5 or alpha_scale <= 0.01) return out;

    const mesh = meshForFileCount(file_count);
    // Slightly expand low-vertex polyhedra so flat faces comfortably enclose the files inside
    const v_f = @as(f32, @floatFromInt(mesh.v_count));
    const eff_radius = radius * (1.0 + 0.26 / @sqrt(@max(1.0, v_f - 3.0)));

    // Gentle per-directory local rotation + camera orientation
    const phase = @as(f32, @floatFromInt(dir_seed % 360)) * (std.math.pi / 180.0);
    const tilt = (@as(f32, @floatFromInt((dir_seed / 7) % 100)) / 100.0 - 0.5) * 0.55;
    const local_yaw = phase + elapsed * 0.14;
    const cl = @cos(local_yaw);
    const sl = @sin(local_yaw);
    const ct = @cos(tilt);
    const st = @sin(tilt);

    const cy_cam = @cos(cam_yaw);
    const sy_cam = @sin(cam_yaw);
    const cp_cam = @cos(cam_pitch);
    const sp_cam = @sin(cam_pitch);

    var cam_v: [MAX_VERTS]Vec3 = undefined;
    var scr_v: [MAX_VERTS][2]f32 = undefined;
    for (0..mesh.v_count) |i| {
        const p = mesh.verts[i];
        // Local spin around Y then slight tilt around X
        const lx = p.x * cl + p.z * sl;
        const lz0 = -p.x * sl + p.z * cl;
        const ly = p.y * ct - lz0 * st;
        const lz = p.y * st + lz0 * ct;

        // Camera yaw then pitch (matches sim.Camera.project3D)
        const rx = lx * cy_cam + lz * sy_cam;
        const rz0 = -lx * sy_cam + lz * cy_cam;
        const ry = ly * cp_cam - rz0 * sp_cam;
        const rz = ly * sp_cam + rz0 * cp_cam;

        cam_v[i] = .{ .x = rx, .y = ry, .z = rz };
        scr_v[i] = .{ cx + rx * eff_radius, cy - ry * eff_radius };
    }

    var vert_front: [MAX_VERTS]bool = @splat(false);

    // Normalized key light coming from top-left-front
    const lx_dir: f32 = -0.45;
    const ly_dir: f32 = 0.55;
    const lz_dir: f32 = -0.70;

    for (0..mesh.f_count) |fi| {
        const f = mesh.faces[fi];
        const v0 = cam_v[f[0]];
        const v1 = cam_v[f[1]];
        const v2 = cam_v[f[2]];
        const e1 = v1.sub(v0);
        const e2 = v2.sub(v0);
        const n = (Vec3{
            .x = e1.y * e2.z - e1.z * e2.y,
            .y = e1.z * e2.x - e1.x * e2.z,
            .z = e1.x * e2.y - e1.y * e2.x,
        }).normalizeOr(.{ .x = 0, .y = 0, .z = -1 });

        const front = n.z < 0.0;
        if (front) {
            vert_front[f[0]] = true;
            vert_front[f[1]] = true;
            vert_front[f[2]] = true;
        }

        const fc = facetColor(base_color, fi, dir_seed);
        const abs_nz = @abs(n.z);
        const omz = 1.0 - abs_nz;
        const fresnel = omz * omz;

        const l_dot = @max(0.0, n.x * lx_dir + n.y * ly_dir + n.z * lz_dir);
        const l2 = l_dot * l_dot;
        const l4 = l2 * l2;
        const spec = if (front) l4 * l4 * 0.42 else 0.0;

        const shade: f32 = if (front) (0.60 + l_dot * 0.44 + heat * 0.18) else (0.36 + heat * 0.10);
        const base_alpha: f32 = if (front)
            (0.11 + fresnel * (0.24 + heat * 0.14) + spec * 0.30)
        else
            (0.05 + fresnel * 0.055);

        const fr: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(fc.r)) * shade + spec * 225.0));
        const fg: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(fc.g)) * shade + spec * 235.0));
        const fb: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(fc.b)) * shade + spec * 250.0));

        out.faces[out.face_count] = .{
            .p0 = scr_v[f[0]],
            .p1 = scr_v[f[1]],
            .p2 = scr_v[f[2]],
            .depth = (v0.z + v1.z + v2.z) * (1.0 / 3.0),
            .color = .{ .r = fr, .g = fg, .b = fb },
            .alpha = std.math.clamp(base_alpha * alpha_scale, 0.0, 0.72),
            .front = front,
        };
        out.face_count += 1;
    }

    // Painter sort faces back-to-front (larger z is farther from camera)
    std.mem.sort(ProjectedFace, out.faces[0..out.face_count], {}, struct {
        fn farther(_: void, a: ProjectedFace, b: ProjectedFace) bool {
            return a.depth > b.depth;
        }
    }.farther);

    for (0..mesh.e_count) |ei| {
        const e = mesh.edges[ei];
        const front = vert_front[e[0]] and vert_front[e[1]];
        const ea: f32 = if (front)
            (0.24 + heat * 0.22) * alpha_scale
        else
            0.075 * alpha_scale;
        out.edges[out.edge_count] = .{
            .p0 = scr_v[e[0]],
            .p1 = scr_v[e[1]],
            .alpha = std.math.clamp(ea, 0.0, 0.65),
            .front = front,
        };
        out.edge_count += 1;
    }

    return out;
}

test "polyhedron meshes satisfy Euler formula V - E + F = 2 for all file counts 4..42" {
    var v: u8 = MIN_VERTS;
    while (v <= MAX_VERTS) : (v += 1) {
        const m = buildMesh(v);
        try std.testing.expectEqual(v, m.v_count);
        const euler: i32 = @as(i32, m.v_count) - @as(i32, m.e_count) + @as(i32, m.f_count);
        try std.testing.expectEqual(@as(i32, 2), euler);
        try std.testing.expectEqual(@as(u8, 2 * v - 4), m.f_count);
        // Every vertex lies on the unit sphere
        for (0..m.v_count) |i| {
            const p = m.verts[i];
            const len = @sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
            try std.testing.expect(@abs(len - 1.0) < 0.001);
        }
    }
    try std.testing.expectEqual(@as(u8, 4), vertexCountForFiles(1));
    try std.testing.expectEqual(@as(u8, 4), vertexCountForFiles(4));
    try std.testing.expectEqual(@as(u8, 12), vertexCountForFiles(12));
    try std.testing.expectEqual(@as(u8, 42), vertexCountForFiles(150));
}

test "facetColor produces distinct analogous colors close to directory tint" {
    const base = Rgb{ .r = 90, .g = 155, .b = 235 };
    const c0 = facetColor(base, 0, 17);
    const c1 = facetColor(base, 1, 17);
    const c2 = facetColor(base, 2, 17);
    try std.testing.expect(c0.r != c1.r or c0.g != c1.g or c0.b != c1.b);
    try std.testing.expect(c1.r != c2.r or c1.g != c2.g or c1.b != c2.b);
    // Still predominantly cool/blue family (not wildly neon green or red)
    try std.testing.expect(c0.b >= c0.r);
    try std.testing.expect(c1.b >= c1.r);
}
