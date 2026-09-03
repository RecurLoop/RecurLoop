#include "AssemblerInternal.hpp"

#include <recurloop/LanguageGrammar.hpp>

namespace recurloop {
  namespace assembler_internal {
compiler::Assembler::Location assembler_open_instruction_location(context::Context &context) {
    AssemblerSessionData data;
    assembler_session(context).fetch(0, data);
    return {context.source.path, data.instructionLine, data.instructionColumn};
  }

  [[noreturn]] void assembler_operand_fail(context::Context &context, const std::string &message) {
    const compiler::Assembler::Location location = assembler_open_instruction_location(context);
    assembler_discard_open_instruction(context);
    assembler_fail(location, message);
  }

bool assembler_identifier_character(char character) {
    return std::isalnum(static_cast<unsigned char>(character)) || character == '_' || character == '.' ||
           character == '$';
  }

  struct AssemblerAlias {
    lexicon::Phrase spelling;
    lexicon::Phrase resolved;
  };

  std::optional<AssemblerAlias> assembler_alias(context::Context &context, lexicon::Phrase grammar) {
    std::string remaining;
    for (Size relative = 0;; ++relative) {
      const char character = assembler_peek(context, relative);
      if (character == '\0' || character == '\n' || character == '}') break;
      remaining.push_back(character);
    }
    lexicon::Phrase spelling = LanguageGrammar::matchLongestAlias(context, grammar, remaining);
    if (spelling.isNull() || spelling.getKey().empty()) return std::nullopt;
    const std::string key = spelling.getKey();
    const char boundary = key.size() < remaining.size() ? remaining[key.size()] : '\0';
    if (assembler_identifier_character(key.back()) && assembler_identifier_character(boundary)) return std::nullopt;
    lexicon::Phrase resolved = LanguageGrammar::resolve(context, grammar, key);
    if (resolved.isNull()) return std::nullopt;
    return AssemblerAlias{spelling, resolved};
  }

bool assembler_statement_separator(char character) {
    return character == '\n' || character == ';' || character == '}';
  }

bool assembler_horizontal_whitespace(char character) {
    return character == ' ' || character == '\t' || character == '\r' || character == '\v';
  }

bool assembler_looks_like_integer(const std::string &text) {
    if (text.empty()) return false;
    const Size offset = (text.front() == '+' || text.front() == '-') ? 1 : 0;
    return offset < text.size() && (std::isdigit(static_cast<unsigned char>(text[offset])) || text[offset] == '\'');
  }

std::int64_t assembler_parse_integer(context::Context &context, const std::string &source) {
    std::string text = source;
    if (text.size() >= 3 && text.front() == '\'' && text.back() == '\'') {
      if (text.size() == 3) return static_cast<unsigned char>(text[1]);
      if (text.size() == 4 && text[1] == '\\') {
        switch (text[2]) {
        case '0': return 0;
        case 'n': return '\n';
        case 'r': return '\r';
        case 't': return '\t';
        case '\\': return '\\';
        case '\'': return '\'';
        default: assembler_operand_fail(context, "unsupported escape in character literal '" + text + "'");
        }
      }
      assembler_operand_fail(context, "a character literal must contain exactly one byte");
    }

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
    if (text.empty()) assembler_operand_fail(context, "invalid immediate value '" + source + "'");

    std::uint64_t value = 0;
    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value, base);
    if (error != std::errc() || end != text.data() + text.size())
      assembler_operand_fail(context, "invalid immediate value '" + source + "'");
    if (negative) {
      constexpr std::uint64_t minimumMagnitude = std::uint64_t{1} << 63;
      if (value > minimumMagnitude) assembler_operand_fail(context, "immediate value is out of range '" + source + "'");
      if (value == minimumMagnitude) return std::numeric_limits<std::int64_t>::min();
      return -static_cast<std::int64_t>(value);
    }
    return static_cast<std::int64_t>(value);
  }

std::string assembler_read_operand_token(context::Context &context, bool memory, std::string token) {
    const char quote = token.empty() && assembler_peek(context) == '\'' ? '\'' : 0;
    bool escaped = false;
    bool quoteOpened = false;

    while (true) {
      const char character = assembler_peek(context);
      if (character == '\0') {
        if (quote != 0) assembler_operand_fail(context, "unterminated character literal");
        break;
      }

      if (quote != 0) {
        if (character == '\n') assembler_operand_fail(context, "unterminated character literal");
        token.push_back(character);
        context::Source::progress(context, Byte::length);
        if (!escaped && character == quote) {
          if (quoteOpened) break;
          quoteOpened = true;
        }
        escaped = !escaped && character == '\\';
        if (character != '\\') escaped = false;
        continue;
      }

      const bool delimiter = assembler_horizontal_whitespace(character) || character == ',' ||
                             assembler_statement_separator(character) ||
                             (memory && (character == '+' || character == '-' || character == '*' || character == ']'));
      if (delimiter) break;
      token.push_back(character);
      context::Source::progress(context, Byte::length);
    }

    if (token.empty()) assembler_operand_fail(context, "expected an operand");
    return token;
  }

void assembler_set_label_operand(context::Context &context, const std::string &label) {
    if (!compiler::Assembler::isIdentifier(label)) assembler_operand_fail(context, "invalid operand '" + label + "'");
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    data.operand = {};
    data.operand.kind = AssemblerOperandKind::LABEL;
    data.operand.labelBytes = label.size();
    session.update(0, data);
  }

void assembler_finish_operand(context::Context &context, const std::string &label) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (data.operand.kind == AssemblerOperandKind::EMPTY) assembler_operand_fail(context, "expected an operand");

