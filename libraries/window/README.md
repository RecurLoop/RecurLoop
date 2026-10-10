# window.rli

A small GLFW binding for RecurLoop Vulkan applications. It initializes GLFW in
`GLFW_NO_API` mode, creates/destroys windows, pumps events, returns GLFW's
required Vulkan instance extensions, and creates the Vulkan window surface.

Installed with the runtime and loaded using `import window`, which imports
`vulkan` transitively before loading the GLFW binding. Applications using
locally built GLFW can add `link path "path/to/glfw/lib"` after the import.
Importing definitions does not initialize GLFW or open a window.
