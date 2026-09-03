#include "AssemblerInternal.hpp"
#ifdef RECURLOOP_ENABLE_LLVM
  #include "LlvmBackend.hpp"
#endif

#include <memory>

namespace recurloop {
  namespace assembler_internal {

    static constexpr char EXECUTABLE_ENTRY_SYMBOL[] = ".Lentry";
    lexicon::Phrase assembler_ensure_label(context::Context &context, const std::string &name,
                                           const compiler::Assembler::Location &location) {
      if (!compiler::Assembler::isIdentifier(name)) assembler_fail(location, "invalid label name '" + name + "'");

      lexicon::Phrase existing = assembler_find_label(context, name);
      if (!existing.isNull()) return existing;
      if (assembler_label_conflicts_with_builtin(context, name))
        assembler_fail(location, "label name '" + name + "' conflicts with a built-in phrase");

      lexicon::Phrase session = assembler_session(context);
      lexicon::Phrase label = session.append(Byte((unsigned char *)name.data()), 0, name.size() * Byte::length)
                                  .make()
                                  .setType(lexicon::phrase::type::getData(session))
                                  .enableSubdictionary()
                                  .save()
                                  .store(AssemblerLabelData{});

      // The registry phrase owns metadata; the body phrase makes the label part of
      // normal longest-phrase matching. Mnemonics already have a body phrase.
      if (!compiler::Assembler::isMnemonic(name)) {
        lexicon::Phrase body = assembler_body(context);
        body.append(Byte((unsigned char *)name.data()), 0, name.size() * Byte::length)
            .make(action_assembler_label)
            .setType(lexicon::phrase::type::getElaborate(session))
            .save()
            .store(label.getAddress());
      }
      return label;
    }

    void assembler_define_label(context::Context &context, const std::string &name,
                                const compiler::Assembler::Location &location) {
      lexicon::Phrase label = assembler_ensure_label(context, name, location);
      AssemblerLabelData data;
      label.fetch(0, data);
      if (data.defined) {
        lexicon::Phrase definition = assembler_match_phrase(label, assembler_internal_key(ASSEMBLER_DEFINITION));
        const compiler::Assembler::Location previous = assembler_load_location(definition, 0);
        assembler_fail(location, "duplicate label '" + name + "'; first declared at " +
                                     (previous.path.empty() ? std::string("<input>") : previous.path) + ":" +
                                     std::to_string(previous.line) + ":" + std::to_string(previous.column));
      }

      AssemblerSourceData source{location.line, location.column, location.path.size()};
      lexicon::Phrase definition =
          label.append(Byte((unsigned char *)assembler_internal_key(ASSEMBLER_DEFINITION).data()), 0, Byte::length)
              .make()
              .setType(lexicon::phrase::type::getData(label))
              .save()
              .store(source);
      assembler_store_path(definition, location.path);

      data.defined = true;
      AssemblerSessionData sessionData;
      assembler_session(context).fetch(0, sessionData);
      data.section = sessionData.currentSection;
      switch (data.section) {
      case compiler::Module::id(compiler::SectionKind::Text): data.codeOffset = context.workspace.code.size(); break;
      case compiler::Module::id(compiler::SectionKind::ReadOnlyData):
        data.codeOffset = context.workspace.readOnlyData.size();
        break;
      case compiler::Module::id(compiler::SectionKind::Data): data.codeOffset = context.workspace.data.size(); break;
      case compiler::Module::id(compiler::SectionKind::Bss): data.codeOffset = context.workspace.bssBytes; break;
      default: {
        const Size custom = data.section - compiler::Module::id(compiler::SectionKind::Count);
        if (custom >= context.workspace.customSections.size()) assembler_fail(location, "invalid custom section");
        data.codeOffset = context.workspace.customSections[custom].bytes.size();
        break;
      }
      }
      label.update(0, data);
    }

    void assembler_add_relocation(context::Context &context, const compiler::Assembler::Relocation &relocation,
                                  Size instructionStart) {
      lexicon::Phrase label = assembler_ensure_label(context, relocation.label, relocation.location);
      AssemblerLabelData labelData;
      label.fetch(0, labelData);

      std::string key(1 + sizeof(Size), '\0');
      key[0] = static_cast<char>(ASSEMBLER_RELOCATION);
      Byte::copy(Byte(&labelData.referenceCount), Byte(key.data() + 1), sizeof(Size));

      AssemblerRelocationData data;
      data.kind = static_cast<std::uint8_t>(relocation.kind);
      data.patchOffset = instructionStart + relocation.patchOffset;
      data.instructionEnd = instructionStart + relocation.instructionEnd;
      data.source = {relocation.location.line, relocation.location.column, relocation.location.path.size()};

      lexicon::Phrase reference = label.append(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length)
                                      .make()
                                      .setType(lexicon::phrase::type::getData(label))
                                      .save()
                                      .store(data);
      assembler_store_path(reference, relocation.location.path);

      ++labelData.referenceCount;
      label.update(0, labelData);
    }