    const std::string key = assembler_operand_key(data.operandCount);
    lexicon::Phrase record = session.append(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length)
                                 .make()
                                 .setType(lexicon::phrase::type::getData(session))
                                 .save()
                                 .store(data.operand);
    if (data.operand.kind == AssemblerOperandKind::LABEL) {
      if (label.size() != data.operand.labelBytes)
        assembler_operand_fail(context, "internal label operand has inconsistent storage");
      if (!label.empty())
        Byte::copy(Byte(const_cast<char *>(label.data())), record.allocate(label.size()), label.size());
    }

    ++data.operandCount;
    data.operandRequired = false;
    data.operand = {};
    session.update(0, data);
    context.workspace.key.clear();
    assembler_enter_operand_state(context, phrases::OPERAND_COMPLETE);
  }

void assembler_validate_memory_register(context::Context &context, const compiler::Assembler::Register &reg) {
    if (reg.bits != 64 || reg.high) assembler_operand_fail(context, "memory addressing requires a 64-bit register");
  }

void assembler_commit_memory_register(context::Context &context, bool scaled, std::uint8_t scale) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    AssemblerMemoryData &memory = data.operand.memory;
    if (!memory.hasPendingRegister) assembler_operand_fail(context, "expected a register before '*'");
    if (memory.termSign < 0) assembler_operand_fail(context, "a memory address register cannot be subtracted");

    const compiler::Assembler::Register reg = memory.pendingRegister;
    if (scaled) {
      if (memory.hasIndex) assembler_operand_fail(context, "memory operand has more than one index register");
      if ((reg.code & 7) == 4) assembler_operand_fail(context, "rsp/r12 cannot be used as an index register");
      memory.index = reg;
      memory.hasIndex = true;
      memory.scale = scale;
    } else if (!memory.hasBase) {
      memory.base = reg;
      memory.hasBase = true;
    } else if (!memory.hasIndex) {
      if ((reg.code & 7) == 4) assembler_operand_fail(context, "rsp/r12 cannot be used as an index register");
      memory.index = reg;
      memory.hasIndex = true;
    } else {
      assembler_operand_fail(context, "memory operand has too many registers");
    }

    memory.hasPendingRegister = false;
    memory.hasTerm = true;
    memory.termSign = 1;
    memory.signExplicit = false;
    session.update(0, data);
  }

