const std = @import("std");
const json = std.json;

message: []const u8,
cursor: usize = 0,
json_parser: json.StreamingParser = json.StreamingParser.init(),
spare_token: ?json.Token = null,

pub const Coord = struct {
    line: usize,
    column: usize,
};

pub const Error = error {
    InvalidMessage,
    ParseError,
    UnexpectedToken,
    UnknownMethod,
};

pub fn init(message: []const u8) @This() {
    return .{ .message = message };
}

pub fn skipParams(parser: *@This()) Error!void {
    var d: u8 = 0;
    while (true) {
        const tok = try parser.nextToken();

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

pub fn nextToken(parser: *@This()) Error!json.Token {
    if (parser.spare_token) |token| {
        parser.spare_token = null;
        return token;
    }

    var toks: [2]?json.Token = .{null, null};
    while (toks[0] == null) : (parser.cursor += 1) {
        parser.json_parser.feed(
            parser.message[parser.cursor],
            &toks[0],
            &toks[1]
        ) catch return Error.ParseError;
    }

    if (toks[1] != null) {
        parser.spare_token = toks[1];
    }

    return toks[0].?;
}

pub fn nextInt(parser: *@This(), comptime T: type) Error!T {
    const token = switch (try parser.nextToken()) {
        .Number => |token| token,
        else => return Error.UnexpectedToken,
    };
    if (!token.is_integer) return Error.UnexpectedToken;
    const slice = token.slice(parser.message, parser.cursor - 1);
    return std.fmt.parseInt(T, slice, 10) catch Error.ParseError;
}

pub fn nextBool(parser: *@This()) Error!bool {
    return switch (try parser.nextToken()) {
        .True => true,
        .False => false,
        else => Error.UnexpectedToken,
    };
}

pub fn nextString(parser: *@This()) Error![]const u8 {
    return switch (try parser.nextToken()) {
        .String => |token| token.slice(parser.message, parser.cursor - 1),
        else => Error.UnexpectedToken,
    };
}

pub fn nextCoord(parser: *@This()) Error!Coord {
    try parser.expectNextToken(.ObjectBegin);

    try parser.expectNextString("line");
    const line = try parser.nextInt(usize);

    try parser.expectNextString("column");
    const column = try parser.nextInt(usize);

    try parser.expectNextToken(.ObjectEnd);

    return .{ .line = line, .column = column };
}

pub fn expectNextToken(parser: *@This(), comptime token: json.Token) Error!void {
    if (std.meta.activeTag(try parser.nextToken()) == token) return;
    return Error.UnexpectedToken;
}

pub fn expectNextString(parser: *@This(), str: []const u8) Error!void {
    if (std.mem.eql(u8, try parser.nextString(), str)) return;
    return Error.UnexpectedToken;
}