    void assembler_add_invocation(context::Context &context, const std::string &reference,
                                  const compiler::Assembler::Location &location, const compiler::TypedFunction *typed,
                                  const std::vector<compiler::TypedValue> &arguments) {
      lexicon::Phrase session = assembler_session(context);
      AssemblerSessionData sessionData;
      session.fetch(0, sessionData);

      if (native_output_kind(context) == NativeOutputKind::Raw)
        assembler_fail(location, "invoke is unavailable in raw output because raw files have no relocation metadata");
      const bool nativeAbi = linked_native_output(context);
      if (typed != nullptr && !nativeAbi)
        assembler_fail(location,
                       "typed invoke requires native object or executable output so its ABI symbol can be relocated");
      const compiler::Assembler::PhraseInvocation invocation =
          nativeAbi ? compiler::Assembler::PhraseInvocation{}
                    : compiler::Assembler::encodePhraseInvocation(location.line, location.column);
      const compiler::Assembler::NativeInvocation nativeInvocation =
          nativeAbi ? (typed == nullptr ? compiler::Assembler::encodeNativeInvocation()
                                        : compiler::Assembler::encodeTypedInvocation(typed->signature, arguments))
                    : compiler::Assembler::NativeInvocation{};
      const std::vector<std::uint8_t> &invocationCode = nativeAbi ? nativeInvocation.code : invocation.code;
      const Size instructionStart = context.workspace.code.size();
      if (instructionStart + invocationCode.size() + 1 > context.workspace.code.getCapacity())
        assembler_fail(location, "generated phrase invocation exceeds workspace.code capacity");

      std::string key(1 + sizeof(Size), '\0');
      key[0] = static_cast<char>(ASSEMBLER_INVOCATION);
      Byte::copy(Byte(&sessionData.invocationCount), Byte(key.data() + 1), sizeof(Size));

      AssemblerInvocationData data;
      data.contextAddressPatchOffset = nativeAbi ? 0 : instructionStart + invocation.contextAddressPatchOffset;
      data.phraseAddressPatchOffset = nativeAbi ? 0 : instructionStart + invocation.phraseAddressPatchOffset;
      data.trampolineAddressPatchOffset =
          instructionStart + (nativeAbi ? nativeInvocation.targetPatchOffset : invocation.trampolineAddressPatchOffset);
      data.referenceBytes = reference.size();
      data.nativeAbi = nativeAbi;
      data.source = {location.line, location.column, location.path.size()};

      lexicon::Phrase record = session.append(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length)
                                   .make()
                                   .setType(lexicon::phrase::type::getData(session))
                                   .save()
                                   .store(data);
      assembler_store_path(record, location.path);
      if (!reference.empty()) {
        Byte destination = record.allocate(reference.size());
        Byte::copy(Byte(const_cast<char *>(reference.data())), destination, reference.size());
      }

      ++sessionData.invocationCount;
      session.update(0, sessionData);

      context.workspace.code.append(Byte((unsigned char *)invocationCode.data()), invocationCode.size());
    }

    void emit_resolved_phrase_invocation(context::Context &context, lexicon::Phrase &target,
                                         const std::string &reference, const compiler::TypedFunction *typed,
                                         const std::vector<compiler::TypedValue> &arguments,
                                         const compiler::Assembler::Location &location) {
      if (native_output_kind(context) == NativeOutputKind::Raw)
        invocation_fail(location, false, "invoke is unavailable in raw output because raw files have no relocations");
      const bool linkedNative = linked_native_output(context);
      const bool processNative =
          !linkedNative && (target.getAction() == invoke_native_action ||
                            (target.getAction() == invoke_deferred_native_action && target.getActionEntry() != 0));
      const bool nativeAbi = linkedNative || processNative;
      if (typed != nullptr && !nativeAbi)
        invocation_fail(location, false, "typed invoke requires native object or executable output");
      const compiler::Assembler::PhraseInvocation invocation =
          nativeAbi ? compiler::Assembler::PhraseInvocation{}
                    : compiler::Assembler::encodePhraseInvocation(location.line, location.column);
      const compiler::Assembler::NativeInvocation nativeInvocation =
          nativeAbi ? (typed == nullptr ? compiler::Assembler::encodeNativeInvocation()
                                        : compiler::Assembler::encodeTypedInvocation(typed->signature, arguments))
                    : compiler::Assembler::NativeInvocation{};
      const std::vector<std::uint8_t> &invocationCode = nativeAbi ? nativeInvocation.code : invocation.code;
      if (context.workspace.code.size() + invocationCode.size() + 1 > context.workspace.code.getCapacity())
        invocation_fail(location, false, "generated phrase invocation exceeds workspace.code capacity");

      lexicon::Phrase session = compiled_scope_session(context);
      CompiledScopeSessionData sessionData;
      session.fetch(0, sessionData);
      const Size instructionStart = context.workspace.code.size();
      const CompiledInvocationData data{
          nativeAbi ? 0 : instructionStart + invocation.contextAddressPatchOffset,
          nativeAbi ? 0 : instructionStart + invocation.phraseAddressPatchOffset,
          instructionStart + (nativeAbi ? nativeInvocation.targetPatchOffset : invocation.trampolineAddressPatchOffset),
          target.getAddress(),
          processNative ? Assembler::nativeEntry(target) : 0,
          reference.size(),
          arguments.size(),
          location.line,
          location.column,
          nativeAbi};
      const std::string key = compiled_invocation_key(sessionData.invocationCount);
      lexicon::Phrase record = session.append(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length)
                                   .make()
                                   .setType(lexicon::phrase::type::getData(session))
                                   .save()
                                   .store(data);
      if (!reference.empty()) {
        Byte destination = record.allocate(reference.size());
        Byte::copy(Byte(const_cast<char *>(reference.data())), destination, reference.size());
      }
      for (const compiler::TypedValue &argument : arguments) {
        const CompiledArgumentData stored{argument.type(), argument.asUnsigned(), argument.bytes().size()};
        Byte destination = record.allocate(sizeof(stored));
        std::memcpy(destination.toPtr(), &stored, sizeof(stored));
      }
      ++sessionData.invocationCount;
      sessionData.tailCallEligible = nativeAbi && typed == nullptr && nativeInvocation.code.size() == 5 &&
                                     nativeInvocation.instructionEnd == nativeInvocation.code.size();
      sessionData.tailCallOpcodeOffset = instructionStart;
      sessionData.tailCallEnd = instructionStart + invocationCode.size();
      session.update(0, sessionData);

      context.workspace.code.append(Byte((unsigned char *)invocationCode.data()), invocationCode.size());
    }

    bool assembler_fits_relative32(std::int64_t value) {
      return value >= std::numeric_limits<std::int32_t>::min() && value <= std::numeric_limits<std::int32_t>::max();
    }

    std::string assembler_trim(std::string text) {
      const auto whitespace = [](unsigned char character) { return std::isspace(character); };
      const auto begin = std::find_if_not(text.begin(), text.end(), whitespace);
      const auto end = std::find_if_not(text.rbegin(), text.rend(), whitespace).base();
      return begin < end ? std::string(begin, end) : std::string();
    }

