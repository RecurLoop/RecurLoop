#include "FunctionsInternal.hpp"

#include <compiler/DebugInfo.hpp>
#include <recurloop/BitString.hpp>
#include <recurloop/PhraseAction.hpp>

#include <bit>
#include <charconv>
#include <limits>
#include <unordered_set>

namespace recurloop {
  namespace function_internal {

    constexpr std::string_view OperatorInferName{"\0fn-infer", 9};
    constexpr std::string_view OperatorEmitName{"\0fn-emit", 8};
    constexpr std::string_view OperatorLvalueName{"\0fn-lvalue", 10};

    class Generator;

    struct OperatorFrame {
      Generator *generator = nullptr;
      const Expression *expression = nullptr;
      compiler::TypeId result = compiler::InvalidType;
      compiler::TypeId expected = compiler::InvalidType;
    };

    enum class IntrinsicPhase : std::uint8_t { Infer, Emit, Lvalue };

    struct IntrinsicBehavior {
      IntrinsicKind kind = IntrinsicKind::Cast;
      IntrinsicPhase phase = IntrinsicPhase::Infer;
    };

    struct StatementFrame {
      Generator *generator = nullptr;
      const Statement *statement = nullptr;
    };

    struct AssignmentFrame {
      Generator *generator = nullptr;
      const Statement *statement = nullptr;
      compiler::TypeId targetType = compiler::InvalidType;
    };

    thread_local OperatorFrame *currentOperatorFrame = nullptr;
    thread_local StatementFrame *currentStatementFrame = nullptr;
    thread_local AssignmentFrame *currentAssignmentFrame = nullptr;

    OperatorFrame &operatorFrame() {
      if (currentOperatorFrame == nullptr) THROW(, "fn operator behavior invoked without a compiler frame")
      return *currentOperatorFrame;
    }

    StatementFrame &statementFrame() {
      if (currentStatementFrame == nullptr) THROW(, "fn statement behavior invoked without a compiler frame")
      return *currentStatementFrame;
    }

    AssignmentFrame &assignmentFrame() {
      if (currentAssignmentFrame == nullptr) THROW(, "fn assignment behavior invoked without a compiler frame")
      return *currentAssignmentFrame;
    }

    class Generator {
    public:
      Generator(context::Context &context, const FunctionDefinition &signature)
          : context(context), signature(signature), integerType(context.language().types.find("i64")),
            realType(context.language().types.find("f64")),
            bytePointer(context.language().types.pointerTo(context.language().types.find("u8"))),
            bitStringPointer(context.language().types.find("BitString*")),
            phraseActionPointer(context.language().types.find("PhraseAction*")) {
        const std::vector<compiler::TypeId> actionParameters = {context.language().types.find("Context*"),
                                                                context.language().types.find("Phrase*")};
        actionFunctionType =
            context.language().types.functionOf(actionParameters, context.language().types.find("void"), "sysv-amd64");
        if (signature.function.signature.convention.name != "sysv-amd64")
          fail({}, 0, "fn currently requires the sysv-amd64 ABI");
      }

