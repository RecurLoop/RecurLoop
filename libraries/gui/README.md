# gui.rli

`gui.rli` is the RecurLoop-native GUI API used by the IDE.  Applications use
only `Gui:*` primitives; they never call a platform toolkit directly.

The first backend is GTK3 because it already supplies mature text editing,
clipboard, IME and accessibility while the RecurLoop widget API is being
stabilized.  GTK symbols are private implementation details.  This boundary is
intentional: another backend (Win32, Cocoa, SDL/Vulkan, Wayland) can implement
the same `Gui:*` surface without changing application source.

Current public surface covers application/window lifecycle, rows/columns,
splitters, scrolling, labels, buttons, editable/read-only text, inputs, tabs,
events, timers and keyboard shortcuts.  Higher-level widgets should be built in
RecurLoop by composition rather than added to the host.