    lexicon::Phrase resolve_phrase_reference(context::Context &context, Size rootAddress, const std::string &reference,
                                             const compiler::Assembler::Location &location, bool assemblerContext) {
      lexicon::Phrase current(&context.lexicon, rootAddress);
      if (current.isNull()) invocation_fail(location, assemblerContext, "phrase reference root is unavailable");
      current.load();

      std::size_t begin = 0;
      while (true) {
        const std::size_t colon = reference.find(':', begin);
        const bool last = colon == std::string::npos;
        const std::string component = assembler_trim(reference.substr(begin, last ? std::string::npos : colon - begin));
        if (component.empty())
          invocation_fail(location, assemblerContext, "empty component in phrase reference '<" + reference + ">'");

        lexicon::Phrase matched = assembler_match_phrase(current, component);
        if (matched.isNull() && begin == 0) {
          // Nested definitions resolve siblings first, then fall back to the
          // global language dictionary.
          lexicon::Phrase root = context.lexicon.phrase();
          if (!root.isNull() && root.getAddress() != current.getAddress()) {
            lexicon::Phrase global = assembler_match_phrase(root, component);
            if (!global.isNull()) {
              current = root;
              matched = global;
            }
          }
        }
        if (matched.isNull())
          invocation_fail(location, assemblerContext,
                          "undefined phrase reference '<" + reference + ">'; missing '" + component + "'");

        current = matched;
        if (last) break;
        if (!current.containsSubdictionary())
          invocation_fail(location, assemblerContext,
                          "phrase reference '<" + reference + ">' cannot enter '" + component +
                              "' because it has no dictionary");
        begin = colon + 1;
      }

      if (!current.isInvokable())
        invocation_fail(location, assemblerContext,
                        "phrase reference '<" + reference + ">' resolves to a non-invokable phrase");
      return current;
    }

    void assembler_patch_u64(context::Context &context, Size offset, std::uint64_t value,
                             const compiler::Assembler::Location &location) {
      if (offset + sizeof(value) > context.workspace.code.size())
        assembler_fail(location, "phrase invocation patch points outside the current assembler block");
      std::uint8_t *patch = context.workspace.code.getMemory().toPtr() + offset;
      for (Size byte = 0; byte < sizeof(value); ++byte)
        patch[byte] = static_cast<std::uint8_t>(value >> (byte * Byte::length));
    }

    void assembler_validate_invocation_patch(context::Context &context, const AssemblerSessionData &sessionData,
                                             Size offset, const compiler::Assembler::Location &location) {
      if (offset < sessionData.codeStartBits / Byte::length || offset > context.workspace.code.size() ||
          sizeof(std::uint64_t) > context.workspace.code.size() - offset)
        assembler_fail(location, "phrase invocation patch points outside the current assembler block");
    }

    void add_native_import(compiler::Module &module, std::vector<NativeImport> &imports, std::string name,
                           std::uintptr_t address) {
      const auto existing = std::find_if(imports.begin(), imports.end(),
                                         [&](const NativeImport &candidate) { return candidate.name == name; });
      if (existing != imports.end()) {
        if (existing->address != address) THROW(, "native import has conflicting addresses: '" << name << "'")
        return;
      }
      module.import(name);
      imports.push_back({std::move(name), address});
    }

    void add_native_invocation(context::Context &context, compiler::Module &module, std::vector<NativeImport> &imports,
                               Size invocationIndex, Size contextPatchOffset, Size phrasePatchOffset,
                               Size trampolinePatchOffset, Size phraseAddress) {
      static constexpr std::string_view contextSymbol = "recurloop.context";
      static constexpr std::string_view trampolineSymbol = "recurloop.invoke";
      const std::string phraseSymbol = "recurloop.phrase." + std::to_string(invocationIndex);

      add_native_import(module, imports, std::string(contextSymbol), reinterpret_cast<std::uintptr_t>(&context));
      add_native_import(module, imports, phraseSymbol, static_cast<std::uintptr_t>(phraseAddress));
      add_native_import(module, imports, std::string(trampolineSymbol),
                        reinterpret_cast<std::uintptr_t>(&invoke_phrase));
      module.relocate(compiler::SectionKind::Text, contextPatchOffset, compiler::RelocationKind::Absolute64,
                      std::string(contextSymbol));
      module.relocate(compiler::SectionKind::Text, phrasePatchOffset, compiler::RelocationKind::Absolute64,
                      phraseSymbol);
      module.relocate(compiler::SectionKind::Text, trampolinePatchOffset, compiler::RelocationKind::Absolute64,
                      std::string(trampolineSymbol));
    }

    void write_file(const std::string &path, const std::vector<std::uint8_t> &bytes, std::string_view description) {
      if (bytes.size() > static_cast<std::size_t>(std::numeric_limits<std::streamsize>::max()))
        THROW(, description << ": output exceeds stream size for '" << path << "'")
      std::ofstream output(path, std::ios::binary | std::ios::trunc);
      if (!output.is_open()) THROW(, description << ": cannot open output file '" << path << "'")
      output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
      output.close();
      if (!output) THROW(, description << ": cannot write output file '" << path << "'")
    }

