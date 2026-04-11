const std = @import("std");
const arcan = @import("arcan");
const Parser = @import("./Parser.zig");
const Tui = @import("./Tui.zig");

default_face: Parser.Face = .{},
padding_face: Parser.Face = .{},
lines: std.ArrayList([]Parser.Atom),
atoms: std.ArrayList(Parser.Atom),
string_buffer: std.ArrayList(u8),

const BufferView = @This();

pub fn init() BufferView {
    return .{
        .lines = .empty,
        .atoms = .empty,
        .string_buffer = .empty,
    };
}

pub fn deinit(view: *BufferView, allocator: std.mem.Allocator) void {
    view.lines.deinit(allocator);
    view.atoms.deinit(allocator);
    view.string_buffer.deinit(allocator);
}

pub fn update(
    view: *BufferView,
    allocator: std.mem.Allocator,
    lines: []const Parser.Line,
    default_face: Parser.Face,
    padding_face: Parser.Face
) !void {
    view.default_face = default_face;
    view.padding_face = padding_face;

    view.lines.clearRetainingCapacity();
    view.atoms.clearRetainingCapacity();
    view.string_buffer.clearRetainingCapacity();

    var required_atoms: usize = 0;
    var required_bytes: usize = 0;
    for (lines) |line| {
        required_atoms += line.len;

        for (line) |atom| {
            required_bytes += atom.contents.len + 1;
        }
    }

    try view.lines.ensureTotalCapacity(allocator, lines.len);
    try view.atoms.ensureTotalCapacity(allocator, required_atoms);
    try view.string_buffer.ensureTotalCapacity(allocator, required_bytes);

    for (lines) |line| {
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
        view.lines.appendAssumeCapacity(view.atoms.items[l0..l1]);
    }
}

pub fn draw(view: *BufferView, tui: *Tui) void {
    const default_screen_attr = tui.faceToScreenAttr(view.default_face);

    var rows: usize = 0;
    var cols: usize = 0;
    arcan.arcan_tui_dimensions(tui.context, &rows, &cols);

    arcan.arcan_tui_eraseattr_region(
        tui.context, 0, 0, cols, rows-1,
        false, default_screen_attr
    );

    var line_index: usize = 0;
    for (view.lines.items) |line| {
        arcan.arcan_tui_move_to(tui.context, 0, line_index);
        tui.drawAtoms(line, view.default_face);
        line_index += 1;
    }

    // Draw padding space
    const face = Tui.mergeFaces(view.default_face, view.padding_face);
    const padding_atom = .{ Parser.Atom{ .contents = "~" } };

    arcan.arcan_tui_eraseattr_region(
        tui.context, 0, line_index, cols, rows-1,
        false, tui.faceToScreenAttr(face)
    );

    while (line_index < rows) {
        arcan.arcan_tui_move_to(tui.context, 0, line_index);
        tui.drawAtoms(&padding_atom, face);
        line_index += 1;
    }
}