      compiler::Module generate(const std::vector<Statement> &body) {
        emit("push", "rbp");
        emit("mov", "rbp, rsp");
        emitBytes({0x48, 0x81, 0xec});
        framePatch = code.size();
        little(0, 4);

        scopes.emplace_back();
        static constexpr std::string_view registers[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
        for (std::size_t index = 0; index < signature.names.size(); ++index) {
          const compiler::TypeDescriptor parameter =
              context.language().types.get(signature.function.parameterTypes[index]);
          if (parameter.kind == compiler::TypeKind::FloatingPoint || parameter.size > 8)
            fail({}, 0, "fn parameters currently require integer, pointer, or scalar types up to 64 bits");
          Local local{signature.function.parameterTypes[index], allocate(), true};
          scopes.back().emplace(signature.names[index], local);
          if (index < std::size(registers))
            emit("mov", slot(local.offset) + ", " + std::string(registers[index]));
          else {
            emit("mov", "rax, qword [rbp + " + std::to_string(16 + (index - std::size(registers)) * 8) + "]");
            emit("mov", slot(local.offset) + ", rax");
          }
        }

        statements(body);
        emit("xor", "eax, eax");
        const std::size_t epilogue = code.size();
        emit("leave", "");
        emit("ret", "");
        for (std::size_t patch : returns) patchRelative(patch, epilogue);

        const std::size_t frame = (frameBytes + 15) & ~std::size_t{15};
        for (std::size_t index = 0; index < 4; ++index)
          code[framePatch + index] = static_cast<std::uint8_t>(frame >> (index * 8));

        compiler::Module module;
        module.append(compiler::SectionKind::Text, code, 16);
        if (!rodata.empty()) module.append(compiler::SectionKind::ReadOnlyData, rodata, rodataAlignment);
        Assembler::defineEntry(context, module, 0);
        for (const StringLiteral &literal : strings)
          module.define(literal.symbol, compiler::SectionKind::ReadOnlyData, literal.offset,
                        compiler::SymbolBinding::Local);
        for (const PendingRelocation &relocation : relocations) {
          if (relocation.imported && module.findSymbol(relocation.symbol) == nullptr) module.import(relocation.symbol);
          module.relocate(relocation.section, relocation.offset, relocation.kind, relocation.symbol, relocation.addend);
        }
        for (const compiler::DebugPoint &point : debugPoints) compiler::DebugInfo::add(module, point);
        return module;
      }

      compiler::TypeId inferLeft(const Expression &value) {
        return infer(*value.children[0]);
      }

      compiler::TypeId inferInteger(const Expression &) {
        return integerType;
      }

      compiler::TypeId emitPrefix(const Expression &value, std::string_view instruction) {
        const compiler::TypeId type = expression(*value.children[0]);
        const compiler::TypeDescriptor descriptor = context.language().types.get(type);
        if (descriptor.kind == compiler::TypeKind::FloatingPoint) {
          if (descriptor.size != sizeof(double)) fail({}, value.offset, "fn currently supports f64 expressions");
          if (instruction == "neg") {
            emit("mov", "rdx, " + std::to_string(std::uint64_t{1} << 63));
            emit("xor", "rax, rdx");
          } else if (!instruction.empty()) {
            fail({}, value.offset, "unsupported floating prefix operator");
          }
          return type;
        }
        if (!instruction.empty()) emit(instruction, "rax");
        return type;
      }

      compiler::TypeId emitLogicalNot(const Expression &value) {
        expression(*value.children[0]);
        emit("test", "rax, rax");
        emit("mov", "rax, 0");
        emitBytes({0x0f, 0x94, 0xc0});
        return integerType;
      }

      compiler::TypeId emitArithmetic(const Expression &value, std::string_view instruction) {
        const compiler::TypeId left = binaryOperands(value);
        const compiler::TypeDescriptor descriptor = context.language().types.get(left);
        if (descriptor.kind == compiler::TypeKind::FloatingPoint) {
          if (descriptor.size != sizeof(double)) fail({}, value.offset, "fn currently supports f64 expressions");
          const std::uint8_t opcode = instruction == "add"    ? 0x58
                                      : instruction == "sub"  ? 0x5c
                                      : instruction == "imul" ? 0x59
                                                              : 0;
          if (opcode == 0) fail({}, value.offset, "unsupported floating arithmetic operator");
          emitBytes({0x66, 0x48, 0x0f, 0x6e, 0xc0}); // movq xmm0, rax
          emitBytes({0x66, 0x48, 0x0f, 0x6e, 0xc9}); // movq xmm1, rcx
          emitBytes({0xf2, 0x0f, opcode, 0xc1});     // op xmm0, xmm1
          emitBytes({0x66, 0x48, 0x0f, 0x7e, 0xc0}); // movq rax, xmm0
          return left;
        }
        emit(instruction, "rax, rcx");
        return left;
      }

      compiler::TypeId emitDivision(const Expression &value, bool remainder) {
        const compiler::TypeId left = binaryOperands(value);
        const compiler::TypeDescriptor descriptor = context.language().types.get(left);
        if (descriptor.kind == compiler::TypeKind::FloatingPoint) {
          if (descriptor.size != sizeof(double) || remainder)
            fail({}, value.offset, "fn floating division supports f64 and no remainder");
          emitBytes({0x66, 0x48, 0x0f, 0x6e, 0xc0}); // movq xmm0, rax
          emitBytes({0x66, 0x48, 0x0f, 0x6e, 0xc9}); // movq xmm1, rcx
          emitBytes({0xf2, 0x0f, 0x5e, 0xc1});       // divsd xmm0, xmm1
          emitBytes({0x66, 0x48, 0x0f, 0x7e, 0xc0}); // movq rax, xmm0
          return left;
        }
        emit("cqo", "");
        emit("idiv", "rcx");
        if (remainder) emit("mov", "rax, rdx");
        return left;
      }

      compiler::TypeId emitComparison(const Expression &value, std::uint8_t condition) {
        binaryOperands(value);
        emit("cmp", "rax, rcx");
        emit("mov", "rax, 0");
        emitBytes({0x0f, condition, 0xc0});
        return integerType;
      }

      compiler::TypeId emitLogical(const Expression &value, bool conjunction) {
        expression(*value.children[0]);
        emit("test", "rax, rax");
        const std::size_t shortcut = jump({0x0f, static_cast<std::uint8_t>(conjunction ? 0x84 : 0x85)});
        expression(*value.children[1]);
        emit("test", "rax, rax");
        emit("mov", "rax, 0");
        emitBytes({0x0f, 0x95, 0xc0});
        const std::size_t end = jump({0xe9});
        patchRelative(shortcut, code.size());
        emit("mov", std::string("rax, ") + (conjunction ? "0" : "1"));
        patchRelative(end, code.size());
        return integerType;
      }

      compiler::TypeId emitCastIntrinsic(const Expression &value) {
        const compiler::TypeId sourceType = expression(*value.children[0]);
        const compiler::TypeDescriptor source = context.language().types.get(sourceType);
        const compiler::TypeDescriptor target = context.language().types.get(value.declaredType);
        if (source.kind == compiler::TypeKind::FloatingPoint && source.size == sizeof(double) &&
            target.kind == compiler::TypeKind::Integer && target.size == sizeof(std::int64_t) && target.isSigned) {
          emitBytes({0x66, 0x48, 0x0f, 0x6e, 0xc0}); // movq xmm0, rax
          emitBytes({0xf2, 0x48, 0x0f, 0x2c, 0xc0}); // cvttsd2si rax, xmm0
          return value.declaredType;
        }
        if (source.kind == compiler::TypeKind::Integer && source.size == sizeof(std::int64_t) && source.isSigned &&
            target.kind == compiler::TypeKind::FloatingPoint && target.size == sizeof(double)) {
          emitBytes({0xf2, 0x48, 0x0f, 0x2a, 0xc0}); // cvtsi2sd xmm0, rax
          emitBytes({0x66, 0x48, 0x0f, 0x7e, 0xc0}); // movq rax, xmm0
          return value.declaredType;
        }
        const bool sourceScalar = source.kind == compiler::TypeKind::Integer ||
                                  source.kind == compiler::TypeKind::Pointer ||
                                  source.kind == compiler::TypeKind::Function;
        const bool targetScalar = target.kind == compiler::TypeKind::Integer ||
                                  target.kind == compiler::TypeKind::Pointer ||
                                  target.kind == compiler::TypeKind::Function;
        if (!sourceScalar || !targetScalar || source.size > 8 || target.size > 8)
          fail({}, value.offset, "fn cast currently requires integer or pointer scalar types");
        return value.declaredType;
      }

      compiler::TypeId inferCastIntrinsic(const Expression &value) {
        return value.declaredType;
      }

      compiler::TypeId emitAddressIntrinsic(const Expression &value, compiler::TypeId expected) {
        if (value.children[0]->kind == Expression::Kind::Variable &&
            findLocalOptional(value.children[0]->text) == nullptr) {
          const std::optional<compiler::TypedFunction> function = functionReference(value.children[0]->text, expected);
          if (!function) fail({}, value.offset, "address target is neither a local nor a typed function");
          emitFunctionAddress(function->signature.symbol, function->imported);
          return context.language().functionType(*function);
        }
        const compiler::TypeId type = lvalue(*value.children[0], false);
        return context.language().types.pointerTo(type);
      }

      compiler::TypeId inferAddressIntrinsic(const Expression &value, compiler::TypeId expected) {
        const compiler::TypeId target = infer(*value.children[0], expected);
        if (value.children[0]->kind == Expression::Kind::Variable &&
            findLocalOptional(value.children[0]->text) == nullptr)
          return target;
        return context.language().types.pointerTo(target);
      }

      compiler::TypeId emitDereferenceIntrinsic(const Expression &value) {
        const compiler::TypeId element = lvalueDereferenceIntrinsic(value);
        load(element, "rax");
        return element;
      }

      compiler::TypeId inferDereferenceIntrinsic(const Expression &value) {
        const compiler::TypeDescriptor pointer = context.language().types.get(infer(*value.children[0]));
        if (pointer.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "dereference requires a pointer");
        return pointer.element;
      }

      compiler::TypeId lvalueDereferenceIntrinsic(const Expression &value) {
        const compiler::TypeId pointerType = expression(*value.children[0]);
        const compiler::TypeDescriptor pointer = context.language().types.get(pointerType);
        if (pointer.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "dereference requires a pointer");
        return pointer.element;
      }

    private:
      compiler::TypeId operatorBehavior(const Expression &value, std::string_view behavior,
                                        compiler::TypeId expected = compiler::InvalidType) {
        lexicon::Phrase syntax = value.syntax;
        if (syntax.isNull()) fail({}, value.offset, "fn expression has no syntax phrase");
        lexicon::Phrase implementation = LanguageGrammar::behavior(syntax, behavior);
        if (implementation.isNull())
          fail({}, value.offset,
               "operator '" + value.text + "' has no fn compiler behavior '" + std::string(behavior.substr(1)) + "'");
        OperatorFrame frame{this, &value, compiler::InvalidType, expected};
        OperatorFrame *previous = currentOperatorFrame;
        currentOperatorFrame = &frame;
        try {
          implementation.invoke(context);
        } catch (...) {
          currentOperatorFrame = previous;
          throw;
        }
        currentOperatorFrame = previous;
        if (frame.result == compiler::InvalidType)
          fail({}, value.offset, "fn operator behavior did not produce a type for '" + value.text + "'");
        return frame.result;
      }

      compiler::TypeId binaryOperands(const Expression &value) {
        const compiler::TypeId left = expression(*value.children[0]);
        emit("push", "rax");
        ++temporaryDepth;
        const compiler::TypeId right = expression(*value.children[1]);
        compatible(left, right, value.offset);
        emit("mov", "rcx, rax");
        emit("pop", "rax");
        --temporaryDepth;
        return left;
      }
      struct PendingRelocation {
        compiler::SectionKind section;
        std::size_t offset;
        compiler::RelocationKind kind;
        std::string symbol;
        std::int64_t addend;
        bool imported;
      };
      struct StringLiteral {
        std::string symbol;
        std::size_t offset;
      };
      struct Loop {
        std::size_t begin;
        std::vector<std::size_t> breaks;
        std::size_t deferDepth;
      };

      void emit(std::string_view mnemonic, const std::string &operands) {
        const compiler::Assembler::Result encoded = compiler::Assembler::encode(std::string(mnemonic), operands, {});
        if (!encoded.relocations.empty()) fail({}, 0, "internal native encoder produced an unexpected relocation");
        code.insert(code.end(), encoded.code.begin(), encoded.code.end());
      }
      void emitBytes(std::initializer_list<std::uint8_t> bytes) {
        code.insert(code.end(), bytes);
      }
      void emitFunctionAddress(const std::string &symbol, bool imported) {
        if (imported) {
          emitBytes({0x48, 0xb8});
          const std::size_t patch = code.size();
          little(0, 8);
          relocations.push_back(
              {compiler::SectionKind::Text, patch, compiler::RelocationKind::Absolute64, symbol, 0, true});
          return;
        }
        emitBytes({0x48, 0x8d, 0x05});
        const std::size_t patch = code.size();
        little(0, 4);
        relocations.push_back({compiler::SectionKind::Text, patch, compiler::RelocationKind::PCRelative32, symbol, -4,
                               symbol != signature.function.signature.symbol});
      }
      void emitDataAddress(const std::string &symbol) {
        emitBytes({0x48, 0x8d, 0x05});
        const std::size_t patch = code.size();
        little(0, 4);
        relocations.push_back(
            {compiler::SectionKind::Text, patch, compiler::RelocationKind::PCRelative32, symbol, -4, false});
      }
      void appendReadOnlyLittle(std::uint64_t value, std::size_t bytes) {
        for (std::size_t index = 0; index < bytes; ++index)
          rodata.push_back(static_cast<std::uint8_t>(value >> (index * 8)));
      }
      void little(std::uint64_t value, std::size_t bytes) {
        for (std::size_t index = 0; index < bytes; ++index) code.push_back(value >> (index * 8));
      }
      std::size_t jump(std::initializer_list<std::uint8_t> opcode) {
        emitBytes(opcode);
        const std::size_t patch = code.size();
        little(0, 4);
        return patch;
      }
      void patchRelative(std::size_t patch, std::size_t target) {
        const std::int64_t relative = static_cast<std::int64_t>(target) - static_cast<std::int64_t>(patch + 4);
        if (relative < INT32_MIN || relative > INT32_MAX) fail({}, patch, "fn branch is out of range");
        const std::uint32_t value = static_cast<std::uint32_t>(relative);
        for (std::size_t index = 0; index < 4; ++index) code[patch + index] = value >> (index * 8);
      }
      std::string slot(std::size_t offset) const {
        return "qword [rbp - " + std::to_string(offset) + "]";
      }
      std::size_t allocate() {
        frameBytes += 8;
        return frameBytes;
      }

      std::pair<std::size_t, std::size_t> sourceLocation(std::size_t offset) const {
        std::size_t line = signature.sourceLine;
        std::size_t column = signature.sourceColumn;
        const std::size_t end = std::min(offset, signature.sourceText.size());
        for (std::size_t index = 0; index < end; ++index) {
          if (signature.sourceText[index] == '\n') {
            ++line;
            column = 1;
          } else {
            ++column;
          }
        }
        return {line, column};
      }

      void recordDebugPoint(const Statement &statement) {
        compiler::DebugPoint point;
        point.symbol = signature.function.signature.symbol;
        point.path = signature.sourcePath;
        point.function = signature.function.name;
        lexicon::Phrase syntax = statement.syntax;
        point.phrase = syntax.getKey();
        if (!point.phrase.empty() && point.phrase.front() == '\0') point.phrase.erase(point.phrase.begin());
        point.offset = code.size();
        const auto [line, column] = sourceLocation(statement.offset);
        point.line = line;
        point.column = column;

        std::unordered_set<std::string> visible;
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
          for (const auto &[name, local] : *scope) {
            if (!visible.insert(name).second) continue;
            const compiler::TypeDescriptor type = context.language().types.get(local.type);
            point.locals.push_back({name, type.name, local.offset, static_cast<std::uint32_t>(type.size),
                                    static_cast<std::uint8_t>(type.kind), type.isSigned});
          }
        }
        std::sort(
            point.locals.begin(), point.locals.end(),
            [](const compiler::DebugLocal &left, const compiler::DebugLocal &right) { return left.name < right.name; });
        debugPoints.push_back(std::move(point));
      }