void assembler_add_memory_displacement(context::Context &context, std::int64_t displacement) {
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    AssemblerMemoryData &memory = data.operand.memory;
    const std::int64_t minimum = std::numeric_limits<std::int64_t>::min();
    const std::int64_t maximum = std::numeric_limits<std::int64_t>::max();
    if (memory.termSign > 0) {
      if ((displacement > 0 && memory.displacement > maximum - displacement) ||
          (displacement < 0 && memory.displacement < minimum - displacement))
        assembler_operand_fail(context, "memory displacement overflow");
      memory.displacement += displacement;
    } else {
      if ((displacement > 0 && memory.displacement < minimum + displacement) ||
          (displacement < 0 && memory.displacement > maximum + displacement))
        assembler_operand_fail(context, "memory displacement overflow");
      memory.displacement -= displacement;
    }
    memory.hasTerm = true;
    memory.termSign = 1;
    memory.signExplicit = false;
    session.update(0, data);
  }

void action_assembler_operand(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperand);
    const std::string state = context::Lookup::current(context).getKey();
    const bool memory = state == phrases::MEMORY_EXPECT;
    if (assembler_identifier_character(assembler_peek(context))) {
      const std::string token = assembler_read_operand_token(context, memory, invoked.getKey());
      if (memory) assembler_operand_fail(context, "invalid memory term '" + token + "'");
      assembler_set_label_operand(context, token);
      assembler_finish_operand(context, token);
      return;
    }

    compiler::Assembler::Register reg;
    invoked.fetch(0, reg);
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (memory) {
      assembler_validate_memory_register(context, reg);
      if (data.operand.kind != AssemblerOperandKind::MEMORY)
        assembler_operand_fail(context, "internal memory operand state is missing");
      data.operand.memory.pendingRegister = reg;
      data.operand.memory.hasPendingRegister = true;
      session.update(0, data);
      assembler_enter_operand_state(context, phrases::MEMORY_REGISTER);
    } else {
      data.operand = {};
      data.operand.kind = AssemblerOperandKind::REGISTER;
      data.operand.reg = reg;
      session.update(0, data);
      assembler_finish_operand(context);
    }
  }

void action_assembler_operand_size(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandSize);
    const char character = assembler_peek(context);
    if (assembler_identifier_character(character)) {
      const std::string token = assembler_read_operand_token(context, false, invoked.getKey());
      assembler_set_label_operand(context, token);
      assembler_finish_operand(context, token);
    } else if (assembler_horizontal_whitespace(character)) {
      std::uint8_t bits = 0;
      invoked.fetch(0, bits);
      lexicon::Phrase session = assembler_session(context);
      AssemblerSessionData data;
      session.fetch(0, data);
      data.operand = {};
      data.operand.kind = AssemblerOperandKind::MEMORY;
      data.operand.memory.bits = bits;
      session.update(0, data);
      assembler_enter_operand_state(context, phrases::OPERAND_SIZE_WHITESPACE);
    } else {
      // Without whitespace, byte/word/dword/qword is an ordinary label.
      const std::string label = invoked.getKey();
      assembler_set_label_operand(context, label);
      assembler_finish_operand(context, label);
    }
  }

void action_assembler_operand_whitespace(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandWhitespace);
    if (context::Lookup::current(context).getKey() == phrases::OPERAND_SIZE_WHITESPACE) {
      assembler_enter_operand_state(context, phrases::OPERAND_SIZE_BRACKET);
    }
  }

void action_assembler_operand_memory_begin(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandMemoryBegin);
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (data.operand.kind == AssemblerOperandKind::EMPTY) {
      data.operand.kind = AssemblerOperandKind::MEMORY;
    } else if (data.operand.kind != AssemblerOperandKind::MEMORY) {
      assembler_operand_fail(context, "unexpected '[' in operand");
    }
    session.update(0, data);
    assembler_enter_operand_state(context, phrases::MEMORY_EXPECT);
  }