    void write_shared_executable(context::Context &context, compiler::Module module, std::string_view entryName,
                                 const std::string &path) {
      const compiler::Symbol *entry = module.findSymbol(entryName);
      if (entry == nullptr || entry->imported)
        THROW(, "dynamic executable: module symbol '" << entryName << "' is missing")
      if (entry->absolute || !compiler::hasFlag(module.section(entry->section).flags, compiler::SectionFlag::Execute))
        THROW(, "dynamic executable: module symbol '" << entryName << "' is not executable")

      if (entryName != "main") {
        const compiler::Symbol *main = module.findSymbol("main");
        if (main != nullptr) THROW(, "dynamic executable: module already contains a 'main' symbol")
        module.define("main", entry->section, entry->offset);
      }

      TemporaryLinkObject object;
      write_file(object.get(), compiler::ElfWriter::write(module), "dynamic linker temporary object");

      const char *configuredDriver = std::getenv("RECURLOOP_CC");
      const std::string driver = configuredDriver == nullptr || *configuredDriver == '\0' ? "cc" : configuredDriver;
      std::vector<std::string> arguments = {driver, "-no-pie", object.get(), "-o", path};
      for (const std::string &searchPath : context.language().linkerSearchPaths())
        arguments.push_back("-L" + searchPath);
      for (const std::string &library : context.language().sharedLibraries()) arguments.push_back("-l" + library);

      std::vector<char *> nativeArguments;
      nativeArguments.reserve(arguments.size() + 1);
      for (std::string &argument : arguments) nativeArguments.push_back(argument.data());
      nativeArguments.push_back(nullptr);

      pid_t process = 0;
      const int spawnError = posix_spawnp(&process, driver.c_str(), nullptr, nullptr, nativeArguments.data(), environ);
      if (spawnError != 0)
        THROW(, "dynamic linker: cannot start C compiler driver '" << driver << "': " << std::strerror(spawnError))

      int status = 0;
      while (waitpid(process, &status, 0) == -1) {
        if (errno == EINTR) continue;
        THROW(, "dynamic linker: cannot wait for C compiler driver: " << std::strerror(errno))
      }
      if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        std::error_code error;
        std::filesystem::remove(path, error);
        if (WIFEXITED(status)) THROW(, "dynamic linker: C compiler driver exited with status " << WEXITSTATUS(status))
        THROW(, "dynamic linker: C compiler driver terminated abnormally")
      }
    }

#ifdef RECURLOOP_ENABLE_LLVM
    void run_llvm_linker(const std::vector<std::string> &arguments, const std::string &path,
                         std::string_view description) {
      std::vector<std::string> writable = arguments;
      std::vector<char *> nativeArguments;
      nativeArguments.reserve(writable.size() + 1);
      for (std::string &argument : writable) nativeArguments.push_back(argument.data());
      nativeArguments.push_back(nullptr);

      pid_t process = 0;
      const int spawnError =
          posix_spawn(&process, writable.front().c_str(), nullptr, nullptr, nativeArguments.data(), environ);
      if (spawnError != 0)
        THROW(, description << ": cannot start '" << writable.front() << "': " << std::strerror(spawnError))
      int status = 0;
      while (waitpid(process, &status, 0) == -1) {
        if (errno == EINTR) continue;
        THROW(, description << ": cannot wait for linker: " << std::strerror(errno))
      }
      if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        std::error_code ignored;
        std::filesystem::remove(path, ignored);
        if (WIFEXITED(status)) THROW(, description << ": linker exited with status " << WEXITSTATUS(status))
        THROW(, description << ": linker terminated abnormally")
      }
    }

    class LlvmLinkFiles {
    public:
      explicit LlvmLinkFiles(context::Context &context) {
        for (const compiler::NativeLinkInput &input : context.language().nativeLinkInputs()) {
          auto file = std::make_unique<TemporaryLinkObject>();
          write_file(file->get(), input.bytes,
                     std::string("LLVM ") + (input.archive ? "archive" : "object") + " input '" + input.path + "'");
          paths.push_back(file->get());
          files.push_back(std::move(file));
        }
      }

      void append(std::vector<std::string> &arguments) const {
        arguments.insert(arguments.end(), paths.begin(), paths.end());
      }

    private:
      std::vector<std::unique_ptr<TemporaryLinkObject>> files;
      std::vector<std::string> paths;
    };
