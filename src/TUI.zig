const std = @import("std");
const Parser = @import("./Parser.zig");
const c = @cImport({
    @cInclude("arcan_shmif.h");
    @cInclude("arcan_tui.h");
});

context: *c.tui_context,
callbacks: c.tui_cbcfg,

const logger = std.log.scoped(.tui);

pub const Error = error {
    SyncFail
};

pub fn init() @This() {
    const connection = c.arcan_tui_open_display("Kakoune", "");

    var tui = @This(){
        .context = undefined,
        .callbacks = std.mem.zeroes(c.tui_cbcfg),
    };

    tui.callbacks.tag = &tui;
    tui.context = c.arcan_tui_setup(
        connection,
        null,
        &tui.callbacks,
        @sizeOf(c.tui_cbcfg)
    ).?;

    _ = c.arcan_tui_set_flags(tui.context, c.TUI_MOUSE_FULL | c.TUI_HIDE_CURSOR);

    return tui;
}

pub fn deinit(tui: *@This()) void {
    c.arcan_tui_destroy(tui.context, null);
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

pub fn refresh(tui: *@This(), force: bool) Error!void {
    if (force) c.arcan_tui_invalidate(tui.context);
    const result = c.arcan_tui_refresh(tui.context);
    if (result < 0) return Error.SyncFail;
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
    const aflags = @intCast(u16,
        (@boolToInt(attr.contains(.underline)) * c.TUI_ATTR_UNDERLINE)
        | (@boolToInt(attr.contains(.reverse)) * c.TUI_ATTR_INVERSE)
        | (@boolToInt(attr.contains(.blink)) * c.TUI_ATTR_BLINK)
        | (@boolToInt(attr.contains(.bold)) * c.TUI_ATTR_BOLD)
        | (@boolToInt(attr.contains(.italic)) * c.TUI_ATTR_ITALIC)
    );

    return @bitCast(c.tui_screen_attr,
        TuiScreenAttr{
            .fc = switch (face.fg) {
                .rgb => |col| .{col.r, col.g, col.b},
                .name => .{0, 0, 0},
            },
            .bc = switch (face.bg) {
                .rgb => |col| .{col.r, col.g, col.b},
                .name => .{0, 0, 0},
            },
            .aflags = aflags,
            .custom_id = 0,
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