      void statements(const std::vector<Statement> &source, bool nested = false) {
        const std::size_t deferDepth = defers.size();
        if (nested) scopes.emplace_back();
        for (const Statement &statement : source) generate(statement);
        emitDefers(deferDepth);
        defers.resize(deferDepth);
        if (nested) scopes.pop_back();
      }

      void emitDefers(std::size_t depth) {
        for (std::size_t index = defers.size(); index-- > depth;) expression(*defers[index]);
      }

      compiler::TypeId expressionBlock(const std::vector<Statement> &source, std::size_t offset) {
        lexicon::Phrase valueSyntax = source.empty()
                                          ? lexicon::Phrase(&context.lexicon)
                                          : LanguageGrammar::behavior(source.back().syntax, StatementValueName);
        if (valueSyntax.isNull()) fail({}, offset, "a value block must end with an expression");
        const std::size_t deferDepth = defers.size();
        scopes.emplace_back();
        for (std::size_t index = 0; index + 1 < source.size(); ++index) generate(source[index]);
        const compiler::TypeId result = expression(*source.back().expression);
        if (defers.size() != deferDepth) {
          const std::size_t saved = allocate();
          emit("mov", slot(saved) + ", rax");
          emitDefers(deferDepth);
          emit("mov", "rax, " + slot(saved));
        }
        defers.resize(deferDepth);
        scopes.pop_back();
        return result;
      }

    public:
      void generate(const Statement &statement) {
        lexicon::Phrase syntax = statement.syntax;
        if (syntax.isNull()) fail({}, statement.offset, "fn statement has no syntax phrase");
        lexicon::Phrase implementation = LanguageGrammar::behavior(syntax, StatementEmitName);
        if (implementation.isNull())
          fail({}, statement.offset, "fn statement syntax '" + syntax.getKeyEscaped() + "' has no emitter");
        recordDebugPoint(statement);
        StatementFrame frame{this, &statement};
        StatementFrame *previous = currentStatementFrame;
        currentStatementFrame = &frame;
        try {
          implementation.invoke(context);
        } catch (...) {
          currentStatementFrame = previous;
          throw;
        }
        currentStatementFrame = previous;
      }

      void generateVariable(const Statement &statement) {
        if (scopes.back().contains(statement.name))
          fail({}, statement.offset, "duplicate local variable '" + statement.name + "'");
        const compiler::TypeId valueType = expression(*statement.expression, statement.declaredType);
        const compiler::TypeId type =
            statement.declaredType == compiler::InvalidType ? valueType : statement.declaredType;
        compatible(type, valueType, statement.offset);
        const compiler::TypeDescriptor descriptor = context.language().types.get(type);
        if (descriptor.size > 8 || descriptor.kind == compiler::TypeKind::Structure ||
            descriptor.kind == compiler::TypeKind::Array)
          fail({}, statement.offset, "fn aggregate locals must currently be held through pointers");
        const Local local{type, allocate(), statement.mutableValue};
        scopes.back().emplace(statement.name, local);
        emit("mov", slot(local.offset) + ", rax");
      }

      void generateAssignment(const Statement &statement) {
        const compiler::TypeId targetType = lvalue(*statement.target, true);
        emit("push", "rax");
        ++temporaryDepth;
        const compiler::TypeId valueType = expression(*statement.expression, targetType);
        compatible(targetType, valueType, statement.offset);
        emit("mov", "rcx, rax");
        emit("pop", "rdx");
        --temporaryDepth;
        emit("mov", "r9, rdx");
        lexicon::Phrase operation = statement.operationSyntax;
        lexicon::Phrase implementation = LanguageGrammar::behavior(operation, AssignmentEmitName);
        if (implementation.isNull())
          fail({}, statement.offset, "assignment operator '" + statement.operation + "' has no fn behavior");
        AssignmentFrame frame{this, &statement, targetType};
        AssignmentFrame *previous = currentAssignmentFrame;
        currentAssignmentFrame = &frame;
        try {
          implementation.invoke(context);
        } catch (...) {
          currentAssignmentFrame = previous;
          throw;
        }
        currentAssignmentFrame = previous;
        store(targetType, "r9");
      }

