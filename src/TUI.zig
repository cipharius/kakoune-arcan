const std = @import("std");
const c = @cImport({
    @cInclude("arcan_shmif.h");
    @cInclude("arcan_tui.h");
});

connection: *c.arcan_tui_conn,
context: *c.tui_context,
callbacks: c.tui_cbcfg,

pub fn init() @This() {
    var tui = @This(){
        .connection = c.arcan_tui_open_display("Kakoune", ""),
        .context = undefined,
        .callbacks = std.mem.zeroes(c.tui_cbcfg),
    };

    tui.callbacks.tag = &tui;
    tui.context = c.arcan_tui_setup(
        tui.connection,
        null,
        &tui.callbacks,
        @sizeOf(c.tui_cbcfg)
    ).?;

    _ = c.arcan_tui_set_flags(tui.context, c.TUI_MOUSE_FULL | c.TUI_HIDE_CURSOR);

    return tui;
}

pub fn deinit(tui: *@This()) void {
    c.arcan_tui_destroy(tui.context, null);
}
