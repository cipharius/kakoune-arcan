const std = @import("std");
const Parser = @import("./Parser.zig");
const TUI = @import("./TUI.zig");

allocator: std.mem.Allocator,
tui: *TUI,

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

pub fn init(allocator: std.mem.Allocator, tui: *TUI) @This() {
    return .{ .allocator = allocator, .tui = tui };
}

pub fn receive(
    server: *const @This(),
    message: []const u8
) Parser.Error!void {
    var parser = Parser.init(server.allocator, message);
    defer parser.deinit();

    try parser.expectNextToken(.ObjectBegin);

    try parser.expectNextString("jsonrpc");
    try parser.expectNextString("2.0");

    try parser.expectNextString("method");
    const method_str = try parser.nextString();

    try parser.expectNextString("params");

    const method = std.meta.stringToEnum(Method, method_str) orelse .Unknown;
    switch (method) {
        .draw           => try server.handleDraw(&parser),
        .draw_status    => try server.handleDrawStatus(&parser),
        .menu_show      => try server.handleMenuShow(&parser),
        .menu_select    => try server.handleMenuSelect(&parser),
        .menu_hide      => try server.handleMenuHide(&parser),
        .info_show      => try server.handleInfoShow(&parser),
        .info_hide      => try server.handleInfoHide(&parser),
        .set_cursor     => try server.handleSetCursor(&parser),
        .set_ui_options => try server.handleSetUiOptions(&parser),
        .refresh        => try server.handleRefresh(&parser),
        .Unknown        => {
            logger.warn("Unknown method: {s}\n", .{message});
            try parser.skipParams();
        },
    }

    try parser.expectNextToken(.ObjectEnd);
}

fn handleDraw(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const lines = try parser.nextLines();
    const default_face = try parser.nextFace();
    const padding_face = try parser.nextFace();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("draw(Lines#{}, {}, {})", .{lines.len, default_face, padding_face});
}

fn handleDrawStatus(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const status_line = try parser.nextLine();
    const mode_line = try parser.nextLine();
    const default_face = try parser.nextFace();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("draw_status(Atoms#{}, Atoms#{}, {})", .{status_line.len, mode_line.len, default_face});
}

fn handleMenuShow(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const items = try parser.nextLines();
    const anchor = try parser.nextCoord();
    const selected_item_face = try parser.nextFace();
    const menu_face = try parser.nextFace();
    const style = try parser.nextMenuStyle();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("menu_show(Lines#{}, {}, {}, {}, {})", .{
        items.len,
        anchor,
        selected_item_face,
        menu_face,
        style,
    });
}

fn handleMenuSelect(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const selected = try parser.nextInt(u32);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("menu_select({})", .{selected});
}

fn handleMenuHide(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("menu_hide()", .{});
}

fn handleInfoShow(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const title = try parser.nextLine();
    const content = try parser.nextLines();
    const anchor = try parser.nextCoord();
    const face = try parser.nextFace();
    const style = try parser.nextInfoStyle();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("info_show(Atoms#{}, Lines#{}, {}, {}, {})", .{
        title.len,
        content.len,
        anchor,
        face,
        style,
    });
}

fn handleInfoHide(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("info_hide()", .{});
}

fn handleSetCursor(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const mode = try parser.nextCursorMode();
    const coord = try parser.nextCoord();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("set_cursor({}, {})", .{mode, coord});
}

fn handleSetUiOptions(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    try parser.expectNextToken(.ObjectBegin);

    logger.debug("set_ui_options({{", .{});
    while (true) {
        const key = parser.nextString() catch |err| {
            if (err != Parser.Error.UnexpectedToken) return err;
            if (parser.last_token.? != .ObjectEnd) return err;
            break;
        };
        const value = try parser.nextString();
        logger.debug("\"{s}\" : \"{s}\",", .{key, value});
    }
    logger.debug("}})", .{});

    try parser.expectNextToken(.ArrayEnd);
}

fn handleRefresh(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.ArrayBegin);
    const force = try parser.nextBool();
    try parser.expectNextToken(.ArrayEnd);

    logger.debug("refresh({})", .{force});
}
