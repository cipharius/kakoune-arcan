const std = @import("std");
const json = std.json;

const logger = std.log.scoped(.rpc_server);

parser: json.StreamingParser = json.StreamingParser.init(),
message: ?[]const u8 = null,
cursor: usize = 0,
spare_token: ?json.Token = null,

const KeyValuePair = struct {
    key: []const u8,
    value: []const u8
};

pub fn init() @This() {
    return .{};
}

pub const Coord = struct {
    line: usize,
    column: usize,
};

pub const Method = enum {
    draw,
    draw_status,
    menu_show,
    menu_select,
    menu_hide,
    info_show,
    info_hide,
    set_cursor,
    set_ui_options,
    refresh,
    Unknown,
};

pub const SetCursorMode = enum {
    prompt,
    buffer,
    Unknown,
};

pub const Error = error {
    InvalidMessage,
    ParseError,
    UnexpectedToken,
    UnknownMethod,
};

pub fn evaluate(
    server: *@This(),
    backing_allocator: std.mem.Allocator,
    message: []const u8
) Error!void {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    // Will be required for later
    _ = allocator;

    server.initParser(message);

    try server.expectNextToken(.ObjectBegin);

    try server.expectNextString("jsonrpc");
    try server.expectNextString("2.0");

    try server.expectNextString("method");
    const method_str = try server.nextString();

    try server.expectNextString("params");

    const method = std.meta.stringToEnum(Method, method_str) orelse .Unknown;
    switch (method) {
        .draw           => try server.handleDraw(),
        .draw_status    => try server.handleDrawStatus(),
        .menu_show      => try server.handleMenuShow(),
        .menu_select    => try server.handleMenuSelect(),
        .menu_hide      => try server.handleMenuHide(),
        .info_show      => try server.handleInfoShow(),
        .info_hide      => try server.handleInfoHide(),
        .set_cursor     => try server.handleSetCursor(),
        .set_ui_options => try server.handleSetUiOptions(),
        .refresh        => try server.handleRefresh(),
        .Unknown        => {
            logger.warn("Unknown method: {s}\n", .{message});
            try server.skipParams();
        },
    }

    try server.expectNextToken(.ObjectEnd);
}

fn handleDraw(server: *@This()) Error!void {
    try server.skipParams();

    logger.debug("draw(?)", .{});
}

fn handleDrawStatus(server: *@This()) Error!void {
    try server.skipParams();

    logger.debug("draw_status(?)", .{});
}

fn handleMenuShow(server: *@This()) Error!void {
    try server.skipParams();

    logger.debug("menu_show(?)", .{});
}

fn handleMenuSelect(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);
    const selected = try server.nextInt(u32);
    try server.expectNextToken(.ArrayEnd);

    logger.debug("menu_select({})", .{selected});
}

fn handleMenuHide(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);
    try server.expectNextToken(.ArrayEnd);

    logger.debug("menu_hide()", .{});
}

fn handleInfoShow(server: *@This()) Error!void {
    try server.skipParams();
}

fn handleInfoHide(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);
    try server.expectNextToken(.ArrayEnd);

    logger.debug("info_hide()", .{});
}

fn handleSetCursor(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);

    const mode = std.meta.stringToEnum(
        SetCursorMode,
        try server.nextString()
    ) orelse .Unknown;
    const coord = try server.nextCoord();

    try server.expectNextToken(.ArrayEnd);

    logger.debug("set_cursor({}, {})", .{mode, coord});
}

fn handleSetUiOptions(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);
    try server.expectNextToken(.ObjectBegin);

    logger.debug("set_ui_options({{", .{});
    while (true) {
        const key = switch (try server.nextToken()) {
            .String => |t| t.slice(server.message.?, server.cursor - 1),
            .ObjectEnd => break,
            else => return Error.UnexpectedToken,
        };
        const value = try server.nextString();
        logger.debug("\"{s}\" : \"{s}\",", .{key, value});
    }
    logger.debug("}})", .{});

    try server.expectNextToken(.ArrayEnd);

}

fn handleRefresh(server: *@This()) Error!void {
    try server.expectNextToken(.ArrayBegin);
    const force = try server.nextBool();
    try server.expectNextToken(.ArrayEnd);

    logger.debug("refresh({})", .{force});
}

fn initParser(server: *@This(), message: []const u8) void {
    server.parser = std.json.StreamingParser.init();
    server.message = message;
    server.cursor = 0;
}

fn skipParams(server: *@This()) Error!void {
    var d: u8 = 0;
    while (true) {
        const tok = try server.nextToken();

        switch (tok) {
            .ArrayBegin => d += 1,
            .ArrayEnd => {
                d -= 1;
                if (d == 0) break;
            },
            else => {},
        }
    }
}

fn nextToken(server: *@This()) Error!json.Token {
    if (server.spare_token) |token| {
        server.spare_token = null;
        return token;
    }

    var toks: [2]?json.Token = .{null, null};
    while (toks[0] == null) : (server.cursor += 1) {
        server.parser.feed(
            server.message.?[server.cursor],
            &toks[0],
            &toks[1]
        ) catch return Error.ParseError;
    }

    if (toks[1] != null) {
        server.spare_token = toks[1];
    }

    return toks[0].?;
}

fn nextInt(server: *@This(), comptime T: type) Error!T {
    const token = switch (try server.nextToken()) {
        .Number => |token| token,
        else => return Error.UnexpectedToken,
    };
    if (!token.is_integer) return Error.UnexpectedToken;
    const slice = token.slice(server.message.?, server.cursor - 1);
    return std.fmt.parseInt(T, slice, 10) catch Error.ParseError;
}

fn nextBool(server: *@This()) Error!bool {
    return switch (try server.nextToken()) {
        .True => true,
        .False => false,
        else => Error.UnexpectedToken,
    };
}

fn nextString(server: *@This()) Error![]const u8 {
    return switch (try server.nextToken()) {
        .String => |token| token.slice(server.message.?, server.cursor - 1),
        else => Error.UnexpectedToken,
    };
}

fn nextCoord(server: *@This()) Error!Coord {
    try server.expectNextToken(.ObjectBegin);

    try server.expectNextString("line");
    const line = try server.nextInt(usize);

    try server.expectNextString("column");
    const column = try server.nextInt(usize);

    try server.expectNextToken(.ObjectEnd);

    return .{ .line = line, .column = column };
}

fn expectNextToken(server: *@This(), comptime token: json.Token) Error!void {
    if (std.meta.activeTag(try server.nextToken()) == token) return;
    return Error.UnexpectedToken;
}

fn expectNextString(server: *@This(), str: []const u8) Error!void {
    if (std.mem.eql(u8, try server.nextString(), str)) return;
    return Error.UnexpectedToken;
}
