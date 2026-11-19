const std = @import("std");
const vcs = @import("vcs.zig");
const sim_mod = @import("sim.zig");
const raster = @import("raster.zig");
const font = @import("font.zig");
const poly = @import("polyhedron.zig");
const terminal = @import("terminal.zig");
const Allocator = std.mem.Allocator;
const Simulation = sim_mod.Simulation;
const InputEvent = terminal.InputEvent;
const Rgb = vcs.Rgb;

const WlProxy = opaque {};
const WlDisplay = opaque {};
const WlEglWindow = opaque {};

const WlMessage = extern struct {
    name: [*:0]const u8,
    signature: [*:0]const u8,
    types: [*]?*const WlInterface,
};

const WlInterface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?[*]const WlMessage,
    event_count: c_int,
    events: ?[*]const WlMessage,
};

const WlArray = extern struct {
    size: usize,
    alloc: usize,
    data: ?*anyopaque,
};

const WL_MARSHAL_FLAG_DESTROY: u32 = 1 << 0;

// Mutable xdg-shell type table patched at runtime with libwayland's wl_surface_interface / wl_seat_interface / wl_output_interface
var xdg_shell_types: [26]?*const WlInterface = @splat(null);

const xdg_wm_base_requests = [_]WlMessage{
    .{ .name = "destroy", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "create_positioner", .signature = "n", .types = @ptrCast(&xdg_shell_types[4]) },
    .{ .name = "get_xdg_surface", .signature = "no", .types = @ptrCast(&xdg_shell_types[5]) },
    .{ .name = "pong", .signature = "u", .types = @ptrCast(&xdg_shell_types[0]) },
};
const xdg_wm_base_events = [_]WlMessage{
    .{ .name = "ping", .signature = "u", .types = @ptrCast(&xdg_shell_types[0]) },
};
var xdg_wm_base_interface = WlInterface{
    .name = "xdg_wm_base",
    .version = 7,
    .method_count = 4,
    .methods = &xdg_wm_base_requests,
    .event_count = 1,
    .events = &xdg_wm_base_events,
};

const xdg_positioner_interface = WlInterface{
    .name = "xdg_positioner",
    .version = 7,
    .method_count = 0,
    .methods = null,
    .event_count = 0,
    .events = null,
};

const xdg_popup_interface = WlInterface{
    .name = "xdg_popup",
    .version = 7,
    .method_count = 0,
    .methods = null,
    .event_count = 0,
    .events = null,
};

const xdg_surface_requests = [_]WlMessage{
    .{ .name = "destroy", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "get_toplevel", .signature = "n", .types = @ptrCast(&xdg_shell_types[7]) },
    .{ .name = "get_popup", .signature = "n?oo", .types = @ptrCast(&xdg_shell_types[8]) },
    .{ .name = "set_window_geometry", .signature = "iiii", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "ack_configure", .signature = "u", .types = @ptrCast(&xdg_shell_types[0]) },
};
const xdg_surface_events = [_]WlMessage{
    .{ .name = "configure", .signature = "u", .types = @ptrCast(&xdg_shell_types[0]) },
};
var xdg_surface_interface = WlInterface{
    .name = "xdg_surface",
    .version = 7,
    .method_count = 5,
    .methods = &xdg_surface_requests,
    .event_count = 1,
    .events = &xdg_surface_events,
};

