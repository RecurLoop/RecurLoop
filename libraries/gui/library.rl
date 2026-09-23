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
link shared "gdk-3"
// Gui:* calls GLib/GObject APIs directly. JIT can accidentally resolve these
// through GTK's already-loaded dependencies, but native executables must link
// their direct dependencies explicitly.
link shared "gobject-2.0"
link shared "glib-2.0"

let Gui = phrase { dictionary = true permanent = true }
let Gui:Backend = phrase { dictionary = true permanent = true }
let Gui:Key = phrase { dictionary = true permanent = true }
let Gui:Modifier = phrase { dictionary = true permanent = true }

let Gui:Signal = fn (widget:u8*, data:u8*) -> void
let Gui:Timer = fn (data:u8*) -> i32
let Gui:TooltipQuery = fn (widget:u8*, x:i32, y:i32, keyboard:i32, tooltip:u8*, data:u8*) -> i32

// -----------------------------------------------------------------------------
// Native GTK3 backend.  Keep every backend symbol private to this library.
// Application code should only call Gui:* wrappers below.
// -----------------------------------------------------------------------------

extern gtk_init_check(argc:i32*, argv:u8***) -> i32 abi sysv-amd64
extern gtk_window_new(kind:i32) -> u8* abi sysv-amd64
extern gtk_window_set_title(window:u8*, title:u8*) -> void abi sysv-amd64
extern gtk_window_set_default_size(window:u8*, width:i32, height:i32) -> void abi sysv-amd64
extern gtk_css_provider_new() -> u8* abi sysv-amd64
extern gtk_css_provider_load_from_data(provider:u8*, data:u8*, length:i64, error:u8**) -> i32 abi sysv-amd64
extern gtk_style_context_add_provider_for_screen(screen:u8*, provider:u8*, priority:u32) -> void abi sysv-amd64
extern gtk_widget_get_style_context(widget:u8*) -> u8* abi sysv-amd64
extern gtk_style_context_add_class(context:u8*, name:u8*) -> void abi sysv-amd64
extern gdk_screen_get_default() -> u8* abi sysv-amd64
extern gtk_widget_set_size_request(widget:u8*, width:i32, height:i32) -> void abi sysv-amd64
extern gtk_box_new(orientation:i32, spacing:i32) -> u8* abi sysv-amd64
extern gtk_paned_new(orientation:i32) -> u8* abi sysv-amd64
extern gtk_paned_pack1(paned:u8*, child:u8*, resize:i32, shrink:i32) -> void abi sysv-amd64
extern gtk_paned_pack2(paned:u8*, child:u8*, resize:i32, shrink:i32) -> void abi sysv-amd64
extern gtk_paned_set_position(paned:u8*, position:i32) -> void abi sysv-amd64
extern gtk_scrolled_window_new(hadjustment:u8*, vadjustment:u8*) -> u8* abi sysv-amd64
extern gtk_scrolled_window_set_policy(window:u8*, horizontal:i32, vertical:i32) -> void abi sysv-amd64
extern gtk_container_add(container:u8*, child:u8*) -> void abi sysv-amd64
extern gtk_stack_new() -> u8* abi sysv-amd64
extern gtk_stack_set_visible_child(stack:u8*, child:u8*) -> void abi sysv-amd64
extern gtk_stack_set_transition_type(stack:u8*, transition:i32) -> void abi sysv-amd64
extern gtk_box_pack_start(box:u8*, child:u8*, expand:i32, fill:i32, padding:u32) -> void abi sysv-amd64
extern gtk_box_pack_end(box:u8*, child:u8*, expand:i32, fill:i32, padding:u32) -> void abi sysv-amd64
extern gtk_label_new(text:u8*) -> u8* abi sysv-amd64
extern gtk_label_set_text(label:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_label_set_xalign(label:u8*, x:f32) -> void abi sysv-amd64
extern gtk_button_new() -> u8* abi sysv-amd64
extern gtk_button_new_with_label(text:u8*) -> u8* abi sysv-amd64
extern gtk_button_set_image(button:u8*, image:u8*) -> void abi sysv-amd64
extern gtk_button_set_always_show_image(button:u8*, always:i32) -> void abi sysv-amd64
extern gtk_image_new_from_icon_name(icon:u8*, size:i32) -> u8* abi sysv-amd64
extern gtk_widget_set_tooltip_text(widget:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_button_set_alignment(button:u8*, x:f32, y:f32) -> void abi sysv-amd64
extern gtk_text_view_new() -> u8* abi sysv-amd64
extern gtk_text_view_get_buffer(view:u8*) -> u8* abi sysv-amd64
extern gtk_text_view_set_monospace(view:u8*, monospace:i32) -> void abi sysv-amd64
extern gtk_text_view_set_editable(view:u8*, editable:i32) -> void abi sysv-amd64
extern gtk_text_view_set_cursor_visible(view:u8*, visible:i32) -> void abi sysv-amd64
extern gtk_text_view_set_left_margin(view:u8*, margin:i32) -> void abi sysv-amd64
extern gtk_text_view_set_right_margin(view:u8*, margin:i32) -> void abi sysv-amd64
extern gtk_text_view_set_top_margin(view:u8*, margin:i32) -> void abi sysv-amd64
extern gtk_text_view_set_bottom_margin(view:u8*, margin:i32) -> void abi sysv-amd64
extern gtk_text_view_scroll_to_iter(view:u8*, iterator:u8*, within_margin:f64, use_align:i32, xalign:f64, yalign:f64) -> i32 abi sysv-amd64
extern gtk_text_buffer_set_text(buffer:u8*, text:u8*, bytes:i32) -> void abi sysv-amd64
extern gtk_text_buffer_get_start_iter(buffer:u8*, iterator:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_get_end_iter(buffer:u8*, iterator:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_get_text(buffer:u8*, start:u8*, finish:u8*, include_hidden:i32) -> u8* abi sysv-amd64
extern gtk_text_buffer_get_iter_at_offset(buffer:u8*, iterator:u8*, offset:i32) -> void abi sysv-amd64
extern gtk_text_buffer_remove_all_tags(buffer:u8*, start:u8*, finish:u8*) -> void abi sysv-amd64
extern gtk_text_buffer_create_tag(buffer:u8*, name:u8*, first_property:u8*, ...) -> u8* abi sysv-amd64
extern gtk_text_buffer_apply_tag(buffer:u8*, tag:u8*, start:u8*, finish:u8*) -> void abi sysv-amd64
extern gtk_text_view_window_to_buffer_coords(view:u8*, window_type:i32, window_x:i32, window_y:i32, buffer_x:i32*, buffer_y:i32*) -> void abi sysv-amd64
extern gtk_text_view_get_iter_at_location(view:u8*, iterator:u8*, x:i32, y:i32) -> void abi sysv-amd64
extern gtk_text_iter_get_offset(iterator:u8*) -> i32 abi sysv-amd64
extern gtk_widget_set_has_tooltip(widget:u8*, enabled:i32) -> void abi sysv-amd64
extern gtk_tooltip_set_text(tooltip:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_entry_new() -> u8* abi sysv-amd64
extern gtk_entry_set_placeholder_text(entry:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_entry_get_text(entry:u8*) -> u8* abi sysv-amd64
extern gtk_entry_set_text(entry:u8*, text:u8*) -> void abi sysv-amd64
extern gtk_entry_set_has_frame(entry:u8*, setting:i32) -> void abi sysv-amd64
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
extern gtk_tree_store_new(columns:i32, ...) -> u8* abi sysv-amd64
extern gtk_tree_store_append(store:u8*, iterator:u8*, parent:u8*) -> void abi sysv-amd64
extern gtk_tree_store_set(store:u8*, iterator:u8*, ...) -> void abi sysv-amd64
extern gtk_tree_store_clear(store:u8*) -> void abi sysv-amd64
extern gtk_tree_view_new_with_model(model:u8*) -> u8* abi sysv-amd64
extern gtk_tree_view_get_model(view:u8*) -> u8* abi sysv-amd64
extern gtk_tree_view_get_selection(view:u8*) -> u8* abi sysv-amd64
extern gtk_tree_view_set_headers_visible(view:u8*, visible:i32) -> void abi sysv-amd64
extern gtk_tree_view_set_enable_tree_lines(view:u8*, enabled:i32) -> void abi sysv-amd64
extern gtk_tree_view_set_level_indentation(view:u8*, indentation:i32) -> void abi sysv-amd64
extern gtk_tree_view_column_new() -> u8* abi sysv-amd64
extern gtk_tree_view_column_pack_start(column:u8*, renderer:u8*, expand:i32) -> void abi sysv-amd64
extern gtk_tree_view_column_add_attribute(column:u8*, renderer:u8*, attribute:u8*, model_column:i32) -> void abi sysv-amd64
extern gtk_tree_view_append_column(view:u8*, column:u8*) -> i32 abi sysv-amd64
extern gtk_cell_renderer_text_new() -> u8* abi sysv-amd64
extern gtk_cell_renderer_pixbuf_new() -> u8* abi sysv-amd64
extern gtk_tree_selection_get_selected(selection:u8*, model:u8**, iterator:u8*) -> i32 abi sysv-amd64
extern gtk_tree_model_get(model:u8*, iterator:u8*, ...) -> void abi sysv-amd64
extern gtk_tree_model_iter_children(model:u8*, iterator:u8*, parent:u8*) -> i32 abi sysv-amd64
extern gtk_tree_model_get_path(model:u8*, iterator:u8*) -> u8* abi sysv-amd64
extern gtk_tree_store_remove(store:u8*, iterator:u8*) -> i32 abi sysv-amd64
extern gtk_tree_path_free(path:u8*) -> void abi sysv-amd64
extern gtk_tree_view_expand_row(view:u8*, path:u8*, open_all:i32) -> i32 abi sysv-amd64
extern gtk_settings_get_default() -> u8* abi sysv-amd64
extern gtk_dialog_new() -> u8* abi sysv-amd64
extern gtk_dialog_add_button(dialog:u8*, text:u8*, response:i32) -> u8* abi sysv-amd64
extern gtk_dialog_get_content_area(dialog:u8*) -> u8* abi sysv-amd64
extern gtk_dialog_run(dialog:u8*) -> i32 abi sysv-amd64
extern gtk_window_set_transient_for(window:u8*, parent:u8*) -> void abi sysv-amd64
extern gtk_window_set_modal(window:u8*, modal:i32) -> void abi sysv-amd64
extern g_object_set(object:u8*, property:u8*, ...) -> void abi sysv-amd64
extern g_object_unref(object:u8*) -> void abi sysv-amd64
extern gtk_main() -> void abi sysv-amd64
extern gtk_main_quit() -> void abi sysv-amd64
extern g_signal_connect_data(instance:u8*, signal:u8*, callback:Gui:Signal, data:u8*, destroy:u8*, flags:u32) -> u64 abi sysv-amd64
extern g_timeout_add(interval:u32, callback:Gui:Timer, data:u8*) -> u32 abi sysv-amd64
extern g_idle_add(callback:Gui:Timer, data:u8*) -> u32 abi sysv-amd64
extern g_source_remove(source:u32) -> i32 abi sysv-amd64
extern g_free(value:u8*) -> void abi sysv-amd64

let Gui:Backend:name = fn () -> u8* { return "gtk3" }

// -----------------------------------------------------------------------------
// Styling. The public API exposes semantic classes; GTK CSS stays backend-only.
// -----------------------------------------------------------------------------

let Gui:Backend:dark_css = fn () -> u8* {
    // RecurLoop does not concatenate adjacent string literals. Keep the whole
    // GTK stylesheet in one literal; the old version only applied its first
    // `* { color: ... }` rule, which is why WSL showed grey text on white.
    return "* { color: #cccccc; font-size: 10pt; } window, window.background, .background, .app-root { background-color: #1e1e1e; color: #cccccc; } box, paned, notebook, scrolledwindow, viewport { background-color: #1e1e1e; color: #cccccc; } label { color: #cccccc; } button { background-image: none; background-color: #2d2d30; color: #cccccc; border: 1px solid #3f3f46; border-radius: 3px; padding: 4px 8px; box-shadow: none; text-shadow: none; } button:hover { background-color: #3a3d41; color: #ffffff; } button:active, button:checked { background-color: #094771; color: #ffffff; } entry { background-image: none; background-color: #1e1e1e; color: #d4d4d4; border: 1px solid #3c3c3c; border-radius: 2px; padding: 4px 6px; box-shadow: none; } entry:focus { border-color: #007acc; } textview, textview.view, textview text, textview.view text { background-color: #1e1e1e; color: #d4d4d4; } treeview, treeview.view { background-color: #181818; color: #cccccc; border: 0; } treeview.view:selected { background-color: #094771; color: #ffffff; } treeview.view:hover { background-color: #2a2d2e; } notebook, notebook > stack { background-color: #181818; } notebook > header { background-color: #181818; border-color: #2b2b2b; } notebook > header > tabs > tab { background-color: #181818; color: #969696; padding: 4px 10px; border: 0; } notebook > header > tabs > tab:checked { background-color: #1e1e1e; color: #ffffff; border-top: 1px solid #007acc; } paned > separator { background-color: #2b2b2b; min-width: 1px; min-height: 1px; } scrollbar, scrollbar trough { background-color: #1e1e1e; } scrollbar slider { background-color: #424242; border-radius: 4px; min-width: 8px; min-height: 8px; } scrollbar slider:hover { background-color: #5a5a5a; } .explorer-pane { background-color: #181818; border-right: 1px solid #2b2b2b; } .explorer-header { background-color: #181818; padding: 2px 4px 2px 8px; border-bottom: 1px solid #242424; } .explorer-title { color: #bbbbbb; font-weight: bold; font-size: 9pt; } .explorer-root { color: #969696; font-weight: bold; padding: 5px 8px 4px 8px; } .explorer-tree { background-color: #181818; color: #cccccc; } .ide-toolbar { background-color: #181818; min-height: 28px; border-bottom: 1px solid #2b2b2b; } .path-label { color: #9d9d9d; padding-left: 8px; } .tool-button, .icon-button { background-image: none; background-color: transparent; border: 0; border-radius: 3px; padding: 3px 5px; box-shadow: none; } .tool-button:hover, .icon-button:hover { background-color: #2a2d2e; } .icon-button:active { background-color: #37373d; } .editor-pane, .editor, .editor text { background-color: #1e1e1e; color: #d4d4d4; } .terminal-panel, .terminal-panel box { background-color: #181818; } .terminal-output, .terminal-output text { background-color: #181818; color: #cccccc; font-family: monospace; } .terminal-command { background-color: #181818; border-top: 1px solid #2b2b2b; } .terminal-input { background-image: none; background-color: #181818; color: #d4d4d4; border: 0; border-radius: 0; font-family: monospace; padding: 5px 4px; box-shadow: none; } .terminal-prompt { color: #4ec9b0; font-family: monospace; padding: 5px 0 5px 8px; } .ide-status { background-color: #007acc; color: #ffffff; padding: 2px 7px; font-size: 9pt; } .dialog-surface { background-color: #252526; } .danger-button { background-color: #5a1d1d; color: #ffffff; border-color: #7a2d2d; } .danger-button:hover { background-color: #7a2424; }"
}

let Gui:Backend:apply_dark_theme = fn () -> void {
    // Ask GTK itself for its dark variant first so native controls and window
    // decorations follow the same policy. The CSS provider then owns the IDE
    // palette at USER priority so a host theme cannot turn the content white.
    let settings = gtk_settings_get_default()
    if settings { g_object_set(settings, "gtk-application-prefer-dark-theme", 1, cast(u8*, 0)) }

    let screen = gdk_screen_get_default()
    let provider = gtk_css_provider_new()
    if !screen || !provider { return }
    let css = Gui:Backend:dark_css()
    if !css { return }
    // Install the provider even if GTK reports a recoverable CSS warning.
    // USER priority (800) keeps WSLg/host themes from repainting the IDE light.
    gtk_css_provider_load_from_data(provider, css, -1, cast(u8**, 0))
    gtk_style_context_add_provider_for_screen(screen, provider, 800)
}

let Gui:class_add = fn (widget:u8*, name:u8*) -> void {
    if !widget || !name { return }
    let context = gtk_widget_get_style_context(widget)
    if context { gtk_style_context_add_class(context, name) }
}

let Gui:size = fn (widget:u8*, width:i32, height:i32) -> void {
    if widget { gtk_widget_set_size_request(widget, width, height) }
}

// -----------------------------------------------------------------------------
// Application lifecycle and windows.
// -----------------------------------------------------------------------------

let Gui:initialize = fn () -> i64 {
    if gtk_init_check(cast(i32*, 0), cast(u8***, 0)) == 0 { return 0 }
    Gui:Backend:apply_dark_theme()
    return 1
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

// Stable render surface used by hot-reloadable applications. Children can be
// fully constructed while detached from the visible generation, then selected
// with one backend operation. Transition type 0 deliberately disables animated
// overlap: generation replacement is an immediate state change.
let Gui:stack = fn () -> u8* {
    let result = gtk_stack_new()
    if result { gtk_stack_set_transition_type(result, 0) }
    return result
}

let Gui:stack_add = fn (stack:u8*, child:u8*) -> void {
    if stack && child { gtk_container_add(stack, child) }
}

let Gui:stack_select = fn (stack:u8*, child:u8*) -> void {
    if stack && child { gtk_stack_set_visible_child(stack, child) }
}

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

let Gui:tooltip = fn (widget:u8*, text:u8*) -> void {
    if widget && text { gtk_widget_set_tooltip_text(widget, text) }
}

let Gui:icon_button = fn (icon:u8*, tooltip:u8*) -> u8* {
    let button = gtk_button_new()
    if !button { return cast(u8*, 0) }
    let image = gtk_image_new_from_icon_name(icon, 1)
    if image {
        gtk_button_set_image(button, image)
        gtk_button_set_always_show_image(button, 1)
    }
    if tooltip { gtk_widget_set_tooltip_text(button, tooltip) }
    Gui:class_add(button, "icon-button")
    return button
}

let Gui:button_align = fn (button:u8*, x:f32) -> void {
    if button { gtk_button_set_alignment(button, x, cast(f32, 0.5)) }
}

let Gui:editor = fn () -> u8* {
    let result = gtk_text_view_new()
    if result {
        gtk_text_view_set_monospace(result, 1)
        gtk_text_view_set_left_margin(result, 10)
        gtk_text_view_set_right_margin(result, 10)
        gtk_text_view_set_top_margin(result, 8)
        gtk_text_view_set_bottom_margin(result, 8)
        Gui:class_add(result, "editor")
    }
    return result
}

let Gui:text_view = fn () -> u8* {
    let result = gtk_text_view_new()
    if result {
        gtk_text_view_set_monospace(result, 1)
        gtk_text_view_set_editable(result, 0)
        gtk_text_view_set_cursor_visible(result, 0)
        gtk_text_view_set_left_margin(result, 8)
        gtk_text_view_set_right_margin(result, 8)
        gtk_text_view_set_top_margin(result, 6)
        gtk_text_view_set_bottom_margin(result, 6)
    }
    return result
}

let Gui:text_set = fn (view:u8*, text:u8*) -> void {
    if !view { return }
    let buffer = gtk_text_view_get_buffer(view)
    if buffer { gtk_text_buffer_set_text(buffer, text, -1) }
}

let Gui:text_scroll_end = fn (view:u8*) -> void {
    if !view { return }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return }
    let last = malloc(128)
    if !last { return }
    gtk_text_buffer_get_end_iter(buffer, last)
    gtk_text_view_scroll_to_iter(view, last, cast(f64, 0.0), 0, cast(f64, 0.0), cast(f64, 1.0))
    free(last)
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

let Gui:text_clear_styles = fn (view:u8*) -> void {
    if !view { return }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return }
    let first = cast(u8*, malloc(128))
    let last = cast(u8*, malloc(128))
    if !first || !last { if first { free(first) }; if last { free(last) }; return }
    gtk_text_buffer_get_start_iter(buffer, first)
    gtk_text_buffer_get_end_iter(buffer, last)
    gtk_text_buffer_remove_all_tags(buffer, first, last)
    free(first)
    free(last)
}

let Gui:text_style = fn (view:u8*, name:u8*, foreground:u8*) -> u8* {
    if !view || !name || !foreground { return cast(u8*, 0) }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return cast(u8*, 0) }
    return gtk_text_buffer_create_tag(buffer, name, "foreground", foreground, cast(u8*, 0))
}

let Gui:text_apply_style = fn (view:u8*, tag:u8*, start:i64, finish:i64) -> void {
    if !view || !tag || start < 0 || finish <= start { return }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return }
    let first = cast(u8*, malloc(128))
    let last = cast(u8*, malloc(128))
    if !first || !last { if first { free(first) }; if last { free(last) }; return }
    gtk_text_buffer_get_iter_at_offset(buffer, first, cast(i32, start))
    gtk_text_buffer_get_iter_at_offset(buffer, last, cast(i32, finish))
    gtk_text_buffer_apply_tag(buffer, tag, first, last)
    free(first)
    free(last)
}

let Gui:text_position_at = fn (view:u8*, x:i32, y:i32) -> i64 {
    if !view { return -1 }
    let bx = alloc(i32)
    let by = alloc(i32)
    let iterator = cast(u8*, malloc(128))
    if !bx || !by || !iterator {
        if bx { free(cast(u8*, bx)) }
        if by { free(cast(u8*, by)) }
        if iterator { free(iterator) }
        return -1
    }
    // GTK_TEXT_WINDOW_WIDGET = 1. Query-tooltip coordinates are widget-local.
    gtk_text_view_window_to_buffer_coords(view, 1, x, y, bx, by)
    gtk_text_view_get_iter_at_location(view, iterator, bx[0], by[0])
    let offset = gtk_text_iter_get_offset(iterator)
    free(cast(u8*, bx))
    free(cast(u8*, by))
    free(iterator)
    return offset
}

let Gui:on_text_changed = fn (view:u8*, callback:Gui:Signal, data:u8*) -> u64 {
    if !view { return 0 }
    let buffer = gtk_text_view_get_buffer(view)
    if !buffer { return 0 }
    return g_signal_connect_data(buffer, "changed", callback, data, cast(u8*, 0), 0)
}

let Gui:on_text_tooltip = fn (view:u8*, callback:Gui:TooltipQuery, data:u8*) -> u64 {
    if !view { return 0 }
    gtk_widget_set_has_tooltip(view, 1)
    return g_signal_connect_data(view, "query-tooltip", cast(Gui:Signal, callback), data, cast(u8*, 0), 0)
}

let Gui:tooltip_text = fn (tooltip:u8*, text:u8*) -> void {
    if tooltip && text { gtk_tooltip_set_text(tooltip, text) }
}

let Gui:idle = fn (callback:Gui:Timer, data:u8*) -> u32 { return g_idle_add(callback, data) }
let Gui:source_remove = fn (source:u32) -> void { if source != 0 { g_source_remove(source) } }

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

let Gui:input_frame = fn (input:u8*, enabled:i64) -> void {
    if input { gtk_entry_set_has_frame(input, enabled != 0) }
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
// Tree view. GTK owns the actual rows, expansion UI and scrolling. Directories
// are lazy: a directory row initially contains one invisible placeholder child
// so GTK shows its native expander, and application code replaces that child
// with the directory's direct entries only when the directory is selected.
//
// Columns: 0 display name, 1 absolute path, 2 directory flag, 3 loaded flag, 4 icon name.
// -----------------------------------------------------------------------------

let Gui:tree = fn () -> u8* {
    // G_TYPE_STRING = 64, G_TYPE_BOOLEAN = 20.
    let store = gtk_tree_store_new(5,
                                   cast(u64, 64),
                                   cast(u64, 64),
                                   cast(u64, 20),
                                   cast(u64, 20),
                                   cast(u64, 64))
    if !store { return cast(u8*, 0) }
    let result = gtk_tree_view_new_with_model(store)
    g_object_unref(store)
    if !result { return cast(u8*, 0) }

    let icon = gtk_cell_renderer_pixbuf_new()
    let text = gtk_cell_renderer_text_new()
    let column = gtk_tree_view_column_new()
    if column {
        if icon {
            gtk_tree_view_column_pack_start(column, icon, 0)
            gtk_tree_view_column_add_attribute(column, icon, "icon-name", 4)
        }
        if text {
            gtk_tree_view_column_pack_start(column, text, 1)
            gtk_tree_view_column_add_attribute(column, text, "text", 0)
        }
        gtk_tree_view_append_column(result, column)
    }
    gtk_tree_view_set_headers_visible(result, 0)
    gtk_tree_view_set_enable_tree_lines(result, 0)
    gtk_tree_view_set_level_indentation(result, 8)
    Gui:class_add(result, "explorer-tree")
    return result
}

let Gui:tree_clear = fn (tree:u8*) -> void {
    if !tree { return }
    let model = gtk_tree_view_get_model(tree)
    if model { gtk_tree_store_clear(model) }
}

// Returns a heap-owned GtkTreeIter. Directory rows start unloaded and receive
// a zero-width placeholder child so the native expander is visible immediately.
let Gui:tree_append = fn (tree:u8*, parent:u8*, text:u8*, path:u8*, directory:i64) -> u8* {
    if !tree || !text || !path { return cast(u8*, 0) }
    let store = gtk_tree_view_get_model(tree)
    if !store { return cast(u8*, 0) }
    let iterator = malloc(32)
    if !iterator { return cast(u8*, 0) }
    gtk_tree_store_append(store, iterator, parent)
    var icon_name:u8* = "text-x-generic-symbolic"
    if directory != 0 { icon_name = "folder-symbolic" }
    gtk_tree_store_set(store, iterator,
                       0, text,
                       1, path,
                       2, directory != 0,
                       3, directory == 0,
                       4, icon_name,
                       -1)

    if directory != 0 {
        let placeholder = malloc(32)
        if placeholder {
            gtk_tree_store_append(store, placeholder, iterator)
            gtk_tree_store_set(store, placeholder,
                               0, "",
                               1, "",
                               2, 0,
                               3, 1,
                               4, "",
                               -1)
            free(placeholder)
        }
    }
    return iterator
}

let Gui:tree_iter_free = fn (iterator:u8*) -> void { if iterator { free(iterator) } }

let Gui:tree_selection = fn (tree:u8*) -> u8* {
    if !tree { return cast(u8*, 0) }
    return gtk_tree_view_get_selection(tree)
}

// Returns a heap-owned copy of the currently selected GtkTreeIter.
let Gui:tree_selected_iter = fn (selection:u8*) -> u8* {
    if !selection { return cast(u8*, 0) }
    let iterator = malloc(32)
    if !iterator { return cast(u8*, 0) }
    var model:u8* = cast(u8*, 0)
    if gtk_tree_selection_get_selected(selection, &model, iterator) == 0 || !model {
        free(iterator)
        return cast(u8*, 0)
    }
    return iterator
}

// Returned path is allocated by GTK and must be released with Gui:text_free.
let Gui:tree_iter_path = fn (tree:u8*, iterator:u8*, directory:i32*, loaded:i32*) -> u8* {
    if !tree || !iterator { return cast(u8*, 0) }
    let model = gtk_tree_view_get_model(tree)
    if !model { return cast(u8*, 0) }
    var path:u8* = cast(u8*, 0)
    var is_directory:i32 = 0
    var is_loaded:i32 = 0
    gtk_tree_model_get(model, iterator,
                       1, &path,
                       2, &is_directory,
                       3, &is_loaded,
                       -1)
    if directory { directory[0] = is_directory }
    if loaded { loaded[0] = is_loaded }
    return path
}

let Gui:tree_selected_path = fn (tree:u8*, directory:i32*) -> u8* {
    if !tree { return cast(u8*, 0) }
    let selection = Gui:tree_selection(tree)
    let iterator = Gui:tree_selected_iter(selection)
    if !iterator { return cast(u8*, 0) }
    defer Gui:tree_iter_free(iterator)
    var loaded:i32 = 0
    return Gui:tree_iter_path(tree, iterator, directory, &loaded)
}

let Gui:tree_clear_children = fn (tree:u8*, parent:u8*) -> void {
    if !tree || !parent { return }
    let store = gtk_tree_view_get_model(tree)
    if !store { return }
    let child = malloc(32)
    if !child { return }
    defer free(child)
    while gtk_tree_model_iter_children(store, child, parent) != 0 {
        gtk_tree_store_remove(store, child)
    }
}

let Gui:tree_mark_loaded = fn (tree:u8*, iterator:u8*) -> void {
    if !tree || !iterator { return }
    let store = gtk_tree_view_get_model(tree)
    if store { gtk_tree_store_set(store, iterator, 3, 1, -1) }
}

let Gui:tree_expand = fn (tree:u8*, iterator:u8*) -> void {
    if !tree || !iterator { return }
    let model = gtk_tree_view_get_model(tree)
    if !model { return }
    let path = gtk_tree_model_get_path(model, iterator)
    if !path { return }
    gtk_tree_view_expand_row(tree, path, 0)
    gtk_tree_path_free(path)
}

let Gui:on_tree_select = fn (tree:u8*, callback:Gui:Signal, data:u8*) -> u64 {
    let selection = Gui:tree_selection(tree)
    if !selection { return 0 }
    return g_signal_connect_data(selection, "changed", callback, data, cast(u8*, 0), 0)
}

// -----------------------------------------------------------------------------
// Small native dialogs used by higher-level toolkits/apps.
// Returned prompt text is malloc-owned by the caller.
// -----------------------------------------------------------------------------

let Gui:prompt = fn (parent:u8*, title:u8*, message:u8*, initial:u8*) -> u8* {
    let dialog = gtk_dialog_new()
    if !dialog { return cast(u8*, 0) }
    if title { gtk_window_set_title(dialog, title) }
    if parent { gtk_window_set_transient_for(dialog, parent) }
    gtk_window_set_modal(dialog, 1)
    Gui:class_add(dialog, "dialog-surface")

    let area = gtk_dialog_get_content_area(dialog)
    if message {
        let label = Gui:label(message)
        Gui:label_align(label, cast(f32, 0.0))
        Gui:append(area, label, 0, 8)
    }
    let entry = Gui:input(cast(u8*, 0))
    if initial { Gui:input_set(entry, initial) }
    Gui:append(area, entry, 0, 8)
    gtk_dialog_add_button(dialog, "Cancel", -6)
    gtk_dialog_add_button(dialog, "OK", -5)
    Gui:show(dialog)
    Gui:focus(entry)

    var result:u8* = cast(u8*, 0)
    if gtk_dialog_run(dialog) == -5 {
        let value = Gui:input_text(entry)
        if value {
            let bytes = strlen(value)
            result = cast(u8*, malloc(bytes + 1))
            if result { memcpy(result, value, bytes + 1) }
        }
    }
    Gui:destroy(dialog)
    return result
}

let Gui:confirm = fn (parent:u8*, title:u8*, message:u8*, action:u8*) -> i64 {
    let dialog = gtk_dialog_new()
    if !dialog { return 0 }
    if title { gtk_window_set_title(dialog, title) }
    if parent { gtk_window_set_transient_for(dialog, parent) }
    gtk_window_set_modal(dialog, 1)
    Gui:class_add(dialog, "dialog-surface")
    let area = gtk_dialog_get_content_area(dialog)
    if message {
        let label = Gui:label(message)
        Gui:label_align(label, cast(f32, 0.0))
        Gui:append(area, label, 0, 10)
    }
    gtk_dialog_add_button(dialog, "Cancel", -6)
    let accept = gtk_dialog_add_button(dialog, action, -5)
    if accept { Gui:class_add(accept, "danger-button") }
    Gui:show(dialog)
    let ok = gtk_dialog_run(dialog) == -5
    Gui:destroy(dialog)
    return ok
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
let Gui:Key:F2 = fn () -> u32 { return 65471 }
let Gui:Key:Delete = fn () -> u32 { return 65535 }
let Gui:Modifier:None = fn () -> u32 { return 0 }
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
set gtk_css_provider_new.serializable = false
set gtk_css_provider_load_from_data.serializable = false
set gtk_style_context_add_provider_for_screen.serializable = false
set gtk_widget_get_style_context.serializable = false
set gtk_style_context_add_class.serializable = false
set gdk_screen_get_default.serializable = false
set gtk_widget_set_size_request.serializable = false
set gtk_button_set_alignment.serializable = false
set gtk_text_view_set_left_margin.serializable = false
set gtk_text_view_set_right_margin.serializable = false
set gtk_text_view_set_top_margin.serializable = false
set gtk_text_view_set_bottom_margin.serializable = false
set gtk_text_view_scroll_to_iter.serializable = false
set gtk_entry_set_has_frame.serializable = false
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
set gtk_button_new.serializable = false
set gtk_button_new_with_label.serializable = false
set gtk_button_set_image.serializable = false
set gtk_button_set_always_show_image.serializable = false
set gtk_image_new_from_icon_name.serializable = false
set gtk_widget_set_tooltip_text.serializable = false
set gtk_text_view_new.serializable = false
set gtk_text_view_get_buffer.serializable = false
set gtk_text_view_set_monospace.serializable = false
set gtk_text_view_set_editable.serializable = false
set gtk_text_view_set_cursor_visible.serializable = false
set gtk_text_buffer_set_text.serializable = false
set gtk_text_buffer_get_start_iter.serializable = false
set gtk_text_buffer_get_end_iter.serializable = false
set gtk_text_buffer_get_text.serializable = false
set gtk_text_buffer_get_iter_at_offset.serializable = false
set gtk_text_buffer_remove_all_tags.serializable = false
set gtk_text_buffer_create_tag.serializable = false
set gtk_text_buffer_apply_tag.serializable = false
set gtk_text_view_window_to_buffer_coords.serializable = false
set gtk_text_view_get_iter_at_location.serializable = false
set gtk_text_iter_get_offset.serializable = false
set gtk_widget_set_has_tooltip.serializable = false
set gtk_tooltip_set_text.serializable = false
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
set gtk_tree_store_new.serializable = false
set gtk_tree_store_append.serializable = false
set gtk_tree_store_set.serializable = false
set gtk_tree_store_clear.serializable = false
set gtk_tree_view_new_with_model.serializable = false
set gtk_tree_view_get_model.serializable = false
set gtk_tree_view_get_selection.serializable = false
set gtk_tree_view_set_headers_visible.serializable = false
set gtk_tree_view_set_enable_tree_lines.serializable = false
set gtk_tree_view_set_level_indentation.serializable = false
set gtk_tree_view_column_new.serializable = false
set gtk_tree_view_column_pack_start.serializable = false
set gtk_tree_view_column_add_attribute.serializable = false
set gtk_tree_view_append_column.serializable = false
set gtk_cell_renderer_text_new.serializable = false
set gtk_cell_renderer_pixbuf_new.serializable = false
set gtk_tree_selection_get_selected.serializable = false
set gtk_tree_model_get.serializable = false
set gtk_tree_model_iter_children.serializable = false
set gtk_tree_model_get_path.serializable = false
set gtk_tree_store_remove.serializable = false
set gtk_tree_path_free.serializable = false
set gtk_tree_view_expand_row.serializable = false
set gtk_settings_get_default.serializable = false
set gtk_dialog_new.serializable = false
set gtk_dialog_add_button.serializable = false
set gtk_dialog_get_content_area.serializable = false
set gtk_dialog_run.serializable = false
set gtk_window_set_transient_for.serializable = false
set gtk_window_set_modal.serializable = false
set g_object_set.serializable = false
set g_object_unref.serializable = false
set gtk_main.serializable = false
set gtk_main_quit.serializable = false
set g_signal_connect_data.serializable = false
set g_timeout_add.serializable = false
set g_idle_add.serializable = false
set g_source_remove.serializable = false
set g_free.serializable = false

languagekit_native_end
include "../build/export.rl"
__recurloop_export_library