#endif

    void add_executable_entry(compiler::Module &module, std::string_view definitionSymbol) {
      static constexpr std::array<std::uint8_t, 23> entry = {
          0x48, 0x8b, 0x3c, 0x24,       // mov rdi, [rsp]     (argc)
          0x48, 0x8d, 0x74, 0x24, 0x08, // lea rsi, [rsp+8]   (argv)
          0xe8, 0,    0,    0,    0,    // call native definition
          0x89, 0xc7,                   // mov edi, eax      (exit status)
          0xb8, 0x3c, 0,    0,    0,    // mov eax, 60 (exit)
          0x0f, 0x05,                   // syscall
      };
      const std::size_t offset = module.append(compiler::SectionKind::Text, entry, 16);
      module.define(EXECUTABLE_ENTRY_SYMBOL, compiler::SectionKind::Text, offset);
      module.relocate(compiler::SectionKind::Text, offset + 10, compiler::RelocationKind::PCRelative32,
                      std::string(definitionSymbol), -4);
    }

    bool write_native_output(context::Context &context, compiler::Module &module) {
      lexicon::Phrase directive = native_output(context);
      if (directive.isNull()) return false;

      NativeOutputData outputData;
      directive.fetch(0, outputData);
      if (outputData.kind == NativeOutputKind::None) return false;
      const char *pathData =
          reinterpret_cast<const char *>(directive.content(sizeof(outputData), outputData.pathBytes).toPtr());
      const std::string path(pathData, outputData.pathBytes);

      const char *description = nullptr;
      switch (outputData.kind) {
      case NativeOutputKind::Object: description = "native object"; break;
      case NativeOutputKind::Executable: description = "native executable"; break;
      case NativeOutputKind::Raw: description = "raw output"; break;
      case NativeOutputKind::None: THROW(, "native output: invalid output kind")
      }

      const std::optional<std::string> configuredEntry = context.language().moduleEntry();
      const std::string entryName = configuredEntry.value_or(context.staging.phrase.getKey());
      if (outputData.kind != NativeOutputKind::Raw) {
#ifdef RECURLOOP_ENABLE_LLVM
        module = context.language().composeModule(module, {}, false);
#else
        module = context.language().composeModule(module);
#endif
        if (outputData.kind == NativeOutputKind::Executable || configuredEntry.has_value() || !outputData.anonymous) {
          const compiler::Symbol *entry = module.findSymbol(entryName);
          if (entry == nullptr || entry->imported)
            THROW(, description << ": module symbol '" << entryName << "' is missing")
        }
        if (context.language().embedsLanguage()) compiler::LanguageImage::embed(context.language(), module);
      }

      std::vector<std::uint8_t> bytes;
      bool linkedExternally = false;
      switch (outputData.kind) {
      case NativeOutputKind::Object:
#ifdef RECURLOOP_ENABLE_LLVM
      {
        if (!std::string_view(RECURLOOP_LLVM_TARGET_TRIPLE).starts_with("x86_64"))
          THROW(, "LLVM object: the built-in assembler emits x86-64; use fn for target '"
                      << RECURLOOP_LLVM_TARGET_TRIPLE << "' or provide a target-compatible object")
        TemporaryLinkObject object;
        write_file(object.get(), compiler::ElfWriter::write(module), "LLVM assembler input");
        std::vector<std::string> arguments = {RECURLOOP_LLVM_LLD, "-r", "-O" + std::to_string(RECURLOOP_LLVM_OPT_LEVEL),
                                              object.get()};
        LlvmLinkFiles linkFiles(context);
        linkFiles.append(arguments);
        arguments.insert(arguments.end(), {"-o", path});
        run_llvm_linker(arguments, path, "LLVM object");
        linkedExternally = true;
        break;
      }
#else
        bytes = compiler::ElfWriter::write(module);
        break;
#endif
      case NativeOutputKind::Executable:
#ifdef RECURLOOP_ENABLE_LLVM
      {
        if (!std::string_view(RECURLOOP_LLVM_TARGET_TRIPLE).starts_with("x86_64"))
          THROW(, "LLVM executable: the built-in assembler emits x86-64 and cannot be linked for target '"
                      << RECURLOOP_LLVM_TARGET_TRIPLE << "'")
        if (entryName != "main") {
          const compiler::Symbol *entry = module.findSymbol(entryName);
          if (entry == nullptr || entry->imported)
            THROW(, "LLVM executable: entry symbol '" << entryName << "' is missing")
          if (module.findSymbol("main") != nullptr) THROW(, "LLVM executable: module already defines 'main'")
          static constexpr std::array<std::uint8_t, 8> wrapper = {
              0x31, 0xc0,                   // xor eax, eax: a bare ret produces status 0
              0xe8, 0x00, 0x00, 0x00, 0x00, // call configured entry
              0xc3,                         // ret to the C runtime
          };
          const std::size_t wrapperOffset = module.append(compiler::SectionKind::Text, wrapper, 16);
          module.define("main", compiler::SectionKind::Text, wrapperOffset);
          module.relocate(compiler::SectionKind::Text, wrapperOffset + 3, compiler::RelocationKind::PCRelative32,
                          entryName, -4);
        }
        TemporaryLinkObject object;
        write_file(object.get(), compiler::ElfWriter::write(module), "LLVM assembler input");
        std::vector<std::string> arguments = {
            RECURLOOP_LLVM_CLANG,
            "--target=" RECURLOOP_LLVM_TARGET_TRIPLE,
            "-fuse-ld=" RECURLOOP_LLVM_LLD,
            "-no-pie",
            "-Wl,-O" + std::to_string(RECURLOOP_LLVM_OPT_LEVEL),
            object.get(),
        };
        LlvmLinkFiles linkFiles(context);
        linkFiles.append(arguments);
        arguments.insert(arguments.end(), {"-o", path});
        if (std::string_view(RECURLOOP_LLVM_SYSROOT).size() != 0)
          arguments.push_back("--sysroot=" RECURLOOP_LLVM_SYSROOT);
        for (const std::string &searchPath : context.language().linkerSearchPaths())
          arguments.push_back("-L" + searchPath);
        for (const std::string &library : context.language().sharedLibraries()) arguments.push_back("-l" + library);
        run_llvm_linker(arguments, path, "LLVM executable");
        linkedExternally = true;
        break;
      }
#else
        if (context.language().hasSharedLibraries()) {
          write_shared_executable(context, module, entryName, path);
        } else {
          add_executable_entry(module, entryName);
          bytes = compiler::ElfWriter::writeExecutable(module, EXECUTABLE_ENTRY_SYMBOL);
        }
        break;
#endif
      case NativeOutputKind::Raw:
        for (const compiler::Section &section : module.sections()) {
          if (section.type == compiler::SectionType::NoBits) {
            bytes.resize(bytes.size() + section.memorySize, 0);
          } else {
            bytes.insert(bytes.end(), section.bytes.begin(), section.bytes.end());
          }
        }
        break;
      case NativeOutputKind::None: THROW(, "native output: invalid output kind")
      }

      if (!linkedExternally &&
          (outputData.kind != NativeOutputKind::Executable || !context.language().hasSharedLibraries()))
        write_file(path, bytes, description);

      if (outputData.kind == NativeOutputKind::Executable) {
        std::error_code error;
        std::filesystem::permissions(path,
                                     std::filesystem::perms::owner_exec | std::filesystem::perms::group_exec |
                                         std::filesystem::perms::others_exec,
                                     std::filesystem::perm_options::add, error);
        if (error)
          THROW(, "native executable: cannot make output file executable '" << path << "': " << error.message())
      }

      outputData.kind = NativeOutputKind::None;
      directive.update(0, outputData);
      context.language().clearModuleSelection();
      context.workspace.code.clear();
      return true;
    }

    void finalize_native_definition(context::Context &context, lexicon::Phrase &invoked, compiler::Module &module,
                                    const std::vector<NativeImport> &imports) {
      const std::string entrySymbol = Assembler::definitionSymbol(context);
      compiler::LanguageState language = compiler::LanguageState::locate(context.lexicon);
      context.exec.pendingNativeEntry = 0;
      context.exec.pendingNativeSymbol.clear();
      lexicon::Phrase directive = native_output(context);
      NativeOutputData outputData;
      if (!directive.isNull()) directive.fetch(0, outputData);
      if (outputData.kind == NativeOutputKind::None || !outputData.anonymous)
        language.rememberModule(entrySymbol, module);
      if (write_native_output(context, module)) {
        context.workspace.readOnlyData.clear();
        context.workspace.data.clear();
        context.workspace.bssBytes = 0;
        context.workspace.customSections.clear();
        return;
      }
      // Compiled fn definitions use ordinary module-symbol calls. Resolve
      // their already-defined RecurLoop dependencies for JIT just as executable
      // output does; the callback remains responsible only for phrase-invocation
      // imports that carry a process-local address.
      compiler::Module linked = language.composeModule(module);
      const auto resolvableImport = [&](std::string_view symbol) {
        const bool nativeImport = std::any_of(imports.begin(), imports.end(),
                                              [&](const NativeImport &candidate) { return candidate.name == symbol; });
        if (nativeImport) return true;
        return compiler::DynamicLinker::instance().resolveFromDefault(symbol).has_value();
      };
      const bool unresolved =
          std::any_of(linked.symbols().begin(), linked.symbols().end(), [&](const compiler::Symbol &symbol) {
            return symbol.imported && symbol.binding != compiler::SymbolBinding::Weak && !resolvableImport(symbol.name);
          });
      if (unresolved) {
        context.staging.phrase.setType(lexicon::phrase::type::getCallable(invoked))
            .setAction(invoke_deferred_native_action);
        context.exec.pendingNativeSymbol = entrySymbol;
        context.workspace.code.clear();
        context.workspace.readOnlyData.clear();
        context.workspace.data.clear();
        context.workspace.bssBytes = 0;
        context.workspace.customSections.clear();
        return;
      }
      const compiler::JitImage image = compiler::JitLinker::link(
          linked, context.runtime, [&](std::string_view symbol) -> std::optional<std::uintptr_t> {
            const auto found = std::find_if(imports.begin(), imports.end(),
                                            [&](const NativeImport &candidate) { return candidate.name == symbol; });
            if (found != imports.end()) return found->address;
            return compiler::DynamicLinker::instance().resolveFromDefault(symbol);
          });
      const std::uintptr_t entry = image.address(entrySymbol);
      // Definitions without process-local phrase imports retain their module
      // and symbol as persistent state. Their eagerly linked entry is merely a
      // process-local cache, so the serialized action remains deferred.
      context.staging.phrase.setType(lexicon::phrase::type::getCallable(invoked))
          .setAction(imports.empty() ? invoke_deferred_native_action : invoke_native_action);
      context.exec.pendingNativeEntry = entry;
      context.exec.pendingNativeSymbol = entrySymbol;
      context.workspace.code.clear();
      context.workspace.readOnlyData.clear();
      context.workspace.data.clear();
      context.workspace.bssBytes = 0;
      context.workspace.customSections.clear();
    }

    void append_native_data_sections(context::Context &context, compiler::Module &module) {
      if (!context.workspace.readOnlyData.empty())
        module.append(compiler::SectionKind::ReadOnlyData, context.workspace.readOnlyData, 1);
      if (!context.workspace.data.empty()) module.append(compiler::SectionKind::Data, context.workspace.data, 1);
      if (context.workspace.bssBytes != 0) module.reserve(compiler::SectionKind::Bss, context.workspace.bssBytes, 1);
      for (const context::Workspace::NativeSection &input : context.workspace.customSections) {
        const compiler::SectionId id =
            module.addSection(input.name, static_cast<compiler::SectionType>(input.type),
                              static_cast<compiler::SectionFlag>(input.flags), input.alignment);
        if (static_cast<compiler::SectionType>(input.type) == compiler::SectionType::NoBits)
          module.reserve(id, input.memorySize, input.alignment);
        else if (!input.bytes.empty())
          module.append(id, input.bytes, input.alignment);
      }
    }

    void assembler_resolve_invocations(context::Context &context, lexicon::Phrase &session,
                                       const AssemblerSessionData &sessionData, compiler::Module *module,
                                       std::vector<NativeImport> *imports) {
      auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };
      Size invocationIndex = 0;

      for (lexicon::Dictionary cursor = session.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
        const std::string entryKey = cursor.getKey();
        if (entryKey.empty() || static_cast<unsigned char>(entryKey[0]) != ASSEMBLER_INVOCATION) continue;

        lexicon::Phrase record = cursor.getPhrase();
        AssemblerInvocationData invocation;
        record.fetch(0, invocation);
        const compiler::Assembler::Location location =
            assembler_load_location(record, offsetof(AssemblerInvocationData, source));
        const char *referenceData = reinterpret_cast<const char *>(
            record.content(sizeof(invocation) + invocation.source.pathBytes, invocation.referenceBytes).toPtr());
        const std::string reference(referenceData, invocation.referenceBytes);

        lexicon::Phrase target =
            resolve_phrase_reference(context, sessionData.referenceRootAddress, reference, location, true);
        if (compiled_scope_open(context)) {
          lexicon::Phrase compiledSession = compiled_scope_session(context);
          CompiledScopeSessionData compiledData;
          compiledSession.fetch(0, compiledData);
          if (target.getAddress() >= compiledData.lexiconCheckpoint)
            assembler_fail(location, "phrase reference '<" + reference +
                                         ">' resolves to a temporary phrase that will not survive the compiled block");
        }
        if (invocation.nativeAbi) {
          if (invocation.trampolineAddressPatchOffset < sessionData.codeStartBits / Byte::length ||
              invocation.trampolineAddressPatchOffset > context.workspace.code.size() ||
              sizeof(std::int32_t) > context.workspace.code.size() - invocation.trampolineAddressPatchOffset)
            assembler_fail(location, "native ABI invocation patch points outside the assembler block");
          if (module == nullptr) assembler_fail(location, "native ABI invocation requires an object module");
          if (module->findSymbol(reference) == nullptr) module->import(reference);
          module->relocate(compiler::SectionKind::Text, invocation.trampolineAddressPatchOffset,
                           compiler::RelocationKind::PCRelative32, reference, -4);
          ++invocationIndex;
          continue;
        }

        assembler_validate_invocation_patch(context, sessionData, invocation.contextAddressPatchOffset, location);
        assembler_validate_invocation_patch(context, sessionData, invocation.phraseAddressPatchOffset, location);
        assembler_validate_invocation_patch(context, sessionData, invocation.trampolineAddressPatchOffset, location);

        if (module == nullptr) {
          assembler_patch_u64(context, invocation.contextAddressPatchOffset, reinterpret_cast<std::uintptr_t>(&context),
                              location);
          assembler_patch_u64(context, invocation.phraseAddressPatchOffset,
                              static_cast<std::uintptr_t>(target.getAddress()), location);
          assembler_patch_u64(context, invocation.trampolineAddressPatchOffset,
                              reinterpret_cast<std::uintptr_t>(&invoke_phrase), location);
        } else {
          if (imports == nullptr) assembler_fail(location, "internal native import registry is missing");
          add_native_invocation(context, *module, *imports, invocationIndex, invocation.contextAddressPatchOffset,
                                invocation.phraseAddressPatchOffset, invocation.trampolineAddressPatchOffset,
                                target.getAddress());
        }
        ++invocationIndex;
      }
    }

    std::string assembler_label_symbol(const std::string &label) {
      return label;
    }

    void assembler_resolve_labels(context::Context &context, lexicon::Phrase &session,
                                  const AssemblerSessionData &sessionData, compiler::Module *module) {
      auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };

      for (lexicon::Dictionary cursor = session.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
        const std::string entryKey = cursor.getKey();
        if (!entryKey.empty() && static_cast<unsigned char>(entryKey[0]) == ASSEMBLER_INVOCATION) continue;

        lexicon::Phrase label = cursor.getPhrase();
        AssemblerLabelData labelData;
        label.fetch(0, labelData);

        if (labelData.defined && module != nullptr)
          module->define(assembler_label_symbol(label.getKey()), labelData.section, labelData.codeOffset);

        for (lexicon::Dictionary child = label.fore(filter); !child.isNull(); child = child.next(filter)) {
          const std::string key = child.getKey();
          if (key.empty() || static_cast<unsigned char>(key[0]) != ASSEMBLER_RELOCATION) continue;

          lexicon::Phrase reference = child.getPhrase();
          AssemblerRelocationData relocation;
          reference.fetch(0, relocation);
          const compiler::Assembler::Location location =
              assembler_load_location(reference, offsetof(AssemblerRelocationData, source));

          if (!labelData.defined) assembler_fail(location, "undefined label '" + label.getKey() + "'");
          if (relocation.kind != static_cast<std::uint8_t>(compiler::Assembler::RelocationKind::Relative32))
            assembler_fail(location, "unsupported relocation kind");
          if (relocation.patchOffset < sessionData.codeStartBits / Byte::length ||
              relocation.patchOffset + sizeof(std::int32_t) > context.workspace.code.size())
            assembler_fail(location, "relocation points outside the current assembler block");

          const std::int64_t relative =
              static_cast<std::int64_t>(labelData.codeOffset) - static_cast<std::int64_t>(relocation.instructionEnd);
          if (!assembler_fits_relative32(relative))
            assembler_fail(location, "branch to label '" + label.getKey() + "' is out of 32-bit range");

          if (module != nullptr) {
            // Module uses S + A - P; assembler branches use S - instructionEnd.
            const std::int64_t addend = static_cast<std::int64_t>(relocation.patchOffset) -
                                        static_cast<std::int64_t>(relocation.instructionEnd);
            module->relocate(compiler::SectionKind::Text, relocation.patchOffset,
                             compiler::RelocationKind::PCRelative32, assembler_label_symbol(label.getKey()), addend);
            continue;
          }

          // First-pass placeholders are patched only while handling the closing }.
          std::uint8_t *patch = context.workspace.code.getMemory().toPtr() + relocation.patchOffset;
          const std::uint32_t encoded = static_cast<std::uint32_t>(relative);
          for (Size byte = 0; byte < sizeof(encoded); ++byte)
            patch[byte] = static_cast<std::uint8_t>(encoded >> (byte * Byte::length));
        }
      }
    }

    void assembler_second_pass(context::Context &context, lexicon::Phrase &session,
                               const AssemblerSessionData &sessionData) {
      assembler_resolve_invocations(context, session, sessionData);
      assembler_resolve_labels(context, session, sessionData, nullptr);
    }

    NativeDefinition assembler_link_staged_definition(context::Context &context, lexicon::Phrase &invoked,
                                                      lexicon::Phrase &session,
                                                      const AssemblerSessionData &sessionData) {
      NativeDefinition result;
      const std::span<const std::uint8_t> code(context.workspace.code.getMemory().toPtr(),
                                               context.workspace.code.size());
      const std::size_t entryOffset = result.module.append(compiler::SectionKind::Text, code, 16);
      append_native_data_sections(context, result.module);
      Assembler::defineEntry(context, result.module, entryOffset);
      assembler_resolve_invocations(context, session, sessionData, &result.module, &result.imports);
      assembler_resolve_labels(context, session, sessionData, &result.module);
      return result;
    }

    NativeDefinition link_compiled_scope_definition(context::Context &context, lexicon::Phrase &invoked,
                                                    lexicon::Phrase &session,
                                                    const CompiledScopeSessionData &sessionData) {
#ifdef RECURLOOP_ENABLE_LLVM
      std::vector<function_internal::LlvmPhraseCall> calls;
      calls.reserve(sessionData.invocationCount);
      auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };
      for (lexicon::Dictionary cursor = session.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
        const std::string key = cursor.getKey();
        if (key.empty() || static_cast<unsigned char>(key[0]) != COMPILED_INVOCATION) continue;
        lexicon::Phrase record = cursor.getPhrase();
        CompiledInvocationData data;
        record.fetch(0, data);
        const std::size_t payload = record.payloadSize();
        if (payload < sizeof(data) || data.referenceBytes > payload - sizeof(data) ||
            data.argumentCount > (payload - sizeof(data) - data.referenceBytes) / sizeof(CompiledArgumentData))
          THROW(, "compiled phrase invocation payload is invalid")
        const std::size_t required =
            sizeof(data) + data.referenceBytes + data.argumentCount * sizeof(CompiledArgumentData);
        if (required != payload) THROW(, "compiled phrase invocation payload is invalid")
        const char *name = reinterpret_cast<const char *>(record.content(sizeof(data), data.referenceBytes).toPtr());
        function_internal::LlvmPhraseCall call;
        call.symbol.assign(name, data.referenceBytes);
        call.function = data.nativeAbi ? context.language().findFunction(call.symbol) : std::nullopt;
        call.directEntry = data.directEntry;
        call.trampoline = reinterpret_cast<std::uintptr_t>(&invoke_phrase);
        call.phraseAddress = data.phraseAddress;
        call.line = data.line;
        call.column = data.column;
        call.nativeAbi = data.nativeAbi;
        std::size_t offset = sizeof(data) + data.referenceBytes;
        for (std::size_t index = 0; index < data.argumentCount; ++index) {
          CompiledArgumentData argument;
          std::memcpy(&argument, record.content(offset, sizeof(argument)).toPtr(), sizeof(argument));
          call.arguments.push_back(compiler::TypedValue::integer(argument.type, argument.value, argument.bytes));
          offset += sizeof(argument);
        }
        calls.push_back(std::move(call));
      }
      if (calls.size() != sessionData.invocationCount) THROW(, "compiled phrase invocation registry is incomplete")
      function_internal::LlvmPhraseModule generated =
          function_internal::generateLlvmPhraseModule(context, Assembler::definitionSymbol(context), calls);
      NativeDefinition result;
      result.module = std::move(generated.module);
      result.imports.reserve(generated.imports.size());
      for (function_internal::LlvmRuntimeImport &item : generated.imports)
        result.imports.push_back({std::move(item.name), item.address});
      return result;
