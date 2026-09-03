#include <compiler/StaticLinker.hpp>

#include <utility>

namespace compiler {
  namespace {
    bool resolvesImport(const Module &result, const ArchiveMember &candidate) {
      for (const std::string &definition : candidate.definitions) {
        const Symbol *unresolved = result.findSymbol(definition);
        if (unresolved != nullptr && unresolved->imported && unresolved->binding != SymbolBinding::Weak) return true;
      }
      return false;
    }
  } // namespace

  void StaticLinker::addObject(Module module) { objects.push_back(std::move(module)); }

  void StaticLinker::addArchive(std::vector<ArchiveMember> members) { archives.push_back(std::move(members)); }

  void StaticLinker::clear() {
    objects.clear();
    archives.clear();
  }

  bool StaticLinker::empty() const { return objects.empty() && archives.empty(); }

  Module StaticLinker::link(const Module &root) const {
    Module result = root;
    for (const Module &object : objects) result.merge(object);

    std::vector<std::vector<bool>> selected;
    selected.reserve(archives.size());
    for (const auto &archive : archives) selected.emplace_back(archive.size(), false);

    bool changed = true;
    while (changed) {
      changed = false;
      for (std::size_t archiveIndex = 0; archiveIndex < archives.size(); ++archiveIndex) {
        for (std::size_t memberIndex = 0; memberIndex < archives[archiveIndex].size(); ++memberIndex) {
          if (selected[archiveIndex][memberIndex]) continue;
          const ArchiveMember &candidate = archives[archiveIndex][memberIndex];
          if (!resolvesImport(result, candidate)) continue;
          result.merge(candidate.load());
          selected[archiveIndex][memberIndex] = true;
          changed = true;
        }
      }
    }
    return result;
  }
} // namespace compiler
