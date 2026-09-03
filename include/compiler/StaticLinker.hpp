#pragma once

#include <compiler/ArchiveReader.hpp>
#include <compiler/Module.hpp>

#include <vector>

namespace compiler {
  class StaticLinker {
  public:
    void addObject(Module module);
    void addArchive(std::vector<ArchiveMember> members);
    void clear();
    bool empty() const;

    Module link(const Module &root) const;

  private:
    std::vector<Module> objects;
    std::vector<std::vector<ArchiveMember>> archives;
  };
} // namespace compiler