#else
      NativeDefinition result;
      const std::span<const std::uint8_t> code(context.workspace.code.getMemory().toPtr(),
                                               context.workspace.code.size());
      const std::size_t entryOffset = result.module.append(compiler::SectionKind::Text, code, 16);
      append_native_data_sections(context, result.module);
      Assembler::defineEntry(context, result.module, entryOffset);

      auto filter = [](radix::Node *item, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };
      Size invocationIndex = 0;
      for (lexicon::Dictionary cursor = session.fore(filter); !cursor.isNull(); cursor = cursor.next(filter)) {
        const std::string key = cursor.getKey();
        if (key.empty() || static_cast<unsigned char>(key[0]) != COMPILED_INVOCATION) continue;

        CompiledInvocationData invocation;
        lexicon::Phrase record = cursor.getPhrase();
        record.fetch(0, invocation);
        if (invocation.nativeAbi) {
          if (invocation.trampolineAddressPatchOffset > context.workspace.code.size() ||
              sizeof(std::int32_t) > context.workspace.code.size() - invocation.trampolineAddressPatchOffset)
            THROW(, "compiled phrase: native ABI invocation relocation points outside generated code")
          std::string symbol;
          if (invocation.directEntry != 0) {
            symbol = ".Lrecurloop.direct." + std::to_string(invocationIndex);
            add_native_import(result.module, result.imports, symbol, invocation.directEntry);
          } else {
            const char *name =
                reinterpret_cast<const char *>(record.content(sizeof(invocation), invocation.referenceBytes).toPtr());
            symbol.assign(name, invocation.referenceBytes);
            if (result.module.findSymbol(symbol) == nullptr) result.module.import(symbol);
          }
          result.module.relocate(compiler::SectionKind::Text, invocation.trampolineAddressPatchOffset,
                                 compiler::RelocationKind::PCRelative32, symbol, -4);
          ++invocationIndex;
          continue;
        }
        const auto validPatch = [&](Size offset) {
          return offset >= sessionData.codeStartBits / Byte::length && offset <= context.workspace.code.size() &&
                 sizeof(std::uint64_t) <= context.workspace.code.size() - offset;
        };
        if (!validPatch(invocation.contextAddressPatchOffset) || !validPatch(invocation.phraseAddressPatchOffset) ||
            !validPatch(invocation.trampolineAddressPatchOffset))
          THROW(, "compiled phrase: internal invocation relocation points outside generated code")

        add_native_invocation(context, result.module, result.imports, invocationIndex,
                              invocation.contextAddressPatchOffset, invocation.phraseAddressPatchOffset,
                              invocation.trampolineAddressPatchOffset, invocation.phraseAddress);
        ++invocationIndex;
      }
      if (invocationIndex != sessionData.invocationCount)
        THROW(, "compiled phrase: internal invocation registry is incomplete")
      return result;