void action_assembler_operand_memory_operator(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandMemoryOperator);
    const std::string state = context::Lookup::current(context).getKey();
    const std::string operation = invoked.getKey();

    if (operation == "*" && state == phrases::MEMORY_REGISTER) {
      assembler_enter_operand_state(context, phrases::MEMORY_SCALE);
      return;
    }
    if ((operation == "+" || operation == "-") &&
        (state == phrases::MEMORY_EXPECT || state == phrases::MEMORY_REGISTER || state == phrases::MEMORY_TERM)) {
      lexicon::Phrase session = assembler_session(context);
      AssemblerSessionData data;
      session.fetch(0, data);
      if (state == phrases::MEMORY_EXPECT && data.operand.memory.signExplicit)
        assembler_operand_fail(context, "empty term in memory operand");
      if (state == phrases::MEMORY_REGISTER) assembler_commit_memory_register(context);
      session.fetch(0, data);
      data.operand.memory.termSign = operation == "-" ? -1 : 1;
      data.operand.memory.signExplicit = true;
      session.update(0, data);
      assembler_enter_operand_state(context, phrases::MEMORY_EXPECT);
      return;
    }
    assembler_operand_fail(context, "unexpected '" + operation + "' in memory operand");
  }

void action_assembler_operand_memory_end(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandMemoryEnd);
    const std::string state = context::Lookup::current(context).getKey();
    if (state != phrases::MEMORY_REGISTER && state != phrases::MEMORY_TERM)
      assembler_operand_fail(context, "memory operand ends before a term is complete");
    if (state == phrases::MEMORY_REGISTER) assembler_commit_memory_register(context);
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    const AssemblerMemoryData &memory = data.operand.memory;
    if (!memory.hasTerm) assembler_operand_fail(context, "empty memory operand");
    if (!memory.hasBase && !memory.hasIndex &&
        (memory.displacement < std::numeric_limits<std::int32_t>::min() ||
         memory.displacement > std::numeric_limits<std::int32_t>::max()))
      assembler_operand_fail(context, "absolute address does not fit a 32-bit displacement");
    assembler_finish_operand(context);
  }

void action_assembler_operand_separator(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandSeparator);
    const std::string state = context::Lookup::current(context).getKey();
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);

    if (state == phrases::OPERAND_COMPLETE) {
      data.operandRequired = true;
      session.update(0, data);
      assembler_enter_operand_state(context, phrases::OPERANDS);
      return;
    }
    if (state == phrases::OPERANDS)
      assembler_operand_fail(context, data.operandRequired ? "empty operand after ','" : "empty operand before ','");
    assembler_operand_fail(context, "unexpected ',' in memory operand");
  }

void assembler_emit_and_leave_operand_parser(context::Context &context) {
    try {
      assembler_emit_open_instruction(context);
    } catch (...) {
      assembler_discard_open_instruction(context);
      throw;
    }
    assembler_leave_operand_parser(context);
  }

void action_assembler_operand_comment(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandComment);
    const std::string state = context::Lookup::current(context).getKey();
    AssemblerSessionData data;
    assembler_session(context).fetch(0, data);
    if (state == phrases::OPERANDS && data.operandRequired) assembler_operand_fail(context, "empty operand after ','");
    if (state != phrases::OPERANDS && state != phrases::OPERAND_COMPLETE)
      assembler_operand_fail(context, "unterminated memory operand before comment");

    assembler_emit_and_leave_operand_parser(context);
    action_assembler_comment(context, invoked);
  }

