const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    const args = try std.process.argsAlloc(arena_allocator);

    const ui_override = block: {
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "-ui")) break :block true;
        }
        break :block false;
    };

    var kak_args: [][]const u8 = undefined;
    if (ui_override) {
        kak_args = try arena_allocator.alloc([]const u8, args.len);
        std.mem.copy([]const u8, kak_args[1..], args[1..]);
        kak_args[0] = "kak";
    } else {
        kak_args = try arena_allocator.alloc([]const u8, args.len + 2);
        std.mem.copy([]const u8, kak_args[3..], args[1..]);
        kak_args[0] = "kak";
        kak_args[1] = "-ui";
        kak_args[2] = "json";
    }

    var process = std.ChildProcess.init(kak_args, arena_allocator);
    try process.spawn();
    _ = try process.wait();
}
