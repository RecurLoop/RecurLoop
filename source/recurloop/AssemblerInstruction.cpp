#include "AssemblerInternal.hpp"

#include <recurloop/LanguageGrammar.hpp>

namespace recurloop {
  namespace assembler_internal {
std::string assembler_read_identifier_suffix(context::Context &context) {
    std::string suffix;
    while (true) {
      const char character = assembler_peek(context);
      if (!std::isalnum(static_cast<unsigned char>(character)) && character != '_' && character != '.' &&
          character != '$')
        return suffix;
      suffix.push_back(character);
      context::Source::progress(context, Byte::length);
    }
  }

void assembler_enter_operand_parser(context::Context &context, const std::string &mnemonic,
                                             const compiler::Assembler::Location &location) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (data.instructionOpen) assembler_fail(location, "an assembler instruction is already being parsed");
    if (mnemonic.size() >= sizeof(data.mnemonic)) assembler_fail(location, "instruction mnemonic is too long");

    data.instructionLine = location.line;
    data.instructionColumn = location.column;
    data.instructionLexiconCheckpoint = context.lexicon.checkpoint().getAddress();
    data.operandCount = 0;
    data.instructionOpen = true;
    data.operandRequired = false;
    data.operand = {};
    std::fill(std::begin(data.mnemonic), std::end(data.mnemonic), '\0');
    std::copy(mnemonic.begin(), mnemonic.end(), data.mnemonic);
    session.update(0, data);

    lexicon::Phrase body = assembler_body(context);
    lexicon::Phrase parser = assembler_match_phrase(body, phrases::OPERANDS);
    if (parser.isNull()) assembler_fail(location, "internal operand parser phrase is missing");

    context.workspace.key.clear();
    context::Lookup::enter(context, parser);
  }

void assembler_emit_open_instruction(context::Context &context) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (!data.instructionOpen)
      assembler_fail(assembler_location(context), "internal operand parser has no open instruction");

    compiler::Assembler::Location location;
    location.path = context.source.path;
    location.line = data.instructionLine;
    location.column = data.instructionColumn;
    compiler::Assembler::Instruction instruction;
    instruction.mnemonic = data.mnemonic;
    instruction.location = location;
    instruction.operands.reserve(data.operandCount);
    for (Size index = 0; index < data.operandCount; ++index) {
      lexicon::Phrase record = assembler_match_phrase(session, assembler_operand_key(index));
      if (record.isNull()) assembler_fail(location, "internal operand phrase is missing");

      AssemblerOperandData operand;
      record.fetch(0, operand);
      switch (operand.kind) {
      case AssemblerOperandKind::REGISTER: instruction.operands.emplace_back(operand.reg); break;
      case AssemblerOperandKind::MEMORY: {
        compiler::Assembler::Memory memory;
        if (operand.memory.hasBase) memory.base = operand.memory.base;
        if (operand.memory.hasIndex) memory.index = operand.memory.index;
        memory.scale = operand.memory.scale;
        memory.displacement = operand.memory.displacement;
        memory.bits = operand.memory.bits;
        instruction.operands.emplace_back(memory);
        break;
      }
      case AssemblerOperandKind::IMMEDIATE:
        instruction.operands.emplace_back(compiler::Assembler::Immediate{operand.immediate});
        break;
      case AssemblerOperandKind::LABEL: {
        const char *label = reinterpret_cast<const char *>(record.content(sizeof(operand), operand.labelBytes).toPtr());
        instruction.operands.emplace_back(compiler::Assembler::LabelOperand{std::string(label, operand.labelBytes)});
        break;
      }
      case AssemblerOperandKind::EMPTY: assembler_fail(location, "internal operand phrase is empty");
      }
    }

    const compiler::Assembler::Result result = compiler::Assembler::encode(std::move(instruction));
    const Size instructionStart = context.workspace.code.size();
    if (instructionStart + result.code.size() + 1 > context.workspace.code.getCapacity())
      assembler_fail(location, "generated code exceeds workspace.code capacity");

    // Completed operand phrases are instruction-local. Restore their arena
    // before relocation phrases are created so only the latter survive until
    // the assembler block's second pass.
    radix::Checkpoint(&context.lexicon, data.instructionLexiconCheckpoint).restore();
    for (const compiler::Assembler::Relocation &relocation : result.relocations)
      assembler_add_relocation(context, relocation, instructionStart);
    if (!result.code.empty())
      context.workspace.code.append(Byte((unsigned char *)result.code.data()), result.code.size());