void action_assembler_operand_dynamic(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerOperandDynamic);
    lexicon::Phrase grammar = context::Lookup::current(context);
    const std::string state = grammar.getKey();
    const char character = assembler_peek(context);
    if (assembler_statement_separator(character)) {
      AssemblerSessionData data;
      assembler_session(context).fetch(0, data);
      if (state == phrases::OPERANDS && data.operandRequired)
        assembler_operand_fail(context, "empty operand after ','");
      if (state != phrases::OPERANDS && state != phrases::OPERAND_COMPLETE)
        assembler_operand_fail(context, "unterminated memory operand");

      // Leave the separator in the source. The assembler body consumes it
      // after the operand parser has emitted the instruction. This also keeps
      // line-oriented error recovery on the line that actually failed.
      assembler_emit_and_leave_operand_parser(context);
      return;
    }

    if (std::optional<AssemblerAlias> alias = assembler_alias(context, grammar)) {
      context::Source::progress(context, alias->spelling.getKey().size() * Byte::length);
      if (alias->resolved.isElaboratable())
        alias->resolved.elaborate(context);
      else
        alias->resolved.invoke(context);
      return;
    }

    if (state == phrases::OPERANDS) {
      const std::string token = assembler_read_operand_token(context, false);
      if (assembler_looks_like_integer(token)) {
        lexicon::Phrase session = assembler_session(context);
        AssemblerSessionData data;
        session.fetch(0, data);
        data.operand = {};
        data.operand.kind = AssemblerOperandKind::IMMEDIATE;
        data.operand.immediate = assembler_parse_integer(context, token);
        session.update(0, data);
        assembler_finish_operand(context);
      } else {
        assembler_set_label_operand(context, token);
        assembler_finish_operand(context, token);
      }
      return;
    }
    if (state == phrases::MEMORY_EXPECT) {
      const std::string token = assembler_read_operand_token(context, true);
      if (!assembler_looks_like_integer(token)) assembler_operand_fail(context, "invalid memory term '" + token + "'");
      assembler_add_memory_displacement(context, assembler_parse_integer(context, token));
      assembler_enter_operand_state(context, phrases::MEMORY_TERM);
      return;
    }
    if (state == phrases::MEMORY_SCALE) {
      const std::string token = assembler_read_operand_token(context, true);
      const std::int64_t scale = assembler_parse_integer(context, token);
      if (scale != 1 && scale != 2 && scale != 4 && scale != 8)
        assembler_operand_fail(context, "index scale must be 1, 2, 4, or 8");
      assembler_commit_memory_register(context, true, static_cast<std::uint8_t>(scale));
      assembler_enter_operand_state(context, phrases::MEMORY_TERM);
      return;
    }
    if (state == phrases::OPERAND_SIZE_WHITESPACE || state == phrases::OPERAND_SIZE_BRACKET)
      assembler_operand_fail(context, "memory size prefix must be followed by '[...]'");
    if (state == phrases::MEMORY_REGISTER || state == phrases::MEMORY_TERM)
      assembler_operand_fail(context, "expected '+', '-', '*' or ']' in memory operand");
    assembler_operand_fail(context, "expected ',' or the end of the instruction");
  }

std::string read_invocation_reference(context::Context &context, const compiler::Assembler::Location &location,
                                               bool assemblerContext) {
    if (assembler_peek(context) == '<') {
      context::Source::progress(context, Byte::length);
      std::string reference;
      while (true) {
        const char character = assembler_peek(context);
        if (character == '\0' || character == '\n' || character == '}')
          invocation_fail(location, assemblerContext, "unterminated phrase reference in 'invoke'; expected '>'");
        if (character == '>') {
          context::Source::progress(context, Byte::length);
          break;
        }
        reference.push_back(character);
        context::Source::progress(context, Byte::length);
      }

      reference = assembler_trim(std::move(reference));
      if (reference.empty()) invocation_fail(location, assemblerContext, "'invoke' phrase reference cannot be empty");
      return reference;
    }

    std::string reference;
    while (true) {
      const char character = assembler_peek(context);
      if (character == '\0' || character == '\n' || character == '}' || character == ';' || character == '(' ||
          std::isspace(static_cast<unsigned char>(character)))
        break;
      reference.push_back(character);
      context::Source::progress(context, Byte::length);
    }
    if (reference.empty())
      invocation_fail(location, assemblerContext, "'invoke' expects a phrase name or a reference written as <phrase>");
    return reference;
  }

