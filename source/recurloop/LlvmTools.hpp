#pragma once

#include <string>
#include <vector>

namespace recurloop::llvm_tools {
  std::string clang();
  std::string linker();
  void appendSysroot(std::vector<std::string> &arguments);
} // namespace recurloop::llvm_tools
