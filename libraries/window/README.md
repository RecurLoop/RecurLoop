# window.rli

A small GLFW binding for RecurLoop Vulkan applications. It initializes GLFW in
`GLFW_NO_API` mode, creates/destroys windows, pumps events, returns GLFW's
required Vulkan instance extensions, and creates the Vulkan window surface.
