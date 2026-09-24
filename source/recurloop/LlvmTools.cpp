#include "LlvmTools.hpp"

#ifdef RECURLOOP_ENABLE_LLVM
  #include <utilities/Exception.hpp>

  #include <cstdlib>
  #include <filesystem>
  #include <initializer_list>
  #include <string>
  #include <string_view>

namespace recurloop::llvm_tools {
  namespace {
    std::filesystem::path pathExecutable(std::string_view name) {
      const char *raw = std::getenv("PATH");
      if (raw == nullptr) return {};
#ifdef _WIN32
      constexpr char separator = ';';
      constexpr std::string_view suffix = ".exe";
#else
      constexpr char separator = ':';
      constexpr std::string_view suffix = "";
#endif
      std::string path(raw);
      std::size_t begin = 0;
      while (begin <= path.size()) {
        const std::size_t end = path.find(separator, begin);
        const std::string directory = path.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
        if (!directory.empty()) {
          auto candidate = std::filesystem::path(directory) / std::string(name);
          candidate += suffix;
          std::error_code error;
          if (std::filesystem::is_regular_file(candidate, error) && !error) return candidate;
        }
        if (end == std::string::npos) break;
        begin = end + 1;
      }
      return {};
    }

    std::string tool(std::initializer_list<std::string_view> names) {
      for (const auto name : names) {
        const auto path = pathExecutable(name);
        if (!path.empty()) return path.string();
      }
      THROW(, "LLVM executable linking tool is not installed. Install Clang/LLD 22 "
               "(Debian/Ubuntu: apt install clang-22 lld-22) or put compatible clang and ld.lld on PATH")
    }
  } // namespace

  std::string clang() {
    return tool({"clang-22", "clang"});
  }

  std::string linker() {
    return tool({"ld.lld-22", "ld.lld"});
  }

  void appendSysroot(std::vector<std::string> &arguments) {
    if (std::string_view(RECURLOOP_LLVM_SYSROOT).size() != 0)
      arguments.push_back("--sysroot=" RECURLOOP_LLVM_SYSROOT);
  }
} // namespace recurloop::llvm_tools
#endif
