const std = @import("std");
const arcan = @import("arcan");
const Parser = @import("./Parser.zig");
const RpcServer = @import("./RpcServer.zig");
const BufferView = @import("./BufferView.zig");
const StatusView = @import("./StatusView.zig");
const MenuView = @import("./MenuView.zig");
const InfoView = @import("./InfoView.zig");

const Tui = @This();

buffer_view: BufferView,
status_view: StatusView,
menu_view: MenuView,
info_view: InfoView,
context: ?*arcan.tui_context,
callbacks: arcan.tui_cbcfg,
event_thread: ?std.Thread = null,
join_request: bool = false,
server: ?*RpcServer = null,

const logger = std.log.scoped(.tui);

pub const Error = error {
    SyncFail,
    SpawnFail,
    NoServer,
};

pub const KeyMod = enum(u16) {
    none   = 0x0000,
    lshift = 0x0001,
    rshift = 0x0002,
    lctrl  = 0x0040,
    rctrl  = 0x0080,
    lalt   = 0x0100,
    ralt   = 0x0200,
    lmeta  = 0x0400,
    rmeta  = 0x0800,
    num    = 0x1000,
    caps   = 0x2000,
    mode   = 0x4000,
    repeat = 0x8000
};

pub fn init() *Tui {
    const connection = arcan.arcan_tui_open_display("Kakoune", "");

    const Static = struct {
        var initialized = false;
        var tui = Tui{
            .context = undefined,
            .buffer_view = undefined,
            .status_view = undefined,
            .menu_view = undefined,
            .info_view = undefined,
            .callbacks = arcan.tui_cbcfg{
                .tag = undefined,
                .apaste = null,
                .bchunk = null,
                .cli_command = null,
                .exec_state = null,
                .geohint = null,
                .input_alabel = null,
                .input_key = &onInputKey,
                .input_label = null,
                .input_misc = null,
                .input_mouse_button = null,
                .input_mouse_motion = null,
                .input_utf8 = &onInputUtf8,
                .query_label = null,
                .recolor = null,
                .reset = null,
                .resized = &onResized,
                .resize = null,
                .seek_absolute = null,
                .seek_relative = null,
                .state = null,
                .substitute = null,
                .subwindow = null,
                .tick = null,
                .utf8 = null,
                .visibility = null,
                .vpaste = null,
            },
        };
    };

    if (Static.initialized) return &Static.tui;

    Static.tui.buffer_view = .init();
    Static.tui.status_view = .init();
    Static.tui.menu_view = .init();
    Static.tui.info_view = .init();

    Static.tui.callbacks.tag = &Static.tui;
    Static.tui.context = arcan.arcan_tui_setup(
        connection,
        null,
        &Static.tui.callbacks,
        @sizeOf(arcan.tui_cbcfg)
    ).?;

    _ = arcan.arcan_tui_set_flags(Static.tui.context, arcan.TUI_MOUSE_FULL | arcan.TUI_HIDE_CURSOR);

    Static.initialized = true;
    return &Static.tui;
}

pub fn deinit(tui: *Tui, allocator: std.mem.Allocator) void {
    arcan.arcan_tui_destroy(tui.context, null);

    tui.info_view.deinit(allocator);
    tui.menu_view.deinit(allocator);
    tui.status_view.deinit(allocator);
    tui.buffer_view.deinit(allocator);

    if (tui.event_thread) |event_thread| {
        tui.join_request = true;
        event_thread.join();
    }
}

pub fn startEventThread(tui: *Tui) Error!void {
    tui.event_thread = std.Thread.spawn(.{}, update, .{tui}) catch |err| {
        logger.err("failed to start event_thread({})", .{err});
        return Error.SpawnFail;
    };
}

fn update(tui: *Tui) void {
    while (!tui.join_request) {
        _ = arcan.arcan_tui_process(&tui.context, 1, null, 0, -1);
        std.Thread.sleep(33 * std.time.ns_per_us);
    }
}

pub fn registerServer(tui: *Tui, server: *RpcServer) void {
    tui.server = server;
}