    data.instructionOpen = false;
    data.instructionLexiconCheckpoint = 0;
    data.operandCount = 0;
    data.operandRequired = false;
    data.operand = {};
    std::fill(std::begin(data.mnemonic), std::end(data.mnemonic), '\0');
    session.update(0, data);
    context.workspace.key.clear();
  }

void assembler_leave_operand_parser(context::Context &context) {
    if (context.lookup.stack.empty())
      assembler_fail(assembler_location(context), "internal operand parser lookup stack is empty");
    context.lookup.dictionary = context.lookup.stack.back();
    context.lookup.stack.pop_back();
  }

void assembler_discard_open_instruction(context::Context &context) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (data.instructionOpen) radix::Checkpoint(&context.lexicon, data.instructionLexiconCheckpoint).restore();
    data.instructionOpen = false;
    data.instructionLexiconCheckpoint = 0;
    data.operandCount = 0;
    data.operandRequired = false;
    data.operand = {};
    std::fill(std::begin(data.mnemonic), std::end(data.mnemonic), '\0');
    session.update(0, data);
    context.workspace.key.clear();
    assembler_leave_operand_parser(context);
  }

void action_assembler_instruction(context::Context &context, lexicon::Phrase &invoked,
                                           const std::string &mnemonic, std::string_view spelling) {
    DEBUG_PROFILE_SCOPE(AssemblerInstruction);
    std::string invokedName = spelling.empty() ? invoked.getKey() : std::string(spelling);
    const compiler::Assembler::Location location = assembler_location(context, invokedName.size());
    AssemblerSessionData sectionState;
    assembler_session(context).fetch(0, sectionState);
    if (sectionState.currentSection != compiler::Module::id(compiler::SectionKind::Text))
      assembler_fail(location, "machine instructions may only be emitted in .text");
    const std::string suffix = assembler_read_identifier_suffix(context);
    assembler_skip_horizontal_whitespace(context);
    if (assembler_peek(context) == ':') {
      context::Source::progress(context, Byte::length);
      assembler_define_label(context, invokedName + suffix, location);
      return;
    }
    if (!suffix.empty()) {
      const std::string extended = invokedName + suffix;
      lexicon::Phrase resolved = LanguageGrammar::resolve(context, assembler_body(context), extended);
      if (resolved.isNull() || assembler_instruction_name(resolved) != mnemonic)
        assembler_fail(location, "unknown instruction '" + extended + "'");
      invokedName = extended;
    }

    assembler_enter_operand_parser(context, mnemonic, location);
  }

std::string assembler_instruction_name(lexicon::Phrase phrase) {
    while (!phrase.isNull()) {
      if (phrase.payloadSize() >= sizeof(AssemblerInstruction)) {
        AssemblerInstruction descriptor{""};
        phrase.fetch(0, descriptor);
        if (descriptor.magic == AssemblerInstruction::Magic)
          return std::string(descriptor.mnemonic, strnlen(descriptor.mnemonic, sizeof(descriptor.mnemonic)));
      }
      if (!phrase.containsPrototype()) break;
      phrase = phrase.getPrototype();
    }
    THROW(, "assembler instruction phrase has no encoding descriptor")
  }

std::vector<std::uint8_t> &assembler_initialized_section(context::Context &context, Size kind,
                                                                  const compiler::Assembler::Location &location) {
    switch (kind) {
    case compiler::Module::id(compiler::SectionKind::ReadOnlyData): return context.workspace.readOnlyData;
    case compiler::Module::id(compiler::SectionKind::Data): return context.workspace.data;
    case compiler::Module::id(compiler::SectionKind::Text):
    case compiler::Module::id(compiler::SectionKind::Bss): break;
    default: {
      const Size custom = kind - compiler::Module::id(compiler::SectionKind::Count);
      if (custom < context.workspace.customSections.size() && context.workspace.customSections[custom].type != 1)
        return context.workspace.customSections[custom].bytes;
      break;
    }
    }
    assembler_fail(location, "initialized data may only be emitted in .rodata or .data");
  }

