#pragma once

#include "AssemblerData.hpp"

#include <compiler/Assembler.hpp>
#include <compiler/ElfWriter.hpp>
#include <compiler/DynamicLinker.hpp>
#include <compiler/JitLinker.hpp>
#include <compiler/LanguageImage.hpp>
#include <compiler/Module.hpp>
#include <context/Context.hpp>

#include <algorithm>
#include <array>
#include <bit>
#include <cctype>
#include <charconv>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace recurloop {
  namespace assembler_internal {

    compiler::Assembler::Location assembler_location(context::Context &context, Size keyBytes = 0);
    std::string assembler_internal_key(unsigned char kind);
    std::string assembler_operand_key(Size index);
    std::string compiled_invocation_key(Size index);
    lexicon::Phrase assembler_match_phrase(lexicon::Phrase &dictionary, const std::string &key);
    lexicon::Phrase native_output(context::Context &context);
    NativeOutputKind native_output_kind(context::Context &context);
    bool linked_native_output(context::Context &context);
    void set_native_output(context::Context &context, const std::string &path, NativeOutputKind kind);
    std::string compiled_scope_session_key();
    lexicon::Phrase compiled_scope_session(context::Context &context, bool required = true);
    bool compiled_scope_open(context::Context &context);
    void compiled_scope_restore_key(context::Context &context, lexicon::Phrase &session,
                                    const CompiledScopeSessionData &data);
    lexicon::Phrase assembler_body(context::Context &context, bool required = true);
    lexicon::Phrase assembler_session(context::Context &context, bool required = true);
    void assembler_enter_operand_state(context::Context &context, const char *key);
    bool assembler_open(context::Context &context);
    void assembler_restore_key(context::Context &context, lexicon::Phrase &session, const AssemblerSessionData &data);
    NativeDefinition link_compiled_scope_definition(context::Context &context, lexicon::Phrase &invoked,
                                                    lexicon::Phrase &session,
                                                    const CompiledScopeSessionData &sessionData);
    void finalize_native_definition(context::Context &context, lexicon::Phrase &invoked, compiler::Module &module,
                                    const std::vector<NativeImport> &imports);
    void action_compiled_scope_end(context::Context &context, lexicon::Phrase &invoked);
    void action_let_scope(context::Context &context, lexicon::Phrase &invoked);
    char assembler_peek(context::Context &context, Size relative = 0);
    void assembler_skip_horizontal_whitespace(context::Context &context);
    [[noreturn]] void assembler_fail(const compiler::Assembler::Location &location, const std::string &message);
    [[noreturn]] void invocation_fail(const compiler::Assembler::Location &location, bool assemblerContext,
                                      const std::string &message);
    int invoke_phrase(context::Context *context, Size phraseAddress, Size line, Size column) noexcept;
    lexicon::Phrase native_action_implementation(lexicon::Phrase phrase, Size minimumPayload);
    void invoke_native_action(context::Context &, lexicon::Phrase &invoked);
    void invoke_deferred_native_action(context::Context &context, lexicon::Phrase &invoked);
    void assembler_store_path(lexicon::Phrase &phrase, const std::string &path);
    compiler::Assembler::Location assembler_load_location(lexicon::Phrase &phrase, Size offset);
    lexicon::Phrase assembler_find_label(context::Context &context, const std::string &name);
    bool assembler_label_conflicts_with_builtin(context::Context &context, const std::string &name);
    lexicon::Phrase assembler_ensure_label(context::Context &context, const std::string &name,
                                           const compiler::Assembler::Location &location);
    void assembler_define_label(context::Context &context, const std::string &name,
                                const compiler::Assembler::Location &location);
    void assembler_add_relocation(context::Context &context, const compiler::Assembler::Relocation &relocation,
                                  Size instructionStart);
    void assembler_add_invocation(context::Context &context, const std::string &reference,
                                  const compiler::Assembler::Location &location,
                                  const compiler::TypedFunction *typed = nullptr,
                                  const std::vector<compiler::TypedValue> &arguments = {});
    void emit_resolved_phrase_invocation(context::Context &context, lexicon::Phrase &target,
                                         const std::string &reference, const compiler::TypedFunction *typed,
                                         const std::vector<compiler::TypedValue> &arguments,
                                         const compiler::Assembler::Location &location);
    bool assembler_fits_relative32(std::int64_t value);
    std::string assembler_trim(std::string text);
    lexicon::Phrase resolve_phrase_reference(context::Context &context, Size rootAddress, const std::string &reference,
                                             const compiler::Assembler::Location &location, bool assemblerContext);
    void assembler_patch_u64(context::Context &context, Size offset, std::uint64_t value,
                             const compiler::Assembler::Location &location);
    void assembler_validate_invocation_patch(context::Context &context, const AssemblerSessionData &sessionData,
                                             Size offset, const compiler::Assembler::Location &location);
    void add_native_import(compiler::Module &module, std::vector<NativeImport> &imports, std::string name,
                           std::uintptr_t address);
    void add_native_invocation(context::Context &context, compiler::Module &module, std::vector<NativeImport> &imports,
                               Size invocationIndex, Size contextPatchOffset, Size phrasePatchOffset,
                               Size trampolinePatchOffset, Size phraseAddress);
    void write_file(const std::string &path, const std::vector<std::uint8_t> &bytes, std::string_view description);
    void write_shared_executable(context::Context &context, compiler::Module module, std::string_view entryName,
                                 const std::string &path);
    void add_executable_entry(compiler::Module &module, std::string_view definitionSymbol);
    bool write_native_output(context::Context &context, compiler::Module &module);
    void append_native_data_sections(context::Context &context, compiler::Module &module);
    void assembler_resolve_invocations(context::Context &context, lexicon::Phrase &session,
                                       const AssemblerSessionData &sessionData, compiler::Module *module = nullptr,
                                       std::vector<NativeImport> *imports = nullptr);
    std::string assembler_label_symbol(const std::string &label);
    void assembler_resolve_labels(context::Context &context, lexicon::Phrase &session,
                                  const AssemblerSessionData &sessionData, compiler::Module *module);
    void assembler_second_pass(context::Context &context, lexicon::Phrase &session,
                               const AssemblerSessionData &sessionData);
    NativeDefinition assembler_link_staged_definition(context::Context &context, lexicon::Phrase &invoked,
                                                      lexicon::Phrase &session,
                                                      const AssemblerSessionData &sessionData);
    std::string assembler_read_identifier_suffix(context::Context &context);
    void assembler_enter_operand_parser(context::Context &context, const std::string &mnemonic,
                                        const compiler::Assembler::Location &location);
    void assembler_emit_open_instruction(context::Context &context);
    void assembler_leave_operand_parser(context::Context &context);
    void assembler_discard_open_instruction(context::Context &context);
    void action_assembler_instruction(context::Context &context, lexicon::Phrase &invoked, const std::string &mnemonic,
                                      std::string_view spelling = {});
    std::string assembler_instruction_name(lexicon::Phrase phrase);
    std::vector<std::uint8_t> &assembler_initialized_section(context::Context &context, Size kind,
                                                             const compiler::Assembler::Location &location);
    std::uint64_t assembler_parse_data_integer(const std::string &source,
                                               const compiler::Assembler::Location &location);
    void action_assembler_section(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_custom_section(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_bytes(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_reserve(context::Context &context, lexicon::Phrase &invoked);
    compiler::Assembler::Location assembler_open_instruction_location(context::Context &context);
    [[noreturn]] void assembler_operand_fail(context::Context &context, const std::string &message);
    bool assembler_identifier_character(char character);
    bool assembler_statement_separator(char character);
    bool assembler_horizontal_whitespace(char character);
    bool assembler_looks_like_integer(const std::string &text);
    std::int64_t assembler_parse_integer(context::Context &context, const std::string &source);
    std::string assembler_read_operand_token(context::Context &context, bool memory, std::string token = {});
    void assembler_set_label_operand(context::Context &context, const std::string &label);
    void assembler_finish_operand(context::Context &context, const std::string &label = {});
    void assembler_validate_memory_register(context::Context &context, const compiler::Assembler::Register &reg);
    void assembler_commit_memory_register(context::Context &context, bool scaled = false, std::uint8_t scale = 1);
    void assembler_add_memory_displacement(context::Context &context, std::int64_t displacement);
    void action_assembler_operand(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_size(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_whitespace(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_memory_begin(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_memory_operator(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_memory_end(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_separator(context::Context &context, lexicon::Phrase &invoked);
    void assembler_emit_and_leave_operand_parser(context::Context &context);
    void action_assembler_operand_comment(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_operand_dynamic(context::Context &context, lexicon::Phrase &invoked);
    std::string read_invocation_reference(context::Context &context, const compiler::Assembler::Location &location,
                                          bool assemblerContext);
    std::vector<compiler::TypedValue> read_typed_call_arguments(context::Context &context,
                                                                const compiler::TypedFunction *function,
                                                                const compiler::Assembler::Location &location,
                                                                bool assemblerContext);
    void action_invoke(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_label(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_unknown(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_comment(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_begin(context::Context &context, lexicon::Phrase &invoked);
    void action_assembler_end(context::Context &context, lexicon::Phrase &invoked);

    class TemporaryLinkObject {
    public:
      TemporaryLinkObject() {
        std::filesystem::path pattern = std::filesystem::temp_directory_path() / "recurloop-link-XXXXXX";
        std::string value = pattern.string();
        std::vector<char> writable(value.begin(), value.end());
        writable.push_back('\0');
        const int descriptor = mkstemp(writable.data());
        if (descriptor == -1) THROW(, "dynamic linker: cannot create temporary object: " << std::strerror(errno))
        if (close(descriptor) != 0) {
          const int error = errno;
          std::filesystem::remove(writable.data());
          THROW(, "dynamic linker: cannot close temporary object: " << std::strerror(error))
        }
        path = writable.data();
      }

      TemporaryLinkObject(const TemporaryLinkObject &) = delete;
      TemporaryLinkObject &operator=(const TemporaryLinkObject &) = delete;

      ~TemporaryLinkObject() {
        std::error_code error;
        std::filesystem::remove(path, error);
      }

      const std::string &get() const {
        return path;
      }

    private:
      std::string path;
    };
  } // namespace assembler_internal
} // namespace recurloop