std::vector<compiler::TypedValue> read_typed_call_arguments(context::Context &context,
                                                                     const compiler::TypedFunction *function,
                                                                     const compiler::Assembler::Location &location,
                                                                     bool assemblerContext) {
    std::vector<compiler::TypedValue> result;
    if (assembler_peek(context) != '(') {
      if (function != nullptr && !function->parameterTypes.empty())
        invocation_fail(location, assemblerContext,
                        "typed invoke of '" + function->signature.symbol + "' requires an argument list");
      return result;
    }
    if (function == nullptr)
      invocation_fail(location, assemblerContext, "an argument list requires a declared typed phrase");
    context::Source::progress(context, Byte::length);
    assembler_skip_horizontal_whitespace(context);
    if (assembler_peek(context) == ')') {
      context::Source::progress(context, Byte::length);
    } else {
      while (true) {
        std::string token;
        while (true) {
          const char character = assembler_peek(context);
          if (character == '\0' || character == '\n' || character == '}')
            invocation_fail(location, assemblerContext, "unterminated typed invoke argument list");
          if (character == ',' || character == ')') break;
          token.push_back(character);
          context::Source::progress(context, Byte::length);
        }
        token = assembler_trim(std::move(token));
        if (token.empty()) invocation_fail(location, assemblerContext, "typed invoke contains an empty argument");
        if (result.size() >= function->parameterTypes.size())
          invocation_fail(location, assemblerContext, "typed invoke has too many arguments");
        const compiler::TypeId typeId = function->parameterTypes[result.size()];
        const compiler::TypeDescriptor type = context.language().types.get(typeId);
        if (type.size > sizeof(std::uint64_t))
          invocation_fail(location, assemblerContext,
                          "aggregate arguments larger than one register require an address");
        if (type.kind == compiler::TypeKind::FloatingPoint) {
          double value = 0;
          const auto [end, error] = std::from_chars(token.data(), token.data() + token.size(), value);
          if (error != std::errc() || end != token.data() + token.size())
            invocation_fail(location, assemblerContext, "invalid floating argument '" + token + "'");
          std::uint64_t bits = 0;
          if (type.size == sizeof(float)) {
            const float narrowed = static_cast<float>(value);
            bits = std::bit_cast<std::uint32_t>(narrowed);
          } else if (type.size == sizeof(double)) {
            bits = std::bit_cast<std::uint64_t>(value);
          } else {
            invocation_fail(location, assemblerContext, "floating argument width is not supported by x86-64 lowering");
          }
          result.push_back(compiler::TypedValue::integer(typeId, bits, type.size));
        } else if (type.kind == compiler::TypeKind::Integer || type.kind == compiler::TypeKind::Pointer ||
                   type.kind == compiler::TypeKind::Function) {
          if (LanguageGrammar::matches(context, token, "null")) {
            if (type.kind != compiler::TypeKind::Pointer && type.kind != compiler::TypeKind::Function)
              invocation_fail(location, assemblerContext, "null is only valid for a pointer argument");
            result.push_back(compiler::TypedValue::pointer(typeId, 0, type.size));
          } else {
            if (token.starts_with('&')) token.erase(token.begin());
            const std::uint64_t value = assembler_parse_data_integer(token, location);
            result.push_back(compiler::TypedValue::integer(typeId, value, type.size));
          }
        } else {
          invocation_fail(location, assemblerContext,
                          "typed invoke requires a pointer for aggregate argument '" + type.name + "'");
        }
        const char delimiter = assembler_peek(context);
        context::Source::progress(context, Byte::length);
        if (delimiter == ')') break;
        assembler_skip_horizontal_whitespace(context);
      }
    }
    std::vector<compiler::ValueType> actual;
    for (std::size_t index = 0; index < result.size(); ++index)
      actual.push_back(context.language().types.abiType(function->parameterTypes[index]));
    compiler::Abi::validateCall(function->signature, actual);
    return result;
  }