const xdg_toplevel_requests = [_]WlMessage{
    .{ .name = "destroy", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_parent", .signature = "?o", .types = @ptrCast(&xdg_shell_types[11]) },
    .{ .name = "set_title", .signature = "s", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_app_id", .signature = "s", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "show_window_menu", .signature = "ouii", .types = @ptrCast(&xdg_shell_types[12]) },
    .{ .name = "move", .signature = "ou", .types = @ptrCast(&xdg_shell_types[16]) },
    .{ .name = "resize", .signature = "ouu", .types = @ptrCast(&xdg_shell_types[18]) },
    .{ .name = "set_max_size", .signature = "ii", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_min_size", .signature = "ii", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_maximized", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "unset_maximized", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_fullscreen", .signature = "?o", .types = @ptrCast(&xdg_shell_types[21]) },
    .{ .name = "unset_fullscreen", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "set_minimized", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
};
const xdg_toplevel_events = [_]WlMessage{
    .{ .name = "configure", .signature = "iia", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "close", .signature = "", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "configure_bounds", .signature = "4ii", .types = @ptrCast(&xdg_shell_types[0]) },
    .{ .name = "wm_capabilities", .signature = "5a", .types = @ptrCast(&xdg_shell_types[0]) },
};
var xdg_toplevel_interface = WlInterface{
    .name = "xdg_toplevel",
    .version = 7,
    .method_count = 14,
    .methods = &xdg_toplevel_requests,
    .event_count = 4,
    .events = &xdg_toplevel_events,
};

const WlClientSyms = struct {
    lib: std.DynLib,
    display_connect: *const fn (?[*:0]const u8) callconv(.c) ?*WlDisplay,
    display_disconnect: *const fn (*WlDisplay) callconv(.c) void,
    display_dispatch_pending: *const fn (*WlDisplay) callconv(.c) c_int,
    display_flush: *const fn (*WlDisplay) callconv(.c) c_int,
    display_roundtrip: *const fn (*WlDisplay) callconv(.c) c_int,
    display_get_fd: *const fn (*WlDisplay) callconv(.c) c_int,
    display_read_events: *const fn (*WlDisplay) callconv(.c) c_int,
    display_prepare_read: *const fn (*WlDisplay) callconv(.c) c_int,
    display_cancel_read: *const fn (*WlDisplay) callconv(.c) void,
    proxy_marshal_flags: *const fn (?*WlProxy, u32, ?*const WlInterface, u32, u32, ...) callconv(.c) ?*WlProxy,
    proxy_add_listener: *const fn (*WlProxy, *const anyopaque, ?*anyopaque) callconv(.c) c_int,
    proxy_get_version: *const fn (*WlProxy) callconv(.c) u32,
    proxy_destroy: *const fn (*WlProxy) callconv(.c) void,

    registry_interface: *const WlInterface,
    compositor_interface: *const WlInterface,
    surface_interface: *const WlInterface,
    shm_interface: *const WlInterface,
    shm_pool_interface: *const WlInterface,
    buffer_interface: *const WlInterface,
    seat_interface: *const WlInterface,
    pointer_interface: *const WlInterface,
    keyboard_interface: *const WlInterface,
    output_interface: *const WlInterface,
};

const EGLDisplay = ?*anyopaque;
const EGLConfig = ?*anyopaque;
const EGLContext = ?*anyopaque;
const EGLSurface = ?*anyopaque;
const GLuint = u32;
const GLint = i32;
const GLenum = u32;
const GLsizei = i32;
const GLfloat = f32;
const GLboolean = u8;

const EGL_DEFAULT_DISPLAY: ?*anyopaque = null;
const EGL_OPENGL_ES_API: u32 = 0x30A0;
const EGL_RED_SIZE: i32 = 0x3024;
const EGL_GREEN_SIZE: i32 = 0x3023;
const EGL_BLUE_SIZE: i32 = 0x3022;
const EGL_ALPHA_SIZE: i32 = 0x3021;
const EGL_RENDERABLE_TYPE: i32 = 0x3040;
const EGL_OPENGL_ES2_BIT: i32 = 0x0004;
const EGL_NONE: i32 = 0x3038;
const EGL_CONTEXT_CLIENT_VERSION: i32 = 0x3098;

const GL_COLOR_BUFFER_BIT: GLenum = 0x00004000;
const GL_BLEND: GLenum = 0x0BE2;
const GL_SRC_ALPHA: GLenum = 0x0302;
const GL_ONE_MINUS_SRC_ALPHA: GLenum = 0x0303;
const GL_ONE: GLenum = 0x0001;
const GL_TRIANGLES: GLenum = 0x0004;
const GL_LINES: GLenum = 0x0001;
const GL_FLOAT: GLenum = 0x1406;
const GL_VERTEX_SHADER: GLenum = 0x8B31;
const GL_FRAGMENT_SHADER: GLenum = 0x8B30;
const GL_COMPILE_STATUS: GLenum = 0x8B81;
const GL_LINK_STATUS: GLenum = 0x8B82;
const GL_ARRAY_BUFFER: GLenum = 0x8892;
const GL_DYNAMIC_DRAW: GLenum = 0x88E8;
const GL_TEXTURE_2D: GLenum = 0x0DE1;
const GL_TEXTURE0: GLenum = 0x84C0;
const GL_RGBA: GLenum = 0x1908;
const GL_UNSIGNED_BYTE: GLenum = 0x1401;
const GL_TEXTURE_MIN_FILTER: GLenum = 0x2801;
const GL_TEXTURE_MAG_FILTER: GLenum = 0x2800;
const GL_TEXTURE_WRAP_S: GLenum = 0x2802;
const GL_TEXTURE_WRAP_T: GLenum = 0x2803;
const GL_NEAREST: GLint = 0x2600;
const GL_CLAMP_TO_EDGE: GLint = 0x812F;

const SphereVert = extern struct {
    cx: f32,
    cy: f32,
    radius: f32,
    uv_x: f32,
    uv_y: f32,
    r: f32,
    g: f32,
    b: f32,
    alpha: f32,
    kind: f32, // 0.0 = solid/glowing orb, 1.0 = translucent glass directory shell
    heat: f32,
};

const LineVert = extern struct {
    x: f32,
    y: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const GpuBackend = struct {
    wl_egl_lib: std.DynLib,
    egl_lib: std.DynLib,
    gl_lib: std.DynLib,

    wl_egl_window_create: *const fn (*WlProxy, c_int, c_int) callconv(.c) ?*WlEglWindow,
    wl_egl_window_destroy: *const fn (*WlEglWindow) callconv(.c) void,
    wl_egl_window_resize: *const fn (*WlEglWindow, c_int, c_int, c_int, c_int) callconv(.c) void,

    eglGetDisplay: *const fn (?*anyopaque) callconv(.c) EGLDisplay,
    eglInitialize: *const fn (EGLDisplay, ?*GLint, ?*GLint) callconv(.c) u32,
    eglBindAPI: *const fn (u32) callconv(.c) u32,
    eglChooseConfig: *const fn (EGLDisplay, [*]const i32, [*]EGLConfig, i32, *i32) callconv(.c) u32,
    eglCreateContext: *const fn (EGLDisplay, EGLConfig, EGLContext, [*]const i32) callconv(.c) EGLContext,
    eglCreateWindowSurface: *const fn (EGLDisplay, EGLConfig, ?*anyopaque, ?[*]const i32) callconv(.c) EGLSurface,
    eglMakeCurrent: *const fn (EGLDisplay, EGLSurface, EGLSurface, EGLContext) callconv(.c) u32,
    eglSwapInterval: *const fn (EGLDisplay, i32) callconv(.c) u32,
    eglSwapBuffers: *const fn (EGLDisplay, EGLSurface) callconv(.c) u32,
    eglDestroySurface: *const fn (EGLDisplay, EGLSurface) callconv(.c) u32,
    eglDestroyContext: *const fn (EGLDisplay, EGLContext) callconv(.c) u32,
    eglTerminate: *const fn (EGLDisplay) callconv(.c) u32,

    glViewport: *const fn (GLint, GLint, GLsizei, GLsizei) callconv(.c) void,
    glClearColor: *const fn (GLfloat, GLfloat, GLfloat, GLfloat) callconv(.c) void,
    glClear: *const fn (GLenum) callconv(.c) void,
    glEnable: *const fn (GLenum) callconv(.c) void,
    glBlendFunc: *const fn (GLenum, GLenum) callconv(.c) void,
    glCreateShader: *const fn (GLenum) callconv(.c) GLuint,
    glShaderSource: *const fn (GLuint, GLsizei, [*]const [*:0]const u8, ?[*]const GLint) callconv(.c) void,
    glCompileShader: *const fn (GLuint) callconv(.c) void,
    glGetShaderiv: *const fn (GLuint, GLenum, *GLint) callconv(.c) void,
    glCreateProgram: *const fn () callconv(.c) GLuint,
    glAttachShader: *const fn (GLuint, GLuint) callconv(.c) void,
    glLinkProgram: *const fn (GLuint) callconv(.c) void,
    glGetProgramiv: *const fn (GLuint, GLenum, *GLint) callconv(.c) void,
    glUseProgram: *const fn (GLuint) callconv(.c) void,
    glGetAttribLocation: *const fn (GLuint, [*:0]const u8) callconv(.c) GLint,
    glGetUniformLocation: *const fn (GLuint, [*:0]const u8) callconv(.c) GLint,
    glUniform2f: *const fn (GLint, GLfloat, GLfloat) callconv(.c) void,
    glUniform1i: *const fn (GLint, GLint) callconv(.c) void,
    glGenBuffers: *const fn (GLsizei, [*]GLuint) callconv(.c) void,
    glBindBuffer: *const fn (GLenum, GLuint) callconv(.c) void,
    glBufferData: *const fn (GLenum, isize, ?*const anyopaque, GLenum) callconv(.c) void,
    glEnableVertexAttribArray: *const fn (GLuint) callconv(.c) void,
    glDisableVertexAttribArray: *const fn (GLuint) callconv(.c) void,
    glVertexAttribPointer: *const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.c) void,
    glDrawArrays: *const fn (GLenum, GLint, GLsizei) callconv(.c) void,
    glGenTextures: *const fn (GLsizei, [*]GLuint) callconv(.c) void,
    glBindTexture: *const fn (GLenum, GLuint) callconv(.c) void,
    glActiveTexture: *const fn (GLenum) callconv(.c) void,
    glTexParameteri: *const fn (GLenum, GLenum, GLint) callconv(.c) void,
    glTexImage2D: *const fn (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, ?*const anyopaque) callconv(.c) void,

    egl_win: *WlEglWindow,
    egl_dpy: EGLDisplay,
    egl_ctx: EGLContext,
    egl_surf: EGLSurface,

    bg_prog: GLuint = 0,
    line_prog: GLuint = 0,
    sphere_prog: GLuint = 0,
    hud_prog: GLuint = 0,
    vbo: GLuint = 0,
    hud_tex: GLuint = 0,

    sphere_verts: std.ArrayList(SphereVert) = .empty,
    line_verts: std.ArrayList(LineVert) = .empty,
    poly_tri_verts: std.ArrayList(LineVert) = .empty,
    poly_edge_verts: std.ArrayList(LineVert) = .empty,
    hud_rgba: []u8 = &.{},
    hud_w: u32 = 0,
    hud_h: u32 = 0,
};

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};
const POLLIN: c_short = 0x0001;
extern "c" fn poll(fds: [*]PollFd, nfds: c_ulong, timeout: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn ftruncate(fd: c_int, length: i64) c_int;
extern "c" fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: i64) ?*anyopaque;
extern "c" fn munmap(addr: *anyopaque, length: usize) c_int;

const PROT_READ: c_int = 1;
const PROT_WRITE: c_int = 2;
const MAP_SHARED: c_int = 1;

const RegistryListener = extern struct {
    global: *const fn (?*anyopaque, *WlProxy, u32, [*:0]const u8, u32) callconv(.c) void,
    global_remove: *const fn (?*anyopaque, *WlProxy, u32) callconv(.c) void,
};

const XdgWmBaseListener = extern struct {
    ping: *const fn (?*anyopaque, *WlProxy, u32) callconv(.c) void,
};

const XdgSurfaceListener = extern struct {
    configure: *const fn (?*anyopaque, *WlProxy, u32) callconv(.c) void,
};

const XdgToplevelListener = extern struct {
    configure: *const fn (?*anyopaque, *WlProxy, i32, i32, *WlArray) callconv(.c) void,
    close: *const fn (?*anyopaque, *WlProxy) callconv(.c) void,
    configure_bounds: *const fn (?*anyopaque, *WlProxy, i32, i32) callconv(.c) void,
    wm_capabilities: *const fn (?*anyopaque, *WlProxy, *WlArray) callconv(.c) void,
};

const SeatListener = extern struct {
    capabilities: *const fn (?*anyopaque, *WlProxy, u32) callconv(.c) void,
};

const PointerListener = extern struct {
    enter: *const fn (?*anyopaque, *WlProxy, u32, ?*WlProxy, i32, i32) callconv(.c) void,
    leave: *const fn (?*anyopaque, *WlProxy, u32, ?*WlProxy) callconv(.c) void,
    motion: *const fn (?*anyopaque, *WlProxy, u32, i32, i32) callconv(.c) void,
    button: *const fn (?*anyopaque, *WlProxy, u32, u32, u32, u32) callconv(.c) void,
    axis: *const fn (?*anyopaque, *WlProxy, u32, u32, i32) callconv(.c) void,
};

const KeyboardListener = extern struct {
    keymap: *const fn (?*anyopaque, *WlProxy, u32, i32, u32) callconv(.c) void,
    enter: *const fn (?*anyopaque, *WlProxy, u32, ?*WlProxy, *WlArray) callconv(.c) void,
    leave: *const fn (?*anyopaque, *WlProxy, u32, ?*WlProxy) callconv(.c) void,
    key: *const fn (?*anyopaque, *WlProxy, u32, u32, u32, u32) callconv(.c) void,
    modifiers: *const fn (?*anyopaque, *WlProxy, u32, u32, u32, u32, u32) callconv(.c) void,
};

pub const WaylandWindow = struct {
    gpa: Allocator,
    wl: WlClientSyms,
    display: *WlDisplay,
    registry: *WlProxy = undefined,
    compositor: ?*WlProxy = null,
    shm: ?*WlProxy = null,
    xdg_wm_base: ?*WlProxy = null,
    seat: ?*WlProxy = null,
    pointer: ?*WlProxy = null,
    keyboard: ?*WlProxy = null,

    surface: *WlProxy = undefined,
    xdg_surface: *WlProxy = undefined,
    xdg_toplevel: *WlProxy = undefined,

    width: u32,
    height: u32,
    pending_w: u32 = 0,
    pending_h: u32 = 0,
    configured: bool = false,
    closed: bool = false,
    resized: bool = false,

    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    dragging_left: bool = false,
    dragging_right: bool = false,
    events_queue: std.ArrayList(InputEvent) = .empty,

    gpu: ?GpuBackend = null,

    shm_fd: c_int = -1,
    shm_map: ?[*]u32 = null,
    shm_bytes: usize = 0,
    shm_pool: ?*WlProxy = null,
    shm_buffer: ?*WlProxy = null,

    pub fn init(gpa: Allocator, width: u32, height: u32, title: []const u8) !*WaylandWindow {
        var lib = std.DynLib.open("libwayland-client.so.0") catch
            std.DynLib.open("libwayland-client.so") catch
            return error.WaylandClientLibUnavailable;
        errdefer lib.close();

        const syms = WlClientSyms{
            .lib = lib,
            .display_connect = lib.lookup(*const fn (?[*:0]const u8) callconv(.c) ?*WlDisplay, "wl_display_connect") orelse return error.MissingWaylandSymbol,
            .display_disconnect = lib.lookup(*const fn (*WlDisplay) callconv(.c) void, "wl_display_disconnect") orelse return error.MissingWaylandSymbol,
            .display_dispatch_pending = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_dispatch_pending") orelse return error.MissingWaylandSymbol,
            .display_flush = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_flush") orelse return error.MissingWaylandSymbol,
            .display_roundtrip = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_roundtrip") orelse return error.MissingWaylandSymbol,
            .display_get_fd = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_get_fd") orelse return error.MissingWaylandSymbol,
            .display_read_events = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_read_events") orelse return error.MissingWaylandSymbol,
            .display_prepare_read = lib.lookup(*const fn (*WlDisplay) callconv(.c) c_int, "wl_display_prepare_read") orelse return error.MissingWaylandSymbol,
            .display_cancel_read = lib.lookup(*const fn (*WlDisplay) callconv(.c) void, "wl_display_cancel_read") orelse return error.MissingWaylandSymbol,
            .proxy_marshal_flags = lib.lookup(*const fn (?*WlProxy, u32, ?*const WlInterface, u32, u32, ...) callconv(.c) ?*WlProxy, "wl_proxy_marshal_flags") orelse return error.MissingWaylandSymbol,
            .proxy_add_listener = lib.lookup(*const fn (*WlProxy, *const anyopaque, ?*anyopaque) callconv(.c) c_int, "wl_proxy_add_listener") orelse return error.MissingWaylandSymbol,
            .proxy_get_version = lib.lookup(*const fn (*WlProxy) callconv(.c) u32, "wl_proxy_get_version") orelse return error.MissingWaylandSymbol,
            .proxy_destroy = lib.lookup(*const fn (*WlProxy) callconv(.c) void, "wl_proxy_destroy") orelse return error.MissingWaylandSymbol,
            .registry_interface = lib.lookup(*const WlInterface, "wl_registry_interface") orelse return error.MissingWaylandSymbol,
            .compositor_interface = lib.lookup(*const WlInterface, "wl_compositor_interface") orelse return error.MissingWaylandSymbol,
            .surface_interface = lib.lookup(*const WlInterface, "wl_surface_interface") orelse return error.MissingWaylandSymbol,
            .shm_interface = lib.lookup(*const WlInterface, "wl_shm_interface") orelse return error.MissingWaylandSymbol,
            .shm_pool_interface = lib.lookup(*const WlInterface, "wl_shm_pool_interface") orelse return error.MissingWaylandSymbol,
            .buffer_interface = lib.lookup(*const WlInterface, "wl_buffer_interface") orelse return error.MissingWaylandSymbol,
            .seat_interface = lib.lookup(*const WlInterface, "wl_seat_interface") orelse return error.MissingWaylandSymbol,
            .pointer_interface = lib.lookup(*const WlInterface, "wl_pointer_interface") orelse return error.MissingWaylandSymbol,
            .keyboard_interface = lib.lookup(*const WlInterface, "wl_keyboard_interface") orelse return error.MissingWaylandSymbol,
            .output_interface = lib.lookup(*const WlInterface, "wl_output_interface") orelse return error.MissingWaylandSymbol,
        };

        // Patch xdg-shell object interface pointers before marshaling any xdg requests
        xdg_shell_types[4] = &xdg_positioner_interface;
        xdg_shell_types[5] = &xdg_surface_interface;
        xdg_shell_types[6] = syms.surface_interface;
        xdg_shell_types[7] = &xdg_toplevel_interface;
        xdg_shell_types[8] = &xdg_popup_interface;
        xdg_shell_types[9] = &xdg_surface_interface;
        xdg_shell_types[10] = &xdg_positioner_interface;
        xdg_shell_types[11] = &xdg_toplevel_interface;
        xdg_shell_types[12] = syms.seat_interface;
        xdg_shell_types[16] = syms.seat_interface;
        xdg_shell_types[18] = syms.seat_interface;
        xdg_shell_types[21] = syms.output_interface;
        xdg_shell_types[22] = syms.seat_interface;
        xdg_shell_types[24] = &xdg_positioner_interface;

        const dpy = syms.display_connect(null) orelse return error.WaylandConnectFailed;
        errdefer syms.display_disconnect(dpy);

        var self = try gpa.create(WaylandWindow);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .wl = syms,
            .display = dpy,
            .width = @max(320, width),
            .height = @max(240, height),
        };

        const dpy_proxy: *WlProxy = @ptrCast(dpy);
        self.registry = self.wl.proxy_marshal_flags(dpy_proxy, 1, self.wl.registry_interface, 1, 0, @as(?*anyopaque, null)) orelse return error.WaylandRegistryFailed;
        _ = self.wl.proxy_add_listener(self.registry, &registry_listener, self);
        _ = self.wl.display_roundtrip(dpy);
        _ = self.wl.display_roundtrip(dpy);

        const comp = self.compositor orelse return error.MissingWaylandCompositor;
        const wm = self.xdg_wm_base orelse return error.MissingXdgWmBase;

        const comp_ver = self.wl.proxy_get_version(comp);
        self.surface = self.wl.proxy_marshal_flags(comp, 0, self.wl.surface_interface, comp_ver, 0, @as(?*anyopaque, null)) orelse return error.WaylandSurfaceFailed;

        const wm_ver = self.wl.proxy_get_version(wm);
        self.xdg_surface = self.wl.proxy_marshal_flags(wm, 2, &xdg_surface_interface, wm_ver, 0, @as(?*anyopaque, null), self.surface) orelse return error.XdgSurfaceFailed;
        _ = self.wl.proxy_add_listener(self.xdg_surface, &xdg_surface_listener, self);

        self.xdg_toplevel = self.wl.proxy_marshal_flags(self.xdg_surface, 1, &xdg_toplevel_interface, wm_ver, 0, @as(?*anyopaque, null)) orelse return error.XdgToplevelFailed;
        _ = self.wl.proxy_add_listener(self.xdg_toplevel, &xdg_toplevel_listener, self);

        var title_z: [192]u8 = undefined;
        const tlen = @min(title.len, title_z.len - 1);
        @memcpy(title_z[0..tlen], title[0..tlen]);
        title_z[tlen] = 0;
        _ = self.wl.proxy_marshal_flags(self.xdg_toplevel, 2, null, wm_ver, 0, @as([*:0]const u8, @ptrCast(&title_z)));
        _ = self.wl.proxy_marshal_flags(self.xdg_toplevel, 3, null, wm_ver, 0, @as([*:0]const u8, "zource"));

        // Empty initial commit triggers the compositor's first xdg_surface.configure
        _ = self.wl.proxy_marshal_flags(self.surface, 6, null, comp_ver, 0);
        while (!self.configured and !self.closed) {
            if (self.wl.display_roundtrip(dpy) < 0) break;
        }

        self.gpu = initGpuBackend(gpa, self.display, self.surface, self.width, self.height) catch null;
        if (self.gpu == null) {
            try self.recreateShmBuffer();
        }

        return self;
    }

    pub fn isGpuAccelerated(self: *const WaylandWindow) bool {
        return self.gpu != null;
    }

    pub fn deinit(self: *WaylandWindow) void {
        if (self.gpu) |*g| {
            deinitGpuBackend(self.gpa, g);
        }
        self.destroyShmBuffer();

        if (self.keyboard) |kb| self.wl.proxy_destroy(kb);
        if (self.pointer) |pt| self.wl.proxy_destroy(pt);
        if (self.seat) |st| self.wl.proxy_destroy(st);

        _ = self.wl.proxy_marshal_flags(self.xdg_toplevel, 0, null, self.wl.proxy_get_version(self.xdg_toplevel), WL_MARSHAL_FLAG_DESTROY);
        _ = self.wl.proxy_marshal_flags(self.xdg_surface, 0, null, self.wl.proxy_get_version(self.xdg_surface), WL_MARSHAL_FLAG_DESTROY);
        _ = self.wl.proxy_marshal_flags(self.surface, 0, null, self.wl.proxy_get_version(self.surface), WL_MARSHAL_FLAG_DESTROY);

        if (self.xdg_wm_base) |wm| self.wl.proxy_destroy(wm);
        if (self.shm) |sh| self.wl.proxy_destroy(sh);
        if (self.compositor) |cp| self.wl.proxy_destroy(cp);
        self.wl.proxy_destroy(self.registry);

        self.wl.display_disconnect(self.display);
        self.wl.lib.close();
        self.events_queue.deinit(self.gpa);
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    fn destroyShmBuffer(self: *WaylandWindow) void {
        if (self.shm_buffer) |b| {
            _ = self.wl.proxy_marshal_flags(b, 0, null, self.wl.proxy_get_version(b), WL_MARSHAL_FLAG_DESTROY);
            self.shm_buffer = null;
        }
        if (self.shm_pool) |p| {
            _ = self.wl.proxy_marshal_flags(p, 1, null, self.wl.proxy_get_version(p), WL_MARSHAL_FLAG_DESTROY);
            self.shm_pool = null;
        }
        if (self.shm_map) |ptr| {
            _ = munmap(@ptrCast(ptr), self.shm_bytes);
            self.shm_map = null;
        }
        if (self.shm_fd >= 0) {
            _ = close(self.shm_fd);
            self.shm_fd = -1;
        }
    }

    fn recreateShmBuffer(self: *WaylandWindow) !void {
        const shm = self.shm orelse return error.MissingWlShm;
        self.destroyShmBuffer();

        const stride: i32 = @intCast(self.width * 4);
        const total_bytes: usize = @as(usize, self.width) * @as(usize, self.height) * 4;
        const mfd_rc = std.os.linux.memfd_create("zource-shm", 1);
        if (std.os.linux.errno(mfd_rc) != .SUCCESS) return error.MemfdFailed;
        const fd: c_int = @intCast(mfd_rc);
        errdefer _ = close(fd);

        if (ftruncate(fd, @intCast(total_bytes)) != 0) return error.FtruncateFailed;
        const mapped = mmap(null, total_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0) orelse return error.MmapFailed;

        const shm_ver = self.wl.proxy_get_version(shm);
        const pool = self.wl.proxy_marshal_flags(shm, 0, self.wl.shm_pool_interface, shm_ver, 0, @as(?*anyopaque, null), fd, @as(i32, @intCast(total_bytes))) orelse return error.ShmPoolFailed;
        const buf = self.wl.proxy_marshal_flags(
            pool,
            0,
            self.wl.buffer_interface,
            shm_ver,
            0,
            @as(?*anyopaque, null),
            @as(i32, 0),
            @as(i32, @intCast(self.width)),
            @as(i32, @intCast(self.height)),
            stride,
            @as(u32, 1), // WL_SHM_FORMAT_XRGB8888
        ) orelse return error.ShmBufferFailed;

        self.shm_fd = fd;
        self.shm_map = @ptrCast(@alignCast(mapped));
        self.shm_bytes = total_bytes;
        self.shm_pool = pool;
        self.shm_buffer = buf;
    }

    pub fn pollInput(self: *WaylandWindow, out: *std.ArrayList(InputEvent)) !void {
        if (terminal.g_signal_quit.load(.acquire)) {
            self.closed = true;
            try out.append(self.gpa, .quit);
            return;
        }

        while (self.wl.display_prepare_read(self.display) != 0) {
            _ = self.wl.display_dispatch_pending(self.display);
        }
        _ = self.wl.display_flush(self.display);

        var pfd = [1]PollFd{.{ .fd = self.wl.display_get_fd(self.display), .events = POLLIN, .revents = 0 }};
        if (poll(&pfd, 1, 0) > 0 and (pfd[0].revents & POLLIN) != 0) {
            _ = self.wl.display_read_events(self.display);
        } else {
            self.wl.display_cancel_read(self.display);
        }
        _ = self.wl.display_dispatch_pending(self.display);

        if (self.closed) {
            try out.append(self.gpa, .quit);
        }

        if (self.resized) {
            self.resized = false;
            if (self.gpu) |*g| {
                g.wl_egl_window_resize(g.egl_win, @intCast(self.width), @intCast(self.height), 0, 0);
            } else {
                try self.recreateShmBuffer();
            }
        }

        try out.appendSlice(self.gpa, self.events_queue.items);
        self.events_queue.clearRetainingCapacity();
    }

    pub fn renderAndPresent(self: *WaylandWindow, sim: *const Simulation, fallback_fb: *raster.Framebuffer) !void {
        if (self.gpu) |*g| {
            try renderSceneGpu(self.gpa, g, self.width, self.height, sim);
            _ = g.eglSwapBuffers(g.egl_dpy, g.egl_surf);
            _ = self.wl.display_flush(self.display);
            return;
        }

        try fallback_fb.resize(self.width, self.height);
        try fallback_fb.renderSimulation(sim);
        if (self.shm_map) |dst_ptr| {
            const count = @as(usize, self.width) * @as(usize, self.height);
            fallback_fb.copyToXrgb8888(dst_ptr[0..count]);
        }
        if (self.shm_buffer) |buf| {
            const surf_ver = self.wl.proxy_get_version(self.surface);
            _ = self.wl.proxy_marshal_flags(self.surface, 1, null, surf_ver, 0, buf, @as(i32, 0), @as(i32, 0));
            _ = self.wl.proxy_marshal_flags(self.surface, 2, null, surf_ver, 0, @as(i32, 0), @as(i32, 0), @as(i32, @intCast(self.width)), @as(i32, @intCast(self.height)));
            _ = self.wl.proxy_marshal_flags(self.surface, 6, null, surf_ver, 0);
            _ = self.wl.display_flush(self.display);
        }
    }
};

const registry_listener = RegistryListener{
    .global = onRegistryGlobal,
    .global_remove = onRegistryRemove,
};

fn onRegistryGlobal(data: ?*anyopaque, registry: *WlProxy, name: u32, iface_z: [*:0]const u8, version: u32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    const iface = std.mem.span(iface_z);

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        const v: u32 = @min(version, 4);
        self.compositor = self.wl.proxy_marshal_flags(registry, 0, self.wl.compositor_interface, v, 0, name, self.wl.compositor_interface.name, v, @as(?*anyopaque, null));
    } else if (std.mem.eql(u8, iface, "wl_shm")) {
        self.shm = self.wl.proxy_marshal_flags(registry, 0, self.wl.shm_interface, 1, 0, name, self.wl.shm_interface.name, @as(u32, 1), @as(?*anyopaque, null));
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        const v: u32 = @min(version, 2);
        if (self.wl.proxy_marshal_flags(registry, 0, &xdg_wm_base_interface, v, 0, name, xdg_wm_base_interface.name, v, @as(?*anyopaque, null))) |wm| {
            self.xdg_wm_base = wm;
            _ = self.wl.proxy_add_listener(wm, &xdg_wm_base_listener, self);
        }
    } else if (std.mem.eql(u8, iface, "wl_seat")) {
        if (self.wl.proxy_marshal_flags(registry, 0, self.wl.seat_interface, 1, 0, name, self.wl.seat_interface.name, @as(u32, 1), @as(?*anyopaque, null))) |st| {
            self.seat = st;
            _ = self.wl.proxy_add_listener(st, &seat_listener, self);
        }
    }
}

fn onRegistryRemove(_: ?*anyopaque, _: *WlProxy, _: u32) callconv(.c) void {}

const xdg_wm_base_listener = XdgWmBaseListener{
    .ping = onWmBasePing,
};

fn onWmBasePing(data: ?*anyopaque, wm: *WlProxy, serial: u32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    _ = self.wl.proxy_marshal_flags(wm, 3, null, self.wl.proxy_get_version(wm), 0, serial);
}

const xdg_surface_listener = XdgSurfaceListener{
    .configure = onXdgSurfaceConfigure,
};

fn onXdgSurfaceConfigure(data: ?*anyopaque, xdg_surf: *WlProxy, serial: u32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    _ = self.wl.proxy_marshal_flags(xdg_surf, 4, null, self.wl.proxy_get_version(xdg_surf), 0, serial);
    if (self.pending_w >= 160 and self.pending_h >= 120) {
        if (self.pending_w != self.width or self.pending_h != self.height) {
            self.width = self.pending_w;
            self.height = self.pending_h;
            self.resized = true;
        }
    }
    self.configured = true;
}

const xdg_toplevel_listener = XdgToplevelListener{
    .configure = onToplevelConfigure,
    .close = onToplevelClose,
    .configure_bounds = onToplevelBounds,
    .wm_capabilities = onToplevelCaps,
};

fn onToplevelConfigure(data: ?*anyopaque, _: *WlProxy, w: i32, h: i32, _: *WlArray) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    if (w > 0 and h > 0) {
        self.pending_w = @intCast(w);
        self.pending_h = @intCast(h);
    }
}

fn onToplevelClose(data: ?*anyopaque, _: *WlProxy) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    self.closed = true;
}

