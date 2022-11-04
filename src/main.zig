const std = @import("std");
const RpcServer = @import("./RpcServer.zig");
const TUI = @import("./TUI.zig");

pub fn main() !void {
    var allocator = std.heap.c_allocator;

    try std.os.sigaction(std.os.SIG.INT, &.{
        .handler = .{ .handler = handleSigint },
        .mask = std.os.empty_sigset,
        .flags = 0,
    }, null);

    var stdout_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout_writer = stdout_buffer.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const ui_override = block: {
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "-ui")) break :block true;
        }
        break :block false;
    };

    var kak_args: [][]const u8 = undefined;
    if (ui_override) {
        kak_args = try allocator.alloc([]const u8, args.len);
        std.mem.copy([]const u8, kak_args[1..], args[1..]);
        kak_args[0] = "kak";
    } else {
        kak_args = try allocator.alloc([]const u8, args.len + 2);
        std.mem.copy([]const u8, kak_args[3..], args[1..]);
        kak_args[0] = "kak";
        kak_args[1] = "-ui";
        kak_args[2] = "json";
    }
    defer allocator.free(kak_args);

    var kak_process = std.ChildProcess.init(kak_args, allocator);
    kak_process.stdout_behavior = std.ChildProcess.StdIo.Pipe;
    try kak_process.spawn();
    defer _ = kak_process.kill() catch {};

    var stdin_stream = std.io.bufferedReader(kak_process.stdout.?.reader());
    var stdin_reader = stdin_stream.reader();

    var tui = TUI.init();
    defer tui.deinit();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    while (stdin_reader.readUntilDelimiterArrayList(&line, '\n', 4096))
    : (line.clearRetainingCapacity()) {
        if (line.items.len == 0) continue;
        if (line.items[0] != '{' or line.items[line.items.len-1] != '}') {
            try stdout_writer.print("{s}\n", .{line.items});
            try stdout_buffer.flush();
            continue;
        }

        try RpcServer.receive(allocator, line.items);
    } else |err| {
        if (err != error.EndOfStream) return err;
    }
}

fn handleSigint(_: c_int) callconv(.C) void {}

test {
    _ = @import("./Parser.zig");
}