std::uint64_t assembler_parse_data_integer(const std::string &source,
                                                    const compiler::Assembler::Location &location) {
    if (source.size() >= 3 && source.front() == '\'' && source.back() == '\'') {
      if (source.size() == 3) return static_cast<unsigned char>(source[1]);
      if (source.size() == 4 && source[1] == '\\') {
        switch (source[2]) {
        case '0': return 0;
        case 'n': return '\n';
        case 'r': return '\r';
        case 't': return '\t';
        case '\\': return '\\';
        case '\'': return '\'';
        }
      }
      assembler_fail(location, "invalid character literal '" + source + "'");
    }
    std::string text = source;
    bool negative = false;
    if (!text.empty() && (text.front() == '+' || text.front() == '-')) {
      negative = text.front() == '-';
      text.erase(text.begin());
    }
    int base = 10;
    if (text.starts_with("0x") || text.starts_with("0X")) {
      base = 16;
      text.erase(0, 2);
    } else if (text.starts_with("0b") || text.starts_with("0B")) {
      base = 2;
      text.erase(0, 2);
    } else if (text.starts_with("0o") || text.starts_with("0O")) {
      base = 8;
      text.erase(0, 2);
    }
    std::uint64_t value = 0;
    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value, base);
    if (text.empty() || error != std::errc() || end != text.data() + text.size())
      assembler_fail(location, "invalid data value '" + source + "'");
    return negative ? std::uint64_t{0} - value : value;
  }

void action_assembler_section(context::Context &context, lexicon::Phrase &invoked) {
    AssemblerSessionData data;
    assembler_session(context).fetch(0, data);
    compiler::SectionKind kind;
    invoked.fetch(0, kind);
    data.currentSection = compiler::Module::id(kind);
    assembler_session(context).update(0, data);
  }

void action_assembler_custom_section(context::Context &context, lexicon::Phrase &invoked) {
    const compiler::Assembler::Location location = assembler_location(context, invoked.getKey().size());
    assembler_skip_horizontal_whitespace(context);
    std::vector<std::string> tokens;
    while (!assembler_statement_separator(assembler_peek(context)) && assembler_peek(context) != '\0') {
      std::string token;
      while (!assembler_horizontal_whitespace(assembler_peek(context)) &&
             !assembler_statement_separator(assembler_peek(context)) && assembler_peek(context) != '\0') {
        token.push_back(assembler_peek(context));
        context::Source::progress(context, Byte::length);
      }
      if (!token.empty()) tokens.push_back(std::move(token));
      assembler_skip_horizontal_whitespace(context);
    }
    if (tokens.empty() || tokens.front().empty()) assembler_fail(location, ".section requires a name");
    context::Workspace::NativeSection section;
    section.name = tokens.front();
    compiler::SectionFlag flags = compiler::SectionFlag::None;
    compiler::SectionType type = compiler::SectionType::ProgramBits;
    for (std::size_t index = 1; index < tokens.size(); ++index) {
      const std::string &token = tokens[index];
      const std::size_t separator = token.find('=');
      const std::string_view spelling(token.data(), separator == std::string::npos ? token.size() : separator);
      lexicon::Phrase qualifier = LanguageGrammar::resolve(context, invoked, spelling);
      lexicon::Phrase metadata = LanguageGrammar::metadata(qualifier, sizeof(AssemblerSectionQualifier));
      if (metadata.isNull()) assembler_fail(location, "unknown .section qualifier '" + token + "'");
      AssemblerSectionQualifier descriptor{AssemblerSectionQualifier::Kind::Flag};
      metadata.fetch(0, descriptor);
      if (descriptor.magic != AssemblerSectionQualifier::Magic)
        assembler_fail(location, "invalid .section qualifier '" + token + "'");
      switch (descriptor.kind) {
      case AssemblerSectionQualifier::Kind::Flag:
        if (separator != std::string::npos)
          assembler_fail(location, "unexpected value in .section qualifier '" + token + "'");
        flags = flags | static_cast<compiler::SectionFlag>(descriptor.value);
        break;
      case AssemblerSectionQualifier::Kind::Type:
        if (separator != std::string::npos)
          assembler_fail(location, "unexpected value in .section qualifier '" + token + "'");
        type = static_cast<compiler::SectionType>(descriptor.value);
        break;
      case AssemblerSectionQualifier::Kind::Alignment:
        if (separator == std::string::npos || separator + 1 == token.size())
          assembler_fail(location, ".section alignment qualifier requires '=value'");
        section.alignment = assembler_parse_data_integer(token.substr(separator + 1), location);
        break;
      }
    }
    section.type = static_cast<std::uint8_t>(type);
    section.flags = static_cast<std::uint16_t>(flags);
    const auto found = std::find_if(context.workspace.customSections.begin(), context.workspace.customSections.end(),
                                    [&](const auto &candidate) { return candidate.name == section.name; });
    Size index;
    if (found == context.workspace.customSections.end()) {
      index = context.workspace.customSections.size();
      context.workspace.customSections.push_back(std::move(section));
    } else {
      index = static_cast<Size>(found - context.workspace.customSections.begin());
    }
    AssemblerSessionData data;
    assembler_session(context).fetch(0, data);
    data.currentSection = compiler::Module::id(compiler::SectionKind::Count) + index;
    assembler_session(context).update(0, data);
  }