fn onToplevelBounds(_: ?*anyopaque, _: *WlProxy, _: i32, _: i32) callconv(.c) void {}
fn onToplevelCaps(_: ?*anyopaque, _: *WlProxy, _: *WlArray) callconv(.c) void {}

const seat_listener = SeatListener{
    .capabilities = onSeatCapabilities,
};

fn onSeatCapabilities(data: ?*anyopaque, seat: *WlProxy, caps: u32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    if ((caps & 1) != 0 and self.pointer == null) {
        if (self.wl.proxy_marshal_flags(seat, 0, self.wl.pointer_interface, 1, 0, @as(?*anyopaque, null))) |pt| {
            self.pointer = pt;
            _ = self.wl.proxy_add_listener(pt, &pointer_listener, self);
        }
    }
    if ((caps & 2) != 0 and self.keyboard == null) {
        if (self.wl.proxy_marshal_flags(seat, 1, self.wl.keyboard_interface, 1, 0, @as(?*anyopaque, null))) |kb| {
            self.keyboard = kb;
            _ = self.wl.proxy_add_listener(kb, &keyboard_listener, self);
        }
    }
}

const pointer_listener = PointerListener{
    .enter = onPointerEnter,
    .leave = onPointerLeave,
    .motion = onPointerMotion,
    .button = onPointerButton,
    .axis = onPointerAxis,
};

