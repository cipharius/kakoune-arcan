const std = @import("std");
const Parser = @import("./Parser.zig");
const RpcServer = @import("./RpcServer.zig");
const BufferView = @import("./BufferView.zig");
const StatusView = @import("./StatusView.zig");
const MenuView = @import("./MenuView.zig");
const c = @import("./c.zig");

const TUI = @This();

buffer_view: BufferView,
status_view: StatusView,
menu_view: MenuView,
context: ?*c.tui_context,
callbacks: c.tui_cbcfg,
event_thread: ?std.Thread = null,
join_request: bool = false,
server: ?*const RpcServer = null,

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

pub fn init(allocator: std.mem.Allocator) *@This() {
    const connection = c.arcan_tui_open_display("Kakoune", "");

    const Static = struct {
        var initialized = false;
        var tui = TUI{
            .context = undefined,
            .buffer_view = undefined,
            .status_view = undefined,
            .menu_view = undefined,
            .callbacks = c.tui_cbcfg{
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
                .resized = onResized,
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

    Static.tui.buffer_view = BufferView.init(allocator);
    Static.tui.status_view = StatusView.init(allocator);
    Static.tui.menu_view = MenuView.init(allocator);

    Static.tui.callbacks.tag = &Static.tui;
    Static.tui.context = c.arcan_tui_setup(
        connection,
        null,
        &Static.tui.callbacks,
        @sizeOf(c.tui_cbcfg)
    ).?;

    _ = c.arcan_tui_set_flags(Static.tui.context, c.TUI_MOUSE_FULL | c.TUI_HIDE_CURSOR);

    Static.initialized = true;
    return &Static.tui;
}

pub fn deinit(tui: *@This()) void {
    tui.buffer_view.deinit();
    tui.status_view.deinit();
    tui.menu_view.deinit();
    c.arcan_tui_destroy(tui.context, null);

    if (tui.event_thread) |event_thread| {
        tui.join_request = true;
        event_thread.join();
    }
}

pub fn startEventThread(tui: *@This()) Error!void {
    tui.event_thread = std.Thread.spawn(.{}, update, .{tui}) catch |err| {
        logger.err("failed to start event_thread({})", .{err});
        return Error.SpawnFail;
    };
}

fn update(tui: *@This()) void {
    while (!tui.join_request) {
        _ = c.arcan_tui_process(&tui.context, 1, null, 0, -1);
        std.time.sleep(1/30 * std.time.ns_per_s);
    }
}

pub fn registerServer(tui: *@This(), server: *const RpcServer) void {
    tui.server = server;
}

pub fn refresh(tui: *@This()) Error!void {
    tui.buffer_view.draw(tui);
    tui.status_view.draw(tui);
    tui.menu_view.draw(tui);
    // TODO Draw menu
    // TODO Draw info

    const result = c.arcan_tui_refresh(tui.context);
    if (result < 0) {
        logger.err("refresh failed({})", .{std.os.errno(result)});
        return Error.SyncFail;
    }
}

fn onInputUtf8(
    _: ?*c.tui_context,
    optChars: ?[*]const u8,
    len: usize,
    optTag: ?*anyopaque
) callconv(.C) bool {
    if (len > 4) return false;
    const tag = optTag orelse return false;
    const tui = @ptrCast(*@This(), @alignCast(8, tag));
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
    _: ?*c.tui_context,
    symest: u32,
    _: u8,
    mods: u16,
    _: u16,
    optTag: ?*anyopaque
) callconv(.C) void {
    const tag = optTag orelse return;
    const tui = @ptrCast(*@This(), @alignCast(8, tag));
    const server = tui.server orelse return;
    var key = [_]u8{0} ** 32;

    key[0] = '<';

    var i: u8 = 1;

    if (mods & (@enumToInt(KeyMod.lalt) | @enumToInt(KeyMod.ralt)) != 0) {
        key[i+0] = 'a';
        key[i+1] = '-';
        i += 2;
    }

    if (mods & (@enumToInt(KeyMod.lctrl) | @enumToInt(KeyMod.rctrl)) != 0) {
        key[i+0] = 'c';
        key[i+1] = '-';
        i += 2;
    }

    if (mods & (@enumToInt(KeyMod.lshift) | @enumToInt(KeyMod.rshift)) != 0) {
        key[i+0] = 's';
        key[i+1] = '-';
        i += 2;
    }

    if (symest > 32 and symest < 127) {
        key[i] = @intCast(u8, symest);
        i += 1;
    } else {
        const key_name = switch (symest) {
            c.TUIK_RETURN => "ret",
            c.TUIK_SPACE => "space",
            c.TUIK_TAB => "tab",
            c.TUIK_BACKSPACE => "backspace",
            c.TUIK_ESCAPE => "esc",
            c.TUIK_UP => "up",
            c.TUIK_DOWN => "down",
            c.TUIK_LEFT => "left",
            c.TUIK_RIGHT => "right",
            c.TUIK_PAGEUP => "pageup",
            c.TUIK_PAGEDOWN => "pagedown",
            c.TUIK_HOME => "home",
            c.TUIK_END => "end",
            c.TUIK_INSERT => "ins",
            c.TUIK_DELETE => "del",
            c.TUIK_F1 => "F1",
            c.TUIK_F2 => "F2",
            c.TUIK_F3 => "F3",
            c.TUIK_F4 => "F4",
            c.TUIK_F5 => "F5",
            c.TUIK_F6 => "F6",
            c.TUIK_F7 => "F7",
            c.TUIK_F8 => "F8",
            c.TUIK_F9 => "F9",
            c.TUIK_F10 => "F10",
            c.TUIK_F12 => "F12",
            else => return
        };

        var i_0 = i;
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
    _: ?*c.tui_context,
    _: usize,
    _: usize,
    cols: usize,
    rows: usize,
    optTag: ?*anyopaque
) callconv(.C) void {
    const tag = optTag orelse return;
    const tui = @ptrCast(*@This(), @alignCast(8, tag));
    const server = tui.server orelse return;

    tui.refresh() catch |err| {
        logger.err("Failed to refresh TUI({})", .{err});
    };

    server.sendResize(rows, cols) catch |err| {
        logger.err("Failed to send resize({})", .{err});
    };
}

pub fn drawAtoms(
    tui: *@This(),
    atoms: []const Parser.Atom,
    default_face: Parser.Face
) void {
    for (atoms) |atom| {
        var face = tui.faceToScreenAttr(mergeFaces(default_face, atom.face));
        _ = c.arcan_tui_writestr(tui.context, atom.contents.ptr, &face);
    }
}

const TuiScreenAttr = extern struct {
    fc: [3]u8,
    bc: [3]u8,
    aflags: u16,
    custom_id: u8,
};

pub fn faceToScreenAttr(tui: *const TUI, face: Parser.Face) c.tui_screen_attr {
    const attr = face.attributes;
    const aflags =
        (@boolToInt(attr.contains(.underline)) * c.TUI_ATTR_UNDERLINE)
        | (@boolToInt(attr.contains(.reverse)) * c.TUI_ATTR_INVERSE)
        | (@boolToInt(attr.contains(.blink)) * c.TUI_ATTR_BLINK)
        | (@boolToInt(attr.contains(.bold)) * c.TUI_ATTR_BOLD)
        | (@boolToInt(attr.contains(.italic)) * c.TUI_ATTR_ITALIC) ;
    const fc: [3]u8 = switch (face.fg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => |name| block: {
            var value: [3]u8 = .{0, 0, 0};

            if (name == .default) {
                c.arcan_tui_get_color(tui.context, c.TUI_COL_TEXT, &value);
            } else {
                const index = @as(u8, c.TUI_COL_TBASE) + (
                    @enumToInt(name) - @enumToInt(Parser.ColorName.black)
                );
                c.arcan_tui_get_color(tui.context, index, &value);
            }

            break :block value;
        },
    };
    const bc: [3]u8 = switch (face.bg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => |name| block: {
            var value: [3]u8 = .{0, 0, 0};

            if (name == .default) {
                c.arcan_tui_get_bgcolor(tui.context, c.TUI_COL_BG, &value);
            } else {
                const index = @as(u8, c.TUI_COL_TBASE) + (
                    @enumToInt(name) - @enumToInt(Parser.ColorName.black)
                );
                c.arcan_tui_get_color(tui.context, index, &value);
            }

            break :block value;
        },
    };

    return @bitCast(
        c.tui_screen_attr,
        TuiScreenAttr{
            .fc = fc,
            .bc = bc,
            .aflags = @intCast(u16, aflags),
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
