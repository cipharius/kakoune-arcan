const std = @import("std");
const json = std.json;

message: []const u8,
arena: std.heap.ArenaAllocator,
cursor: usize = 0,
json_parser: json.StreamingParser = json.StreamingParser.init(),
spare_token: ?json.Token = null,
last_token: ?json.Token = null,

pub const Coord = struct {
    line: usize,
    column: usize,
};

pub const Attribute = enum {
    underline,
    reverse,
    blink,
    bold,
    dim,
    italic,
    final_fg,
    final_bg,
    final_attr,
    strikethrough,
    Unknown
};

pub const MenuStyle = enum {
    prompt,
    search,
    @"inline",
    Unknown,
};

pub const InfoStyle = enum {
    prompt,
    @"inline",
    inlineAbove,
    inlineBelow,
    menuDoc,
    modal,
    Unknown,
};

pub const CursorMode = enum {
    prompt,
    buffer,
    Unknown,
};

pub const ColorName = enum {
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    @"bright-black",
    @"bright-red",
    @"bright-green",
    @"bright-yellow",
    @"bright-blue",
    @"bright-magenta",
    @"bright-cyan",
    @"bright-white",
    Unknown,
};

pub const Color = union(enum) {
    name: ColorName,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const Face = struct {
    fg: Color = .{ .name = .default },
    bg: Color = .{ .name = .default },
    underline: Color = .{ .name = .default },
    attributes: std.EnumSet(Attribute) = .{},
};

pub const Atom = struct {
    face: Face = .{},
    contents: [:0]const u8,
};

pub const Line = []Atom;

pub const Error = error {
    InvalidMessage,
    ParseError,
    UnexpectedToken,
    UnknownMethod,
    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, message: []const u8) @This() {
    return .{
        .message = message,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(parser: *@This()) void {
    parser.arena.deinit();
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
        parser.last_token = token;
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

    parser.last_token = toks[0].?;
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

pub fn nextAttribute(parser: *@This()) Error!Attribute {
    const str = try parser.nextString();
    return std.meta.stringToEnum(Attribute, str) orelse .Unknown;
}

pub fn nextMenuStyle(parser: *@This()) Error!MenuStyle {
    const str = try parser.nextString();
    return std.meta.stringToEnum(MenuStyle, str) orelse .Unknown;
}

pub fn nextInfoStyle(parser: *@This()) Error!InfoStyle {
    const str = try parser.nextString();
    return std.meta.stringToEnum(InfoStyle, str) orelse .Unknown;
}

pub fn nextCursorMode(parser: *@This()) Error!CursorMode {
    const str = try parser.nextString();
    return std.meta.stringToEnum(CursorMode, str) orelse .Unknown;
}

pub fn nextColor(parser: *@This()) Error!Color {
    const str = try parser.nextString();

    const hex = block: {
        if (std.mem.startsWith(u8, str, "rgb:")) {
            break :block str[4..];
        } else if (std.mem.startsWith(u8, str, "#")) {
            break :block str[1..];
        } else {
            return Color{
                .name = std.meta.stringToEnum(ColorName, str) orelse .Unknown
            };
        }
    };

    const rgb = .{
        .r = std.fmt.parseInt(u8, hex[0..2], 16) catch return Error.ParseError,
        .g = std.fmt.parseInt(u8, hex[2..4], 16) catch return Error.ParseError,
        .b = std.fmt.parseInt(u8, hex[4..6], 16) catch return Error.ParseError,
    };

    return Color{ .rgb = rgb };
}

test "nextColor" {
    const msg = "[\"rgb:ff00aa\", \"#00ffbb\", \"default\"]";
    var parser = @This().init(std.testing.allocator, msg);
    defer parser.deinit();

    try parser.expectNextToken(.ArrayBegin);

    try std.testing.expectEqual(
        Color{ .rgb = .{.r = 0xff, .g = 0x00, .b = 0xaa} },
        try parser.nextColor()
    );

    try std.testing.expectEqual(
        Color{ .rgb = .{.r = 0x00, .g = 0xff, .b = 0xbb} },
        try parser.nextColor()
    );

    const namedColor = try parser.nextColor();
    try std.testing.expectEqualStrings("default", namedColor.name);

    try parser.expectNextToken(.ArrayEnd);
}

pub fn nextFace(parser: *@This()) Error!Face {
    try parser.expectNextToken(.ObjectBegin);

    try parser.expectNextString("fg");
    const fg = try parser.nextColor();

    try parser.expectNextString("bg");
    const bg = try parser.nextColor();

    try parser.expectNextString("underline");
    const underline = try parser.nextColor();

    try parser.expectNextString("attributes");
    try parser.expectNextToken(.ArrayBegin);

    var attributes = std.EnumSet(Attribute){};

    while (true) {
        const attribute = parser.nextAttribute() catch |err| {
            if (err != Error.UnexpectedToken) return err;
            if (parser.last_token.? != .ArrayEnd) return err;
            break;
        };
        attributes.insert(attribute);
    }

    try parser.expectNextToken(.ObjectEnd);

    return .{
        .fg = fg,
        .bg = bg,
        .underline = underline,
        .attributes = attributes,
    };
}

test "nextFace" {
    const msg =
        \\{
        \\"fg":"default",
        \\"bg":"#aabbcc",
        \\"underline":"#123456",
        \\"attributes":["bold", "underline"]
        \\}
    ;
    var parser = @This().init(std.testing.allocator, msg);
    defer parser.deinit();

    const face = try parser.nextFace();

    try std.testing.expectEqualStrings("default", face.fg.name);
    try std.testing.expectEqual(
        Color{ .rgb = .{.r = 0xaa, .g = 0xbb, .b = 0xcc} },
        face.bg
    );
    try std.testing.expectEqual(
        Color{ .rgb = .{.r = 0x12, .g = 0x34, .b = 0x56} },
        face.underline
    );

    try std.testing.expectEqual(@as(usize, 2), face.attributes.count());
    try std.testing.expect(face.attributes.contains(.bold));
    try std.testing.expect(face.attributes.contains(.underline));
}

pub fn nextAtom(parser: *@This()) Error!Atom {
    try parser.expectNextToken(.ObjectBegin);

    try parser.expectNextString("face");
    const face = try parser.nextFace();

    try parser.expectNextString("contents");
    const contents = try parser.nextString();

    try parser.expectNextToken(.ObjectEnd);

    const allocator = parser.arena.allocator();
    var contents_owned = allocator.allocSentinel(u8, contents.len, 0)
        catch return Error.OutOfMemory;

    for (contents) |char, i| {
        contents_owned[i] = char;
    }

    return .{ .face = face, .contents = contents_owned };
}

pub fn nextLine(parser: *@This()) Error!Line {
    try parser.expectNextToken(.ArrayBegin);

    const allocator = parser.arena.allocator();
    var atoms = std.ArrayList(Atom).init(allocator);

    while (true) {
        const atom = parser.nextAtom() catch |err| {
            if (err != Error.UnexpectedToken) return err;
            if (parser.last_token.? != .ArrayEnd) return err;
            break;
        };
        atoms.append(atom) catch return Error.OutOfMemory;
    }

    return atoms.toOwnedSlice();
}

test "nextLine" {
    const msg =
        \\[
        \\{"face":{"fg":"default", "bg":"default", "underline":"default", "attributes":[]}, "contents":"hello "},
        \\{"face":{"fg":"default", "bg":"default", "underline":"default", "attributes":["underline"]}, "contents":"world!"}
        \\]
    ;
    var parser = @This().init(std.testing.allocator, msg);
    defer parser.deinit();

    const line = try parser.nextLine();

    try std.testing.expectEqual(@as(usize, 2), line.len);
    try std.testing.expectEqualStrings("hello ", line[0].contents);
    try std.testing.expectEqualStrings("world!", line[1].contents);

    try std.testing.expectEqual(@as(usize, 0), line[0].face.attributes.count());
    try std.testing.expectEqual(@as(usize, 1), line[1].face.attributes.count());
    try std.testing.expect(line[1].face.attributes.contains(.underline));
}

pub fn nextLines(parser: *@This()) Error![]Line {
    try parser.expectNextToken(.ArrayBegin);

    const allocator = parser.arena.allocator();
    var lines = std.ArrayList(Line).init(allocator);

    while (true) {
        const line = parser.nextLine() catch |err| {
            if (err != Error.UnexpectedToken) return err;
            if (parser.last_token.? != .ArrayEnd) return err;
            break;
        };
        lines.append(line) catch return Error.OutOfMemory;
    }

    return lines.toOwnedSlice();
}

pub fn expectNextToken(parser: *@This(), comptime token: json.Token) Error!void {
    if (std.meta.activeTag(try parser.nextToken()) == token) return;
    return Error.UnexpectedToken;
}

pub fn expectNextString(parser: *@This(), str: []const u8) Error!void {
    if (std.mem.eql(u8, try parser.nextString(), str)) return;
    return Error.UnexpectedToken;
}