      void emitAssignmentMove(compiler::TypeId) {
        emit("mov", "rax, rcx");
      }

      void emitAssignmentArithmetic(compiler::TypeId targetType, std::string_view instruction) {
        load(targetType, "rdx");
        emit(instruction, "rax, rcx");
      }

      void emitAssignmentDivision(compiler::TypeId targetType, bool remainder) {
        load(targetType, "rdx");
        emit("cqo", "");
        emit("idiv", "rcx");
        if (remainder) emit("mov", "rax, rdx");
      }

      void generateConditional(const Statement &statement) {
        expression(*statement.expression);
        emit("test", "rax, rax");
        const std::size_t rejected = jump({0x0f, 0x84});
        statements(statement.accepted, true);
        const std::size_t end = jump({0xe9});
        patchRelative(rejected, code.size());
        statements(statement.rejected, true);
        patchRelative(end, code.size());
      }

      void generateLoop(const Statement &statement) {
        const std::size_t begin = code.size();
        expression(*statement.expression);
        emit("test", "rax, rax");
        const std::size_t end = jump({0x0f, 0x84});
        loops.push_back({begin, {}, defers.size()});
        statements(statement.accepted, true);
        const std::size_t again = jump({0xe9});
        patchRelative(again, begin);
        patchRelative(end, code.size());
        for (const std::size_t patch : loops.back().breaks) patchRelative(patch, code.size());
        loops.pop_back();
      }

      void generateBreak(const Statement &statement) {
        if (loops.empty()) fail({}, statement.offset, "break requires an enclosing while loop");
        emitDefers(loops.back().deferDepth);
        loops.back().breaks.push_back(jump({0xe9}));
      }

      void generateContinue(const Statement &statement) {
        if (loops.empty()) fail({}, statement.offset, "continue requires an enclosing while loop");
        emitDefers(loops.back().deferDepth);
        const std::size_t again = jump({0xe9});
        patchRelative(again, loops.back().begin);
      }

      void generateReturn(const Statement &statement) {
        if (statement.expression) {
          const compiler::TypeId result = expression(*statement.expression, signature.function.resultType);
          compatible(signature.function.resultType, result, statement.offset);
        } else {
          if (context.language().types.get(signature.function.resultType).kind != compiler::TypeKind::Void)
            fail({}, statement.offset, "non-void fn requires a return value");
          emit("xor", "eax, eax");
        }
        if (!defers.empty()) {
          if (returnSlot == 0) returnSlot = allocate();
          emit("mov", slot(returnSlot) + ", rax");
          emitDefers(0);
          emit("mov", "rax, " + slot(returnSlot));
        }
        returns.push_back(jump({0xe9}));
      }

      void generateDefer(const Statement &statement) {
        defers.push_back(statement.expression.get());
      }

      void generateExpression(const Statement &statement) {
        expression(*statement.expression);
      }