pub fn refresh(tui: *Tui) Error!void {
    tui.buffer_view.draw(tui);
    tui.status_view.draw(tui);
    tui.menu_view.draw(tui);
    tui.info_view.draw(tui);

    const result = arcan.arcan_tui_refresh(tui.context);
    if (result < 0) {
        const err = std.posix.errno(result);
        if (err == .AGAIN) return;
        logger.err("refresh failed({})", .{err});
        return Error.SyncFail;
    }
}

fn onInputUtf8(
    _: ?*arcan.tui_context,
    optChars: ?[*]const u8,
    len: usize,
    optTag: ?*anyopaque
) callconv(.c) bool {
    if (len > 4) return false;
    const tag = optTag orelse return false;
    const tui: *Tui = @ptrCast(@alignCast(tag));
    const server = tui.server orelse return false;

    if (optChars) |chars| {
        // Leave special keys for tui_input_key
        if (len == 1 and chars[0] <= 32 or chars[0] == 127) return false;
        // Leave upper case letters for tui_input_key to access modifiers
        if (len == 1 and chars[0] >= 65 and chars[0] <= 90) return false;

        server.sendKey(chars[0..len]) catch |err| {
            logger.err("Failed to send key({})", .{err});
            return false;
        };
        return true;
    }

    return false;
}

fn onInputKey(
    _: ?*arcan.tui_context,
    symest: u32,
    _: u8,
    mods: u16,
    _: u16,
    optTag: ?*anyopaque
) callconv(.c) void {
    const tag = optTag orelse return;
    const tui: *Tui = @ptrCast(@alignCast(tag));
    const server = tui.server orelse return;
    var key = [_]u8{0} ** 32;

    key[0] = '<';

    var i: u8 = 1;

    if (mods & (@intFromEnum(KeyMod.lalt) | @intFromEnum(KeyMod.ralt)) != 0) {
        key[i+0] = 'a';
        key[i+1] = '-';
        i += 2;
    }

    if (mods & (@intFromEnum(KeyMod.lctrl) | @intFromEnum(KeyMod.rctrl)) != 0) {
        key[i+0] = 'c';
        key[i+1] = '-';
        i += 2;
    }

    if (mods & (@intFromEnum(KeyMod.lshift) | @intFromEnum(KeyMod.rshift)) != 0) {
        key[i+0] = 's';
        key[i+1] = '-';
        i += 2;
    }

    if (symest > 32 and symest < 127) {
        key[i] = @intCast(symest);
        i += 1;
    } else {
        const key_name = switch (symest) {
            arcan.TUIK_RETURN => "ret",
            arcan.TUIK_SPACE => "space",
            arcan.TUIK_TAB => "tab",
            arcan.TUIK_BACKSPACE => "backspace",
            arcan.TUIK_ESCAPE => "esc",
            arcan.TUIK_UP => "up",
            arcan.TUIK_DOWN => "down",
            arcan.TUIK_LEFT => "left",
            arcan.TUIK_RIGHT => "right",
            arcan.TUIK_PAGEUP => "pageup",
            arcan.TUIK_PAGEDOWN => "pagedown",
            arcan.TUIK_HOME => "home",
            arcan.TUIK_END => "end",
            arcan.TUIK_INSERT => "ins",
            arcan.TUIK_DELETE => "del",
            arcan.TUIK_F1 => "F1",
            arcan.TUIK_F2 => "F2",
            arcan.TUIK_F3 => "F3",
            arcan.TUIK_F4 => "F4",
            arcan.TUIK_F5 => "F5",
            arcan.TUIK_F6 => "F6",
            arcan.TUIK_F7 => "F7",
            arcan.TUIK_F8 => "F8",
            arcan.TUIK_F9 => "F9",
            arcan.TUIK_F10 => "F10",
            arcan.TUIK_F12 => "F12",
            else => return
        };

        const i_0 = i;
        while (i - i_0 < key_name.len) : (i += 1) {
            key[i] = key_name[i - i_0];
        }
    }

    key[i] = '>';

    server.sendKey(key[0..i+1]) catch |err| {
        logger.err("Failed to send key({})", .{err});
        return;
    };
}

