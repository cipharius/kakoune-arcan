const std = @import("std");
const Parser = @import("./Parser.zig");
const RpcServer = @import("./RpcServer.zig");
const c = @cImport({
    @cInclude("arcan_shmif.h");
    @cInclude("arcan_tui.h");
});

const TUI = @This();

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

pub fn init() *@This() {
    const connection = c.arcan_tui_open_display("Kakoune", "");

    const Static = struct {
        var initialized = false;
        var tui = TUI{
            .context = undefined,
            .callbacks = c.tui_cbcfg{
                .tag = undefined,
                .apaste = null,
                .bchunk = null,
                .cli_command = null,
                .exec_state = null,
                .geohint = null,
                .input_alabel = null,
                .input_key = null,
                .input_label = null,
                .input_misc = null,
                .input_mouse_button = null,
                .input_mouse_motion = null,
                .input_utf8 = &onInputUtf8,
                .query_label = null,
                .recolor = null,
                .reset = null,
                .resized = null,
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

pub fn draw(
    tui: *@This(),
    lines: []const Parser.Line,
    default_face: Parser.Face,
    padding_face: Parser.Face
) Error!void {
    const default_screen_attr = faceToScreenAttr(default_face);

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui.context, &rows, &cols);

    var line_index: usize = 0;
    for (lines) |line| {
        c.arcan_tui_eraseattr_region(
            tui.context, 0, line_index, cols, line_index,
            false, default_screen_attr
        );
        c.arcan_tui_move_to(tui.context, 0, line_index);
        tui.drawAtoms(line, default_face);
        line_index += 1;
    }

    // Draw padding space
    const face = mergeFaces(default_face, padding_face);
    c.arcan_tui_eraseattr_region(
        tui.context, 0, line_index, cols, rows,
        false, faceToScreenAttr(face)
    );

    const padding_atom = .{ Parser.Atom{ .contents = "~" } };

    while (line_index < rows) {
        c.arcan_tui_move_to(tui.context, 0, line_index);
        tui.drawAtoms(&padding_atom, face);
        line_index += 1;
    }
}

pub fn drawStatus(
    tui: *@This(),
    status_line: Parser.Line,
    mode_line: Parser.Line,
    default_face: Parser.Face
) Error!void {
    const default_screen_attr = faceToScreenAttr(default_face);

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui.context, &rows, &cols);

    c.arcan_tui_eraseattr_region(
        tui.context,
        0, rows-1, cols, rows-1,
        false, default_screen_attr
    );
    c.arcan_tui_move_to(tui.context, 0, rows);
    tui.drawAtoms(status_line, default_face);

    var mode_len: usize = 0;
    for (mode_line) |atom| {
        mode_len += atom.contents.len;
    }

    var status_len: usize = 0;
    for (status_line) |atom| {
        status_len += atom.contents.len;
    }

    const remaining = cols - status_len;

    if (mode_len < remaining) {
        c.arcan_tui_move_to(tui.context, cols - mode_len, rows-1);
        tui.drawAtoms(mode_line, default_face);
    }
}

pub fn refresh(tui: *@This(), force: bool) Error!void {
    if (force) c.arcan_tui_invalidate(tui.context);
    const result = c.arcan_tui_refresh(tui.context);
    if (result < 0) return Error.SyncFail;
}

fn onInputUtf8(
    _: ?*c.tui_context,
    optChars: ?[*]const u8,
    len: usize,
    optTag: ?*anyopaque
) callconv(.C) bool {
    if (len > 4) return false;
    const tag = if (optTag) |t| t else return false;
    const tui = @ptrCast(*@This(), @alignCast(8, tag));
    const server = if (tui.server) |s| s else return false;

    if (optChars) |chars| {
        server.sendKey(chars[0..len]) catch unreachable;
        return true;
    }

    return false;
}

fn drawAtoms(
    tui: *@This(),
    atoms: []const Parser.Atom,
    default_face: Parser.Face
) void {
    for (atoms) |atom| {
        var face = faceToScreenAttr(mergeFaces(default_face, atom.face));
        _ = c.arcan_tui_writestr(tui.context, atom.contents.ptr, &face);
    }
}

const TuiScreenAttr = extern struct {
    fc: [3]u8,
    bc: [3]u8,
    aflags: u16,
    custom_id: u8,
};

fn faceToScreenAttr(face: Parser.Face) c.tui_screen_attr {
    const attr = face.attributes;
    var aflags =
        (@boolToInt(attr.contains(.underline)) * c.TUI_ATTR_UNDERLINE)
        | (@boolToInt(attr.contains(.reverse)) * c.TUI_ATTR_INVERSE)
        | (@boolToInt(attr.contains(.blink)) * c.TUI_ATTR_BLINK)
        | (@boolToInt(attr.contains(.bold)) * c.TUI_ATTR_BOLD)
        | (@boolToInt(attr.contains(.italic)) * c.TUI_ATTR_ITALIC) ;

    var fc: [3]u8 = switch (face.fg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => .{255, 255, 255},
    };
    var bc: [3]u8 = switch (face.bg) {
        .rgb => |col| .{col.r, col.g, col.b},
        .name => .{255, 255, 255},
    };

    if (face.fg == .name and face.bg == .name) {
        aflags |= c.TUI_ATTR_COLOR_INDEXED;

        if (face.fg.name == .default) {
            fc[0] = c.TUI_COL_TEXT;
        } else {
            fc[0] = @as(u8, c.TUI_COL_TBASE) + (
                @enumToInt(face.fg.name) - @enumToInt(Parser.ColorName.default)
            );
        }

        if (face.bg.name == .default) {
            bc[0] = c.TUI_COL_TEXT;
        } else {
            bc[0] = @as(u8, c.TUI_COL_TBASE) + (
                @enumToInt(face.bg.name) - @enumToInt(Parser.ColorName.default)
            );
        }
    }

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

fn mergeFaces(base: Parser.Face, face: Parser.Face) Parser.Face {
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