void action_assembler_bytes(context::Context &context, lexicon::Phrase &invoked) {
    const compiler::Assembler::Location location = assembler_location(context, invoked.getKey().size());
    AssemblerSessionData state;
    assembler_session(context).fetch(0, state);
    const bool textSection = state.currentSection == compiler::Module::id(compiler::SectionKind::Text);
    std::vector<std::uint8_t> *sectionOutput =
        textSection ? nullptr : &assembler_initialized_section(context, state.currentSection, location);
    const auto appendByte = [&](std::uint8_t value) {
      if (textSection) {
        if (context.workspace.code.size() + 1 > context.workspace.code.getCapacity())
          assembler_fail(location, "data directive exceeds workspace.code capacity");
        context.workspace.code.append(value);
      } else {
        sectionOutput->push_back(value);
      }
    };
    std::uint8_t width = 0;
    invoked.fetch(0, width);
    assembler_skip_horizontal_whitespace(context);
    bool emitted = false;
    while (true) {
      const char current = assembler_peek(context);
      if (assembler_statement_separator(current) || current == '\0') break;
      if (current == '"') {
        if (width != 1) assembler_fail(location, "string literals are only valid with db");
        context::Source::progress(context, Byte::length);
        bool escaped = false;
        while (true) {
          const char character = assembler_peek(context);
          if (character == '\0' || character == '\n') assembler_fail(location, "unterminated data string");
          context::Source::progress(context, Byte::length);
          if (!escaped && character == '"') break;
          if (!escaped && character == '\\') {
            escaped = true;
            continue;
          }
          if (escaped) {
            switch (character) {
            case '0': appendByte(0); break;
            case 'n': appendByte('\n'); break;
            case 'r': appendByte('\r'); break;
            case 't': appendByte('\t'); break;
            default: appendByte(static_cast<std::uint8_t>(character)); break;
            }
            escaped = false;
          } else {
            appendByte(static_cast<std::uint8_t>(character));
          }
        }
      } else {
        std::string token;
        bool quoted = false;
        while (true) {
          const char character = assembler_peek(context);
          if (character == '\'') quoted = !quoted;
          if (!quoted && (character == ',' || assembler_horizontal_whitespace(character) ||
                          assembler_statement_separator(character) || character == '\0'))
            break;
          token.push_back(character);
          context::Source::progress(context, Byte::length);
        }
        const std::uint64_t value = assembler_parse_data_integer(token, location);
        for (std::uint8_t byte = 0; byte < width; ++byte) appendByte(static_cast<std::uint8_t>(value >> (byte * 8)));
      }
      emitted = true;
      assembler_skip_horizontal_whitespace(context);
      if (assembler_peek(context) != ',') break;
      context::Source::progress(context, Byte::length);
      assembler_skip_horizontal_whitespace(context);
    }
    if (!emitted) assembler_fail(location, "data directive requires at least one value");
  }

void action_assembler_reserve(context::Context &context, lexicon::Phrase &invoked) {
    const compiler::Assembler::Location location = assembler_location(context, invoked.getKey().size());
    AssemblerSessionData state;
    assembler_session(context).fetch(0, state);
    const bool standardBss = state.currentSection == compiler::Module::id(compiler::SectionKind::Bss);
    const Size customIndex = state.currentSection >= compiler::Module::id(compiler::SectionKind::Count)
                                 ? state.currentSection - compiler::Module::id(compiler::SectionKind::Count)
                                 : std::numeric_limits<Size>::max();
    const bool customBss =
        customIndex < context.workspace.customSections.size() &&
        context.workspace.customSections[customIndex].type == static_cast<std::uint8_t>(compiler::SectionType::NoBits);
    if (!standardBss && !customBss) assembler_fail(location, "resb may only be used in a NOBITS section");
    assembler_skip_horizontal_whitespace(context);
    std::string token;
    while (true) {
      const char character = assembler_peek(context);
      if (assembler_horizontal_whitespace(character) || assembler_statement_separator(character) || character == '\0')
        break;
      token.push_back(character);
      context::Source::progress(context, Byte::length);
    }
    const std::uint64_t bytes = assembler_parse_data_integer(token, location);
    Size &extent = standardBss ? context.workspace.bssBytes : context.workspace.customSections[customIndex].memorySize;
    if (bytes > std::numeric_limits<Size>::max() - extent)
      assembler_fail(location, "BSS reservation exceeds addressable size");
    extent += static_cast<Size>(bytes);
  }
  } // namespace assembler_internal
} // namespace recurloop
