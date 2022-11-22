const std = @import("std");
const Parser = @import("./Parser.zig");
const TUI = @import("./TUI.zig");
const c = @import("./c.zig");

cursor: usize = 0,
anchor: Parser.Coord = .{ .line = 0, .column = 0 },
menu_face: Parser.Face = .{},
selected_item_face: Parser.Face = .{},
style: Parser.MenuStyle = .Unknown,
items: std.ArrayList([]Parser.Atom),
atoms: std.ArrayList(Parser.Atom),
string_buffer: std.ArrayList(u8),
active: bool = false,

const MenuView = @This();

pub fn init(allocator: std.mem.Allocator) MenuView {
    return .{
        .items = std.ArrayList([]Parser.Atom).init(allocator),
        .atoms = std.ArrayList(Parser.Atom).init(allocator),
        .string_buffer = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(view: *MenuView) void {
    view.items.deinit();
    view.atoms.deinit();
    view.string_buffer.deinit();
}

pub fn update(
    view: *MenuView,
    items: []const Parser.Line,
    anchor: Parser.Coord,
    selected_item_face: Parser.Face,
    menu_face: Parser.Face,
    style: Parser.MenuStyle,
) !void {
    view.anchor = anchor;
    view.selected_item_face = selected_item_face;
    view.menu_face = menu_face;
    view.style = style;
    view.cursor = 0;
    view.active = true;

    view.items.clearRetainingCapacity();
    view.atoms.clearRetainingCapacity();
    view.string_buffer.clearRetainingCapacity();

    var required_atoms: usize = 0;
    var required_bytes: usize = 0;
    for (items) |item| {
        required_atoms += item.len;

        for (item) |atom| {
            required_bytes += atom.contents.len + 1;
        }
    }

    try view.items.ensureTotalCapacity(items.len);
    try view.atoms.ensureTotalCapacity(required_atoms);
    try view.string_buffer.ensureTotalCapacity(required_bytes);

    for (items) |item| {
        const l0 = view.atoms.items.len;

        for (item) |atom| {
            const s0 = view.string_buffer.items.len;
            view.string_buffer.appendSliceAssumeCapacity(atom.contents);
            view.string_buffer.appendAssumeCapacity(0);
            const s1 = view.string_buffer.items.len - 1;

            const atom_ptr = view.atoms.addOneAssumeCapacity();
            atom_ptr.* = atom;
            atom_ptr.contents = view.string_buffer.items[s0..s1 :0];
        }

        const l1 = view.atoms.items.len;
        view.items.appendAssumeCapacity(view.atoms.items[l0..l1]);
    }
}

pub fn draw(view: *MenuView, tui: *TUI) void {
    switch (view.style) {
        .prompt => view.drawPromptStyle(tui),
        else => {} // TODO Render other styles
    }
}

pub fn drawPromptStyle(view: *MenuView, tui: *TUI) void {
    const max_rows: usize = 10;
    if (!view.active) return;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui.context, &rows, &cols);

    const menu_rows = std.math.min(view.items.items.len, max_rows);

    const x0: usize = 0;
    const y0: usize = rows - 1 - menu_rows;
    const x1: usize = cols - 1;
    const y1: usize = rows - 2;

    c.arcan_tui_eraseattr_region(
        tui.context, x0, y0, x1, y1,
        false, tui.faceToScreenAttr(view.menu_face)
    );

    var max_item_width: usize = 0;
    for (view.items.items) |item| {
        var item_width: usize = 0;
        for (item) |atom| {
            item_width += std.unicode.utf8CountCodepoints(atom.contents) catch 0;
        }
        max_item_width = std.math.max(max_item_width, item_width);
    }
    if (max_item_width == 0) return;

    const max_cols: usize = @divFloor(cols - 1, max_item_width);
    const column_width: usize = @divFloor(cols - 1, max_cols);

    const current_page: usize = @divFloor(
        view.cursor,
        max_cols * max_rows
    );
    const total_pages: usize = @divFloor(
        view.items.items.len,
        max_cols * max_rows
    ) + 1;

    view.drawScrollbar(tui, x1, y0, menu_rows, current_page, total_pages);

    const page_cursor: usize = current_page * max_cols * max_rows;
    var i: usize = 0;
    const n = std.math.min(
        max_cols * max_rows,
        view.items.items.len - page_cursor
    );
    while (i < n) : (i += 1) {
        const item = view.items.items[page_cursor + i];
        const row = i % max_rows;
        const column = @divTrunc(i, max_rows);

        if (column == max_cols) break;

        const face =
            if (page_cursor + i == view.cursor) view.selected_item_face
            else view.menu_face;

        c.arcan_tui_eraseattr_region(
            tui.context,
            x0 + column_width * column,
            y0 + row,
            x0 + column_width * (column + 1) - 1,
            y0 + row,
            false, tui.faceToScreenAttr(face)
        );

        c.arcan_tui_move_to(
            tui.context,
            x0 + column_width * column,
            y0 + row
        );

        tui.drawAtoms(item, face);
    }
}

fn drawScrollbar(
    view: *MenuView,
    tui: *TUI,
    x: usize,
    y: usize,
    rows: usize,
    current_page: usize,
    total_pages: usize
) void {
    var face = tui.faceToScreenAttr(view.menu_face);

    const offset: usize =
        if (total_pages <= 1) 0
        else @floatToInt(usize, @intToFloat(f32, rows) * (@intToFloat(f32, current_page) / @intToFloat(f32, total_pages - 1)));
    const width: usize =
        if (total_pages <= 1) rows
        else @floatToInt(usize, @intToFloat(f32, rows) * (@intToFloat(f32, 1) / @intToFloat(f32, total_pages - 1)));

    var i: usize = 0;
    while (i < rows) : (i += 1) {
        c.arcan_tui_move_to(tui.context, x, y + i);

        const codepoint =
            if (i >= offset and i <= offset+width) @as(u32, 9608) // #9608 = █
            else @as(u32, 9617); // #9617 = ░

        c.arcan_tui_write(tui.context, codepoint, &face);
    }
}