    private:
      compiler::TypeId expression(const Expression &value, compiler::TypeId expected = compiler::InvalidType) {
        switch (value.kind) {
        case Expression::Kind::Integer: {
          std::string text = value.text;
          text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
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
          std::uint64_t number = 0;
          const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), number, base);
          if (text.empty() || error != std::errc() || end != text.data() + text.size())
            fail({}, value.offset, "invalid integer literal");
          emit("mov", "rax, " + std::to_string(number));
          return integerType;
        }
        case Expression::Kind::Real: {
          std::string text = value.text;
          text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
          double number = 0;
          const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), number);
          if (text.empty() || error != std::errc() || end != text.data() + text.size())
            fail({}, value.offset, "invalid real literal");
          emit("mov", "rax, " + std::to_string(std::bit_cast<std::uint64_t>(number)));
          return realType;
        }
        case Expression::Kind::String: {
          const std::string symbol =
              ".Lnative." + signature.function.signature.symbol + ".string." + std::to_string(strings.size());
          const std::size_t offset = rodata.size();
          rodata.insert(rodata.end(), value.text.begin(), value.text.end());
          rodata.push_back(0);
          strings.push_back({symbol, offset});
          emitDataAddress(symbol);
          return bytePointer;
        }
        case Expression::Kind::BitString: {
          const std::size_t index = strings.size();
          const std::string prefix =
              ".Lnative." + signature.function.signature.symbol + ".bits." + std::to_string(index);
          const std::string dataSymbol = prefix + ".data";
          const std::size_t dataOffset = rodata.size();
          rodata.resize(dataOffset + Bit::bytes(value.text.size()), 0);
          for (std::size_t bit = 0; bit < value.text.size(); ++bit)
            if (value.text[bit] == '1') rodata[dataOffset + bit / Byte::length] |= 1u << (7 - bit % Byte::length);
          strings.push_back({dataSymbol, dataOffset});

          const std::size_t alignment = alignof(BitString);
          const std::size_t descriptorOffset = (rodata.size() + alignment - 1) & ~(alignment - 1);
          rodata.resize(descriptorOffset, 0);
          const std::string descriptorSymbol = prefix + ".descriptor";
          strings.push_back({descriptorSymbol, descriptorOffset});
          appendReadOnlyLittle(0, sizeof(BitString::data));
          appendReadOnlyLittle(value.text.size(), sizeof(BitString::bits));
          rodataAlignment = std::max(rodataAlignment, alignment);
          relocations.push_back({compiler::SectionKind::ReadOnlyData, descriptorOffset,
                                 compiler::RelocationKind::Absolute64, dataSymbol, 0, false});
          emitDataAddress(descriptorSymbol);
          return bitStringPointer;
        }
        case Expression::Kind::FunctionLiteral: {
          const std::optional<compiler::TypedFunction> function = context.language().findFunction(value.text);
          if (!function) fail({}, value.offset, "inline fn implementation is unavailable: '" + value.text + "'");
          const compiler::TypeId functionType = context.language().functionType(*function);
          if (expected != phraseActionPointer) {
            emitFunctionAddress(function->signature.symbol, function->imported);
            return functionType;
          }
          if (functionType != actionFunctionType)
            fail({}, value.offset, "phrase action requires fn (context:Context*, phrase:Phrase*) -> void");
          const std::size_t index = strings.size();
          const std::string prefix =
              ".Lnative." + signature.function.signature.symbol + ".action." + std::to_string(index);
          const std::string symbolName = prefix + ".symbol";
          const std::size_t symbolOffset = rodata.size();
          rodata.insert(rodata.end(), value.text.begin(), value.text.end());
          rodata.push_back(0);
          strings.push_back({symbolName, symbolOffset});

          const std::size_t alignment = alignof(PhraseAction);
          const std::size_t descriptorOffset = (rodata.size() + alignment - 1) & ~(alignment - 1);
          rodata.resize(descriptorOffset, 0);
          const std::string descriptorSymbol = prefix + ".descriptor";
          strings.push_back({descriptorSymbol, descriptorOffset});
          appendReadOnlyLittle(0, sizeof(PhraseAction::symbol));
          appendReadOnlyLittle(value.text.size(), sizeof(PhraseAction::bytes));
          rodataAlignment = std::max(rodataAlignment, alignment);
          relocations.push_back({compiler::SectionKind::ReadOnlyData, descriptorOffset,
                                 compiler::RelocationKind::Absolute64, symbolName, 0, false});
          emitDataAddress(descriptorSymbol);
          return phraseActionPointer;
        }
        case Expression::Kind::Variable: {
          if (const Local *local = findLocalOptional(value.text)) {
            emit("mov", "rax, " + slot(local->offset));
            return local->type;
          }
          const std::optional<compiler::TypedFunction> function = functionReference(value.text, expected);
          if (!function) fail({}, value.offset, "unknown fn local or typed function '" + value.text + "'");
          emitFunctionAddress(function->signature.symbol, function->imported);
          return context.language().functionType(*function);
        }
        case Expression::Kind::Index: {
          const compiler::TypeId type = lvalue(value, false);
          load(type, "rax");
          return type;
        }
        case Expression::Kind::Member: {
          const compiler::TypeId type = lvalue(value, false);
          load(type, "rax");
          return type;
        }
        case Expression::Kind::Call: return call(value);
        case Expression::Kind::MethodCall: return methodCall(value);
        case Expression::Kind::Unary: return operatorBehavior(value, OperatorEmitName, expected);
        case Expression::Kind::Binary: return operatorBehavior(value, OperatorEmitName);
        case Expression::Kind::Block: return expressionBlock(value.body->accepted, value.offset);
        case Expression::Kind::Conditional: {
          expression(*value.body->condition);
          emit("test", "rax, rax");
          const std::size_t rejected = jump({0x0f, 0x84});
          const compiler::TypeId accepted = expressionBlock(value.body->accepted, value.offset);
          const std::size_t end = jump({0xe9});
          patchRelative(rejected, code.size());
          const compiler::TypeId rejectedType = expressionBlock(value.body->rejected, value.offset);
          compatible(accepted, rejectedType, value.offset);
          patchRelative(end, code.size());
          return accepted;
        }
        case Expression::Kind::Propagate: {
          const compiler::TypeId type = expression(*value.children[0]);
          const compiler::TypeDescriptor descriptor = context.language().types.get(type);
          const compiler::TypeDescriptor result = context.language().types.get(signature.function.resultType);
          if (descriptor.kind != compiler::TypeKind::Pointer || result.kind != compiler::TypeKind::Pointer)
            fail({}, value.offset, "'?' currently propagates null pointers from pointer-returning functions");
          emit("test", "rax, rax");
          const std::size_t present = jump({0x0f, 0x85});
          emitDefers(0);
          emit("xor", "eax, eax");
          returns.push_back(jump({0xe9}));
          patchRelative(present, code.size());
          return type;
        }
        }
        fail({}, value.offset, "invalid fn expression");
      }

      compiler::TypeId infer(const Expression &value, compiler::TypeId expected = compiler::InvalidType) {
        switch (value.kind) {
        case Expression::Kind::Integer: return integerType;
        case Expression::Kind::Real: return realType;
        case Expression::Kind::String: return bytePointer;
        case Expression::Kind::BitString: return bitStringPointer;
        case Expression::Kind::FunctionLiteral: {
          const std::optional<compiler::TypedFunction> function = context.language().findFunction(value.text);
          if (!function) fail({}, value.offset, "inline fn implementation is unavailable: '" + value.text + "'");
          const compiler::TypeId functionType = context.language().functionType(*function);
          if (expected != phraseActionPointer) return functionType;
          if (functionType != actionFunctionType)
            fail({}, value.offset, "phrase action requires fn (context:Context*, phrase:Phrase*) -> void");
          return phraseActionPointer;
        }
        case Expression::Kind::Variable:
          if (const Local *local = findLocalOptional(value.text)) return local->type;
          if (const std::optional<compiler::TypedFunction> function = functionReference(value.text, expected))
            return context.language().functionType(*function);
          fail({}, value.offset, "unknown fn local or typed function '" + value.text + "'");
        case Expression::Kind::Index: {
          const compiler::TypeDescriptor pointer = context.language().types.get(infer(*value.children[0]));
          if (pointer.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "indexing requires a pointer");
          return pointer.element;
        }
        case Expression::Kind::Member: {
          compiler::TypeDescriptor owner = context.language().types.get(infer(*value.children[0]));
          if (owner.kind == compiler::TypeKind::Pointer) owner = context.language().types.get(owner.element);
          if (owner.kind != compiler::TypeKind::Structure)
            fail({}, value.offset, "member access requires a record or pointer to a record");
          const auto field =
              std::find_if(owner.fields.begin(), owner.fields.end(),
                           [&](const compiler::TypeField &candidate) { return candidate.name == value.text; });
          if (field == owner.fields.end())
            fail({}, value.offset, "record '" + owner.name + "' has no field '" + value.text + "'");
          return field->type;
        }
        case Expression::Kind::Call: {
          if (!functions(value.text).empty()) return resolveDirect(value).resultType;
          const Local &callee = findLocal(value.text, value.offset);
          const compiler::TypeDescriptor callable = context.language().types.get(callee.type);
          if (callable.kind == compiler::TypeKind::Function) return callable.resultType;
          if (callable.kind == compiler::TypeKind::Pointer) return integerType;
          fail({}, value.offset, "indirect fn call requires a function or pointer local");
        }
        case Expression::Kind::MethodCall: return methodFunction(value).resultType;
        case Expression::Kind::Unary: return operatorBehavior(value, OperatorInferName, expected);
        case Expression::Kind::Binary: return operatorBehavior(value, OperatorInferName);
        case Expression::Kind::Propagate: return infer(*value.children[0]);
        case Expression::Kind::Block:
        case Expression::Kind::Conditional:
          fail({}, value.offset, "value blocks cannot currently be used as assignment targets or receivers");
        }
        fail({}, value.offset, "invalid fn expression type");
      }

      compiler::TypeId lvalue(const Expression &value, bool requireMutable) {
        if (value.kind == Expression::Kind::Variable) {
          const Local &local = findLocal(value.text, value.offset);
          if (requireMutable && !local.mutableValue)
            fail({}, value.offset, "cannot assign to const local '" + value.text + "'");
          emit("lea", "rax, [rbp - " + std::to_string(local.offset) + "]");
          return local.type;
        }
        if (value.kind == Expression::Kind::Unary) {
          lexicon::Phrase implementation = LanguageGrammar::behavior(value.syntax, OperatorLvalueName);
          if (!implementation.isNull()) return operatorBehavior(value, OperatorLvalueName);
        }
        if (value.kind == Expression::Kind::Index) {
          const compiler::TypeId baseType = expression(*value.children[0]);
          const compiler::TypeDescriptor pointer = context.language().types.get(baseType);
          if (pointer.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "indexing requires a pointer");
          emit("push", "rax");
          ++temporaryDepth;
          const compiler::TypeId indexType = expression(*value.children[1]);
          if (context.language().types.get(indexType).kind != compiler::TypeKind::Integer)
            fail({}, value.offset, "pointer index must be an integer");
          emit("mov", "rcx, rax");
          emit("pop", "rax");
          --temporaryDepth;
          const std::size_t scale = context.language().types.get(pointer.element).size;
          if (scale == 0) fail({}, value.offset, "cannot index a zero-sized element");
          if (scale != 1) emit("imul", "rcx, " + std::to_string(scale));
          emit("add", "rax, rcx");
          return pointer.element;
        }
        if (value.kind == Expression::Kind::Member) {
          compiler::TypeDescriptor owner = context.language().types.get(infer(*value.children[0]));
          if (owner.kind == compiler::TypeKind::Pointer) {
            expression(*value.children[0]);
            owner = context.language().types.get(owner.element);
          } else {
            lvalue(*value.children[0], requireMutable);
          }
          if (owner.kind != compiler::TypeKind::Structure)
            fail({}, value.offset, "member access requires a record or pointer to a record");
          const auto field =
              std::find_if(owner.fields.begin(), owner.fields.end(),
                           [&](const compiler::TypeField &candidate) { return candidate.name == value.text; });
          if (field == owner.fields.end())
            fail({}, value.offset, "record '" + owner.name + "' has no field '" + value.text + "'");
          if (field->offset != 0) emit("add", "rax, " + std::to_string(field->offset));
          return field->type;
        }
        fail({}, value.offset, "assignment target is not writable");
      }

      void load(compiler::TypeId type, std::string_view address) {
        const compiler::TypeDescriptor descriptor = context.language().types.get(type);
        if (descriptor.kind == compiler::TypeKind::Structure || descriptor.kind == compiler::TypeKind::Array ||
            descriptor.size == 0 || descriptor.size > 8)
          fail({}, 0, "fn aggregate values must currently be accessed through pointers");
        if (descriptor.size == 8)
          emit("mov", "rax, qword [" + std::string(address) + "]");
        else if (descriptor.size == 4)
          emit("mov", "eax, dword [" + std::string(address) + "]");
        else
          emit("movzx",
               "eax, " + std::string(descriptor.size == 1 ? "byte" : "word") + " [" + std::string(address) + "]");
      }

      void store(compiler::TypeId type, std::string_view address) {
        const compiler::TypeDescriptor descriptor = context.language().types.get(type);
        if (descriptor.kind == compiler::TypeKind::Structure || descriptor.kind == compiler::TypeKind::Array ||
            descriptor.size == 0 || descriptor.size > 8)
          fail({}, 0, "fn aggregate values must currently be accessed through pointers");
        const std::string operand = descriptor.size == 1   ? "byte [" + std::string(address) + "], al"
                                    : descriptor.size == 2 ? "word [" + std::string(address) + "], ax"
                                    : descriptor.size == 4 ? "dword [" + std::string(address) + "], eax"
                                                           : "qword [" + std::string(address) + "], rax";
        emit("mov", operand);
      }

      std::optional<compiler::TypedFunction> functionReference(const std::string &name, compiler::TypeId expected) {
        std::vector<compiler::TypedFunction> candidates = functions(name);
        if (candidates.empty()) {
          const std::optional<compiler::TypedFunction> physical = context.language().findFunction(name);
          if (physical) candidates.push_back(*physical);
        }
        if (expected != compiler::InvalidType &&
            context.language().types.get(expected).kind == compiler::TypeKind::Function) {
          candidates.erase(std::remove_if(candidates.begin(), candidates.end(),
                                          [&](const auto &candidate) {
                                            return context.language().functionType(candidate) != expected;
                                          }),
                           candidates.end());
        }
        return candidates.size() == 1 ? std::optional<compiler::TypedFunction>{candidates.front()} : std::nullopt;
      }

      std::optional<compiler::TypeId> contextualArgumentType(const Expression &value, compiler::TypeId expected) {
        if (value.kind == Expression::Kind::Variable && findLocalOptional(value.text) == nullptr &&
            !functions(value.text).empty()) {
          const std::optional<compiler::TypedFunction> function = functionReference(value.text, expected);
          if (!function) return std::nullopt;
          return context.language().functionType(*function);
        }
        return infer(value, expected);
      }

      compiler::TypedFunction resolveDirect(const Expression &value, const std::string &name = {}) {
        const std::string &callName = name.empty() ? value.text : name;
        const std::vector<compiler::TypedFunction> candidates = functions(callName);
        const compiler::TypedFunction *best = nullptr;
        std::size_t bestCost = std::numeric_limits<std::size_t>::max();
        bool ambiguous = false;
        for (const compiler::TypedFunction &candidate : candidates) {
          if ((!candidate.signature.variadic && candidate.parameterTypes.size() != value.children.size()) ||
              (candidate.signature.variadic && candidate.parameterTypes.size() > value.children.size()))
            continue;
          std::size_t cost = candidate.signature.variadic ? 2 : 0;
          bool compatible = true;
          for (std::size_t index = 0; index < value.children.size(); ++index) {
            const compiler::TypeId expected =
                index < candidate.parameterTypes.size() ? candidate.parameterTypes[index] : compiler::InvalidType;
            const std::optional<compiler::TypeId> actual = contextualArgumentType(*value.children[index], expected);
            if (!actual) {
              compatible = false;
              break;
            }
            if (expected == compiler::InvalidType) continue;
            const std::optional<std::size_t> conversion = context.language().conversionCost(expected, *actual);
            if (!conversion) {
              compatible = false;
              break;
            }
            cost += *conversion;
          }
          if (!compatible) continue;
          if (cost < bestCost) {
            best = &candidate;
            bestCost = cost;
            ambiguous = false;
          } else if (cost == bestCost) {
            ambiguous = true;
          }
        }
        if (ambiguous) fail({}, value.offset, "ambiguous typed function overload: '" + callName + "'");
        if (best == nullptr) fail({}, value.offset, "no matching overload for '" + callName + "'");
        return *best;
      }

      compiler::TypeId call(const Expression &value) {
        const bool hasOverloads = !functions(value.text).empty();
        const std::optional<compiler::TypedFunction> function =
            hasOverloads ? std::optional<compiler::TypedFunction>{resolveDirect(value)} : std::nullopt;
        const Local *indirect = hasOverloads ? nullptr : findLocalOptional(value.text);
        if (!function && indirect == nullptr)
          fail({}, value.offset, "call target is neither a typed phrase nor a pointer local: '" + value.text + "'");
        return callResolved(value, function, indirect, value.text);
      }

      compiler::TypeId callResolved(const Expression &value, const std::optional<compiler::TypedFunction> &function,
                                    const Local *indirect, const std::string &symbol) {
        std::optional<compiler::TypedFunction> callable = function;
        if (!callable && indirect != nullptr) {
          const compiler::TypeDescriptor type = context.language().types.get(indirect->type);
          if (type.kind == compiler::TypeKind::Function) {
            compiler::TypedFunction typed;
            typed.signature = context.language().functionSignature(indirect->type);
            typed.parameterTypes = type.parameterTypes;
            typed.resultType = type.resultType;
            callable = std::move(typed);
          } else if (type.kind != compiler::TypeKind::Pointer) {
            fail({}, value.offset, "indirect fn call requires a function or pointer local");
          }
        }
        if (callable && callable->signature.convention.name != "sysv-amd64")
          fail({}, value.offset, "fn calls currently require the sysv-amd64 ABI");
        if (callable && ((!callable->signature.variadic && value.children.size() != callable->parameterTypes.size()) ||
                         (callable->signature.variadic && value.children.size() < callable->parameterTypes.size())))
          fail({}, value.offset, "invalid argument count for '" + symbol + "'");

        static constexpr std::string_view registers[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
        const std::size_t registerArguments = std::min(value.children.size(), std::size(registers));
        const std::size_t stackArguments = value.children.size() - registerArguments;
        const bool padding = ((temporaryDepth + stackArguments) & 1u) != 0;
        if (padding) {
          emit("sub", "rsp, 8");
          ++temporaryDepth;
        }
        for (std::size_t reverse = value.children.size(); reverse-- > 0;) {
          const compiler::TypeId expected = callable && reverse < callable->parameterTypes.size()
                                                ? callable->parameterTypes[reverse]
                                                : compiler::InvalidType;
          const compiler::TypeId actual = expression(*value.children[reverse], expected);
          const compiler::TypeDescriptor actualDescriptor = context.language().types.get(actual);
          if (actualDescriptor.kind == compiler::TypeKind::FloatingPoint || actualDescriptor.size > 8)
            fail({}, value.offset, "fn calls currently require integer, pointer, or scalar arguments up to 64 bits");
          if (expected != compiler::InvalidType) compatible(expected, actual, value.offset);
          emit("push", "rax");
          ++temporaryDepth;
        }
        for (std::size_t index = 0; index < registerArguments; ++index) {
          emit("pop", std::string(registers[index]));
          --temporaryDepth;
        }
        if (callable && callable->signature.variadic) emit("xor", "eax, eax");
        if (function) {
          if (function->imported) {
            emitBytes({0x49, 0xbb});
            const std::size_t patch = code.size();
            little(0, 8);
            relocations.push_back({compiler::SectionKind::Text, patch, compiler::RelocationKind::Absolute64,
                                   function->signature.symbol, 0, true});
            emitBytes({0x41, 0xff, 0xd3});
          } else {
            emitBytes({0xe8});
            const std::size_t patch = code.size();
            little(0, 4);
            relocations.push_back({compiler::SectionKind::Text, patch, compiler::RelocationKind::PCRelative32,
                                   function->signature.symbol, -4,
                                   function->signature.symbol != signature.function.signature.symbol});
          }
        } else {
          emit("mov", "rax, " + slot(indirect->offset));
          emit("call", "rax");
        }
        if (stackArguments != 0) {
          emit("add", "rsp, " + std::to_string(stackArguments * 8));
          temporaryDepth -= stackArguments;
        }
        if (padding) {
          emit("add", "rsp, 8");
          --temporaryDepth;
        }
        return callable ? callable->resultType : integerType;
      }

      compiler::TypedFunction methodFunction(const Expression &value) {
        compiler::TypeDescriptor owner = context.language().types.get(infer(*value.children.front()));
        if (owner.kind == compiler::TypeKind::Pointer) owner = context.language().types.get(owner.element);
        if (owner.kind != compiler::TypeKind::Structure)
          fail({}, value.offset, "method call requires a record or pointer to a record");
        if (std::none_of(owner.methods.begin(), owner.methods.end(),
                         [&](const compiler::TypeMethod &candidate) { return candidate.name == value.text; }))
          fail({}, value.offset, "record '" + owner.name + "' has no method '" + value.text + "'");
        const std::string name = owner.name + ":" + value.text;
        return resolveDirect(value, name);
      }

      std::vector<compiler::TypedFunction> functions(std::string_view name) const {
        return context.language().findFunctions(name, signature.scope);
      }

      compiler::TypeId methodCall(const Expression &value) {
        const compiler::TypedFunction function = methodFunction(value);
        return callResolved(value, std::optional<compiler::TypedFunction>{function}, nullptr,
                            function.signature.symbol);
      }

      Local *findLocalOptional(const std::string &name) {
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
          const auto found = scope->find(name);
          if (found != scope->end()) return &found->second;
        }
        return nullptr;
      }
      const Local *findLocalOptional(const std::string &name) const {
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
          const auto found = scope->find(name);
          if (found != scope->end()) return &found->second;
        }
        return nullptr;
      }
      const Local &findLocal(const std::string &name, std::size_t offset) const {
        const Local *found = findLocalOptional(name);
        if (found == nullptr) fail({}, offset, "unknown fn local '" + name + "'");
        return *found;
      }
      void compatible(compiler::TypeId expected, compiler::TypeId actual, std::size_t offset) const {
        if (context.language().conversionCost(expected, actual)) return;
        const compiler::TypeDescriptor &left = context.language().types.get(expected);
        const compiler::TypeDescriptor &right = context.language().types.get(actual);
        fail({}, offset, "fn expression type '" + right.name + "' is incompatible with '" + left.name + "'");
      }

      context::Context &context;
      const FunctionDefinition &signature;
      compiler::TypeId integerType;
      compiler::TypeId realType;
      compiler::TypeId bytePointer;
      compiler::TypeId bitStringPointer;
      compiler::TypeId phraseActionPointer;
      compiler::TypeId actionFunctionType = compiler::InvalidType;
      std::vector<std::uint8_t> code;
      std::vector<std::uint8_t> rodata;
      std::vector<PendingRelocation> relocations;
      std::vector<StringLiteral> strings;
      std::vector<compiler::DebugPoint> debugPoints;
      std::vector<std::size_t> returns;
      std::vector<std::unordered_map<std::string, Local>> scopes;
      std::vector<Loop> loops;
      std::vector<const Expression *> defers;
      std::size_t frameBytes = 0;
      std::size_t framePatch = 0;
      std::size_t returnSlot = 0;
      std::size_t temporaryDepth = 0;
      std::size_t rodataAlignment = 1;
    };

    namespace {
      void inferLeft(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->inferLeft(*frame.expression);
      }

      void inferInteger(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->inferInteger(*frame.expression);
      }

      void emitPositive(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitPrefix(*frame.expression, {});
      }

      void emitNegative(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitPrefix(*frame.expression, "neg");
      }

      void emitNot(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitLogicalNot(*frame.expression);
      }

      void emitAdd(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitArithmetic(*frame.expression, "add");
      }

      void emitSubtract(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitArithmetic(*frame.expression, "sub");
      }

      void emitMultiply(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitArithmetic(*frame.expression, "imul");
      }

      void emitDivide(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitDivision(*frame.expression, false);
      }

      void emitModulo(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitDivision(*frame.expression, true);
      }

      void emitEqual(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x94);
      }

      void emitNotEqual(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x95);
      }

      void emitLess(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x9c);
      }

      void emitLessEqual(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x9e);
      }

      void emitGreater(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x9f);
      }

      void emitGreaterEqual(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitComparison(*frame.expression, 0x9d);
      }

      void emitAnd(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitLogical(*frame.expression, true);
      }

      void emitOr(context::Context &, lexicon::Phrase &) {
        OperatorFrame &frame = operatorFrame();
        frame.result = frame.generator->emitLogical(*frame.expression, false);
      }

      void compileIntrinsic(context::Context &, lexicon::Phrase &invoked) {
        OperatorFrame &frame = operatorFrame();
        IntrinsicBehavior behavior;
        invoked.fetch(0, behavior);
        switch (behavior.kind) {
        case IntrinsicKind::Cast:
          frame.result = behavior.phase == IntrinsicPhase::Infer
                             ? frame.generator->inferCastIntrinsic(*frame.expression)
                             : frame.generator->emitCastIntrinsic(*frame.expression);
          return;
        case IntrinsicKind::Address:
          frame.result = behavior.phase == IntrinsicPhase::Infer
                             ? frame.generator->inferAddressIntrinsic(*frame.expression, frame.expected)
                             : frame.generator->emitAddressIntrinsic(*frame.expression, frame.expected);
          return;
        case IntrinsicKind::Dereference:
          if (behavior.phase == IntrinsicPhase::Infer)
            frame.result = frame.generator->inferDereferenceIntrinsic(*frame.expression);
          else if (behavior.phase == IntrinsicPhase::Emit)
            frame.result = frame.generator->emitDereferenceIntrinsic(*frame.expression);
          else
            frame.result = frame.generator->lvalueDereferenceIntrinsic(*frame.expression);
          return;
        }
      }

      void emitVariableStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateVariable(*frame.statement);
      }

      void emitAssignmentStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateAssignment(*frame.statement);
      }

      void emitConditionalStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateConditional(*frame.statement);
      }

      void emitLoopStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateLoop(*frame.statement);
      }

      void emitBreakStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateBreak(*frame.statement);
      }

      void emitContinueStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateContinue(*frame.statement);
      }

      void emitReturnStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateReturn(*frame.statement);
      }

      void emitDeferStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateDefer(*frame.statement);
      }

      void emitExpressionStatement(context::Context &, lexicon::Phrase &) {
        StatementFrame &frame = statementFrame();
        frame.generator->generateExpression(*frame.statement);
      }

      void emitAssignmentMove(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentMove(frame.targetType);
      }

      void emitAssignmentAdd(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentArithmetic(frame.targetType, "add");
      }

      void emitAssignmentSubtract(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentArithmetic(frame.targetType, "sub");
      }

      void emitAssignmentMultiply(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentArithmetic(frame.targetType, "imul");
      }

      void emitAssignmentDivide(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentDivision(frame.targetType, false);
      }

      void emitAssignmentModulo(context::Context &, lexicon::Phrase &) {
        AssignmentFrame &frame = assignmentFrame();
        frame.generator->emitAssignmentDivision(frame.targetType, true);
      }

      lexicon::Phrase installBehavior(lexicon::Phrase owner, std::string_view key, lexicon::Phrase::Action action,
                                      lexicon::Phrase type) {
        return owner.append(Byte(const_cast<char *>(key.data())), 0, key.size() * Byte::length)
            .make(action)
            .setType(type)
            .save();
      }
    } // namespace

    void setupCompilerSyntax(context::Context &context) {
      const auto action = [&](std::string name, lexicon::Phrase::Action implementation) {
        context.actions().define(std::move(name), implementation);
      };
      action("fn.operator.infer-left", inferLeft);
      action("fn.operator.infer-integer", inferInteger);
      action("fn.operator.emit-positive", emitPositive);
      action("fn.operator.emit-negative", emitNegative);
      action("fn.operator.emit-not", emitNot);
      action("fn.operator.emit-add", emitAdd);
      action("fn.operator.emit-subtract", emitSubtract);
      action("fn.operator.emit-multiply", emitMultiply);
      action("fn.operator.emit-divide", emitDivide);
      action("fn.operator.emit-modulo", emitModulo);
      action("fn.operator.emit-equal", emitEqual);
      action("fn.operator.emit-not-equal", emitNotEqual);
      action("fn.operator.emit-less", emitLess);
      action("fn.operator.emit-less-equal", emitLessEqual);
      action("fn.operator.emit-greater", emitGreater);
      action("fn.operator.emit-greater-equal", emitGreaterEqual);
      action("fn.operator.emit-and", emitAnd);
      action("fn.operator.emit-or", emitOr);
      action("fn.intrinsic.compile", compileIntrinsic);
      action("fn.statement.emit-variable", emitVariableStatement);
      action("fn.statement.emit-assignment", emitAssignmentStatement);
      action("fn.statement.emit-conditional", emitConditionalStatement);
      action("fn.statement.emit-loop", emitLoopStatement);
      action("fn.statement.emit-break", emitBreakStatement);
      action("fn.statement.emit-continue", emitContinueStatement);
      action("fn.statement.emit-return", emitReturnStatement);
      action("fn.statement.emit-defer", emitDeferStatement);
      action("fn.statement.emit-expression", emitExpressionStatement);
      action("fn.assignment.emit-move", emitAssignmentMove);
      action("fn.assignment.emit-add", emitAssignmentAdd);
      action("fn.assignment.emit-subtract", emitAssignmentSubtract);
      action("fn.assignment.emit-multiply", emitAssignmentMultiply);
      action("fn.assignment.emit-divide", emitAssignmentDivide);
      action("fn.assignment.emit-modulo", emitAssignmentModulo);

      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
      const auto install = [&](bool prefix, std::string_view symbol, lexicon::Phrase::Action inference,
                               lexicon::Phrase::Action emission) {
        lexicon::Phrase syntax =
            prefix ? Expressions::prefixOperator(context, symbol) : Expressions::infixOperator(context, symbol);
        if (syntax.isNull()) THROW(, "cannot install fn behavior for missing operator '" << symbol << "'")
        installBehavior(syntax, OperatorInferName, inference, callable);
        installBehavior(syntax, OperatorEmitName, emission, callable);
      };

      install(true, "+", inferLeft, emitPositive);
      install(true, "-", inferLeft, emitNegative);
      install(true, "!", inferInteger, emitNot);
      install(false, "+", inferLeft, emitAdd);
      install(false, "-", inferLeft, emitSubtract);
      install(false, "*", inferLeft, emitMultiply);
      install(false, "/", inferLeft, emitDivide);
      install(false, "%", inferLeft, emitModulo);
      install(false, "==", inferInteger, emitEqual);
      install(false, "!=", inferInteger, emitNotEqual);
      install(false, "<", inferInteger, emitLess);
      install(false, "<=", inferInteger, emitLessEqual);
      install(false, ">", inferInteger, emitGreater);
      install(false, ">=", inferInteger, emitGreaterEqual);
      install(false, "&&", inferInteger, emitAnd);
      install(false, "||", inferInteger, emitOr);

      lexicon::Phrase grammar = exact(root, FunctionGrammarName);
      lexicon::Phrase intrinsics = exact(grammar, IntrinsicDictionaryName);
      if (intrinsics.isNull()) THROW(, "cannot install fn intrinsic compiler behaviors without intrinsic syntax")
      const auto intrinsic = [&](std::string_view name, IntrinsicKind kind, bool lvalue = false) {
        lexicon::Phrase syntax = exact(intrinsics, name);
        if (syntax.isNull()) THROW(, "cannot install fn behavior for missing intrinsic syntax '" << name << "'")
        installBehavior(syntax, OperatorInferName, compileIntrinsic, callable)
            .store(IntrinsicBehavior{kind, IntrinsicPhase::Infer});
        installBehavior(syntax, OperatorEmitName, compileIntrinsic, callable)
            .store(IntrinsicBehavior{kind, IntrinsicPhase::Emit});
        if (lvalue)
          installBehavior(syntax, OperatorLvalueName, compileIntrinsic, callable)
              .store(IntrinsicBehavior{kind, IntrinsicPhase::Lvalue});
      };
      intrinsic("cast", IntrinsicKind::Cast);
      intrinsic("&", IntrinsicKind::Address);
      intrinsic("*", IntrinsicKind::Dereference, true);

      lexicon::Phrase statements = exact(grammar, "statements");
      if (statements.isNull()) THROW(, "cannot install fn statement compiler behaviors without statement syntax")
      const auto statement = [&](std::string_view name, lexicon::Phrase::Action emission) {
        lexicon::Phrase syntax = exact(statements, name);
        if (syntax.isNull()) THROW(, "cannot install fn behavior for missing statement syntax")
        installBehavior(syntax, StatementEmitName, emission, callable);
        return syntax;
      };
      statement("var", emitVariableStatement);
      statement("let", emitVariableStatement);
      statement("const", emitVariableStatement);
      statement("set", emitAssignmentStatement);
      statement("if", emitConditionalStatement);
      statement("while", emitLoopStatement);
      statement("break", emitBreakStatement);
      statement("continue", emitContinueStatement);
      statement("return", emitReturnStatement);
      statement("defer", emitDeferStatement);
      statement(AssignmentStatementName, emitAssignmentStatement);
      lexicon::Phrase expressionSyntax = statement(ExpressionStatementName, emitExpressionStatement);
      expressionSyntax
          .append(Byte(const_cast<char *>(StatementValueName.data())), 0, StatementValueName.size() * Byte::length)
          .make()
          .setType(lexicon::phrase::type::getData(root))
          .save();

      lexicon::Phrase assignments = exact(exact(root, std::string_view{"\0expressions", 12}), "assignments");
      const auto assignment = [&](std::string_view name, lexicon::Phrase::Action emission) {
        lexicon::Phrase syntax = exact(assignments, name);
        if (syntax.isNull()) THROW(, "cannot install fn behavior for missing assignment operator '" << name << "'")
        installBehavior(syntax, AssignmentEmitName, emission, callable);
      };
      assignment("=", emitAssignmentMove);
      assignment("+=", emitAssignmentAdd);
      assignment("-=", emitAssignmentSubtract);
      assignment("*=", emitAssignmentMultiply);
      assignment("/=", emitAssignmentDivide);
      assignment("%=", emitAssignmentModulo);
    }

    compiler::Module generateModule(context::Context &context, const FunctionDefinition &signature,
                                    const std::vector<Statement> &body) {
      DiagnosticScope diagnostics(signature.sourceText,
                                  {signature.sourcePath, signature.sourceLine, signature.sourceColumn});
      Generator generator(context, signature);
      return generator.generate(body);
    }

  } // namespace function_internal
} // namespace recurloop
