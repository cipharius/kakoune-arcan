# Kakoune Arcan frontend

Work in progress Kakoune frontend powered by Arcan TUI.

## Dependencies

* Zig compiler 0.10.0 (build dependency)
* Arcan

## Progress

* [x] Wrap kakoune binary
* [x] Parse kakoune JSON RPC requests
* [x] Implement user interaction
* [x] Render kakoune editor window
* [ ] Render suggestions menu popup
* [ ] Render info popup

## Design

The first prototype for Kakoune frontend was implemented by extending Kakoune source code with a custom UI logic, which could be selected with `-ui arcan` commandline option.
While it was simple to implement, keeping it up to date with upstream was unpractical, especially since Kakoune refactored terminal UI to drop ncurses dependency in result producing difficult to untangle merge conflict.

This time the custom frontend is based on Kakoune JSON RPC interface, which is designed for custom frontend purposes so hopefully it will be stable and remain compatible with future kakoune releases.
This requires additional logic for JSON serialization/deseralization layer, but in result it will decouple frontend from Kakoune and allow for simpler maintenance.

## Why Zig?

Besides the [reasons listed on the Zig homepage](https://ziglang.org/learn/why_zig_rust_d_cpp/), here are some of mine:

* Type system has a decent balance between simplicity and safety, without getting too much in the way;
* The standard library has lots of useful utilities that are written in pure Zig, making it independent of libc(not in this project's case, since dependency on arcan TUI is required);
* Increases awareness of memory management, since developer has to make decisions about which allocators to use and allows handling allocation errors;
* Has a small, dependency free and easy to acquire compiler;
* Elegant language design with focus on code readability and predictability.