void action_invoke(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(Invoke);
    const bool assemblerContext = assembler_open(context);
    const std::string mnemonic = invoked.getKey();
    const compiler::Assembler::Location location = assembler_location(context, mnemonic.size());
    const std::string suffix = assembler_read_identifier_suffix(context);
    assembler_skip_horizontal_whitespace(context);
    if (assemblerContext && assembler_peek(context) == ':') {
      context::Source::progress(context, Byte::length);
      assembler_define_label(context, mnemonic + suffix, location);
      return;
    }
    if (!suffix.empty())
      invocation_fail(location, assemblerContext,
                      assemblerContext ? "unknown instruction '" + mnemonic + suffix + "'"
                                       : "'" + mnemonic + "' must be followed by whitespace or '<'");

    if (assemblerContext) {
      AssemblerSessionData state;
      assembler_session(context).fetch(0, state);
      if (state.currentSection != compiler::Module::id(compiler::SectionKind::Text))
        assembler_fail(location, "invoke may only be emitted in .text");
      const std::string reference = read_invocation_reference(context, location, true);
      assembler_skip_horizontal_whitespace(context);
      const std::optional<compiler::TypedFunction> typed = context.language().findFunction(reference);
      const std::vector<compiler::TypedValue> arguments =
          read_typed_call_arguments(context, typed ? &*typed : nullptr, location, true);
      assembler_add_invocation(context, reference, location, typed ? &*typed : nullptr, arguments);
      return;
    }

    if (!compiled_scope_open(context))
      invocation_fail(location, false,
                      "'invoke' can emit code only inside a compiled phrase block: let name = { ... }");

    const std::string reference = read_invocation_reference(context, location, false);
    assembler_skip_horizontal_whitespace(context);
    const std::optional<compiler::TypedFunction> typed = context.language().findFunction(reference);
    const std::vector<compiler::TypedValue> arguments =
        read_typed_call_arguments(context, typed ? &*typed : nullptr, location, false);
    lexicon::Phrase session = compiled_scope_session(context);
    CompiledScopeSessionData data;
    session.fetch(0, data);

    lexicon::Phrase target = resolve_phrase_reference(context, data.referenceRootAddress, reference, location, false);
    if (target.getAddress() >= data.lexiconCheckpoint)
      invocation_fail(location, false,
                      "phrase reference '<" + reference +
                          ">' resolves to a temporary phrase that will not survive the compiled block");
    emit_resolved_phrase_invocation(context, target, reference, typed ? &*typed : nullptr, arguments, location);
  }

void action_assembler_label(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerLabel);
    const std::string invokedName = invoked.getKey();
    const compiler::Assembler::Location location = assembler_location(context, invokedName.size());
    const std::string name = invokedName + assembler_read_identifier_suffix(context);
    assembler_skip_horizontal_whitespace(context);
    if (assembler_peek(context) != ':')
      assembler_fail(location, "expected ':' after label '" + name + "'");
    context::Source::progress(context, Byte::length);

    std::string labelName = name;
    if (name == invokedName) {
      Size address;
      invoked.fetch(0, address);
      labelName = lexicon::Phrase(&context.lexicon, address).load().getKey();
    }
    assembler_define_label(context, labelName, location);
  }