#endif
    }
  } // namespace assembler_internal

  void Assembler::finalizeLlvm(context::Context &context, lexicon::Phrase &,
                               std::span<const std::vector<std::uint8_t>> objects,
                               std::span<const std::string> providedSymbols, std::span<const std::string> imports) {
#ifndef RECURLOOP_ENABLE_LLVM
    (void)context;
    (void)objects;
    (void)providedSymbols;
    (void)imports;
    THROW(, "LLVM output was requested from a build without RECURLOOP_ENABLE_LLVM")
#else
    const std::optional<NativeFileRequest> request = nativeFileRequest(context);
    if (!request || request->kind == NativeFileKind::Raw)
      THROW(, "LLVM output requires an active object or executable directive")

    compiler::Module dependencyRoot;
    for (const std::string &symbol : imports)
      if (dependencyRoot.findSymbol(symbol) == nullptr) dependencyRoot.import(symbol);
    if (objects.empty()) THROW(, "LLVM output did not produce an object")
    compiler::Module dependencies = context.language().composeModule(dependencyRoot, providedSymbols, false);
    if (context.language().embedsLanguage()) compiler::LanguageImage::embed(context.language(), dependencies);
    const bool hasDependencies = std::any_of(dependencies.symbols().begin(), dependencies.symbols().end(),
                                             [](const compiler::Symbol &symbol) { return !symbol.imported; });

    std::vector<std::unique_ptr<assembler_internal::TemporaryLinkObject>> llvmObjects;
    std::vector<std::string> llvmPaths;
    llvmObjects.reserve(objects.size());
    llvmPaths.reserve(objects.size());
    for (const std::vector<std::uint8_t> &object : objects) {
      auto file = std::make_unique<assembler_internal::TemporaryLinkObject>();
      assembler_internal::write_file(file->get(), object, "LLVM temporary object");
      llvmPaths.push_back(file->get());
      llvmObjects.push_back(std::move(file));
    }
    assembler_internal::TemporaryLinkObject dependencyObject;
    if (hasDependencies)
      assembler_internal::write_file(dependencyObject.get(), compiler::ElfWriter::write(dependencies),
                                     "LLVM dependency object");

    std::vector<std::string> arguments;
    assembler_internal::LlvmLinkFiles linkFiles(context);
    if (request->kind == NativeFileKind::Object) {
      arguments = {RECURLOOP_LLVM_LLD, "-r", "-O" + std::to_string(RECURLOOP_LLVM_OPT_LEVEL)};
      arguments.insert(arguments.end(), llvmPaths.begin(), llvmPaths.end());
      if (hasDependencies) arguments.push_back(dependencyObject.get());
      linkFiles.append(arguments);
      arguments.insert(arguments.end(), {"-o", request->path});
      assembler_internal::run_llvm_linker(arguments, request->path, "LLVM object");
    } else {
      arguments = {RECURLOOP_LLVM_CLANG, "--target=" RECURLOOP_LLVM_TARGET_TRIPLE, "-fuse-ld=" RECURLOOP_LLVM_LLD,
                   "-no-pie", "-Wl,-O" + std::to_string(RECURLOOP_LLVM_OPT_LEVEL)};
      arguments.insert(arguments.end(), llvmPaths.begin(), llvmPaths.end());
      if (hasDependencies) arguments.push_back(dependencyObject.get());
      linkFiles.append(arguments);
      arguments.insert(arguments.end(), {"-o", request->path});
      if (std::string_view(RECURLOOP_LLVM_SYSROOT).size() != 0)
        arguments.push_back("--sysroot=" RECURLOOP_LLVM_SYSROOT);
      for (const std::string &path : context.language().linkerSearchPaths()) arguments.push_back("-L" + path);
      for (const std::string &library : context.language().sharedLibraries()) arguments.push_back("-l" + library);
      assembler_internal::run_llvm_linker(arguments, request->path, "LLVM executable");
      std::error_code error;
      std::filesystem::permissions(request->path,
                                   std::filesystem::perms::owner_exec | std::filesystem::perms::group_exec |
                                       std::filesystem::perms::others_exec,
                                   std::filesystem::perm_options::add, error);
      if (error)
        THROW(, "LLVM executable: cannot make output file executable '" << request->path << "': " << error.message())
    }

    lexicon::Phrase directive = assembler_internal::native_output(context);
    NativeOutputData data;
    directive.fetch(0, data);
    data.kind = NativeOutputKind::None;
    directive.update(0, data);
    context.language().clearModuleSelection();
    context.workspace.code.clear();
    context.workspace.readOnlyData.clear();
    context.workspace.data.clear();
    context.workspace.bssBytes = 0;
    context.workspace.customSections.clear();
#endif
  }
} // namespace recurloop
