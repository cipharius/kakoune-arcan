const std = @import("std");
const Parser = @import("./Parser.zig");

const logger = std.log.scoped(.rpc_server);

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

pub fn receive(
    backing_allocator: std.mem.Allocator,
    message: []const u8
) Parser.Error!void {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    // Will be required for later
    _ = allocator;

    var parser = Parser.init(message);

    try parser.expectNextToken(.ObjectBegin);

    try parser.expectNextString("jsonrpc");
    try parser.expectNextString("2.0");

    try parser.expectNextString("method");
    const method_str = try parser.nextString();

    try parser.expectNextString("params");

    const method = std.meta.stringToEnum(Method, method_str) orelse .Unknown;
    switch (method) {
        .draw           => try handleDraw(&parser),
        .draw_status    => try handleDrawStatus(&parser),
        .menu_show      => try handleMenuShow(&parser),
        .menu_select    => try handleMenuSelect(&parser),
        .menu_hide      => try handleMenuHide(&parser),
        .info_show      => try handleInfoShow(&parser),
        .info_hide      => try handleInfoHide(&parser),
        .set_cursor     => try handleSetCursor(&parser),
        .set_ui_options => try handleSetUiOptions(&parser),
        .refresh        => try handleRefresh(&parser),
        .Unknown        => {
            logger.warn("Unknown method: {s}\n", .{message});
            try parser.skipParams();
        },
    }

    try parser.expectNextToken(.ObjectEnd);
}

fn handleDraw(parser: *Parser) Parser.Error!void {
    try parser.skipParams();

    logger.debug("draw(?)", .{});
}

fn handleDrawStatus(parser: *Parser) Parser.Error!void {
    try parser.skipParams();

    logger.debug("draw_status(?)", .{});
}

fn handleMenuShow(parser: *Parser) Parser.Error!void {
    try parser.skipParams();

    logger.debug("menu_show(?)", .{});
}

fn handleMenuSelect(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const selected = try parser.nextInt(u32);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("menu_select({})", .{selected});
}

fn handleMenuHide(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("menu_hide()", .{});
}

fn handleInfoShow(parser: *Parser) Parser.Error!void {
    try parser.skipParams();
}

fn handleInfoHide(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("info_hide()", .{});
}

fn handleSetCursor(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);

    const mode = std.meta.stringToEnum(
        SetCursorMode,
        try parser.nextString()
    ) orelse .Unknown;
    const coord = try parser.nextCoord();

    try parser.expectNextToken(.ArrayEnd);

    logger.debug("set_cursor({}, {})", .{mode, coord});
}

fn handleSetUiOptions(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ObjectBegin);

    logger.debug("set_ui_options({{", .{});
    while (true) {
        const key = switch (try parser.nextToken()) {
            .String => |t| t.slice(parser.message, parser.cursor - 1),
            .ObjectEnd => break,
            else => return Parser.Error.UnexpectedToken,
        };
        const value = try parser.nextString();
        logger.debug("\"{s}\" : \"{s}\",", .{key, value});
    }
    logger.debug("}})", .{});

    try parser.expectNextToken(.ArrayEnd);
}

fn handleRefresh(parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const force = try parser.nextBool();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("refresh({})", .{force});
}