void action_assembler_unknown(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerUnknown);
    const compiler::Assembler::Location location = assembler_location(context);
    lexicon::Phrase body = assembler_body(context);
    if (std::optional<AssemblerAlias> alias = assembler_alias(context, body)) {
      const std::string spelling = alias->spelling.getKey();
      context::Source::progress(context, spelling.size() * Byte::length);
      lexicon::Phrase descriptor = LanguageGrammar::metadata(alias->resolved, sizeof(AssemblerInstruction));
      if (!descriptor.isNull()) {
        AssemblerInstruction data{""};
        descriptor.fetch(0, data);
        if (data.magic == AssemblerInstruction::Magic) {
          action_assembler_instruction(context, alias->resolved, assembler_instruction_name(alias->resolved), spelling);
          return;
        }
      }
      if (alias->resolved.isElaboratable()) {
        alias->resolved.elaborate(context);
        return;
      }
      if (alias->resolved.isInvokable()) {
        alias->resolved.invoke(context);
        return;
      }
      assembler_fail(location, "assembler alias '" + spelling + "' does not resolve to an action");
    }

    std::string name;
    while (true) {
      const char character = assembler_peek(context);
      const bool valid = name.empty() ? std::isalpha(static_cast<unsigned char>(character)) || character == '_' ||
                                            character == '.' || character == '$'
                                      : std::isalnum(static_cast<unsigned char>(character)) || character == '_' ||
                                            character == '.' || character == '$';
      if (!valid) break;
      name.push_back(character);
      context::Source::progress(context, Byte::length);
    }

    if (name.empty())
      assembler_fail(location, "unexpected character '" + std::string(1, assembler_peek(context)) + "'");

    assembler_skip_horizontal_whitespace(context);
    if (assembler_peek(context) != ':')
      assembler_fail(location, "unknown instruction '" + name + "'");
    context::Source::progress(context, Byte::length);

    assembler_define_label(context, name, location);
  }

void action_assembler_comment(context::Context &context, lexicon::Phrase &invoked) {
    while (true) {
      const char character = assembler_peek(context);
      if (character == '\0' || character == '\n') return;
      context::Source::progress(context, Byte::length);
    }
  }

void action_assembler_begin(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerBegin);
    const AssemblerSessionData data{context.lexicon.checkpoint().getAddress(), context.workspace.code.bits(),
                                    context.workspace.key.bits(), context.staging.dictionary.getAddress(), 0};
    const std::string key = assembler_internal_key(ASSEMBLER_SESSION);
    lexicon::Phrase session = invoked.append(Byte((unsigned char *)key.data()), 0, key.size() * Byte::length)
                                  .make()
                                  .setType(lexicon::phrase::type::getData(invoked))
                                  .enableSubdictionary()
                                  .save()
                                  .store(data);
    const Size keyBytes = Bit::bytes(data.keyStartBits);
    if (keyBytes != 0) {
      Byte savedKey = session.allocate(keyBytes);
      Bit::copy(Bit(context.workspace.key.getMemory(), 0), Bit(savedKey, 0), data.keyStartBits);
    }
    context::Lookup::enter(context, invoked);
  }

void action_assembler_end(context::Context &context, lexicon::Phrase &invoked) {
    DEBUG_PROFILE_SCOPE(AssemblerEnd);
    lexicon::Phrase session = assembler_session(context);
    AssemblerSessionData data;
    session.fetch(0, data);
    if (context.staging.stack.size() > 1) {
      NativeDefinition definition = assembler_link_staged_definition(context, invoked, session, data);
      assembler_restore_key(context, session, data);
      context::Lookup::leave(context, invoked);
      radix::Checkpoint(&context.lexicon, data.lexiconCheckpoint).restore();
      context.exec.invoked = nullptr;
      finalize_native_definition(context, invoked, definition.module, definition.imports);
    } else {
      assembler_second_pass(context, session, data);
      assembler_restore_key(context, session, data);
      context::Lookup::leave(context, invoked);
      radix::Checkpoint(&context.lexicon, data.lexiconCheckpoint).restore();
    }
  }
  } // namespace assembler_internal
} // namespace recurloop
