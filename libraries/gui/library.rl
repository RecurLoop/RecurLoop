// =============================================================================
// RecurLoop GUI toolkit.
//
// Public widget/layout/event API is source-defined in RecurLoop.  GTK3 is the
// first native backend and is deliberately hidden behind Gui:* so applications
// never depend on GTK symbols directly.  A future backend can replace these
// functions without changing application source.
// =============================================================================

languagekit_native_begin

link shared "c"
link shared "gtk-3"

let Gui = phrase { dictionary = true permanent = true }
let Gui:Backend = phrase { dictionary = true permanent = true }
let Gui:Key = phrase { dictionary = true permanent = true }
let Gui:Modifier = phrase { dictionary = true permanent = true }

let Gui:Signal = fn (widget:u8*, data:u8*) -> void
let Gui:Timer = fn (data:u8*) -> i32

// -----------------------------------------------------------------------------
// Native GTK3 backend.  Keep every backend symbol private to this library.
// Application code should only call Gui:* wrappers below.
// -----------------------------------------------------------------------------

extern gtk_init_check(argc:i32*, argv:u8***) -> i32 abi sysv-amd64
extern gtk_window_new(kind:i32) -> u8* abi sysv-amd64
extern gtk_window_set_title(window:u8*, title:u8*) -> void abi sysv-amd64
extern gtk_window_set_default_size(window:u8*, width:i32, height:i32) -> void abi sysv-amd64
extern gtk_box_new(orientation:i32, spacing:i32) -> u8* abi sysv-amd64
extern gtk_paned_new(orientation:i32) -> u8* abi sysv-amd64
extern gtk_paned_pack1(paned:u8*, child:u8*, resize:i32, shrink:i32) -> void abi sysv-amd64
extern gtk_paned_pack2(paned:u8*, child:u8*, resize:i32, shrink:i32) -> void abi sysv-amd64
extern gtk_paned_set_position(paned:u8*, position:i32) -> void abi sysv-amd64
extern gtk_scrolled_window_new(hadjustment:u8*, vadjustment:u8*) -> u8* abi sysv-amd64
extern gtk_scrolled_window_set_policy(window:u8*, horizontal:i32, vertical:i32) -> void abi sysv-amd64
extern gtk_container_add(container:u8*, child:u8*) -> void abi sysv-amd64
extern gtk_box_pack_start(box:u8*, child:u8*, expand:i32, fill:i32, padding:u32) -> void abi sysv-amd64
extern gtk_box_pack_end(box:u8*, child:u8*, expand:i32, fill:i32, padding:u32) -> void abi sysv-amd64
extern gtk_label_new(text:u8*) -> u8* abi sysv-amd64
extern gtk_label_set_text(label:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_label_set_xalign(label:u8*, x:f32) -> void abi sysv-amd64
extern gtk_button_new_with_label(text:u8*) -> u8* abi sysv-amd64
extern gtk_text_view_new() -> u8* abi sysv-amd64
extern gtk_text_view_get_buffer(view:u8*) -> u8* abi sysv-amd64
extern gtk_text_view_set_monospace(view:u8*, monospace:i32) -> void abi sysv-amd64
extern gtk_text_view_set_editable(view:u8*, editable:i32) -> void abi sysv-amd64
extern gtk_text_view_set_cursor_visible(view:u8*, visible:i32) -> void abi sysv-amd64
extern gtk_text_buffer_set_text(buffer:u8*, text:u8*, bytes:i32) -> void abi sysv-amd64
extern gtk_text_buffer_get_start_iter(buffer:u8*, iterator:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_get_end_iter(buffer:u8*, iterator:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_get_text(buffer:u8*, start:u8*, finish:u8*, include_hidden:i32) -> u8* abi sysv-amd64
extern gtk_entry_new() -> u8* abi sysv-amd64
extern gtk_entry_set_placeholder_text(entry:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_entry_get_text(entry:u8*) -> u8* abi sysv-amd64
extern gtk_entry_set_text(entry:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_notebook_new() -> u8* abi sysv-amd64
extern gtk_notebook_append_page(notebook:u8*, child:u8*, tab:u8*) -> i32 abi sysv-amd64
extern gtk_notebook_set_current_page(notebook:u8*, page:i32) -> void abi sysv-amd64
extern gtk_notebook_set_scrollable(notebook:u8*, scrollable:i32) -> void abi sysv-amd64
extern gtk_widget_set_hexpand(widget:u8*, expand:i32) -> void abi sysv-amd64
extern gtk_widget_set_vexpand(widget:u8*, expand:i32) -> void abi sysv-amd64
extern gtk_widget_show_all(widget:u8*) -> void abi sysv-amd64
extern gtk_widget_grab_focus(widget:u8*) -> void abi sysv-amd64
extern gtk_widget_destroy(widget:u8*) -> void abi sysv-amd64
extern gtk_accel_group_new() -> u8* abi sysv-amd64
extern gtk_window_add_accel_group(window:u8*, group:u8*) -> void abi sysv-amd64
extern gtk_widget_add_accelerator(widget:u8*, signal:u8*, group:u8*, key:u32, modifiers:u32, flags:u32) -> void abi sysv-amd64
extern gtk_main() -> void abi sysv-amd64
extern gtk_main_quit() -> void abi sysv-amd64
extern g_signal_connect_data(instance:u8*, signal:u8*, callback:Gui:Signal, data:u8*, destroy:u8*, flags:u32) -> u64 abi sysv-amd64
extern g_timeout_add(interval:u32, callback:Gui:Timer, data:u8*) -> u32 abi sysv-amd64
extern g_free(value:u8*) -> void abi sysv-amd64

let Gui:Backend:name = fn () -> u8* { return "gtk3" }

// -----------------------------------------------------------------------------
// Application lifecycle and windows.
// -----------------------------------------------------------------------------

let Gui:initialize = fn () -> i64 {
    return gtk_init_check(cast(i32*, 0), cast(u8***, 0)) != 0
}

let Gui:window = fn (title:u8*, width:i32, height:i32) -> u8* {
    let result = gtk_window_new(0)
    if !result { return cast(u8*, 0) }
    if title { gtk_window_set_title(result, title) }
    gtk_window_set_default_size(result, width, height)
    return result
}

let Gui:window_title = fn (window:u8*, title:u8*) -> void {
    if window && title { gtk_window_set_title(window, title) }
}

let Gui:window_size = fn (window:u8*, width:i32, height:i32) -> void {
    if window { gtk_window_set_default_size(window, width, height) }
}

let Gui:run = fn () -> void { gtk_main() }
let Gui:quit = fn () -> void { gtk_main_quit() }
let Gui:show = fn (widget:u8*) -> void { if widget { gtk_widget_show_all(widget) } }
let Gui:destroy = fn (widget:u8*) -> void { if widget { gtk_widget_destroy(widget) } }
let Gui:focus = fn (widget:u8*) -> void { if widget { gtk_widget_grab_focus(widget) } }

// -----------------------------------------------------------------------------
// Layout primitives.  The application owns composition; the backend only
// materializes it.
// -----------------------------------------------------------------------------

let Gui:row = fn (spacing:i32) -> u8* { return gtk_box_new(0, spacing) }
let Gui:column = fn (spacing:i32) -> u8* { return gtk_box_new(1, spacing) }
let Gui:split_horizontal = fn () -> u8* { return gtk_paned_new(0) }
let Gui:split_vertical = fn () -> u8* { return gtk_paned_new(1) }

let Gui:split_first = fn (split:u8*, child:u8*, grow:i64) -> void {
    if split && child { gtk_paned_pack1(split, child, grow != 0, 0) }
}

let Gui:split_second = fn (split:u8*, child:u8*, grow:i64) -> void {
    if split && child { gtk_paned_pack2(split, child, grow != 0, 0) }
}

let Gui:split_position = fn (split:u8*, position:i32) -> void {
    if split { gtk_paned_set_position(split, position) }
}

let Gui:add = fn (container:u8*, child:u8*) -> void {
    if container && child { gtk_container_add(container, child) }
}

let Gui:append = fn (box:u8*, child:u8*, grow:i64, padding:u32) -> void {
    if box && child { gtk_box_pack_start(box, child, grow != 0, 1, padding) }
}

let Gui:append_end = fn (box:u8*, child:u8*, grow:i64, padding:u32) -> void {
    if box && child { gtk_box_pack_end(box, child, grow != 0, 1, padding) }
}

let Gui:expand_x = fn (widget:u8*, enabled:i64) -> void {
    if widget { gtk_widget_set_hexpand(widget, enabled != 0) }
}

let Gui:expand_y = fn (widget:u8*, enabled:i64) -> void {
    if widget { gtk_widget_set_vexpand(widget, enabled != 0) }
}

let Gui:scroll = fn (child:u8*) -> u8* {
    let result = gtk_scrolled_window_new(cast(u8*, 0), cast(u8*, 0))
    if !result { return cast(u8*, 0) }
    gtk_scrolled_window_set_policy(result, 1, 1)
    if child { gtk_container_add(result, child) }
    return result
}

// -----------------------------------------------------------------------------
// Basic widgets.
// -----------------------------------------------------------------------------

let Gui:label = fn (text:u8*) -> u8* { return gtk_label_new(text) }
let Gui:label_text = fn (label:u8*, text:u8*) -> void {
    if label && text { gtk_label_set_text(label, text) }
}
let Gui:label_align = fn (label:u8*, x:f32) -> void {
    if label { gtk_label_set_xalign(label, x) }
}

let Gui:button = fn (text:u8*) -> u8* { return gtk_button_new_with_label(text) }

let Gui:editor = fn () -> u8* {
    let result = gtk_text_view_new()
    if result { gtk_text_view_set_monospace(result, 1) }
    return result
}

let Gui:text_view = fn () -> u8* {
    let result = gtk_text_view_new()
    if result {
        gtk_text_view_set_monospace(result, 1)
        gtk_text_view_set_editable(result, 0)
        gtk_text_view_set_cursor_visible(result, 0)
    }
    return result
}

let Gui:text_set = fn (view:u8*, text:u8*) -> void {
    if !view { return }
    let buffer = gtk_text_view_get_buffer(view)
    if buffer { gtk_text_buffer_set_text(buffer, text, -1) }
}

// Returned memory is owned by GLib; release it with Gui:text_free.
let Gui:text_get = fn (view:u8*) -> u8* {
    if !view { return cast(u8*, 0) }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return cast(u8*, 0) }
    let first = malloc(128)
    let last = malloc(128)
    if !first || !last {
        if first { free(first) }
        if last { free(last) }
        return cast(u8*, 0)
    }
    gtk_text_buffer_get_start_iter(buffer, first)
    gtk_text_buffer_get_end_iter(buffer, last)
    let result = gtk_text_buffer_get_text(buffer, first, last, 1)
    free(first)
    free(last)
    return result
}

let Gui:text_free = fn (text:u8*) -> void { if text { g_free(text) } }

let Gui:input = fn (placeholder:u8*) -> u8* {
    let result = gtk_entry_new()
    if result && placeholder { gtk_entry_set_placeholder_text(result, placeholder) }
    return result
}

let Gui:input_text = fn (input:u8*) -> u8* {
    if !input { return cast(u8*, 0) }
    return gtk_entry_get_text(input)
}

let Gui:input_set = fn (input:u8*, text:u8*) -> void {
    if input && text { gtk_entry_set_text(input, text) }
}

let Gui:tabs = fn () -> u8* {
    let result = gtk_notebook_new()
    if result { gtk_notebook_set_scrollable(result, 1) }
    return result
}

let Gui:tabs_append = fn (tabs:u8*, child:u8*, title:u8*) -> i32 {
    if !tabs || !child { return -1 }
    let label = gtk_label_new(title)
    return gtk_notebook_append_page(tabs, child, label)
}

let Gui:tabs_select = fn (tabs:u8*, page:i32) -> void {
    if tabs { gtk_notebook_set_current_page(tabs, page) }
}

// -----------------------------------------------------------------------------
// Events, timers and shortcuts.
// -----------------------------------------------------------------------------

let Gui:on_click = fn (widget:u8*, callback:Gui:Signal, data:u8*) -> u64 {
    if !widget { return 0 }
    return g_signal_connect_data(widget, "clicked", callback, data, cast(u8*, 0), 0)
}

let Gui:on_activate = fn (widget:u8*, callback:Gui:Signal, data:u8*) -> u64 {
    if !widget { return 0 }
    return g_signal_connect_data(widget, "activate", callback, data, cast(u8*, 0), 0)
}

let Gui:on_destroy = fn (widget:u8*, callback:Gui:Signal, data:u8*) -> u64 {
    if !widget { return 0 }
    return g_signal_connect_data(widget, "destroy", callback, data, cast(u8*, 0), 0)
}

let Gui:timer = fn (interval_ms:u32, callback:Gui:Timer, data:u8*) -> u32 {
    return g_timeout_add(interval_ms, callback, data)
}

let Gui:Key:S = fn () -> u32 { return 115 }
let Gui:Modifier:Control = fn () -> u32 { return 4 }

let Gui:shortcut_click = fn (window:u8*, button:u8*, key:u32, modifiers:u32) -> void {
    if !window || !button { return }
    let group = gtk_accel_group_new()
    if !group { return }
    gtk_window_add_accel_group(window, group)
    gtk_widget_add_accelerator(button, "clicked", group, key, modifiers, 1)
}

// Native symbols are implementation details and must be rebound from the
// backend shared library when an image is imported.
set gtk_init_check.serializable = false
set gtk_window_new.serializable = false
set gtk_window_set_title.serializable = false
set gtk_window_set_default_size.serializable = false
set gtk_box_new.serializable = false
set gtk_paned_new.serializable = false
set gtk_paned_pack1.serializable = false
set gtk_paned_pack2.serializable = false
set gtk_paned_set_position.serializable = false
set gtk_scrolled_window_new.serializable = false
set gtk_scrolled_window_set_policy.serializable = false
set gtk_container_add.serializable = false
set gtk_box_pack_start.serializable = false
set gtk_box_pack_end.serializable = false
set gtk_label_new.serializable = false
set gtk_label_set_text.serializable = false
set gtk_label_set_xalign.serializable = false
set gtk_button_new_with_label.serializable = false
set gtk_text_view_new.serializable = false
set gtk_text_view_get_buffer.serializable = false
set gtk_text_view_set_monospace.serializable = false
set gtk_text_view_set_editable.serializable = false
set gtk_text_view_set_cursor_visible.serializable = false
set gtk_text_buffer_set_text.serializable = false
set gtk_text_buffer_get_start_iter.serializable = false
set gtk_text_buffer_get_end_iter.serializable = false
set gtk_text_buffer_get_text.serializable = false
set gtk_entry_new.serializable = false
set gtk_entry_set_placeholder_text.serializable = false
set gtk_entry_get_text.serializable = false
set gtk_entry_set_text.serializable = false
set gtk_notebook_new.serializable = false
set gtk_notebook_append_page.serializable = false
set gtk_notebook_set_current_page.serializable = false
set gtk_notebook_set_scrollable.serializable = false
set gtk_widget_set_hexpand.serializable = false
set gtk_widget_set_vexpand.serializable = false
set gtk_widget_show_all.serializable = false
set gtk_widget_grab_focus.serializable = false
set gtk_widget_destroy.serializable = false
set gtk_accel_group_new.serializable = false
set gtk_window_add_accel_group.serializable = false
set gtk_widget_add_accelerator.serializable = false
set gtk_main.serializable = false
set gtk_main_quit.serializable = false
set g_signal_connect_data.serializable = false
set g_timeout_add.serializable = false
set g_free.serializable = false

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
