#pragma once

#include <compiler/TypeSystem.hpp>
#include <context/Context.hpp>

#include <span>
#include <string_view>

namespace recurloop {
  // Process-local implementation registry required by persisted language
  // images. Host ABI registration installs no user-visible language phrases;
  // it only makes stable action names resolvable when an .rli is restored.
  class HostAbi {
  public:
    HostAbi() = delete;

    static void registerActions(context::Context &context);

    // Bootstrap-only materialization of the complete host-layout-dependent type
    // set. Source core uses the two declaration-driven methods below instead.
    static void setupCompilerTypes(context::Context &context);

    // The source core owns the semantic type/field graph. Host ABI supplies
    // only the physical C++ size/alignment/offsets for names it implements.
    static compiler::TypeId defineOpaqueCompilerType(context::Context &context, std::string_view name);
    static compiler::TypeId defineStructureCompilerType(context::Context &context, std::string_view name,
                                                        std::span<const compiler::FieldDeclaration> fields);
  };
} // namespace recurloop
