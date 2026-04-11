const std = @import("std");
const Parser = @import("./Parser.zig");
const Tui = @import("./Tui.zig");

const RpcServer = @This();

allocator: std.mem.Allocator,
tui: *Tui,
channel: *std.io.Writer,

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

const Error = Parser.Error || Tui.Error || error {
    WriteFail
};

pub fn init(
    allocator: std.mem.Allocator,
    tui: *Tui,
    channel: *std.io.Writer,
) RpcServer {
    return .{ .allocator = allocator, .tui = tui, .channel = channel };
}

pub fn sendKey(server: *RpcServer, key: []const u8) Error!void {
    var w = server.channel;

    w.writeAll("{ \"jsonrpc\": \"2.0\", \"method\": \"keys\", \"params\": [")
        catch |err| std.debug.panic("{}", .{err});//return Error.WriteFail;
    std.json.Stringify.encodeJsonString(key, .{}, w)
        catch |err| std.debug.panic("{}", .{err});// return Error.WriteFail;
    w.writeAll("] }")
        catch |err| std.debug.panic("{}", .{err});// return Error.WriteFail;

   w.flush() catch |err| std.debug.panic("{}", .{err});// return Error.WriteFail;
}

pub fn sendResize(server: *RpcServer, rows: usize, cols: usize) Error!void {
    var w = server.channel;

    w.print(
    \\{{ "jsonrpc": "2.0", "method": "resize", "params": [{}, {}] }}
    , .{rows, cols}) catch return Error.WriteFail;

    w.flush() catch return Error.WriteFail;
}

pub fn receive(
    server: *const RpcServer,
    message: []const u8
) Error!void {
    var parser = Parser.init(server.allocator, message);
    defer parser.deinit();

    try parser.expectNextToken(.object_begin);

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

    try parser.expectNextToken(.object_end);
}

fn handleDraw(server: *const @This(), parser: *Parser) Error!void {
    try parser.expectNextToken(.array_begin);
    const lines = try parser.nextLines();
    const default_face = try parser.nextFace();
    const padding_face = try parser.nextFace();
    try parser.expectNextToken(.array_end);

    try server.tui.buffer_view.update(server.allocator, lines, default_face, padding_face);
}

fn handleDrawStatus(server: *const @This(), parser: *Parser) Error!void {
    try parser.expectNextToken(.array_begin);
    const status_line = try parser.nextLine();
    const mode_line = try parser.nextLine();
    const default_face = try parser.nextFace();
    try parser.expectNextToken(.array_end);

    try server.tui.status_view.update(server.allocator, status_line, mode_line, default_face);
}

fn handleMenuShow(server: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    const items = try parser.nextLines();
    const anchor = try parser.nextCoord();
    const selected_item_face = try parser.nextFace();
    const menu_face = try parser.nextFace();
    const style = try parser.nextMenuStyle();
    try parser.expectNextToken(.array_end);

    try server.tui.menu_view.update(
        server.allocator,
        items,
        anchor,
        selected_item_face,
        menu_face,
        style
    );
}

fn handleMenuSelect(server: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    const selected = try parser.nextInt(u32);
    try parser.expectNextToken(.array_end);

    server.tui.menu_view.cursor = selected;
}

fn handleMenuHide(server: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    try parser.expectNextToken(.array_end);

    server.tui.menu_view.active = false;
}

fn handleInfoShow(server: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    const title = try parser.nextLine();
    const content = try parser.nextLines();
    const anchor = try parser.nextCoord();
    const face = try parser.nextFace();
    const style = try parser.nextInfoStyle();
    try parser.expectNextToken(.array_end);

    try server.tui.info_view.update(
        server.allocator,
        title,
        content,
        anchor,
        face,
        style
    );
}

fn handleInfoHide(server: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    try parser.expectNextToken(.array_end);

    server.tui.info_view.active = false;
}

fn handleSetCursor(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    const mode = try parser.nextCursorMode();
    const coord = try parser.nextCoord();
    try parser.expectNextToken(.array_end);

    logger.debug("set_cursor({}, {})", .{mode, coord});
}

fn handleSetUiOptions(_: *const @This(), parser: *Parser) Parser.Error!void {
    try parser.expectNextToken(.array_begin);
    try parser.expectNextToken(.object_begin);

    logger.debug("set_ui_options({{", .{});
    while (true) {
        const key = parser.nextString() catch |err| {
            if (err != Parser.Error.UnexpectedToken) return err;
            if (parser.last_token.? != .object_end) return err;
            break;
        };
        const value = try parser.nextString();
        logger.debug("\"{s}\" : \"{s}\",", .{key, value});
    }
    logger.debug("}})", .{});

    try parser.expectNextToken(.array_end);
}

fn handleRefresh(server: *const @This(), parser: *Parser) Error!void {
    try parser.expectNextToken(.array_begin);
    _ = try parser.nextToken(); // Force flag not required for Arcan TUI
    try parser.expectNextToken(.array_end);

    try server.tui.refresh();
}
