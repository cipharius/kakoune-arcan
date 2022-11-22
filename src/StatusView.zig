const std = @import("std");
const Parser = @import("./Parser.zig");
const TUI = @import("./TUI.zig");
const c = @import("./c.zig");

default_face: Parser.Face = .{},
status_line: ?Parser.Line = null,
mode_line: ?Parser.Line = null,
atoms: std.ArrayList(Parser.Atom),
string_buffer: std.ArrayList(u8),

const StatusView = @This();

pub fn init(allocator: std.mem.Allocator) StatusView {
    return .{
        .atoms = std.ArrayList(Parser.Atom).init(allocator),
        .string_buffer = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(view: *StatusView) void {
    view.atoms.deinit();
    view.string_buffer.deinit();
}

pub fn update(
    view: *StatusView,
    status_line: Parser.Line,
    mode_line: Parser.Line,
    default_face: Parser.Face
) !void {
    view.default_face = default_face;

    view.atoms.clearRetainingCapacity();
    view.string_buffer.clearRetainingCapacity();

    const required_atoms = status_line.len + mode_line.len;
    var required_bytes: usize = 0;
    for (status_line) |atom| {
        required_bytes += atom.contents.len + 1;
    }
    for (mode_line) |atom| {
        required_bytes += atom.contents.len + 1;
    }

    try view.atoms.ensureTotalCapacity(required_atoms);
    try view.string_buffer.ensureTotalCapacity(required_bytes);

    const l0 = view.atoms.items.len;
    for (status_line) |atom| {
        const s0 = view.string_buffer.items.len;
        view.string_buffer.appendSliceAssumeCapacity(atom.contents);
        view.string_buffer.appendAssumeCapacity(0);
        const s1 = view.string_buffer.items.len - 1;

        const atom_ptr = view.atoms.addOneAssumeCapacity();
        atom_ptr.* = atom;
        atom_ptr.contents = view.string_buffer.items[s0..s1 :0];
    }

    const l1 = view.atoms.items.len;
    for (mode_line) |atom| {
        const s0 = view.string_buffer.items.len;
        view.string_buffer.appendSliceAssumeCapacity(atom.contents);
        view.string_buffer.appendAssumeCapacity(0);
        const s1 = view.string_buffer.items.len - 1;

        const atom_ptr = view.atoms.addOneAssumeCapacity();
        atom_ptr.* = atom;
        atom_ptr.contents = view.string_buffer.items[s0..s1 :0];
    }

    const l2 = view.atoms.items.len;

    view.status_line = view.atoms.items[l0..l1];
    view.mode_line = view.atoms.items[l1..l2];
}

pub fn draw(view: *StatusView, tui: *TUI) void {
    const default_screen_attr = tui.faceToScreenAttr(view.default_face);

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui.context, &rows, &cols);

    c.arcan_tui_eraseattr_region(
        tui.context,
        0, rows-1, cols, rows-1,
        false, default_screen_attr
    );
    c.arcan_tui_move_to(tui.context, 0, rows-1);
    tui.drawAtoms(view.status_line.?, view.default_face);

    var mode_len: usize = 0;
    for (view.mode_line.?) |atom| {
        mode_len += atom.contents.len;
    }

    var status_len: usize = 0;
    for (view.status_line.?) |atom| {
        status_len += atom.contents.len;
    }

    const remaining = cols - status_len;

    if (mode_len < remaining) {
        c.arcan_tui_move_to(tui.context, cols - mode_len, rows-1);
        tui.drawAtoms(view.mode_line.?, view.default_face);
    }
}
