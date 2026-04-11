const std = @import("std");
const RpcServer = @import("./RpcServer.zig");
const TUI = @import("./Tui.zig");

const logger = std.log.scoped(.main);

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = handleSigint },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    }, null);

    const stdout = std.fs.File.stdout();
    var write_buffer: [4096]u8 = undefined;
    var stdout_buffer = stdout.writer(&write_buffer);
    const stdout_writer = &stdout_buffer.interface;

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
        std.mem.copyForwards([]const u8, kak_args[1..], args[1..]);
        kak_args[0] = "kak";
    } else {
        kak_args = try allocator.alloc([]const u8, args.len + 2);
        std.mem.copyForwards([]const u8, kak_args[3..], args[1..]);
        kak_args[0] = "kak";
        kak_args[1] = "-ui";
        kak_args[2] = "json";
    }
    defer allocator.free(kak_args);

    var kak_process = std.process.Child.init(kak_args, allocator);
    kak_process.stdout_behavior = .Pipe;
    kak_process.stdin_behavior = .Pipe;
    kak_process.stderr_behavior = .Inherit;
    try kak_process.spawn();
    defer _ = kak_process.kill() catch {};

    var tui = TUI.init();
    defer tui.deinit(allocator);

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_stream = kak_process.stdout.?.reader(&stdin_buffer);
    var stdin_reader = &stdin_stream.interface;

    var channel_buffer: [4096]u8 = undefined;
    var channel = kak_process.stdin.?.writer(&channel_buffer);
    var server = RpcServer.init(allocator, tui, &channel.interface);

    tui.registerServer(&server);
    try tui.startEventThread();

    var line_buffer: std.Io.Writer.Allocating = .init(allocator);
    defer line_buffer.deinit();

    while (stdin_reader.streamDelimiter(&line_buffer.writer, '\n')) |bytes_read|
    : (line_buffer.clearRetainingCapacity()) {
        if (bytes_read == 0) continue;
        stdin_reader.toss(1);
        const line = line_buffer.written();

        if (line[0] != '{' or line[line.len-1] != '}') {
            try stdout_writer.print("{s}\n", .{line});
            try stdout_writer.flush();
            continue;
        }

        // server.receive(line.items) catch |err| {
        //     logger.warn("{}: {s}", .{err, line.items});
        // };
        std.log.debug("Line: {s}", .{line});
        try server.receive(line);
    } else |err| {
        if (err != error.EndOfStream) return err;
    }
}

fn handleSigint(_: c_int) callconv(.c) void {}

test {
    _ = @import("./Parser.zig");
}