fn onResized(
    _: ?*arcan.tui_context,
    _: usize,
    _: usize,
    cols: usize,
    rows: usize,
    optTag: ?*anyopaque
) callconv(.c) void {
    const tag = optTag orelse return;
    const tui: *Tui = @ptrCast(@alignCast(tag));
    const server = tui.server orelse return;

    server.sendResize(rows - 1, cols) catch |err| {
        logger.err("Failed to send resize({})", .{err});
    };
}

pub fn drawAtoms(
    tui: *Tui,
    atoms: []const Parser.Atom,
    default_face: Parser.Face
) void {
    for (atoms) |atom| {
        var face = tui.faceToScreenAttr(mergeFaces(default_face, atom.face));
        _ = arcan.arcan_tui_writestr(tui.context, atom.contents.ptr, &face);
    }
}

const TuiScreenAttr = extern struct {
    fc: [3]u8,
    bc: [3]u8,
    aflags: u16,
    custom_id: u8,
};

pub fn faceToScreenAttr(tui: *const Tui, face: Parser.Face) arcan.tui_screen_attr {
    const attr = face.attributes;
    const aflags =
        (@intFromBool(attr.contains(.underline)) * arcan.TUI_ATTR_UNDERLINE)
        | (@intFromBool(attr.contains(.reverse)) * arcan.TUI_ATTR_INVERSE)
        | (@intFromBool(attr.contains(.blink)) * arcan.TUI_ATTR_BLINK)
        | (@intFromBool(attr.contains(.bold)) * arcan.TUI_ATTR_BOLD)
        | (@intFromBool(attr.contains(.italic)) * arcan.TUI_ATTR_ITALIC) ;
    const fc: [3]u8 = switch (face.fg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => |name| block: {
            var value: [3]u8 = .{0, 0, 0};

            if (name == .default) {
                arcan.arcan_tui_get_color(tui.context, arcan.TUI_COL_TEXT, &value);
            } else {
                const index = @as(u8, arcan.TUI_COL_TBASE) + (
                    @intFromEnum(name) - @intFromEnum(Parser.ColorName.black)
                );
                arcan.arcan_tui_get_color(tui.context, index, &value);
            }

            break :block value;
        },
    };
    const bc: [3]u8 = switch (face.bg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => |name| block: {
            var value: [3]u8 = .{0, 0, 0};

            if (name == .default) {
                arcan.arcan_tui_get_bgcolor(tui.context, arcan.TUI_COL_BG, &value);
            } else {
                const index = @as(u8, arcan.TUI_COL_TBASE) + (
                    @intFromEnum(name) - @intFromEnum(Parser.ColorName.black)
                );
                arcan.arcan_tui_get_color(tui.context, index, &value);
            }

            break :block value;
        },
    };

    return @bitCast(
        TuiScreenAttr{
            .fc = fc,
            .bc = bc,
            .aflags = @intCast(aflags),
            .custom_id = 0
        }
    );
}

fn chooseColor(
    base_face: Parser.Face,
    face: Parser.Face,
    base_color: Parser.Color,
    color: Parser.Color,
    final_attr: ?Parser.Attribute
) Parser.Color {
    if (final_attr) |attr| {
        if (face.attributes.contains(attr)) return color;
        if (base_face.attributes.contains(attr)) return color;
    }

    return switch (color) {
        .name => |name| if (name == .default) base_color else color,
        .rgb => color,
    };
}

pub fn mergeFaces(base: Parser.Face, face: Parser.Face) Parser.Face {
    return .{
        .fg = chooseColor(base, face, base.fg, face.fg, .final_fg),
        .bg = chooseColor(base, face, base.bg, face.bg, .final_bg),
        .underline = chooseColor(base, face, base.underline, face.underline, null),
        .attributes =
            if (face.attributes.contains(.final_attr)) face.attributes
            else if (base.attributes.contains(.final_attr)) base.attributes
            else block: {
                var set = face.attributes;
                set.setUnion(base.attributes);
                break :block set;
            },
    };
}
