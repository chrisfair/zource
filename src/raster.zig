const std = @import("std");
const vcs = @import("vcs.zig");
const sim_mod = @import("sim.zig");
const font = @import("font.zig");
const poly = @import("polyhedron.zig");
const Allocator = std.mem.Allocator;
const Rgb = vcs.Rgb;
const Simulation = sim_mod.Simulation;
const Vec3 = sim_mod.Vec3;

const ItemKind = enum {
    dir_shell,
    file_orb,
    author_orb,
    particle,
};

const ProjectedItem = struct {
    kind: ItemKind,
    index: usize,
    sx: f32,
    sy: f32,
    sr: f32,
    depth: f32,
    fog: f32,
    alpha: f32,
    heat: f32,
    color: Rgb,
    file_count: u32 = 0,
};

pub const Framebuffer = struct {
    gpa: Allocator,
    width: u32,
    height: u32,
    rgb: []u8,
    bg_template: []u8,
    items_scratch: std.ArrayList(ProjectedItem) = .empty,

    pub fn init(gpa: Allocator, width: u32, height: u32) !Framebuffer {
        const w = @max(width, 64);
        const h = @max(height, 64);
        const byte_len = @as(usize, w) * @as(usize, h) * 3;
        const rgb = try gpa.alloc(u8, byte_len);
        errdefer gpa.free(rgb);
        const bg = try gpa.alloc(u8, byte_len);
        errdefer gpa.free(bg);

        var fb = Framebuffer{
            .gpa = gpa,
            .width = w,
            .height = h,
            .rgb = rgb,
            .bg_template = bg,
        };
        fb.rebuildBackdrop();
        return fb;
    }

    pub fn deinit(self: *Framebuffer) void {
        self.items_scratch.deinit(self.gpa);
        self.gpa.free(self.bg_template);
        self.gpa.free(self.rgb);
    }

    pub fn resize(self: *Framebuffer, width: u32, height: u32) !void {
        const w = @max(width, 64);
        const h = @max(height, 64);
        if (w == self.width and h == self.height) return;
        const byte_len = @as(usize, w) * @as(usize, h) * 3;
        const new_rgb = try self.gpa.realloc(self.rgb, byte_len);
        self.rgb = new_rgb;
        const new_bg = try self.gpa.realloc(self.bg_template, byte_len);
        self.bg_template = new_bg;
        self.width = w;
        self.height = h;
        self.rebuildBackdrop();
    }

    fn rebuildBackdrop(self: *Framebuffer) void {
        const wf: f32 = @floatFromInt(self.width);
        const hf: f32 = @floatFromInt(self.height);
        const cx = wf * 0.5;
        const cy = hf * 0.5;
        const inv_max_r = 1.0 / @max(1.0, @sqrt(cx * cx + cy * cy));

        var idx: usize = 0;
        for (0..self.height) |uy| {
            const dy = @as(f32, @floatFromInt(uy)) - cy;
            for (0..self.width) |ux| {
                const dx = @as(f32, @floatFromInt(ux)) - cx;
                const dist_norm = @min(1.0, @sqrt(dx * dx + dy * dy) * inv_max_r);
                const glow = 1.0 - dist_norm * dist_norm;
                self.bg_template[idx + 0] = @intFromFloat(5.0 + glow * 8.0);
                self.bg_template[idx + 1] = @intFromFloat(8.0 + glow * 13.0);
                self.bg_template[idx + 2] = @intFromFloat(15.0 + glow * 24.0);
                idx += 3;
            }
        }
    }

    pub fn clear(self: *Framebuffer) void {
        @memcpy(self.rgb, self.bg_template);
    }

    inline fn blendPixel(self: *Framebuffer, x: i32, y: i32, r: u8, g: u8, b: u8, alpha: f32) void {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return;
        const a = std.math.clamp(alpha, 0.0, 1.0);
        if (a <= 0.004) return;
        const idx = (@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))) * 3;
        const inv = 1.0 - a;
        self.rgb[idx + 0] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 0])) * inv + @as(f32, @floatFromInt(r)) * a));
        self.rgb[idx + 1] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 1])) * inv + @as(f32, @floatFromInt(g)) * a));
        self.rgb[idx + 2] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 2])) * inv + @as(f32, @floatFromInt(b)) * a));
    }

    inline fn addPixel(self: *Framebuffer, x: i32, y: i32, r: u8, g: u8, b: u8, intensity: f32) void {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return;
        const k = std.math.clamp(intensity, 0.0, 2.0);
        if (k <= 0.004) return;
        const idx = (@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))) * 3;
        self.rgb[idx + 0] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 0])) + @as(f32, @floatFromInt(r)) * k));
        self.rgb[idx + 1] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 1])) + @as(f32, @floatFromInt(g)) * k));
        self.rgb[idx + 2] = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(self.rgb[idx + 2])) + @as(f32, @floatFromInt(b)) * k));
    }

    pub fn fillRectAlpha(self: *Framebuffer, x0: i32, y0: i32, w: i32, h: i32, c: Rgb, alpha: f32) void {
        const sx = @max(0, x0);
        const sy = @max(0, y0);
        const ex = @min(@as(i32, @intCast(self.width)), x0 + w);
        const ey = @min(@as(i32, @intCast(self.height)), y0 + h);
        if (sx >= ex or sy >= ey) return;

        const a = std.math.clamp(alpha, 0.0, 1.0);
        const inv = 1.0 - a;
        const cr = @as(f32, @floatFromInt(c.r)) * a;
        const cg = @as(f32, @floatFromInt(c.g)) * a;
        const cb = @as(f32, @floatFromInt(c.b)) * a;

        var y = sy;
        while (y < ey) : (y += 1) {
            var idx = (@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(sx))) * 3;
            var x = sx;
            while (x < ex) : (x += 1) {
                self.rgb[idx + 0] = @intFromFloat(@as(f32, @floatFromInt(self.rgb[idx + 0])) * inv + cr);
                self.rgb[idx + 1] = @intFromFloat(@as(f32, @floatFromInt(self.rgb[idx + 1])) * inv + cg);
                self.rgb[idx + 2] = @intFromFloat(@as(f32, @floatFromInt(self.rgb[idx + 2])) * inv + cb);
                idx += 3;
            }
        }
    }

    pub fn drawLineAdditive(self: *Framebuffer, x0_f: f32, y0_f: f32, x1_f: f32, y1_f: f32, c: Rgb, intensity: f32, thick: bool) void {
        const wf: f32 = @floatFromInt(self.width);
        const hf: f32 = @floatFromInt(self.height);
        if ((x0_f < -60 and x1_f < -60) or (x0_f > wf + 60 and x1_f > wf + 60) or
            (y0_f < -60 and y1_f < -60) or (y0_f > hf + 60 and y1_f > hf + 60)) return;

        const dx = x1_f - x0_f;
        const dy = y1_f - y0_f;
        const steps_f = @max(@abs(dx), @abs(dy));
        if (steps_f < 0.5) return;
        const steps: usize = @intFromFloat(@min(steps_f, 2400.0));
        if (steps == 0) return;

        const inv_s = 1.0 / @as(f32, @floatFromInt(steps));
        var px = x0_f;
        var py = y0_f;
        const sx = dx * inv_s;
        const sy = dy * inv_s;

        for (0..steps + 1) |_| {
            const ix: i32 = @intFromFloat(px);
            const iy: i32 = @intFromFloat(py);
            self.addPixel(ix, iy, c.r, c.g, c.b, intensity);
            if (thick) {
                const side = intensity * 0.42;
                self.addPixel(ix + 1, iy, c.r, c.g, c.b, side);
                self.addPixel(ix - 1, iy, c.r, c.g, c.b, side);
                self.addPixel(ix, iy + 1, c.r, c.g, c.b, side);
                self.addPixel(ix, iy - 1, c.r, c.g, c.b, side);
            }
            px += sx;
            py += sy;
        }
    }

    fn drawLineBlended(self: *Framebuffer, x0: f32, y0: f32, x1: f32, y1: f32, c: Rgb, alpha: f32) void {
        if (alpha <= 0.01) return;
        const dx = x1 - x0;
        const dy = y1 - y0;
        const steps_f = @max(@abs(dx), @abs(dy));
        if (steps_f < 0.5) return;
        const steps: usize = @min(2048, @as(usize, @intFromFloat(@ceil(steps_f))));
        const sx = dx / @as(f32, @floatFromInt(steps));
        const sy = dy / @as(f32, @floatFromInt(steps));
        var px = x0;
        var py = y0;
        for (0..steps + 1) |_| {
            self.blendPixel(@intFromFloat(@round(px)), @intFromFloat(@round(py)), c.r, c.g, c.b, alpha);
            px += sx;
            py += sy;
        }
    }

    fn fillTriangleBlended(self: *Framebuffer, p0: [2]f32, p1: [2]f32, p2: [2]f32, c: Rgb, alpha: f32) void {
        if (alpha <= 0.005) return;
        const area = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0]);
        if (@abs(area) < 0.25) return;

        // Ensure consistent positive signed area for edge tests
        const a = p0;
        var b = p1;
        var cc = p2;
        if (area < 0.0) {
            const tmp = b;
            b = cc;
            cc = tmp;
        }

        const min_x = @max(0, @as(i32, @intFromFloat(@floor(@min(a[0], @min(b[0], cc[0]))))));
        const max_x = @min(@as(i32, @intCast(self.width)) - 1, @as(i32, @intFromFloat(@ceil(@max(a[0], @max(b[0], cc[0]))))));
        const min_y = @max(0, @as(i32, @intFromFloat(@floor(@min(a[1], @min(b[1], cc[1]))))));
        const max_y = @min(@as(i32, @intCast(self.height)) - 1, @as(i32, @intFromFloat(@ceil(@max(a[1], @max(b[1], cc[1]))))));
        if (min_x > max_x or min_y > max_y) return;

        const ab_x = b[0] - a[0];
        const ab_y = b[1] - a[1];
        const bc_x = cc[0] - b[0];
        const bc_y = cc[1] - b[1];
        const ca_x = a[0] - cc[0];
        const ca_y = a[1] - cc[1];

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const px = @as(f32, @floatFromInt(x)) + 0.5;
                const w0 = ab_x * (py - a[1]) - ab_y * (px - a[0]);
                const w1 = bc_x * (py - b[1]) - bc_y * (px - b[0]);
                const w2 = ca_x * (py - cc[1]) - ca_y * (px - cc[0]);
                if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) {
                    self.blendPixel(x, y, c.r, c.g, c.b, alpha);
                }
            }
        }
    }

    pub fn drawPolyhedronShell(
        self: *Framebuffer,
        cx: f32,
        cy: f32,
        radius: f32,
        c: Rgb,
        alpha_scale: f32,
        heat: f32,
        file_count: u32,
        cam_yaw: f32,
        cam_pitch: f32,
        elapsed: f32,
        dir_seed: u32,
    ) void {
        if (radius < 2.5 or alpha_scale <= 0.01) return;
        const r = @min(radius, @as(f32, @floatFromInt(@max(self.width, self.height))) * 0.65);
        const projected = poly.projectPolyhedron(
            file_count,
            cx,
            cy,
            r,
            c,
            alpha_scale,
            heat,
            cam_yaw,
            cam_pitch,
            elapsed,
            dir_seed,
        );

        for (projected.faces[0..projected.face_count]) |face| {
            self.fillTriangleBlended(face.p0, face.p1, face.p2, face.color, face.alpha);
        }

        const edge_col = Rgb{
            .r = @intCast(@min(255, @as(u16, c.r) + 55)),
            .g = @intCast(@min(255, @as(u16, c.g) + 55)),
            .b = @intCast(@min(255, @as(u16, c.b) + 55)),
        };
        for (projected.edges[0..projected.edge_count]) |edge| {
            self.drawLineBlended(edge.p0[0], edge.p0[1], edge.p1[0], edge.p1[1], edge_col, edge.alpha);
        }
    }

    pub fn drawLitSphere(self: *Framebuffer, cx: f32, cy: f32, radius: f32, c: Rgb, alpha: f32, glow: f32, bloom_enabled: bool) void {
        if (radius < 0.8 or alpha <= 0.01) return;
        const core_r = @min(radius, 96.0);
        const halo_r = if (bloom_enabled and glow > 0.02) core_r * (1.55 + glow * 1.15) else core_r;

        const min_x = @max(0, @as(i32, @intFromFloat(@floor(cx - halo_r - 1.0))));
        const max_x = @min(@as(i32, @intCast(self.width)) - 1, @as(i32, @intFromFloat(@ceil(cx + halo_r + 1.0))));
        const min_y = @max(0, @as(i32, @intFromFloat(@floor(cy - halo_r - 1.0))));
        const max_y = @min(@as(i32, @intCast(self.height)) - 1, @as(i32, @intFromFloat(@ceil(cy + halo_r + 1.0))));
        if (min_x > max_x or min_y > max_y) return;

        const inv_core = 1.0 / core_r;
        const inv_halo = 1.0 / @max(halo_r, 1.0);
        const cr: f32 = @floatFromInt(c.r);
        const cg: f32 = @floatFromInt(c.g);
        const cb: f32 = @floatFromInt(c.b);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - cy;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) + 0.5 - cx;
                const dist2_px = dx * dx + dy * dy;

                const nx = dx * inv_core;
                const ny = dy * inv_core;
                const d2 = nx * nx + ny * ny;

                if (d2 < 1.0) {
                    const nz = @sqrt(1.0 - d2);
                    const diff = @max(0.0, -0.48 * nx - 0.58 * ny + 0.66 * nz);
                    const h_dot = @max(0.0, -0.26 * nx - 0.34 * ny + 0.90 * nz);
                    const h2 = h_dot * h_dot;
                    const h4 = h2 * h2;
                    const spec = h4 * h4 * h4 * 0.72;
                    const rim = (1.0 - nz) * (1.0 - nz) * 0.35;

                    const shade = 0.28 + diff * 0.78 + glow * 0.32 + rim;
                    const edge_aa = std.math.clamp((1.0 - @sqrt(d2)) * core_r + 0.5, 0.0, 1.0);

                    const pr: u8 = @intFromFloat(@min(255.0, cr * shade + spec * 245.0));
                    const pg: u8 = @intFromFloat(@min(255.0, cg * shade + spec * 250.0));
                    const pb: u8 = @intFromFloat(@min(255.0, cb * shade + spec * 255.0));

                    self.blendPixel(x, y, pr, pg, pb, alpha * edge_aa);
                } else if (bloom_enabled and glow > 0.02) {
                    const hd = @sqrt(dist2_px) * inv_halo;
                    if (hd < 1.0) {
                        const falloff = (1.0 - hd) * (1.0 - hd) * glow * 0.38 * alpha;
                        self.addPixel(x, y, c.r, c.g, c.b, falloff);
                    }
                }
            }
        }
    }

    pub fn drawText(self: *Framebuffer, x0: i32, y0: i32, text: []const u8, c: Rgb, scale: i32, alpha: f32) void {
        if (scale <= 0 or alpha <= 0.01) return;
        var cx = x0;
        for (text) |ch| {
            if (cx >= @as(i32, @intCast(self.width))) break;
            if (cx + font.GLYPH_W * scale >= 0) {
                const rows = font.glyphRowBits(ch);
                for (rows, 0..) |bits, ry| {
                    var col: u3 = 0;
                    while (col < 5) : (col += 1) {
                        const mask: u8 = @as(u8, 0x10) >> col;
                        if ((bits & mask) != 0) {
                            const px0 = cx + @as(i32, col) * scale;
                            const py0 = y0 + @as(i32, @intCast(ry)) * scale;
                            var sy: i32 = 0;
                            while (sy < scale) : (sy += 1) {
                                var sx: i32 = 0;
                                while (sx < scale) : (sx += 1) {
                                    self.blendPixel(px0 + sx, py0 + sy, c.r, c.g, c.b, alpha);
                                }
                            }
                        }
                    }
                }
            }
            cx += font.ADVANCE_X * scale;
        }
    }

    fn projectBlended(
        sim: *const Simulation,
        p2: sim_mod.Vec2,
        p3: Vec3,
        wf: f32,
        hf: f32,
    ) struct { x: f32, y: f32, scale: f32, depth: f32, visible: bool } {
        const b = sim.blend_3d;
        const pr2 = sim.camera.project2D(p2, wf, hf);
        if (b <= 0.001) {
            return .{ .x = pr2.x, .y = pr2.y, .scale = pr2.scale, .depth = 500.0, .visible = true };
        }
        const pr3 = sim.camera.project3D(p3, wf, hf);
        if (!pr3.visible) {
            return .{ .x = pr2.x, .y = pr2.y, .scale = 0, .depth = pr3.depth, .visible = false };
        }
        if (b >= 0.999) {
            return .{ .x = pr3.x, .y = pr3.y, .scale = pr3.scale, .depth = pr3.depth, .visible = true };
        }
        return .{
            .x = pr2.x + (pr3.x - pr2.x) * b,
            .y = pr2.y + (pr3.y - pr2.y) * b,
            .scale = pr2.scale + (pr3.scale - pr2.scale) * b,
            .depth = 500.0 + (pr3.depth - 500.0) * b,
            .visible = true,
        };
    }

    pub fn renderSimulation(self: *Framebuffer, sim: *const Simulation) !void {
        self.clear();
        const wf: f32 = @floatFromInt(self.width);
        const hf: f32 = @floatFromInt(self.height);
        const b3d = sim.blend_3d;

        self.items_scratch.clearRetainingCapacity();

        for (sim.dirs.items, 0..) |d, idx| {
            if (idx > 0 and d.subtree_files == 0 and d.heat <= 0.02) continue;
            const cur_p = projectBlended(sim, d.pos2, d.pos3, wf, hf);
            if (!cur_p.visible) continue;

            const fog = std.math.clamp(780.0 / @max(180.0, cur_p.depth), 0.22, 1.15);

            if (d.parent) |p_idx| {
                const parent = sim.dirs.items[p_idx];
                const par_p = projectBlended(sim, parent.pos2, parent.pos3, wf, hf);
                if (par_p.visible) {
                    const branch_col = Rgb{
                        .r = @intCast((@as(u16, d.tint.r) + 50) / 2),
                        .g = @intCast((@as(u16, d.tint.g) + 95) / 2),
                        .b = @intCast((@as(u16, d.tint.b) + 145) / 2),
                    };
                    self.drawLineAdditive(
                        par_p.x,
                        par_p.y,
                        cur_p.x,
                        cur_p.y,
                        branch_col,
                        (0.24 + d.heat * 0.35) * fog,
                        d.depth <= 2,
                    );
                }
            }

            if (b3d > 0.04) {
                try self.items_scratch.append(self.gpa, .{
                    .kind = .dir_shell,
                    .index = idx,
                    .sx = cur_p.x,
                    .sy = cur_p.y,
                    .sr = @max(6.0, d.bubble_radius * cur_p.scale),
                    .depth = cur_p.depth,
                    .fog = fog,
                    .alpha = b3d * fog,
                    .heat = d.heat,
                    .color = d.tint,
                    .file_count = if (d.alive_files > 0) d.alive_files else d.subtree_files,
                });
            } else {
                self.drawLitSphere(cur_p.x, cur_p.y, @max(2.5, 4.0 * cur_p.scale), d.tint, 0.7, d.heat * 0.5, sim.enable_bloom);
            }
        }

        for (sim.files.items, 0..) |f, idx| {
            if (f.alpha <= 0.01) continue;
            const fp = projectBlended(sim, f.pos2, f.pos3, wf, hf);
            if (!fp.visible) continue;
            const fog = std.math.clamp(780.0 / @max(180.0, fp.depth), 0.25, 1.2);

            if (b3d < 0.65) {
                const d = sim.dirs.items[f.dir_idx];
                const dp = projectBlended(sim, d.pos2, d.pos3, wf, hf);
                if (dp.visible) {
                    self.drawLineAdditive(dp.x, dp.y, fp.x, fp.y, f.color, 0.14 * (1.0 - b3d) * f.alpha, false);
                }
            }

            try self.items_scratch.append(self.gpa, .{
                .kind = .file_orb,
                .index = idx,
                .sx = fp.x,
                .sy = fp.y,
                .sr = @max(1.8, f.radius * fp.scale),
                .depth = fp.depth,
                .fog = fog,
                .alpha = f.alpha * @min(1.0, fog),
                .heat = f.heat,
                .color = f.color,
            });
        }

        for (sim.authors.items, 0..) |a, idx| {
            if (a.energy <= 0.02) continue;
            const ap = projectBlended(sim, a.pos2, a.pos3, wf, hf);
            if (!ap.visible) continue;
            const fog = std.math.clamp(800.0 / @max(180.0, ap.depth), 0.3, 1.2);
            try self.items_scratch.append(self.gpa, .{
                .kind = .author_orb,
                .index = idx,
                .sx = ap.x,
                .sy = ap.y,
                .sr = @max(4.0, 8.5 * ap.scale),
                .depth = ap.depth,
                .fog = fog,
                .alpha = @min(1.0, a.energy * 1.4),
                .heat = a.energy,
                .color = a.color,
            });
        }

        for (sim.particles.items, 0..) |pt, idx| {
            const pp = projectBlended(sim, pt.pos2, pt.pos3, wf, hf);
            if (!pp.visible) continue;
            const life = std.math.clamp(pt.ttl / pt.max_ttl, 0.0, 1.0);
            try self.items_scratch.append(self.gpa, .{
                .kind = .particle,
                .index = idx,
                .sx = pp.x,
                .sy = pp.y,
                .sr = @max(1.2, pt.size * pp.scale),
                .depth = pp.depth,
                .fog = 1.0,
                .alpha = life,
                .heat = life,
                .color = pt.color,
            });
        }

        // Back-to-front painter sort so translucent foreground directory shells glaze over background clusters
        std.mem.sort(ProjectedItem, self.items_scratch.items, {}, struct {
            fn farther(_: void, a: ProjectedItem, b: ProjectedItem) bool {
                return a.depth > b.depth;
            }
        }.farther);

        for (sim.beams.items) |beam| {
            if (beam.author_idx >= sim.authors.items.len or beam.file_idx >= sim.files.items.len) continue;
            const a = sim.authors.items[beam.author_idx];
            const f = sim.files.items[beam.file_idx];
            const ap = projectBlended(sim, a.pos2, a.pos3, wf, hf);
            const fp = projectBlended(sim, f.pos2, f.pos3, wf, hf);
            if (!ap.visible or !fp.visible) continue;
            const life = std.math.clamp(beam.ttl / beam.max_ttl, 0.0, 1.0);
            self.drawLineAdditive(ap.x, ap.y, fp.x, fp.y, beam.color, life * 0.85, true);
        }

        for (self.items_scratch.items) |item| {
            switch (item.kind) {
                .dir_shell => self.drawPolyhedronShell(
                    item.sx,
                    item.sy,
                    item.sr,
                    item.color,
                    item.alpha,
                    item.heat,
                    item.file_count,
                    sim.camera.yaw,
                    sim.camera.pitch,
                    sim.phase_clock,
                    @intCast(item.index *% 37 +% 11),
                ),
                .file_orb => self.drawLitSphere(item.sx, item.sy, item.sr, item.color, item.alpha, item.heat * 0.9, sim.enable_bloom),
                .author_orb => self.drawLitSphere(item.sx, item.sy, item.sr, item.color, item.alpha, 0.55 + item.heat * 0.45, sim.enable_bloom),
                .particle => self.addPixel(@intFromFloat(item.sx), @intFromFloat(item.sy), item.color.r, item.color.g, item.color.b, item.alpha),
            }
        }

        if (sim.show_labels) {
            const label_scale: i32 = if (self.width >= 1100) 2 else 1;
            var dir_labels_drawn: usize = 0;
            for (sim.dirs.items, 0..) |d, idx| {
                if (dir_labels_drawn >= 22) break;
                if (idx > 0 and d.subtree_files < 2 and d.heat < 0.25) continue;
                if (d.depth > 2 and d.heat < 0.25) continue;
                const dp = projectBlended(sim, d.pos2, d.pos3, wf, hf);
                if (!dp.visible) continue;
                const tw = font.textWidth(d.name, label_scale);
                const lx: i32 = @as(i32, @intFromFloat(dp.x)) - @divTrunc(tw, 2);
                const ly: i32 = @as(i32, @intFromFloat(dp.y - @max(8.0, d.bubble_radius * dp.scale) - @as(f32, @floatFromInt(10 * label_scale))));
                self.drawText(lx + 1, ly + 1, d.name, .{ .r = 0, .g = 0, .b = 0 }, label_scale, 0.65);
                self.drawText(lx, ly, d.name, .{ .r = 210, .g = 228, .b = 250 }, label_scale, 0.82);
                dir_labels_drawn += 1;
            }

            for (sim.authors.items) |a| {
                if (a.energy < 0.18) continue;
                const ap = projectBlended(sim, a.pos2, a.pos3, wf, hf);
                if (!ap.visible) continue;
                const lx: i32 = @as(i32, @intFromFloat(ap.x + 8.0));
                const ly: i32 = @as(i32, @intFromFloat(ap.y - 4.0));
                self.drawText(lx + 1, ly + 1, a.name, .{ .r = 0, .g = 0, .b = 0 }, label_scale, 0.75);
                self.drawText(lx, ly, a.name, a.color, label_scale, @min(1.0, a.energy * 1.5));
            }
        }

        self.drawHud(sim);
    }

    fn drawHud(self: *Framebuffer, sim: *const Simulation) void {
        const w_i: i32 = @intCast(self.width);
        const h_i: i32 = @intCast(self.height);
        const scale: i32 = if (self.width >= 1200) 2 else 1;
        const bar_h: i32 = if (scale == 2) 28 else 17;

        self.fillRectAlpha(0, 0, w_i, bar_h, .{ .r = 6, .g = 10, .b = 18 }, 0.78);
        self.fillRectAlpha(0, h_i - bar_h - 4, w_i, bar_h + 4, .{ .r = 6, .g = 10, .b = 18 }, 0.78);

        var date_buf: [20]u8 = undefined;
        const date_str = sim_mod.formatTimestampUtc(sim.sim_time, &date_buf);

        var top_left_buf: [256]u8 = undefined;
        const top_left = std.fmt.bufPrint(&top_left_buf, "[{s}] {s}   {s}   {d} files  {d} dirs  {d} authors", .{
            sim.vcs_kind.badge(),
            sim.repo_name,
            date_str,
            sim.active_file_count,
            sim.dirs.items.len,
            sim.authors.items.len,
        }) catch sim.repo_name;

        const pad_y: i32 = if (scale == 2) 7 else 4;
        self.drawText(10, pad_y, top_left, .{ .r = 226, .g = 236, .b = 248 }, scale, 0.95);

        var top_right_buf: [128]u8 = undefined;
        const state_str = if (sim.paused) "PAUSED" else if (sim.streaming_mode) "STREAM" else if (sim.finished) "DONE" else "PLAY";
        const top_right = std.fmt.bufPrint(&top_right_buf, "{s}  {s}  {d:.2}s/d", .{
            sim.view_mode.label(),
            state_str,
            sim.seconds_per_day,
        }) catch sim.view_mode.label();

        const tr_w = font.textWidth(top_right, scale);
        if (w_i - tr_w - 12 > font.textWidth(top_left, scale) + 20) {
            self.drawText(w_i - tr_w - 10, pad_y, top_right, .{ .r = 96, .g = 205, .b = 255 }, scale, 0.95);
        }

        const span = sim.end_time - sim.start_time;
        const progress: f32 = if (span > 0.001)
            @floatCast(std.math.clamp((sim.sim_time - sim.start_time) / span, 0.0, 1.0))
        else
            1.0;
        const prog_px: i32 = @intFromFloat(@as(f32, @floatFromInt(w_i)) * progress);
        self.fillRectAlpha(0, h_i - bar_h - 4, w_i, 2, .{ .r = 35, .g = 52, .b = 78 }, 0.9);
        self.fillRectAlpha(0, h_i - bar_h - 4, prog_px, 2, .{ .r = 56, .g = 189, .b = 248 }, 0.95);

        var bot_buf: [256]u8 = undefined;
        const bot_text = if (sim.last_commit_hash.len > 0 or sim.last_commit_msg.len > 0)
            std.fmt.bufPrint(&bot_buf, "{s} {s}: {s}", .{
                sim.last_commit_hash,
                sim.last_author,
                sim.last_commit_msg,
            }) catch ""
        else
            std.fmt.bufPrint(&bot_buf, "Space:Pause  Tab:2D/3D  +/-:Speed  Arrows/Drag:Orbit  O:AutoOrbit  Q:Quit", .{}) catch "";

        const max_chars: usize = @intCast(@max(8, @divTrunc(w_i - 20, font.ADVANCE_X * scale)));
        const clipped_bot = if (bot_text.len > max_chars) bot_text[0..max_chars] else bot_text;
        self.drawText(10, h_i - bar_h + pad_y - 1, clipped_bot, .{ .r = 175, .g = 194, .b = 218 }, scale, 0.92);
    }

    // WL_SHM_FORMAT_XRGB8888 expects little-endian 0xFFRRGGBB
    pub fn copyToXrgb8888(self: *const Framebuffer, dst_u32: []u32) void {
        const count = @min(dst_u32.len, @as(usize, self.width) * @as(usize, self.height));
        var src_idx: usize = 0;
        for (0..count) |i| {
            const r: u32 = self.rgb[src_idx + 0];
            const g: u32 = self.rgb[src_idx + 1];
            const b: u32 = self.rgb[src_idx + 2];
            dst_u32[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
            src_idx += 3;
        }
    }

    pub fn writePpmFrame(self: *const Framebuffer, writer: *std.Io.Writer) !void {
        try writer.print("P6\n{d} {d}\n255\n", .{ self.width, self.height });
        try writer.writeAll(self.rgb);
    }
};

test "framebuffer renders 3D bubble scene and exports valid P6 PPM frame" {
    var sim = try Simulation.init(std.testing.allocator, "zource", .git, .bubbles_3d);
    defer sim.deinit();

    try sim.applyEvent(.{
        .timestamp = 1700000000,
        .author = "Christopher",
        .action = .add,
        .path = "src/main.zig",
        .commit_hash = "deadbee",
        .commit_msg = "Initial 3D sphere test",
    }, true);
    try sim.step(0.016);

    var fb = try Framebuffer.init(std.testing.allocator, 160, 100);
    defer fb.deinit();
    try fb.renderSimulation(&sim);

    var ppm_buf: [160 * 100 * 3 + 64]u8 = undefined;
    var fixed_writer = std.Io.Writer.fixed(&ppm_buf);
    try fb.writePpmFrame(&fixed_writer);

    const written = fixed_writer.buffered();
    try std.testing.expect(std.mem.startsWith(u8, written, "P6\n160 100\n255\n"));
    try std.testing.expectEqual(@as(usize, 15 + 160 * 100 * 3), written.len);
}
