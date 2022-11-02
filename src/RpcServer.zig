const std = @import("std");
const json = std.json;

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

pub const Error = error {
    InvalidMessage,
    ParseError,
    UnexpectedToken,
    UnknownMethod,
};

pub fn evaluate(server: *@This(), message: []const u8) Error!void {
    server.initParser(message);

    try server.expectNextToken(.ObjectBegin);

    try server.expectNextString("jsonrpc");
    try server.expectNextString("2.0");

    try server.expectNextString("method");
    const method_str = try server.nextString();

    try server.expectNextString("params");
    try server.expectNextToken(.ArrayBegin);

    const method = std.meta.stringToEnum(Method, method_str) orelse .Unknown;
    switch (method) {
        .draw => std.debug.print("Draw\n", .{}),
        .draw_status => std.debug.print("DrawStatus\n", .{}),
        .menu_show => std.debug.print("MenuShow\n", .{}),
        .menu_select => std.debug.print("MenuSelect\n", .{}),
        .menu_hide => std.debug.print("MenuHide\n", .{}),
        .info_show => std.debug.print("InfoShow\n", .{}),
        .info_hide => std.debug.print("InfoHide\n", .{}),
        .set_cursor => std.debug.print("SetCursor\n", .{}),
        .set_ui_options => std.debug.print("SetUiOptions\n", .{}),
        .refresh => std.debug.print("Refresh\n", .{}),
        .Unknown => {
            std.debug.print("Unknown method: {s}\n", .{message});
        },
    }
    try server.skipParams();

    try server.expectNextToken(.ObjectEnd);
}

fn initParser(server: *@This(), message: []const u8) void {
    server.parser = std.json.StreamingParser.init();
    server.message = message;
    server.cursor = 0;
}

fn skipParams(server: *@This()) Error!void {
    var d: u8 = 1;
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

fn nextString(server: *@This()) Error![]const u8 {
    return switch (try server.nextToken()) {
        // Fetching token advances cursor, so step one char back
        .String => |token| token.slice(server.message.?, server.cursor - 1),
        else => Error.UnexpectedToken,
    };
}

fn expectNextToken(server: *@This(), comptime token: json.Token) Error!void {
    if (std.meta.activeTag(try server.nextToken()) == token) return;
    return Error.UnexpectedToken;
}

fn expectNextString(server: *@This(), str: []const u8) Error!void {
    if (std.mem.eql(u8, try server.nextString(), str)) return;
    return Error.UnexpectedToken;
}