fn onPointerEnter(data: ?*anyopaque, _: *WlProxy, _: u32, _: ?*WlProxy, sx: i32, sy: i32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    self.pointer_x = @as(f32, @floatFromInt(sx)) / 256.0;
    self.pointer_y = @as(f32, @floatFromInt(sy)) / 256.0;
}

fn onPointerLeave(data: ?*anyopaque, _: *WlProxy, _: u32, _: ?*WlProxy) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    self.dragging_left = false;
    self.dragging_right = false;
}

fn onPointerMotion(data: ?*anyopaque, _: *WlProxy, _: u32, sx: i32, sy: i32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    const nx = @as(f32, @floatFromInt(sx)) / 256.0;
    const ny = @as(f32, @floatFromInt(sy)) / 256.0;
    const dx = nx - self.pointer_x;
    const dy = ny - self.pointer_y;
    self.pointer_x = nx;
    self.pointer_y = ny;

    if (self.dragging_left) {
        self.events_queue.append(self.gpa, .{ .orbit = .{ .dyaw = dx * 0.0065, .dpitch = dy * 0.0065 } }) catch {};
    } else if (self.dragging_right) {
        self.events_queue.append(self.gpa, .{ .pan = .{ .dx = dx, .dy = dy } }) catch {};
    }
}

fn onPointerButton(data: ?*anyopaque, _: *WlProxy, _: u32, _: u32, button: u32, state: u32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    const pressed = state == 1;
    if (button == 0x110) self.dragging_left = pressed;
    if (button == 0x111 or button == 0x112) self.dragging_right = pressed;
}

fn onPointerAxis(data: ?*anyopaque, _: *WlProxy, _: u32, axis: u32, value: i32) callconv(.c) void {
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    if (axis == 0 and value != 0) {
        const factor: f32 = if (value < 0) 1.10 else (1.0 / 1.10);
        self.events_queue.append(self.gpa, .{ .zoom = factor }) catch {};
    }
}

const keyboard_listener = KeyboardListener{
    .keymap = onKeyboardKeymap,
    .enter = onKeyboardEnter,
    .leave = onKeyboardLeave,
    .key = onKeyboardKey,
    .modifiers = onKeyboardModifiers,
};

fn onKeyboardKeymap(_: ?*anyopaque, _: *WlProxy, _: u32, fd: i32, _: u32) callconv(.c) void {
    if (fd >= 0) _ = close(fd);
}

