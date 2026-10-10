#include <recurloop/Library.hpp>
#include <context/Context.hpp>
#include <utilities/ExecutablePath.hpp>
#include <utilities/Exception.hpp>

#include <cstdlib>
#include <sstream>
#include <vector>

namespace recurloop {
  namespace {
    void appendLibraryPathList(std::vector<std::filesystem::path> &paths, const char *value) {
      if (value == nullptr || *value == '\0') return;
#if defined(_WIN32)
      constexpr char separator = ';';
#else
      constexpr char separator = ':';
#endif
      std::string_view list(value);
      std::size_t begin = 0;
      while (begin <= list.size()) {
        const std::size_t end = list.find(separator, begin);
        const std::string_view item =
            list.substr(begin, end == std::string_view::npos ? list.size() - begin : end - begin);
        if (!item.empty()) paths.emplace_back(item);
        if (end == std::string_view::npos) break;
        begin = end + 1;
      }
    }

  } // namespace

  std::filesystem::path Library::resolve(context::Context &context, std::string_view requested,
                                         std::span<const std::filesystem::path> explicitPaths) {
    namespace fs = std::filesystem;
    if (requested.empty() || requested.find('\0') != std::string_view::npos)
      THROW(, "library name must be nonempty and contain no NUL bytes")
    fs::path name(requested);
    if (name.has_parent_path() || name.is_absolute()) {
      if (fs::exists(name)) return fs::absolute(name).lexically_normal();
      THROW(, "library image not found: " << name.string())
    }
    if (name.extension() != ".rli") name += ".rli";

    std::vector<fs::path> paths(explicitPaths.begin(), explicitPaths.end());
    if (paths.empty() && context.exec.args.ptr != nullptr) {
      // Source imports reuse the startup search path after session cloning.
      // Stop at the source operands/separator, never treating program arguments
      // as runtime configuration.
      for (int index = 1; index < context.exec.args.index && index < context.exec.args.count; ++index) {
        const std::string_view option(context.exec.args.ptr[index]);
        if (option == "--reset") continue;
        if (option != "--library-path" && option != "--library" && option != "--import") break;
        if (++index >= context.exec.args.count) break;
        if (option == "--library-path") paths.emplace_back(context.exec.args.ptr[index]);
      }
    }
    appendLibraryPathList(paths, std::getenv("RECURLOOP_LIBRARY_PATH"));

    const auto executablePath = utilities::executablePath();
    if (!executablePath.empty()) {
      paths.push_back(executablePath.parent_path() / "../share/recurloop/libraries");
    }

    if (context.exec.args.ptr != nullptr && context.exec.args.count > 0 && context.exec.args.ptr[0] != nullptr) {
      fs::path executable(context.exec.args.ptr[0]);
      if (executable.has_parent_path()) {
        std::error_code error;
        executable = fs::absolute(executable, error).lexically_normal();
        if (!error) {
          const fs::path prefixOrBuild = executable.parent_path().parent_path();
          paths.push_back(prefixOrBuild / "libraries");
          paths.push_back(prefixOrBuild / "share" / "recurloop" / "libraries");
        }
      }
    }

#ifdef RECURLOOP_DEFAULT_LIBRARY_DIR
    paths.emplace_back(RECURLOOP_DEFAULT_LIBRARY_DIR);
#endif
    paths.push_back(fs::current_path() / "libraries");

    for (const fs::path &directory : paths) {
      std::error_code error;
      const fs::path candidate = fs::absolute(directory / name, error).lexically_normal();
      if (!error && fs::exists(candidate)) return candidate;
    }

    std::ostringstream message;
    message << "library image '" << requested << "' was not found";
    if (!paths.empty()) {
      message << " in";
      for (const auto &path : paths) message << "\n  " << path.string();
    }
    THROW(, message.str())
  }
} // namespace recurloop
