const std = @import("std");
const Parser = @import("./Parser.zig");
const TUI = @import("./TUI.zig");
const c = @import("./c.zig");

anchor: Parser.Coord = .{ .line = 0, .column = 0 },
face: Parser.Face = .{},
style: Parser.InfoStyle = .Unknown,
title: ?[]Parser.Atom = null,
content: std.ArrayList([]Parser.Atom),
atoms: std.ArrayList(Parser.Atom),
string_buffer: std.ArrayList(u8),
active: bool = false,

const InfoView = @This();

pub fn init(allocator: std.mem.Allocator) InfoView {
    return .{
        .content = std.ArrayList([]Parser.Atom).init(allocator),
        .atoms = std.ArrayList(Parser.Atom).init(allocator),
        .string_buffer = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(view: *InfoView) void {
    view.content.deinit();
    view.atoms.deinit();
    view.string_buffer.deinit();
}

pub fn update(
    view: *InfoView,
    title: Parser.Line,
    content: []const Parser.Line,
    anchor: Parser.Coord,
    face: Parser.Face,
    style: Parser.InfoStyle,
) !void {
    view.anchor = anchor;
    view.face = face;
    view.style = style;
    view.active = true;

    view.content.clearRetainingCapacity();
    view.atoms.clearRetainingCapacity();
    view.string_buffer.clearRetainingCapacity();

    var required_atoms: usize = 0;
    var required_bytes: usize = 0;

    for (title) |atom| {
        required_atoms += 1;
        required_bytes += atom.contents.len + 1;
    }

    for (content) |line| {
        required_atoms += line.len;
        for (line) |atom| {
            required_bytes += atom.contents.len + 1;
        }
    }

    try view.content.ensureTotalCapacity(content.len);
    try view.atoms.ensureTotalCapacity(required_atoms);
    try view.string_buffer.ensureTotalCapacity(required_bytes);

    for (title) |atom| {
        const s0 = view.string_buffer.items.len;
        view.string_buffer.appendSliceAssumeCapacity(atom.contents);
        view.string_buffer.appendAssumeCapacity(0);
        const s1 = view.string_buffer.items.len - 1;

        const atom_ptr = view.atoms.addOneAssumeCapacity();
        atom_ptr.* = atom;
        atom_ptr.contents = view.string_buffer.items[s0..s1 :0];
    }
    view.title = view.atoms.items[0..];

    for (content) |line| {
        const l0 = view.atoms.items.len;

        for (line) |atom| {
            const s0 = view.string_buffer.items.len;
            view.string_buffer.appendSliceAssumeCapacity(atom.contents);
            view.string_buffer.appendAssumeCapacity(0);
            const s1 = view.string_buffer.items.len - 1;

            const atom_ptr = view.atoms.addOneAssumeCapacity();
            atom_ptr.* = atom;
            atom_ptr.contents = view.string_buffer.items[s0..s1 :0];
        }

        const l1 = view.atoms.items.len;
        view.content.appendAssumeCapacity(view.atoms.items[l0..l1]);
    }
}

pub fn draw(view: *InfoView, tui: *TUI) void {
    switch (view.style) {
        .prompt => view.drawPromptStyle(tui),
        .@"inline" => {},
        .inlineAbove => {},
        .inlineBelow => {},
        .menuDoc => {},
        .modal => {},
        .Unknown => {},
    }
}

const max_rows: usize = 10; // TODO Take from MenuView
pub fn drawPromptStyle(view: *InfoView, tui: *TUI) void {
    if (!view.active) return;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui.context, &rows, &cols);

    const y1 = rows -| max_rows -| 2;
    const y0 = y1 -| view.content.items.len -| 1;
    const x1 = cols - 1;

    var max_line_width: usize = 0;
    for (view.content.items) |line| {
        var line_width: usize = 0;
        for (line) |atom| {
            line_width += std.unicode.utf8CountCodepoints(atom.contents) catch 0;
        }
        max_line_width = @max(max_line_width, line_width);
    }

    var title_width: usize = 0;
    for (view.title.?) |atom| {
        title_width += std.unicode.utf8CountCodepoints(atom.contents) catch 0;
    }

    const x0 = x1 -| max_line_width -| 3;
    const box_width = x1 - x0 - 3;
    const box_height = y1 - y0 - 1;

    const face = tui.faceToScreenAttr(view.face);
    c.arcan_tui_eraseattr_region(
        tui.context,
        x0, y0,
        x1, y1,
        false, face
    );

    // Draw box art
    c.arcan_tui_move_to(tui.context, x0, y0);
    c.arcan_tui_write(tui.context, @as(u32, 9581), &face); // ╭
    c.arcan_tui_move_to(tui.context, x1, y0);
    c.arcan_tui_write(tui.context, @as(u32, 9582), &face); // ╮
    c.arcan_tui_move_to(tui.context, x1, y1);
    c.arcan_tui_write(tui.context, @as(u32, 9583), &face); // ╯
    c.arcan_tui_move_to(tui.context, x0, y1);
    c.arcan_tui_write(tui.context, @as(u32, 9584), &face); // ╰

    var i: usize = 0;
    while (i <= x1 - x0 - 2) : (i += 1) {
        c.arcan_tui_move_to(tui.context, x0 + i + 1, y0);
        c.arcan_tui_write(tui.context, @as(u32, 9472), &face); // ─
        c.arcan_tui_move_to(tui.context, x0 + i + 1, y1);
        c.arcan_tui_write(tui.context, @as(u32, 9472), &face); // ─
    }

    i = 0;
    while (i <= y1 - y0 - 2) : (i += 1) {
        c.arcan_tui_move_to(tui.context, x0, y0 + i + 1);
        c.arcan_tui_write(tui.context, @as(u32, 9474), &face); // │
        c.arcan_tui_move_to(tui.context, x1, y0 + i + 1);
        c.arcan_tui_write(tui.context, @as(u32, 9474), &face); // │
    }

    const title_x = @divFloor(x0 + x1 - title_width, 2);
    c.arcan_tui_move_to(tui.context, title_x, y0);
    tui.drawAtoms(view.title.?, view.face);
    c.arcan_tui_move_to(tui.context, title_x - 1, y0);
    c.arcan_tui_write(tui.context, @as(u32, 9474), &face); // │
    c.arcan_tui_move_to(tui.context, title_x + title_width, y0);
    c.arcan_tui_write(tui.context, @as(u32, 9474), &face); // │

    i = 0;
    while (i < @min(box_height, view.content.items.len)) : (i += 1) {
        const line = view.content.items[i];
        const line_end = @min(box_width, line.len);
        c.arcan_tui_move_to(tui.context, x0 + 2, y0 + 1 + i);
        tui.drawAtoms(line[0..line_end], view.face);
    }
}