fn onKeyboardEnter(_: ?*anyopaque, _: *WlProxy, _: u32, _: ?*WlProxy, _: *WlArray) callconv(.c) void {}
fn onKeyboardLeave(_: ?*anyopaque, _: *WlProxy, _: u32, _: ?*WlProxy) callconv(.c) void {}
fn onKeyboardModifiers(_: ?*anyopaque, _: *WlProxy, _: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

fn onKeyboardKey(data: ?*anyopaque, _: *WlProxy, _: u32, _: u32, key: u32, state: u32) callconv(.c) void {
    if (state != 1) return; // press only
    const self: *WaylandWindow = @ptrCast(@alignCast(data.?));
    const ev: ?InputEvent = switch (key) {
        1, 16 => .quit, // ESC, Q
        57 => .toggle_pause, // SPACE
        15, 47 => .toggle_view_mode, // TAB, V
        3 => .set_2d, // 2
        4 => .set_3d, // 3
        24 => .toggle_auto_orbit, // O
        38 => .toggle_labels, // L
        48 => .toggle_bloom, // B
        13, 27 => .speed_up, // =, ]
        12, 26 => .speed_down, // -, [
        52 => .seek_forward, // .
        51 => .seek_backward, // ,
        19 => .restart, // R
        17, 103 => .{ .orbit = .{ .dyaw = 0, .dpitch = -0.08 } }, // W, UP
        31, 108 => .{ .orbit = .{ .dyaw = 0, .dpitch = 0.08 } }, // S, DOWN
        30, 105 => .{ .orbit = .{ .dyaw = -0.09, .dpitch = 0 } }, // A, LEFT
        32, 106 => .{ .orbit = .{ .dyaw = 0.09, .dpitch = 0 } }, // D, RIGHT
        44 => .{ .zoom = 1.12 }, // Z
        45 => .{ .zoom = 1.0 / 1.12 }, // X
        else => null,
    };
    if (ev) |e| {
        self.events_queue.append(self.gpa, e) catch {};
    }
}

const bg_vs_src: [*:0]const u8 =
    \\attribute vec2 a_pos;
    \\varying vec2 v_uv;
    \\void main() {
    \\  v_uv = a_pos;
    \\  gl_Position = vec4(a_pos, 0.0, 1.0);
    \\}
;

const bg_fs_src: [*:0]const u8 =
    \\precision mediump float;
    \\varying vec2 v_uv;
    \\void main() {
    \\  float d = clamp(length(v_uv) * 0.72, 0.0, 1.0);
    \\  float g = 1.0 - d * d;
    \\  vec3 col = vec3(5.0 + g * 9.0, 8.0 + g * 14.0, 15.0 + g * 26.0) / 255.0;
    \\  gl_FragColor = vec4(col, 1.0);
    \\}
;

const line_vs_src: [*:0]const u8 =
    \\attribute vec2 a_pos;
    \\attribute vec4 a_col;
    \\uniform vec2 u_res;
    \\varying vec4 v_col;
    \\void main() {
    \\  vec2 ndc = vec2((a_pos.x / u_res.x) * 2.0 - 1.0, 1.0 - (a_pos.y / u_res.y) * 2.0);
    \\  gl_Position = vec4(ndc, 0.0, 1.0);
    \\  v_col = a_col;
    \\}
;

const line_fs_src: [*:0]const u8 =
    \\precision mediump float;
    \\varying vec4 v_col;
    \\void main() {
    \\  gl_FragColor = vec4(v_col.rgb * v_col.a, v_col.a);
    \\}
;

const sphere_vs_src: [*:0]const u8 =
    \\attribute vec2 a_center;
    \\attribute float a_radius;
    \\attribute vec2 a_uv;
    \\attribute vec4 a_color;
    \\attribute vec2 a_meta;
    \\uniform vec2 u_res;
    \\varying vec2 v_uv;
    \\varying vec4 v_color;
    \\varying vec2 v_meta;
    \\varying float v_rad;
    \\void main() {
    \\  float extent = a_radius * (a_meta.x < 0.5 ? (1.6 + a_meta.y * 1.1) : 1.04);
    \\  vec2 px = a_center + a_uv * extent;
    \\  vec2 ndc = vec2((px.x / u_res.x) * 2.0 - 1.0, 1.0 - (px.y / u_res.y) * 2.0);
    \\  gl_Position = vec4(ndc, 0.0, 1.0);
    \\  v_uv = a_uv * (extent / max(a_radius, 0.5));
    \\  v_color = a_color;
    \\  v_meta = a_meta;
    \\  v_rad = a_radius;
    \\}
;

const sphere_fs_src: [*:0]const u8 =
    \\precision mediump float;
    \\varying vec2 v_uv;
    \\varying vec4 v_color;
    \\varying vec2 v_meta;
    \\varying float v_rad;
    \\void main() {
    \\  float d2 = dot(v_uv, v_uv);
    \\  float d = sqrt(d2);
    \\  if (v_meta.x > 0.5) {
    \\    if (d2 >= 1.0) discard;
    \\    float nz = sqrt(1.0 - d2);
    \\    float omz = 1.0 - nz;
    \\    float fresnel = omz * omz * omz;
    \\    float ldot = max(0.0, -0.45 * v_uv.x - 0.55 * v_uv.y + 0.70 * nz);
    \\    float spec = pow(ldot, 12.0) * 0.6;
    \\    float aa = clamp((1.0 - d) * v_rad, 0.0, 1.0);
    \\    float a = (0.04 + fresnel * (0.36 + v_meta.y * 0.25) + spec * 0.48) * v_color.a * aa;
    \\    vec3 rgb = v_color.rgb * (0.78 + fresnel * 0.52) + vec3(spec);
    \\    gl_FragColor = vec4(rgb, clamp(a, 0.0, 1.0));
    \\  } else {
    \\    if (d2 < 1.0) {
    \\      float nz = sqrt(1.0 - d2);
    \\      float diff = max(0.0, -0.48 * v_uv.x - 0.58 * v_uv.y + 0.66 * nz);
    \\      float hdot = max(0.0, -0.26 * v_uv.x - 0.34 * v_uv.y + 0.90 * nz);
    \\      float spec = pow(hdot, 16.0) * 0.78;
    \\      float rim = (1.0 - nz) * (1.0 - nz) * 0.35;
    \\      float shade = 0.28 + diff * 0.78 + v_meta.y * 0.34 + rim;
    \\      float aa = clamp((1.0 - d) * v_rad + 0.5, 0.0, 1.0);
    \\      vec3 rgb = clamp(v_color.rgb * shade + vec3(spec), 0.0, 1.0);
    \\      gl_FragColor = vec4(rgb, v_color.a * aa);
    \\    } else {
    \\      float halo_max = 1.6 + v_meta.y * 1.1;
    \\      if (d >= halo_max || v_meta.y <= 0.02) discard;
    \\      float t = 1.0 - (d / halo_max);
    \\      float ha = t * t * v_meta.y * 0.42 * v_color.a;
    \\      gl_FragColor = vec4(v_color.rgb, ha);
    \\    }
    \\  }
    \\}
;

const hud_vs_src: [*:0]const u8 =
    \\attribute vec2 a_pos;
    \\attribute vec2 a_uv;
    \\varying vec2 v_uv;
    \\void main() {
    \\  v_uv = a_uv;
    \\  gl_Position = vec4(a_pos, 0.0, 1.0);
    \\}
;

const hud_fs_src: [*:0]const u8 =
    \\precision mediump float;
    \\varying vec2 v_uv;
    \\uniform sampler2D u_tex;
    \\void main() {
    \\  gl_FragColor = texture2D(u_tex, v_uv);
    \\}
;

fn compileProgram(g: *const GpuBackend, vs: [*:0]const u8, fs: [*:0]const u8) !GLuint {
    const vsh = g.glCreateShader(GL_VERTEX_SHADER);
    const vs_arr = [_][*:0]const u8{vs};
    g.glShaderSource(vsh, 1, &vs_arr, null);
    g.glCompileShader(vsh);
    var ok: GLint = 0;
    g.glGetShaderiv(vsh, GL_COMPILE_STATUS, &ok);
    if (ok == 0) return error.ShaderCompileFailed;

    const fsh = g.glCreateShader(GL_FRAGMENT_SHADER);
    const fs_arr = [_][*:0]const u8{fs};
    g.glShaderSource(fsh, 1, &fs_arr, null);
    g.glCompileShader(fsh);
    g.glGetShaderiv(fsh, GL_COMPILE_STATUS, &ok);
    if (ok == 0) return error.ShaderCompileFailed;

    const prog = g.glCreateProgram();
    g.glAttachShader(prog, vsh);
    g.glAttachShader(prog, fsh);
    g.glLinkProgram(prog);
    g.glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (ok == 0) return error.ProgramLinkFailed;
    return prog;
}

fn initGpuBackend(gpa: Allocator, display: *WlDisplay, surface: *WlProxy, width: u32, height: u32) !GpuBackend {
    var wl_egl_lib = std.DynLib.open("libwayland-egl.so.1") catch
        std.DynLib.open("libwayland-egl.so") catch
        return error.NoWaylandEgl;
    errdefer wl_egl_lib.close();

    var egl_lib = std.DynLib.open("libEGL.so.1") catch
        std.DynLib.open("libEGL.so") catch
        return error.NoEgl;
    errdefer egl_lib.close();

    var gl_lib = std.DynLib.open("libGLESv2.so.2") catch
        std.DynLib.open("libGLESv2.so") catch
        return error.NoGles2;
    errdefer gl_lib.close();

    var g = GpuBackend{
        .wl_egl_lib = wl_egl_lib,
        .egl_lib = egl_lib,
        .gl_lib = gl_lib,
        .wl_egl_window_create = wl_egl_lib.lookup(*const fn (*WlProxy, c_int, c_int) callconv(.c) ?*WlEglWindow, "wl_egl_window_create") orelse return error.MissingSymbol,
        .wl_egl_window_destroy = wl_egl_lib.lookup(*const fn (*WlEglWindow) callconv(.c) void, "wl_egl_window_destroy") orelse return error.MissingSymbol,
        .wl_egl_window_resize = wl_egl_lib.lookup(*const fn (*WlEglWindow, c_int, c_int, c_int, c_int) callconv(.c) void, "wl_egl_window_resize") orelse return error.MissingSymbol,
        .eglGetDisplay = egl_lib.lookup(*const fn (?*anyopaque) callconv(.c) EGLDisplay, "eglGetDisplay") orelse return error.MissingSymbol,
        .eglInitialize = egl_lib.lookup(*const fn (EGLDisplay, ?*GLint, ?*GLint) callconv(.c) u32, "eglInitialize") orelse return error.MissingSymbol,
        .eglBindAPI = egl_lib.lookup(*const fn (u32) callconv(.c) u32, "eglBindAPI") orelse return error.MissingSymbol,
        .eglChooseConfig = egl_lib.lookup(*const fn (EGLDisplay, [*]const i32, [*]EGLConfig, i32, *i32) callconv(.c) u32, "eglChooseConfig") orelse return error.MissingSymbol,
        .eglCreateContext = egl_lib.lookup(*const fn (EGLDisplay, EGLConfig, EGLContext, [*]const i32) callconv(.c) EGLContext, "eglCreateContext") orelse return error.MissingSymbol,
        .eglCreateWindowSurface = egl_lib.lookup(*const fn (EGLDisplay, EGLConfig, ?*anyopaque, ?[*]const i32) callconv(.c) EGLSurface, "eglCreateWindowSurface") orelse return error.MissingSymbol,
        .eglMakeCurrent = egl_lib.lookup(*const fn (EGLDisplay, EGLSurface, EGLSurface, EGLContext) callconv(.c) u32, "eglMakeCurrent") orelse return error.MissingSymbol,
        .eglSwapInterval = egl_lib.lookup(*const fn (EGLDisplay, i32) callconv(.c) u32, "eglSwapInterval") orelse return error.MissingSymbol,
        .eglSwapBuffers = egl_lib.lookup(*const fn (EGLDisplay, EGLSurface) callconv(.c) u32, "eglSwapBuffers") orelse return error.MissingSymbol,
        .eglDestroySurface = egl_lib.lookup(*const fn (EGLDisplay, EGLSurface) callconv(.c) u32, "eglDestroySurface") orelse return error.MissingSymbol,
        .eglDestroyContext = egl_lib.lookup(*const fn (EGLDisplay, EGLContext) callconv(.c) u32, "eglDestroyContext") orelse return error.MissingSymbol,
        .eglTerminate = egl_lib.lookup(*const fn (EGLDisplay) callconv(.c) u32, "eglTerminate") orelse return error.MissingSymbol,
        .glViewport = gl_lib.lookup(*const fn (GLint, GLint, GLsizei, GLsizei) callconv(.c) void, "glViewport") orelse return error.MissingSymbol,
        .glClearColor = gl_lib.lookup(*const fn (GLfloat, GLfloat, GLfloat, GLfloat) callconv(.c) void, "glClearColor") orelse return error.MissingSymbol,
        .glClear = gl_lib.lookup(*const fn (GLenum) callconv(.c) void, "glClear") orelse return error.MissingSymbol,
        .glEnable = gl_lib.lookup(*const fn (GLenum) callconv(.c) void, "glEnable") orelse return error.MissingSymbol,
        .glBlendFunc = gl_lib.lookup(*const fn (GLenum, GLenum) callconv(.c) void, "glBlendFunc") orelse return error.MissingSymbol,
        .glCreateShader = gl_lib.lookup(*const fn (GLenum) callconv(.c) GLuint, "glCreateShader") orelse return error.MissingSymbol,
        .glShaderSource = gl_lib.lookup(*const fn (GLuint, GLsizei, [*]const [*:0]const u8, ?[*]const GLint) callconv(.c) void, "glShaderSource") orelse return error.MissingSymbol,
        .glCompileShader = gl_lib.lookup(*const fn (GLuint) callconv(.c) void, "glCompileShader") orelse return error.MissingSymbol,
        .glGetShaderiv = gl_lib.lookup(*const fn (GLuint, GLenum, *GLint) callconv(.c) void, "glGetShaderiv") orelse return error.MissingSymbol,
        .glCreateProgram = gl_lib.lookup(*const fn () callconv(.c) GLuint, "glCreateProgram") orelse return error.MissingSymbol,
        .glAttachShader = gl_lib.lookup(*const fn (GLuint, GLuint) callconv(.c) void, "glAttachShader") orelse return error.MissingSymbol,
        .glLinkProgram = gl_lib.lookup(*const fn (GLuint) callconv(.c) void, "glLinkProgram") orelse return error.MissingSymbol,
        .glGetProgramiv = gl_lib.lookup(*const fn (GLuint, GLenum, *GLint) callconv(.c) void, "glGetProgramiv") orelse return error.MissingSymbol,
        .glUseProgram = gl_lib.lookup(*const fn (GLuint) callconv(.c) void, "glUseProgram") orelse return error.MissingSymbol,
        .glGetAttribLocation = gl_lib.lookup(*const fn (GLuint, [*:0]const u8) callconv(.c) GLint, "glGetAttribLocation") orelse return error.MissingSymbol,
        .glGetUniformLocation = gl_lib.lookup(*const fn (GLuint, [*:0]const u8) callconv(.c) GLint, "glGetUniformLocation") orelse return error.MissingSymbol,
        .glUniform2f = gl_lib.lookup(*const fn (GLint, GLfloat, GLfloat) callconv(.c) void, "glUniform2f") orelse return error.MissingSymbol,
        .glUniform1i = gl_lib.lookup(*const fn (GLint, GLint) callconv(.c) void, "glUniform1i") orelse return error.MissingSymbol,
        .glGenBuffers = gl_lib.lookup(*const fn (GLsizei, [*]GLuint) callconv(.c) void, "glGenBuffers") orelse return error.MissingSymbol,
        .glBindBuffer = gl_lib.lookup(*const fn (GLenum, GLuint) callconv(.c) void, "glBindBuffer") orelse return error.MissingSymbol,
        .glBufferData = gl_lib.lookup(*const fn (GLenum, isize, ?*const anyopaque, GLenum) callconv(.c) void, "glBufferData") orelse return error.MissingSymbol,
        .glEnableVertexAttribArray = gl_lib.lookup(*const fn (GLuint) callconv(.c) void, "glEnableVertexAttribArray") orelse return error.MissingSymbol,
        .glDisableVertexAttribArray = gl_lib.lookup(*const fn (GLuint) callconv(.c) void, "glDisableVertexAttribArray") orelse return error.MissingSymbol,
        .glVertexAttribPointer = gl_lib.lookup(*const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.c) void, "glVertexAttribPointer") orelse return error.MissingSymbol,
        .glDrawArrays = gl_lib.lookup(*const fn (GLenum, GLint, GLsizei) callconv(.c) void, "glDrawArrays") orelse return error.MissingSymbol,
        .glGenTextures = gl_lib.lookup(*const fn (GLsizei, [*]GLuint) callconv(.c) void, "glGenTextures") orelse return error.MissingSymbol,
        .glBindTexture = gl_lib.lookup(*const fn (GLenum, GLuint) callconv(.c) void, "glBindTexture") orelse return error.MissingSymbol,
        .glActiveTexture = gl_lib.lookup(*const fn (GLenum) callconv(.c) void, "glActiveTexture") orelse return error.MissingSymbol,
        .glTexParameteri = gl_lib.lookup(*const fn (GLenum, GLenum, GLint) callconv(.c) void, "glTexParameteri") orelse return error.MissingSymbol,
        .glTexImage2D = gl_lib.lookup(*const fn (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, ?*const anyopaque) callconv(.c) void, "glTexImage2D") orelse return error.MissingSymbol,
        .egl_win = undefined,
        .egl_dpy = null,
        .egl_ctx = null,
        .egl_surf = null,
    };

    const egl_dpy = g.eglGetDisplay(@ptrCast(display)) orelse return error.EglDisplayFailed;
    if (g.eglInitialize(egl_dpy, null, null) == 0) return error.EglInitFailed;
    errdefer _ = g.eglTerminate(egl_dpy);

    _ = g.eglBindAPI(EGL_OPENGL_ES_API);
    const cfg_attribs = [_]i32{
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_ALPHA_SIZE,      8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE,
    };
    var cfg: [1]EGLConfig = .{null};
    var num_cfg: i32 = 0;
    if (g.eglChooseConfig(egl_dpy, &cfg_attribs, &cfg, 1, &num_cfg) == 0 or num_cfg < 1) return error.EglConfigFailed;

    const ctx_attribs = [_]i32{ EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    const ctx = g.eglCreateContext(egl_dpy, cfg[0], null, &ctx_attribs) orelse return error.EglContextFailed;
    errdefer _ = g.eglDestroyContext(egl_dpy, ctx);

    const egl_win = g.wl_egl_window_create(surface, @intCast(width), @intCast(height)) orelse return error.WlEglWindowFailed;
    errdefer g.wl_egl_window_destroy(egl_win);

    const surf = g.eglCreateWindowSurface(egl_dpy, cfg[0], @ptrCast(egl_win), null) orelse return error.EglSurfaceFailed;
    errdefer _ = g.eglDestroySurface(egl_dpy, surf);

    if (g.eglMakeCurrent(egl_dpy, surf, surf, ctx) == 0) return error.EglMakeCurrentFailed;
    _ = g.eglSwapInterval(egl_dpy, 0);

    g.egl_win = egl_win;
    g.egl_dpy = egl_dpy;
    g.egl_ctx = ctx;
    g.egl_surf = surf;

    g.bg_prog = try compileProgram(&g, bg_vs_src, bg_fs_src);
    g.line_prog = try compileProgram(&g, line_vs_src, line_fs_src);
    g.sphere_prog = try compileProgram(&g, sphere_vs_src, sphere_fs_src);
    g.hud_prog = try compileProgram(&g, hud_vs_src, hud_fs_src);

    var bufs = [1]GLuint{0};
    g.glGenBuffers(1, &bufs);
    g.vbo = bufs[0];

    var texs = [1]GLuint{0};
    g.glGenTextures(1, &texs);
    g.hud_tex = texs[0];
    g.glBindTexture(GL_TEXTURE_2D, g.hud_tex);
    g.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    g.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    g.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    g.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    _ = gpa;
    return g;
}

fn deinitGpuBackend(gpa: Allocator, g: *GpuBackend) void {
    if (g.hud_rgba.len > 0) gpa.free(g.hud_rgba);
    g.poly_edge_verts.deinit(gpa);
    g.poly_tri_verts.deinit(gpa);
    g.sphere_verts.deinit(gpa);
    g.line_verts.deinit(gpa);
    _ = g.eglMakeCurrent(g.egl_dpy, null, null, null);
    _ = g.eglDestroySurface(g.egl_dpy, g.egl_surf);
    g.wl_egl_window_destroy(g.egl_win);
    _ = g.eglDestroyContext(g.egl_dpy, g.egl_ctx);
    _ = g.eglTerminate(g.egl_dpy);
    g.gl_lib.close();
    g.egl_lib.close();
    g.wl_egl_lib.close();
}

const GpuSortItem = struct {
    cx: f32,
    cy: f32,
    sr: f32,
    depth: f32,
    r: f32,
    g: f32,
    b: f32,
    alpha: f32,
    kind: f32,
    heat: f32,
    file_count: u32 = 0,
    dir_seed: u32 = 0,
};

fn projectGpu(sim: *const Simulation, p2: sim_mod.Vec2, p3: sim_mod.Vec3, wf: f32, hf: f32) struct { x: f32, y: f32, scale: f32, depth: f32, visible: bool } {
    const b = sim.blend_3d;
    const pr2 = sim.camera.project2D(p2, wf, hf);
    if (b <= 0.001) return .{ .x = pr2.x, .y = pr2.y, .scale = pr2.scale, .depth = 500.0, .visible = true };
    const pr3 = sim.camera.project3D(p3, wf, hf);
    if (!pr3.visible) return .{ .x = pr2.x, .y = pr2.y, .scale = 0, .depth = pr3.depth, .visible = false };
    return .{
        .x = pr2.x + (pr3.x - pr2.x) * b,
        .y = pr2.y + (pr3.y - pr2.y) * b,
        .scale = pr2.scale + (pr3.scale - pr2.scale) * b,
        .depth = 500.0 + (pr3.depth - 500.0) * b,
        .visible = true,
    };
}

fn pushSphereQuad(list: *std.ArrayList(SphereVert), gpa: Allocator, it: GpuSortItem) !void {
    const corners = [6][2]f32{
        .{ -1.0, -1.0 },
        .{ 1.0, -1.0 },
        .{ 1.0, 1.0 },
        .{ -1.0, -1.0 },
        .{ 1.0, 1.0 },
        .{ -1.0, 1.0 },
    };
    for (corners) |uv| {
        try list.append(gpa, .{
            .cx = it.cx,
            .cy = it.cy,
            .radius = it.sr,
            .uv_x = uv[0],
            .uv_y = uv[1],
            .r = it.r,
            .g = it.g,
            .b = it.b,
            .alpha = it.alpha,
            .kind = it.kind,
            .heat = it.heat,
        });
    }
}

fn drawRgbaText(buf: []u8, w: u32, h: u32, x0: i32, y0: i32, text: []const u8, c: Rgb, alpha: u8) void {
    var cx = x0;
    for (text) |ch| {
        if (cx >= @as(i32, @intCast(w))) break;
        if (cx + font.GLYPH_W >= 0) {
            const rows = font.glyphRowBits(ch);
            for (rows, 0..) |bits, ry| {
                const py = y0 + @as(i32, @intCast(ry));
                if (py < 0 or py >= @as(i32, @intCast(h))) continue;
                var col: u3 = 0;
                while (col < 5) : (col += 1) {
                    if ((bits & (@as(u8, 0x10) >> col)) != 0) {
                        const px = cx + @as(i32, col);
                        if (px >= 0 and px < @as(i32, @intCast(w))) {
                            const idx = (@as(usize, @intCast(py)) * @as(usize, w) + @as(usize, @intCast(px))) * 4;
                            buf[idx + 0] = c.r;
                            buf[idx + 1] = c.g;
                            buf[idx + 2] = c.b;
                            buf[idx + 3] = alpha;
                        }
                    }
                }
            }
        }
        cx += font.ADVANCE_X;
    }
}

fn renderSceneGpu(gpa: Allocator, g: *GpuBackend, width: u32, height: u32, sim: *const Simulation) !void {
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);

    g.glViewport(0, 0, @intCast(width), @intCast(height));
    g.glClearColor(0.02, 0.03, 0.06, 1.0);
    g.glClear(GL_COLOR_BUFFER_BIT);
    g.glEnable(GL_BLEND);

    g.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    g.glUseProgram(g.bg_prog);
    g.glBindBuffer(GL_ARRAY_BUFFER, g.vbo);
    const bg_quad = [_]f32{ -1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1 };
    g.glBufferData(GL_ARRAY_BUFFER, @sizeOf(@TypeOf(bg_quad)), &bg_quad, GL_DYNAMIC_DRAW);
    const bg_pos = g.glGetAttribLocation(g.bg_prog, "a_pos");
    if (bg_pos >= 0) {
        g.glEnableVertexAttribArray(@intCast(bg_pos));
        g.glVertexAttribPointer(@intCast(bg_pos), 2, GL_FLOAT, 0, 8, null);
        g.glDrawArrays(GL_TRIANGLES, 0, 6);
        g.glDisableVertexAttribArray(@intCast(bg_pos));
    }

    g.line_verts.clearRetainingCapacity();
    g.sphere_verts.clearRetainingCapacity();

    var sort_items: std.ArrayList(GpuSortItem) = .empty;
    defer sort_items.deinit(gpa);

    const b3d = sim.blend_3d;

    for (sim.dirs.items, 0..) |d, idx| {
        if (idx > 0 and d.subtree_files == 0 and d.heat <= 0.02) continue;
        const cp = projectGpu(sim, d.pos2, d.pos3, wf, hf);
        if (!cp.visible) continue;
        const fog = std.math.clamp(780.0 / @max(180.0, cp.depth), 0.22, 1.15);

        if (d.parent) |p_idx| {
            const par = sim.dirs.items[p_idx];
            const pp = projectGpu(sim, par.pos2, par.pos3, wf, hf);
            if (pp.visible) {
                const a = (0.32 + d.heat * 0.42) * fog;
                const cr = (@as(f32, @floatFromInt(d.tint.r)) / 255.0) * 0.6 + 0.15;
                const cg = (@as(f32, @floatFromInt(d.tint.g)) / 255.0) * 0.6 + 0.25;
                const cb = (@as(f32, @floatFromInt(d.tint.b)) / 255.0) * 0.6 + 0.35;
                try g.line_verts.append(gpa, .{ .x = pp.x, .y = pp.y, .r = cr, .g = cg, .b = cb, .a = a });
                try g.line_verts.append(gpa, .{ .x = cp.x, .y = cp.y, .r = cr, .g = cg, .b = cb, .a = a });
            }
        }

        if (b3d > 0.04) {
            try sort_items.append(gpa, .{
                .cx = cp.x,
                .cy = cp.y,
                .sr = @max(6.0, d.bubble_radius * cp.scale),
                .depth = cp.depth,
                .r = @as(f32, @floatFromInt(d.tint.r)) / 255.0,
                .g = @as(f32, @floatFromInt(d.tint.g)) / 255.0,
                .b = @as(f32, @floatFromInt(d.tint.b)) / 255.0,
                .alpha = b3d * fog,
                .kind = 1.0,
                .heat = d.heat,
                .file_count = if (d.alive_files > 0) d.alive_files else d.subtree_files,
                .dir_seed = @intCast(idx *% 37 +% 11),
            });
        } else {
            try sort_items.append(gpa, .{
                .cx = cp.x,
                .cy = cp.y,
                .sr = @max(3.0, 4.5 * cp.scale),
                .depth = cp.depth,
                .r = @as(f32, @floatFromInt(d.tint.r)) / 255.0,
                .g = @as(f32, @floatFromInt(d.tint.g)) / 255.0,
                .b = @as(f32, @floatFromInt(d.tint.b)) / 255.0,
                .alpha = 0.78,
                .kind = 0.0,
                .heat = d.heat * 0.5,
            });
        }
    }

    for (sim.files.items) |f| {
        if (f.alpha <= 0.01) continue;
        const fp = projectGpu(sim, f.pos2, f.pos3, wf, hf);
        if (!fp.visible) continue;
        const fog = std.math.clamp(780.0 / @max(180.0, fp.depth), 0.25, 1.15);

        if (b3d < 0.65) {
            const d = sim.dirs.items[f.dir_idx];
            const dp = projectGpu(sim, d.pos2, d.pos3, wf, hf);
            if (dp.visible) {
                const a = 0.20 * (1.0 - b3d) * f.alpha;
                const cr = @as(f32, @floatFromInt(f.color.r)) / 255.0;
                const cg = @as(f32, @floatFromInt(f.color.g)) / 255.0;
                const cb = @as(f32, @floatFromInt(f.color.b)) / 255.0;
                try g.line_verts.append(gpa, .{ .x = dp.x, .y = dp.y, .r = cr, .g = cg, .b = cb, .a = a });
                try g.line_verts.append(gpa, .{ .x = fp.x, .y = fp.y, .r = cr, .g = cg, .b = cb, .a = a });
            }
        }

        try sort_items.append(gpa, .{
            .cx = fp.x,
            .cy = fp.y,
            .sr = @max(2.0, f.radius * fp.scale),
            .depth = fp.depth,
            .r = @as(f32, @floatFromInt(f.color.r)) / 255.0,
            .g = @as(f32, @floatFromInt(f.color.g)) / 255.0,
            .b = @as(f32, @floatFromInt(f.color.b)) / 255.0,
            .alpha = f.alpha * @min(1.0, fog),
            .kind = 0.0,
            .heat = if (sim.enable_bloom) f.heat else 0.0,
        });
    }

    for (sim.authors.items) |a| {
        if (a.energy <= 0.02) continue;
        const ap = projectGpu(sim, a.pos2, a.pos3, wf, hf);
        if (!ap.visible) continue;
        try sort_items.append(gpa, .{
            .cx = ap.x,
            .cy = ap.y,
            .sr = @max(4.5, 9.0 * ap.scale),
            .depth = ap.depth,
            .r = @as(f32, @floatFromInt(a.color.r)) / 255.0,
            .g = @as(f32, @floatFromInt(a.color.g)) / 255.0,
            .b = @as(f32, @floatFromInt(a.color.b)) / 255.0,
            .alpha = @min(1.0, a.energy * 1.4),
            .kind = 0.0,
            .heat = if (sim.enable_bloom) (0.5 + a.energy * 0.5) else 0.0,
        });
    }

    for (sim.beams.items) |bm| {
        if (bm.author_idx >= sim.authors.items.len or bm.file_idx >= sim.files.items.len) continue;
        const ap = projectGpu(sim, sim.authors.items[bm.author_idx].pos2, sim.authors.items[bm.author_idx].pos3, wf, hf);
        const fp = projectGpu(sim, sim.files.items[bm.file_idx].pos2, sim.files.items[bm.file_idx].pos3, wf, hf);
        if (!ap.visible or !fp.visible) continue;
        const life = std.math.clamp(bm.ttl / bm.max_ttl, 0.0, 1.0);
        const cr = @as(f32, @floatFromInt(bm.color.r)) / 255.0;
        const cg = @as(f32, @floatFromInt(bm.color.g)) / 255.0;
        const cb = @as(f32, @floatFromInt(bm.color.b)) / 255.0;
        try g.line_verts.append(gpa, .{ .x = ap.x, .y = ap.y, .r = cr, .g = cg, .b = cb, .a = life });
        try g.line_verts.append(gpa, .{ .x = fp.x, .y = fp.y, .r = cr, .g = cg, .b = cb, .a = life });
    }

    if (g.line_verts.items.len > 0) {
        g.glBlendFunc(GL_ONE, GL_ONE);
        g.glUseProgram(g.line_prog);
        g.glUniform2f(g.glGetUniformLocation(g.line_prog, "u_res"), wf, hf);
        g.glBufferData(
            GL_ARRAY_BUFFER,
            @intCast(g.line_verts.items.len * @sizeOf(LineVert)),
            g.line_verts.items.ptr,
            GL_DYNAMIC_DRAW,
        );
        const a_pos: GLuint = @intCast(@max(0, g.glGetAttribLocation(g.line_prog, "a_pos")));
        const a_col: GLuint = @intCast(@max(0, g.glGetAttribLocation(g.line_prog, "a_col")));
        g.glEnableVertexAttribArray(a_pos);
        g.glEnableVertexAttribArray(a_col);
        g.glVertexAttribPointer(a_pos, 2, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(0));
        g.glVertexAttribPointer(a_col, 4, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(8));
        g.glDrawArrays(GL_LINES, 0, @intCast(g.line_verts.items.len));
        g.glDisableVertexAttribArray(a_pos);
        g.glDisableVertexAttribArray(a_col);
    }

    std.mem.sort(GpuSortItem, sort_items.items, {}, struct {
        fn farther(_: void, a: GpuSortItem, b: GpuSortItem) bool {
            return a.depth > b.depth;
        }
    }.farther);

    const flushSpheres = struct {
        fn run(gpu: *GpuBackend, w_f: f32, h_f: f32) void {
            if (gpu.sphere_verts.items.len == 0) return;
            gpu.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            gpu.glUseProgram(gpu.sphere_prog);
            gpu.glUniform2f(gpu.glGetUniformLocation(gpu.sphere_prog, "u_res"), w_f, h_f);
            gpu.glBufferData(
                GL_ARRAY_BUFFER,
                @intCast(gpu.sphere_verts.items.len * @sizeOf(SphereVert)),
                gpu.sphere_verts.items.ptr,
                GL_DYNAMIC_DRAW,
            );
            const loc_c: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.sphere_prog, "a_center")));
            const loc_r: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.sphere_prog, "a_radius")));
            const loc_uv: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.sphere_prog, "a_uv")));
            const loc_col: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.sphere_prog, "a_color")));
            const loc_meta: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.sphere_prog, "a_meta")));

            const stride: GLsizei = @sizeOf(SphereVert);
            gpu.glEnableVertexAttribArray(loc_c);
            gpu.glEnableVertexAttribArray(loc_r);
            gpu.glEnableVertexAttribArray(loc_uv);
            gpu.glEnableVertexAttribArray(loc_col);
            gpu.glEnableVertexAttribArray(loc_meta);

            gpu.glVertexAttribPointer(loc_c, 2, GL_FLOAT, 0, stride, @ptrFromInt(@offsetOf(SphereVert, "cx")));
            gpu.glVertexAttribPointer(loc_r, 1, GL_FLOAT, 0, stride, @ptrFromInt(@offsetOf(SphereVert, "radius")));
            gpu.glVertexAttribPointer(loc_uv, 2, GL_FLOAT, 0, stride, @ptrFromInt(@offsetOf(SphereVert, "uv_x")));
            gpu.glVertexAttribPointer(loc_col, 4, GL_FLOAT, 0, stride, @ptrFromInt(@offsetOf(SphereVert, "r")));
            gpu.glVertexAttribPointer(loc_meta, 2, GL_FLOAT, 0, stride, @ptrFromInt(@offsetOf(SphereVert, "kind")));

            gpu.glDrawArrays(GL_TRIANGLES, 0, @intCast(gpu.sphere_verts.items.len));

            gpu.glDisableVertexAttribArray(loc_c);
            gpu.glDisableVertexAttribArray(loc_r);
            gpu.glDisableVertexAttribArray(loc_uv);
            gpu.glDisableVertexAttribArray(loc_col);
            gpu.glDisableVertexAttribArray(loc_meta);
            gpu.sphere_verts.clearRetainingCapacity();
        }
    }.run;

    const flushPolys = struct {
        fn run(gpu: *GpuBackend, w_f: f32, h_f: f32) void {
            if (gpu.poly_tri_verts.items.len == 0 and gpu.poly_edge_verts.items.len == 0) return;
            // line_fs outputs vec4(rgb * a, a); GL_ONE / GL_ONE_MINUS_SRC_ALPHA is exact standard alpha blending
            gpu.glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            gpu.glUseProgram(gpu.line_prog);
            gpu.glUniform2f(gpu.glGetUniformLocation(gpu.line_prog, "u_res"), w_f, h_f);
            const a_pos: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.line_prog, "a_pos")));
            const a_col: GLuint = @intCast(@max(0, gpu.glGetAttribLocation(gpu.line_prog, "a_col")));
            gpu.glEnableVertexAttribArray(a_pos);
            gpu.glEnableVertexAttribArray(a_col);

            if (gpu.poly_tri_verts.items.len > 0) {
                gpu.glBufferData(
                    GL_ARRAY_BUFFER,
                    @intCast(gpu.poly_tri_verts.items.len * @sizeOf(LineVert)),
                    gpu.poly_tri_verts.items.ptr,
                    GL_DYNAMIC_DRAW,
                );
                gpu.glVertexAttribPointer(a_pos, 2, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(0));
                gpu.glVertexAttribPointer(a_col, 4, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(8));
                gpu.glDrawArrays(GL_TRIANGLES, 0, @intCast(gpu.poly_tri_verts.items.len));
                gpu.poly_tri_verts.clearRetainingCapacity();
            }

            if (gpu.poly_edge_verts.items.len > 0) {
                gpu.glBufferData(
                    GL_ARRAY_BUFFER,
                    @intCast(gpu.poly_edge_verts.items.len * @sizeOf(LineVert)),
                    gpu.poly_edge_verts.items.ptr,
                    GL_DYNAMIC_DRAW,
                );
                gpu.glVertexAttribPointer(a_pos, 2, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(0));
                gpu.glVertexAttribPointer(a_col, 4, GL_FLOAT, 0, @sizeOf(LineVert), @ptrFromInt(8));
                gpu.glDrawArrays(GL_LINES, 0, @intCast(gpu.poly_edge_verts.items.len));
                gpu.poly_edge_verts.clearRetainingCapacity();
            }

            gpu.glDisableVertexAttribArray(a_pos);
            gpu.glDisableVertexAttribArray(a_col);
        }
    }.run;

    g.poly_tri_verts.clearRetainingCapacity();
    g.poly_edge_verts.clearRetainingCapacity();

    for (sort_items.items) |it| {
        if (it.kind > 0.5) {
            flushSpheres(g, wf, hf);
            const base_rgb = Rgb{
                .r = @intFromFloat(std.math.clamp(it.r * 255.0, 0.0, 255.0)),
                .g = @intFromFloat(std.math.clamp(it.g * 255.0, 0.0, 255.0)),
                .b = @intFromFloat(std.math.clamp(it.b * 255.0, 0.0, 255.0)),
            };
            const projected = poly.projectPolyhedron(
                it.file_count,
                it.cx,
                it.cy,
                @min(it.sr, @max(wf, hf) * 0.65),
                base_rgb,
                it.alpha,
                it.heat,
                sim.camera.yaw,
                sim.camera.pitch,
                sim.phase_clock,
                it.dir_seed,
            );
            for (projected.faces[0..projected.face_count]) |face| {
                const fr = @as(f32, @floatFromInt(face.color.r)) / 255.0;
                const fg = @as(f32, @floatFromInt(face.color.g)) / 255.0;
                const fb = @as(f32, @floatFromInt(face.color.b)) / 255.0;
                try g.poly_tri_verts.append(gpa, .{ .x = face.p0[0], .y = face.p0[1], .r = fr, .g = fg, .b = fb, .a = face.alpha });
                try g.poly_tri_verts.append(gpa, .{ .x = face.p1[0], .y = face.p1[1], .r = fr, .g = fg, .b = fb, .a = face.alpha });
                try g.poly_tri_verts.append(gpa, .{ .x = face.p2[0], .y = face.p2[1], .r = fr, .g = fg, .b = fb, .a = face.alpha });
            }
            const er = @min(1.0, it.r + 0.22);
            const eg = @min(1.0, it.g + 0.22);
            const eb = @min(1.0, it.b + 0.22);
            for (projected.edges[0..projected.edge_count]) |edge| {
                try g.poly_edge_verts.append(gpa, .{ .x = edge.p0[0], .y = edge.p0[1], .r = er, .g = eg, .b = eb, .a = edge.alpha });
                try g.poly_edge_verts.append(gpa, .{ .x = edge.p1[0], .y = edge.p1[1], .r = er, .g = eg, .b = eb, .a = edge.alpha });
            }
        } else {
            flushPolys(g, wf, hf);
            try pushSphereQuad(&g.sphere_verts, gpa, it);
        }
    }
    flushPolys(g, wf, hf);
    flushSpheres(g, wf, hf);

    const hud_w = @max(320, width / 2);
    const hud_h = @max(180, height / 2);
    const hud_bytes = @as(usize, hud_w) * @as(usize, hud_h) * 4;
    if (g.hud_rgba.len != hud_bytes) {
        g.hud_rgba = try gpa.realloc(g.hud_rgba, hud_bytes);
        g.hud_w = hud_w;
        g.hud_h = hud_h;
    }
    @memset(g.hud_rgba, 0);

    const bar_rows: usize = 15;
    for (0..bar_rows) |ry| {
        const top_row = ry * hud_w * 4;
        const bot_row = (hud_h - 1 - ry) * hud_w * 4;
        for (0..hud_w) |rx| {
            const ti = top_row + rx * 4;
            g.hud_rgba[ti + 0] = 6;
            g.hud_rgba[ti + 1] = 10;
            g.hud_rgba[ti + 2] = 18;
            g.hud_rgba[ti + 3] = 195;

            const bi = bot_row + rx * 4;
            g.hud_rgba[bi + 0] = 6;
            g.hud_rgba[bi + 1] = 10;
            g.hud_rgba[bi + 2] = 18;
            g.hud_rgba[bi + 3] = 195;
        }
    }

    var date_buf: [20]u8 = undefined;
    const date_str = sim_mod.formatTimestampUtc(sim.sim_time, &date_buf);
    var tl_buf: [256]u8 = undefined;
    const tl = std.fmt.bufPrint(&tl_buf, "[{s}] {s}   {s}   {d} files  {d} dirs  {d} authors", .{
        sim.vcs_kind.badge(),
        sim.repo_name,
        date_str,
        sim.active_file_count,
        sim.dirs.items.len,
        sim.authors.items.len,
    }) catch sim.repo_name;
    drawRgbaText(g.hud_rgba, hud_w, hud_h, 6, 4, tl, .{ .r = 228, .g = 238, .b = 250 }, 245);

    var tr_buf: [128]u8 = undefined;
    const st = if (sim.paused) "PAUSED" else if (sim.streaming_mode) "STREAM" else if (sim.finished) "DONE" else "PLAY";
    const tr = std.fmt.bufPrint(&tr_buf, "{s}  {s}  {d:.2}s/d", .{ sim.view_mode.label(), st, sim.seconds_per_day }) catch "";
    const tr_w = font.textWidth(tr, 1);
    drawRgbaText(g.hud_rgba, hud_w, hud_h, @as(i32, @intCast(hud_w)) - tr_w - 6, 4, tr, .{ .r = 96, .g = 205, .b = 255 }, 245);

    var bt_buf: [256]u8 = undefined;
    const bt = if (sim.last_commit_hash.len > 0 or sim.last_commit_msg.len > 0)
        std.fmt.bufPrint(&bt_buf, "{s} {s}: {s}", .{ sim.last_commit_hash, sim.last_author, sim.last_commit_msg }) catch ""
    else
        "Space:Pause  Tab:2D/3D  +/-:Speed  Drag/WASD:Orbit  Scroll:Zoom  O:AutoOrbit  Q:Quit";
    drawRgbaText(g.hud_rgba, hud_w, hud_h, 6, @as(i32, @intCast(hud_h)) - 11, bt, .{ .r = 180, .g = 198, .b = 222 }, 235);

    if (sim.show_labels) {
        const sx_ratio = @as(f32, @floatFromInt(hud_w)) / wf;
        const sy_ratio = @as(f32, @floatFromInt(hud_h)) / hf;
        var count_lbl: usize = 0;
        for (sim.dirs.items, 0..) |d, idx| {
            if (count_lbl >= 24) break;
            if (idx > 0 and d.subtree_files < 2 and d.heat < 0.25) continue;
            if (d.depth > 2 and d.heat < 0.25) continue;
            const dp = projectGpu(sim, d.pos2, d.pos3, wf, hf);
            if (!dp.visible) continue;
            const lx: i32 = @as(i32, @intFromFloat(dp.x * sx_ratio)) - @divTrunc(font.textWidth(d.name, 1), 2);
            const ly: i32 = @as(i32, @intFromFloat((dp.y - @max(8.0, d.bubble_radius * dp.scale)) * sy_ratio)) - 9;
            drawRgbaText(g.hud_rgba, hud_w, hud_h, lx, ly, d.name, .{ .r = 212, .g = 228, .b = 250 }, 210);
            count_lbl += 1;
        }
        for (sim.authors.items) |a| {
            if (a.energy < 0.18) continue;
            const ap = projectGpu(sim, a.pos2, a.pos3, wf, hf);
            if (!ap.visible) continue;
            drawRgbaText(
                g.hud_rgba,
                hud_w,
                hud_h,
                @as(i32, @intFromFloat((ap.x + 8.0) * sx_ratio)),
                @as(i32, @intFromFloat(ap.y * sy_ratio)) - 3,
                a.name,
                a.color,
                235,
            );
        }
    }

    g.glActiveTexture(GL_TEXTURE0);
    g.glBindTexture(GL_TEXTURE_2D, g.hud_tex);
    g.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, @intCast(hud_w), @intCast(hud_h), 0, GL_RGBA, GL_UNSIGNED_BYTE, g.hud_rgba.ptr);

    g.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    g.glUseProgram(g.hud_prog);
    g.glUniform1i(g.glGetUniformLocation(g.hud_prog, "u_tex"), 0);
    const hud_quad = [_]f32{
        -1, -1, 0, 1,
        1,  -1, 1, 1,
        1,  1,  1, 0,
        -1, -1, 0, 1,
        1,  1,  1, 0,
        -1, 1,  0, 0,
    };
    g.glBufferData(GL_ARRAY_BUFFER, @sizeOf(@TypeOf(hud_quad)), &hud_quad, GL_DYNAMIC_DRAW);
    const hp: GLuint = @intCast(@max(0, g.glGetAttribLocation(g.hud_prog, "a_pos")));
    const huv: GLuint = @intCast(@max(0, g.glGetAttribLocation(g.hud_prog, "a_uv")));
    g.glEnableVertexAttribArray(hp);
    g.glEnableVertexAttribArray(huv);
    g.glVertexAttribPointer(hp, 2, GL_FLOAT, 0, 16, @ptrFromInt(0));
    g.glVertexAttribPointer(huv, 2, GL_FLOAT, 0, 16, @ptrFromInt(8));
    g.glDrawArrays(GL_TRIANGLES, 0, 6);
    g.glDisableVertexAttribArray(hp);
    g.glDisableVertexAttribArray(huv);
}
