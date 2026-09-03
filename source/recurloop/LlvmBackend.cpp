#include "LlvmBackend.hpp"

#include <compiler/ElfReader.hpp>
#include <recurloop/BitString.hpp>
#include <recurloop/PhraseAction.hpp>

// utilities/Console.hpp exposes this historical formatting macro globally;
// LLVM uses RESET as a scoped enum member in raw_ostream.
#ifdef RESET
  #undef RESET
#endif

#include <llvm/ADT/SmallVector.h>
#include <llvm/TargetParser/Triple.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/GlobalVariable.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/PassManager.h>
#include <llvm/IR/Verifier.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

#include <algorithm>
#include <charconv>
#include <deque>
#include <functional>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop::function_internal {
  namespace {
    struct Emitted {
      llvm::Value *value = nullptr;
      compiler::TypeId type = compiler::InvalidType;
    };

    struct LlvmLocal {
      llvm::AllocaInst *address = nullptr;
      compiler::TypeId type = compiler::InvalidType;
      bool mutableValue = true;
    };

    struct LlvmLoop {
      llvm::BasicBlock *condition = nullptr;
      llvm::BasicBlock *end = nullptr;
      std::size_t deferDepth = 0;
    };

    class LlvmGenerator {
    public:
      LlvmGenerator(context::Context &context, const FunctionDefinition &signature, std::string_view executableEntry,
                    std::string targetTriple = RECURLOOP_LLVM_TARGET_TRIPLE, std::string targetCpu = RECURLOOP_LLVM_CPU,
                    std::string targetFeatures = RECURLOOP_LLVM_FEATURES)
          : context(context), signature(signature), llvmContext(), module("recurloop", llvmContext),
            builder(llvmContext), integerType(context.language().types.find("i64")),
            realType(context.language().types.find("f64")),
            bytePointer(context.language().types.pointerTo(context.language().types.find("u8"))),
            bitStringPointer(context.language().types.find("BitString*")),
            phraseActionPointer(context.language().types.find("PhraseAction*")), executableEntry(executableEntry),
            triple(std::move(targetTriple)), cpu(std::move(targetCpu)), features(std::move(targetFeatures)) {}

      LlvmProgram generate(const std::vector<Statement> &body) {
        initializeTargets();
        if (triple.empty()) triple = llvm::sys::getDefaultTargetTriple();
        triple = llvm::Triple::normalize(triple);
        module.setTargetTriple(triple);

        std::string targetError;
        const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, targetError);
        if (target == nullptr) fail({}, 0, "LLVM target '" + triple + "' is unavailable: " + targetError);
        llvm::TargetOptions options;
        const llvm::CodeGenOptLevel codegenLevel = RECURLOOP_LLVM_OPT_LEVEL == 0   ? llvm::CodeGenOptLevel::None
                                                   : RECURLOOP_LLVM_OPT_LEVEL == 1 ? llvm::CodeGenOptLevel::Less
                                                   : RECURLOOP_LLVM_OPT_LEVEL == 2 ? llvm::CodeGenOptLevel::Default
                                                                                   : llvm::CodeGenOptLevel::Aggressive;
        machine.reset(target->createTargetMachine(triple, cpu, features, options, llvm::Reloc::PIC_,
                                                  llvm::CodeModel::Small, codegenLevel));
        if (!machine) fail({}, 0, "LLVM could not create a target machine for '" + triple + "'");
        module.setDataLayout(machine->createDataLayout());

        createFunction();
        statements(body);
        if (!builder.GetInsertBlock()->getTerminator()) defaultReturn();
        if (!executableEntry.empty()) createMainWrapper();

        std::string verification;
        llvm::raw_string_ostream verificationStream(verification);
        if (llvm::verifyModule(module, &verificationStream))
          fail({}, 0, "LLVM generated invalid IR: " + verificationStream.str());
        optimize();

        llvm::SmallVector<char, 0> bytes;
        llvm::raw_svector_ostream output(bytes);
        llvm::legacy::PassManager emitter;
        if (machine->addPassesToEmitFile(emitter, output, nullptr, llvm::CodeGenFileType::ObjectFile))
          fail({}, 0, "LLVM target cannot emit object files");
        emitter.run(module);

        LlvmProgram result;
        result.objects.emplace_back(bytes.begin(), bytes.end());
        result.providedSymbols.push_back(signature.function.signature.symbol);
        result.imports.assign(imports.begin(), imports.end());
        std::sort(result.imports.begin(), result.imports.end());
        result.triple = triple;
        return result;
      }

    private:
      static void initializeTargets() {
        static const bool initialized = [] {
          llvm::InitializeAllTargetInfos();
          llvm::InitializeAllTargets();
          llvm::InitializeAllTargetMCs();
          llvm::InitializeAllAsmParsers();
          llvm::InitializeAllAsmPrinters();
          return true;
        }();
        (void)initialized;
      }

      llvm::Type *type(compiler::TypeId id) {
        const compiler::TypeDescriptor descriptor = context.language().types.get(id);
        switch (descriptor.kind) {
        case compiler::TypeKind::Void: return llvm::Type::getVoidTy(llvmContext);
        case compiler::TypeKind::Integer:
          return llvm::IntegerType::get(llvmContext,
                                        static_cast<unsigned>(std::max<std::size_t>(1, descriptor.size * 8)));
        case compiler::TypeKind::FloatingPoint:
          return descriptor.size == sizeof(float) ? llvm::Type::getFloatTy(llvmContext)
                                                  : llvm::Type::getDoubleTy(llvmContext);
        case compiler::TypeKind::Pointer:
        case compiler::TypeKind::Function: return llvm::PointerType::getUnqual(llvmContext);
        case compiler::TypeKind::Array: return llvm::ArrayType::get(type(descriptor.element), descriptor.elementCount);
        case compiler::TypeKind::Structure:
          // Record accesses use the layout offsets owned by RecurLoop's type
          // registry. An opaque byte aggregate prevents LLVM from silently
          // inventing a second, incompatible layout.
          return llvm::ArrayType::get(llvm::Type::getInt8Ty(llvmContext), descriptor.size);
        }
        fail({}, 0, "LLVM encountered an invalid RecurLoop type");
      }

      llvm::FunctionType *functionType(const compiler::TypedFunction &function) {
        std::vector<llvm::Type *> parameters;
        parameters.reserve(function.parameterTypes.size());
        for (compiler::TypeId parameter : function.parameterTypes) parameters.push_back(type(parameter));
        return llvm::FunctionType::get(type(function.resultType), parameters, function.signature.variadic);
      }

      void createFunction() {
        function = llvm::Function::Create(functionType(signature.function), llvm::GlobalValue::ExternalLinkage,
                                          signature.function.signature.symbol, module);
        llvm::BasicBlock *entry = llvm::BasicBlock::Create(llvmContext, "entry", function);
        builder.SetInsertPoint(entry);
        scopes.emplace_back();
        std::size_t index = 0;
        for (llvm::Argument &argument : function->args()) {
          const std::string name =
              index < signature.names.size() ? signature.names[index] : "arg" + std::to_string(index);
          argument.setName(name);
          LlvmLocal local{allocate(signature.function.parameterTypes[index], name),
                          signature.function.parameterTypes[index], true};
          builder.CreateStore(&argument, local.address);
          scopes.back().emplace(name, local);
          ++index;
        }
      }

      llvm::AllocaInst *allocate(compiler::TypeId valueType, const std::string &name = {}) {
        llvm::IRBuilder<> entryBuilder(&function->getEntryBlock(), function->getEntryBlock().begin());
        return entryBuilder.CreateAlloca(type(valueType), nullptr, name);
      }

      void optimize() {
        llvm::PassBuilder passes(machine.get());
        llvm::LoopAnalysisManager loops;
        llvm::FunctionAnalysisManager functions;
        llvm::CGSCCAnalysisManager callGraph;
        llvm::ModuleAnalysisManager modules;
        passes.registerModuleAnalyses(modules);
        passes.registerCGSCCAnalyses(callGraph);
        passes.registerFunctionAnalyses(functions);
        passes.registerLoopAnalyses(loops);
        passes.crossRegisterProxies(loops, functions, callGraph, modules);
        const llvm::OptimizationLevel level = RECURLOOP_LLVM_OPT_LEVEL == 0   ? llvm::OptimizationLevel::O0
                                              : RECURLOOP_LLVM_OPT_LEVEL == 1 ? llvm::OptimizationLevel::O1
                                              : RECURLOOP_LLVM_OPT_LEVEL == 2 ? llvm::OptimizationLevel::O2
                                                                              : llvm::OptimizationLevel::O3;
        llvm::ModulePassManager pipeline = passes.buildPerModuleDefaultPipeline(level);
        pipeline.run(module, modules);
      }

      void defaultReturn() {
        const compiler::TypeDescriptor result = context.language().types.get(signature.function.resultType);
        if (result.kind == compiler::TypeKind::Void) {
          builder.CreateRetVoid();
        } else {
          builder.CreateRet(llvm::Constant::getNullValue(type(signature.function.resultType)));
        }
      }

      void createMainWrapper() {
        compiler::TypedFunction entryDefinition;
        llvm::Function *entryFunction = nullptr;
        if (executableEntry == signature.function.signature.symbol) {
          entryDefinition = signature.function;
          entryFunction = function;
        } else {
          const std::optional<compiler::TypedFunction> selected = context.language().findFunction(executableEntry);
          if (!selected)
            fail({}, 0, "LLVM executable entry has no typed function declaration: '" + executableEntry + "'");
          entryDefinition = *selected;
          entryFunction = declare(entryDefinition);
        }
        if (entryFunction->getName() == "main") return;
        llvm::FunctionType *mainType = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(llvmContext),
            {llvm::Type::getInt32Ty(llvmContext), llvm::PointerType::getUnqual(llvmContext)}, false);
        llvm::Function *main = llvm::Function::Create(mainType, llvm::GlobalValue::ExternalLinkage, "main", module);
        llvm::BasicBlock *entry = llvm::BasicBlock::Create(llvmContext, "entry", main);
        llvm::IRBuilder<> wrapper(entry);
        std::vector<llvm::Value *> arguments;
        auto source = main->arg_begin();
        if (!entryDefinition.parameterTypes.empty()) {
          arguments.push_back(coerceWith(wrapper, &*source, context.language().types.find("i32"),
                                         entryDefinition.parameterTypes[0], 0));
          ++source;
        }
        if (entryDefinition.parameterTypes.size() >= 2)
          arguments.push_back(coerceWith(wrapper, &*source, context.language().types.find("u8**"),
                                         entryDefinition.parameterTypes[1], 0));
        if (entryDefinition.parameterTypes.size() > 2)
          fail({}, 0, "LLVM executable entry supports at most argc and argv parameters");
        llvm::CallInst *call = wrapper.CreateCall(functionType(entryDefinition), entryFunction, arguments);
        const compiler::TypeDescriptor result = context.language().types.get(entryDefinition.resultType);
        if (result.kind == compiler::TypeKind::Void) {
          wrapper.CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(llvmContext), 0));
        } else if (result.kind == compiler::TypeKind::Integer) {
          wrapper.CreateRet(
              coerceWith(wrapper, call, entryDefinition.resultType, context.language().types.find("i32"), 0));
        } else {
          fail({}, 0, "LLVM executable entry must return void or an integer status");
        }
      }

      llvm::Value *coerceWith(llvm::IRBuilder<> &output, llvm::Value *value, compiler::TypeId sourceId,
                              compiler::TypeId targetId, std::size_t offset, bool explicitCast = false) {
        if (sourceId == targetId) return value;
        const compiler::TypeDescriptor source = context.language().types.get(sourceId);
        const compiler::TypeDescriptor target = context.language().types.get(targetId);
        if (!explicitCast && !context.language().conversionCost(targetId, sourceId))
          incompatible(targetId, sourceId, offset);
        if (source.kind == compiler::TypeKind::Integer && target.kind == compiler::TypeKind::Integer) {
          const unsigned sourceBits = static_cast<unsigned>(source.size * 8);
          const unsigned targetBits = static_cast<unsigned>(target.size * 8);
          if (sourceBits < targetBits)
            return source.isSigned ? output.CreateSExt(value, type(targetId))
                                   : output.CreateZExt(value, type(targetId));
          if (sourceBits > targetBits) return output.CreateTrunc(value, type(targetId));
          return value;
        }
        if (source.kind == compiler::TypeKind::FloatingPoint && target.kind == compiler::TypeKind::FloatingPoint)
          return source.size < target.size ? output.CreateFPExt(value, type(targetId))
                                           : output.CreateFPTrunc(value, type(targetId));
        if (explicitCast && source.kind == compiler::TypeKind::Integer &&
            target.kind == compiler::TypeKind::FloatingPoint)
          return source.isSigned ? output.CreateSIToFP(value, type(targetId))
                                 : output.CreateUIToFP(value, type(targetId));
        if (explicitCast && source.kind == compiler::TypeKind::FloatingPoint &&
            target.kind == compiler::TypeKind::Integer)
          return target.isSigned ? output.CreateFPToSI(value, type(targetId))
                                 : output.CreateFPToUI(value, type(targetId));
        const bool sourcePointer =
            source.kind == compiler::TypeKind::Pointer || source.kind == compiler::TypeKind::Function;
        const bool targetPointer =
            target.kind == compiler::TypeKind::Pointer || target.kind == compiler::TypeKind::Function;
        if (sourcePointer && targetPointer) return value;
        if (explicitCast && sourcePointer && target.kind == compiler::TypeKind::Integer)
          return output.CreatePtrToInt(value, type(targetId));
        if (explicitCast && source.kind == compiler::TypeKind::Integer && targetPointer)
          return output.CreateIntToPtr(value, type(targetId));
        incompatible(targetId, sourceId, offset);
      }

      Emitted coerce(Emitted value, compiler::TypeId expected, std::size_t offset, bool explicitCast = false) {
        if (expected == compiler::InvalidType) return value;
        value.value = coerceWith(builder, value.value, value.type, expected, offset, explicitCast);
        value.type = expected;
        return value;
      }

      llvm::Value *truth(Emitted value) {
        const compiler::TypeDescriptor descriptor = context.language().types.get(value.type);
        if (descriptor.kind == compiler::TypeKind::FloatingPoint)
          return builder.CreateFCmpONE(value.value, llvm::ConstantFP::get(type(value.type), 0.0));
        if (descriptor.kind == compiler::TypeKind::Pointer || descriptor.kind == compiler::TypeKind::Function)
          return builder.CreateICmpNE(value.value,
                                      llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(llvmContext)));
        if (descriptor.kind == compiler::TypeKind::Integer)
          return builder.CreateICmpNE(value.value, llvm::ConstantInt::get(type(value.type), 0));
        fail({}, 0, "LLVM condition requires an integer, pointer, or floating value");
      }

      void statements(const std::vector<Statement> &source, bool nested = false) {
        const std::size_t deferDepth = defers.size();
        if (nested) scopes.emplace_back();
        for (const Statement &statement : source) {
          if (builder.GetInsertBlock()->getTerminator()) break;
          generate(statement);
        }
        if (!builder.GetInsertBlock()->getTerminator()) emitDefers(deferDepth);
        defers.resize(deferDepth);
        if (nested) scopes.pop_back();
      }

      void emitDefers(std::size_t depth) {
        for (std::size_t index = defers.size(); index-- > depth;) expression(*defers[index]);
      }

      std::string syntaxName(lexicon::Phrase phrase, std::initializer_list<std::string_view> recognized) const {
        for (std::size_t depth = 0; !phrase.isNull() && depth < 64; ++depth) {
          const std::string key = phrase.getKey();
          if (std::find(recognized.begin(), recognized.end(), std::string_view(key)) != recognized.end()) return key;
          if (!phrase.containsPrototype()) break;
          lexicon::Phrase prototype = phrase.getPrototype();
          if (prototype.isNull() || prototype.getAddress() == phrase.getAddress()) break;
          phrase = prototype;
        }
        return {};
      }

      std::string behaviorAction(lexicon::Phrase syntax, std::string_view behavior) const {
        lexicon::Phrase implementation = LanguageGrammar::behavior(syntax, behavior);
        if (implementation.isNull() || !implementation.containsAction()) return {};
        return context.actions().name(implementation.getAction());
      }

      std::string operatorSymbol(const Expression &value) const {
        const std::string action = behaviorAction(value.syntax, StatementEmitName);
        if (action == "fn.operator.emit-positive" || action == "fn.operator.emit-add") return "+";
        if (action == "fn.operator.emit-negative" || action == "fn.operator.emit-subtract") return "-";
        if (action == "fn.operator.emit-not") return "!";
        if (action == "fn.operator.emit-multiply") return "*";
        if (action == "fn.operator.emit-divide") return "/";
        if (action == "fn.operator.emit-modulo") return "%";
        if (action == "fn.operator.emit-equal") return "==";
        if (action == "fn.operator.emit-not-equal") return "!=";
        if (action == "fn.operator.emit-less") return "<";
        if (action == "fn.operator.emit-less-equal") return "<=";
        if (action == "fn.operator.emit-greater") return ">";
        if (action == "fn.operator.emit-greater-equal") return ">=";
        if (action == "fn.operator.emit-and") return "&&";
        if (action == "fn.operator.emit-or") return "||";
        if (action == "fn.intrinsic.compile") return syntaxName(value.syntax, {"&", "*", "cast"});
        return {};
      }

      void generate(const Statement &statement) {
        const std::string action = behaviorAction(statement.syntax, StatementEmitName);
        if (action == "fn.statement.emit-variable") return variable(statement);
        if (action == "fn.statement.emit-assignment") return assignment(statement);
        if (action == "fn.statement.emit-conditional") return conditional(statement);
        if (action == "fn.statement.emit-loop") return loop(statement);
        if (action == "fn.statement.emit-break") return breakLoop(statement);
        if (action == "fn.statement.emit-continue") return continueLoop(statement);
        if (action == "fn.statement.emit-return") return returnValue(statement);
        if (action == "fn.statement.emit-defer") {
          defers.push_back(statement.expression.get());
          return;
        }
        if (action == "fn.statement.emit-expression") {
          expression(*statement.expression);
          return;
        }
        lexicon::Phrase syntax = statement.syntax;
        fail({}, statement.offset, "statement syntax '" + syntax.getKeyEscaped() + "' has no LLVM emitter");
      }

      void variable(const Statement &statement) {
        if (scopes.back().contains(statement.name))
          fail({}, statement.offset, "duplicate local variable '" + statement.name + "'");
        Emitted initial = expression(*statement.expression, statement.declaredType);
        const compiler::TypeId valueType =
            statement.declaredType == compiler::InvalidType ? initial.type : statement.declaredType;
        initial = coerce(initial, valueType, statement.offset);
        const compiler::TypeDescriptor descriptor = context.language().types.get(valueType);
        if (descriptor.kind == compiler::TypeKind::Structure || descriptor.kind == compiler::TypeKind::Array)
          fail({}, statement.offset, "LLVM aggregate locals must be held through pointers");
        LlvmLocal local{allocate(valueType, statement.name), valueType, statement.mutableValue};
        builder.CreateStore(initial.value, local.address);
        scopes.back().emplace(statement.name, local);
      }

      void assignment(const Statement &statement) {
        auto [address, targetType] = lvalue(*statement.target, true);
        Emitted right = coerce(expression(*statement.expression, targetType), targetType, statement.offset);
        const std::string action = behaviorAction(statement.operationSyntax, AssignmentEmitName);
        const std::string operation = action == "fn.assignment.emit-move"       ? "="
                                      : action == "fn.assignment.emit-add"      ? "+="
                                      : action == "fn.assignment.emit-subtract" ? "-="
                                      : action == "fn.assignment.emit-multiply" ? "*="
                                      : action == "fn.assignment.emit-divide"   ? "/="
                                      : action == "fn.assignment.emit-modulo"   ? "%="
                                                                                : "";
        if (operation.empty())
          fail({}, statement.offset, "assignment operator '" + statement.operation + "' has no LLVM emitter");
        llvm::Value *result = right.value;
        if (operation != "=") {
          Emitted left{builder.CreateLoad(type(targetType), address), targetType};
          result = binaryValue(operation.substr(0, 1), left, right, statement.offset).value;
        }
        builder.CreateStore(result, address);
      }

      void conditional(const Statement &statement) {
        llvm::Function *owner = builder.GetInsertBlock()->getParent();
        llvm::BasicBlock *accepted = llvm::BasicBlock::Create(llvmContext, "if.then", owner);
        llvm::BasicBlock *rejected = llvm::BasicBlock::Create(llvmContext, "if.else", owner);
        llvm::BasicBlock *end = llvm::BasicBlock::Create(llvmContext, "if.end", owner);
        builder.CreateCondBr(truth(expression(*statement.expression)), accepted, rejected);
        builder.SetInsertPoint(accepted);
        statements(statement.accepted, true);
        if (!builder.GetInsertBlock()->getTerminator()) builder.CreateBr(end);
        builder.SetInsertPoint(rejected);
        statements(statement.rejected, true);
        if (!builder.GetInsertBlock()->getTerminator()) builder.CreateBr(end);
        builder.SetInsertPoint(end);
      }

      void loop(const Statement &statement) {
        llvm::Function *owner = builder.GetInsertBlock()->getParent();
        llvm::BasicBlock *condition = llvm::BasicBlock::Create(llvmContext, "while.cond", owner);
        llvm::BasicBlock *body = llvm::BasicBlock::Create(llvmContext, "while.body", owner);
        llvm::BasicBlock *end = llvm::BasicBlock::Create(llvmContext, "while.end", owner);
        builder.CreateBr(condition);
        builder.SetInsertPoint(condition);
        builder.CreateCondBr(truth(expression(*statement.expression)), body, end);
        loops.push_back({condition, end, defers.size()});
        builder.SetInsertPoint(body);
        statements(statement.accepted, true);
        if (!builder.GetInsertBlock()->getTerminator()) builder.CreateBr(condition);
        loops.pop_back();
        builder.SetInsertPoint(end);
      }

      void breakLoop(const Statement &statement) {
        if (loops.empty()) fail({}, statement.offset, "break requires an enclosing while loop");
        emitDefers(loops.back().deferDepth);
        builder.CreateBr(loops.back().end);
      }

      void continueLoop(const Statement &statement) {
        if (loops.empty()) fail({}, statement.offset, "continue requires an enclosing while loop");
        emitDefers(loops.back().deferDepth);
        builder.CreateBr(loops.back().condition);
      }

      void returnValue(const Statement &statement) {
        if (statement.expression) {
          Emitted result = coerce(expression(*statement.expression, signature.function.resultType),
                                  signature.function.resultType, statement.offset);
          emitDefers(0);
          builder.CreateRet(result.value);
        } else {
          if (context.language().types.get(signature.function.resultType).kind != compiler::TypeKind::Void)
            fail({}, statement.offset, "non-void fn requires a return value");
          emitDefers(0);
          builder.CreateRetVoid();
        }
      }

      Emitted expression(const Expression &value, compiler::TypeId expected = compiler::InvalidType) {
        switch (value.kind) {
        case Expression::Kind::Integer: return coerce(integer(value), expected, value.offset);
        case Expression::Kind::Real: return coerce(real(value), expected, value.offset);
        case Expression::Kind::String:
          return coerce({builder.CreateGlobalStringPtr(value.text), bytePointer}, expected, value.offset);
        case Expression::Kind::BitString: return coerce(bitString(value), expected, value.offset);
        case Expression::Kind::FunctionLiteral: return coerce(functionLiteral(value, expected), expected, value.offset);
        case Expression::Kind::Variable: return coerce(variableValue(value, expected), expected, value.offset);
        case Expression::Kind::Index:
        case Expression::Kind::Member: {
          auto [address, valueType] = lvalue(value, false);
          return coerce({builder.CreateLoad(type(valueType), address), valueType}, expected, value.offset);
        }
        case Expression::Kind::Call: return coerce(call(value), expected, value.offset);
        case Expression::Kind::MethodCall: return coerce(methodCall(value), expected, value.offset);
        case Expression::Kind::Unary: return coerce(unary(value, expected), expected, value.offset);
        case Expression::Kind::Binary: return coerce(binary(value), expected, value.offset);
        case Expression::Kind::Block:
          return coerce(expressionBlock(value.body->accepted, value.offset), expected, value.offset);
        case Expression::Kind::Conditional: return coerce(conditionalExpression(value), expected, value.offset);
        case Expression::Kind::Propagate: return coerce(propagate(value), expected, value.offset);
        }
        fail({}, value.offset, "invalid LLVM fn expression");
      }

      Emitted integer(const Expression &value) {
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
        return {llvm::ConstantInt::get(type(integerType), number), integerType};
      }

      Emitted real(const Expression &value) {
        std::string text = value.text;
        text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
        double number = 0;
        const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), number);
        if (text.empty() || error != std::errc() || end != text.data() + text.size())
          fail({}, value.offset, "invalid real literal");
        return {llvm::ConstantFP::get(type(realType), number), realType};
      }

      Emitted bitString(const Expression &value) {
        std::vector<std::uint8_t> data((value.text.size() + 7) / 8, 0);
        for (std::size_t bit = 0; bit < value.text.size(); ++bit)
          if (value.text[bit] == '1') data[bit / 8] |= 1u << (7 - bit % 8);
        llvm::Constant *bytes = llvm::ConstantDataArray::get(llvmContext, data);
        auto *storage =
            new llvm::GlobalVariable(module, bytes->getType(), true, llvm::GlobalValue::PrivateLinkage, bytes, ".bits");
        llvm::StructType *descriptorType = llvm::StructType::get(
            llvmContext, {llvm::PointerType::getUnqual(llvmContext), llvm::Type::getInt64Ty(llvmContext)});
        llvm::Constant *descriptor = llvm::ConstantStruct::get(
            descriptorType, {storage, llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), value.text.size())});
        auto *global = new llvm::GlobalVariable(module, descriptorType, true, llvm::GlobalValue::PrivateLinkage,
                                                descriptor, ".bitstring");
        return {global, bitStringPointer};
      }

      Emitted functionLiteral(const Expression &value, compiler::TypeId expected) {
        const std::optional<compiler::TypedFunction> target = context.language().findFunction(value.text);
        if (!target) fail({}, value.offset, "inline fn implementation is unavailable: '" + value.text + "'");
        const compiler::TypeId functionId = context.language().functionType(*target);
        if (expected != phraseActionPointer) return {declare(*target), functionId};
        llvm::Constant *name = builder.CreateGlobalString(value.text, ".action.symbol");
        llvm::StructType *descriptorType = llvm::StructType::get(
            llvmContext, {llvm::PointerType::getUnqual(llvmContext), llvm::Type::getInt64Ty(llvmContext)});
        llvm::Constant *descriptor = llvm::ConstantStruct::get(
            descriptorType, {name, llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), value.text.size())});
        auto *global = new llvm::GlobalVariable(module, descriptorType, true, llvm::GlobalValue::PrivateLinkage,
                                                descriptor, ".action");
        return {global, phraseActionPointer};
      }

      Emitted variableValue(const Expression &value, compiler::TypeId expected) {
        if (const LlvmLocal *local = findLocalOptional(value.text))
          return {builder.CreateLoad(type(local->type), local->address), local->type};
        const std::optional<compiler::TypedFunction> target = functionReference(value.text, expected);
        if (!target) fail({}, value.offset, "unknown fn local or typed function '" + value.text + "'");
        return {declare(*target), context.language().functionType(*target)};
      }

      Emitted unary(const Expression &value, compiler::TypeId expected) {
        const std::string operation = operatorSymbol(value);
        if (value.declaredType != compiler::InvalidType || operation == "cast")
          return coerce(expression(*value.children[0]), value.declaredType, value.offset, true);
        if (operation == "&") {
          if (value.children[0]->kind == Expression::Kind::Variable &&
              findLocalOptional(value.children[0]->text) == nullptr) {
            const std::optional<compiler::TypedFunction> target = functionReference(value.children[0]->text, expected);
            if (!target) fail({}, value.offset, "address target is neither a local nor a typed function");
            return {declare(*target), context.language().functionType(*target)};
          }
          auto [address, valueType] = lvalue(*value.children[0], false);
          return {address, context.language().types.pointerTo(valueType)};
        }
        if (operation == "*") {
          Emitted pointer = expression(*value.children[0]);
          const compiler::TypeDescriptor descriptor = context.language().types.get(pointer.type);
          if (descriptor.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "dereference requires a pointer");
          return {builder.CreateLoad(type(descriptor.element), pointer.value), descriptor.element};
        }
        Emitted operand = expression(*value.children[0]);
        const compiler::TypeDescriptor descriptor = context.language().types.get(operand.type);
        if (operation == "+") return operand;
        if (operation == "-")
          return {descriptor.kind == compiler::TypeKind::FloatingPoint ? builder.CreateFNeg(operand.value)
                                                                       : builder.CreateNeg(operand.value),
                  operand.type};
        if (operation == "!")
          return {builder.CreateZExt(builder.CreateNot(truth(operand)), type(integerType)), integerType};
        fail({}, value.offset, "operator '" + value.text + "' has no LLVM emitter");
      }

      Emitted binary(const Expression &value) {
        const std::string operation = operatorSymbol(value);
        if (operation == "&&" || operation == "||") return logical(value, operation == "&&");
        Emitted left = expression(*value.children[0]);
        Emitted right = coerce(expression(*value.children[1], left.type), left.type, value.offset);
        return binaryValue(operation, left, right, value.offset);
      }

      Emitted binaryValue(std::string_view operation, Emitted left, Emitted right, std::size_t offset) {
        const compiler::TypeDescriptor descriptor = context.language().types.get(left.type);
        const bool floating = descriptor.kind == compiler::TypeKind::FloatingPoint;
        llvm::Value *result = nullptr;
        if (operation == "+")
          result = floating ? builder.CreateFAdd(left.value, right.value) : builder.CreateAdd(left.value, right.value);
        else if (operation == "-")
          result = floating ? builder.CreateFSub(left.value, right.value) : builder.CreateSub(left.value, right.value);
        else if (operation == "*")
          result = floating ? builder.CreateFMul(left.value, right.value) : builder.CreateMul(left.value, right.value);
        else if (operation == "/")
          result = floating              ? builder.CreateFDiv(left.value, right.value)
                   : descriptor.isSigned ? builder.CreateSDiv(left.value, right.value)
                                         : builder.CreateUDiv(left.value, right.value);
        else if (operation == "%") {
          if (floating) fail({}, offset, "floating remainder has no LLVM emitter");
          result = descriptor.isSigned ? builder.CreateSRem(left.value, right.value)
                                       : builder.CreateURem(left.value, right.value);
        } else {
          llvm::Value *comparison = nullptr;
          if (floating) {
            if (operation == "==")
              comparison = builder.CreateFCmpOEQ(left.value, right.value);
            else if (operation == "!=")
              comparison = builder.CreateFCmpONE(left.value, right.value);
            else if (operation == "<")
              comparison = builder.CreateFCmpOLT(left.value, right.value);
            else if (operation == "<=")
              comparison = builder.CreateFCmpOLE(left.value, right.value);
            else if (operation == ">")
              comparison = builder.CreateFCmpOGT(left.value, right.value);
            else if (operation == ">=")
              comparison = builder.CreateFCmpOGE(left.value, right.value);
          } else {
            if (operation == "==")
              comparison = builder.CreateICmpEQ(left.value, right.value);
            else if (operation == "!=")
              comparison = builder.CreateICmpNE(left.value, right.value);
            else if (operation == "<")
              comparison = descriptor.isSigned ? builder.CreateICmpSLT(left.value, right.value)
                                               : builder.CreateICmpULT(left.value, right.value);
            else if (operation == "<=")
              comparison = descriptor.isSigned ? builder.CreateICmpSLE(left.value, right.value)
                                               : builder.CreateICmpULE(left.value, right.value);
            else if (operation == ">")
              comparison = descriptor.isSigned ? builder.CreateICmpSGT(left.value, right.value)
                                               : builder.CreateICmpUGT(left.value, right.value);
            else if (operation == ">=")
              comparison = descriptor.isSigned ? builder.CreateICmpSGE(left.value, right.value)
                                               : builder.CreateICmpUGE(left.value, right.value);
          }
          if (comparison) return {builder.CreateZExt(comparison, type(integerType)), integerType};
        }
        if (!result) fail({}, offset, "operator '" + std::string(operation) + "' has no LLVM emitter");
        return {result, left.type};
      }

      Emitted logical(const Expression &value, bool conjunction) {
        llvm::Function *owner = builder.GetInsertBlock()->getParent();
        llvm::Value *left = truth(expression(*value.children[0]));
        llvm::BasicBlock *origin = builder.GetInsertBlock();
        llvm::BasicBlock *rightBlock = llvm::BasicBlock::Create(llvmContext, "logic.rhs", owner);
        llvm::BasicBlock *end = llvm::BasicBlock::Create(llvmContext, "logic.end", owner);
        if (conjunction)
          builder.CreateCondBr(left, rightBlock, end);
        else
          builder.CreateCondBr(left, end, rightBlock);
        builder.SetInsertPoint(rightBlock);
        llvm::Value *right = truth(expression(*value.children[1]));
        builder.CreateBr(end);
        rightBlock = builder.GetInsertBlock();
        builder.SetInsertPoint(end);
        llvm::PHINode *phi = builder.CreatePHI(llvm::Type::getInt1Ty(llvmContext), 2);
        phi->addIncoming(llvm::ConstantInt::getBool(llvmContext, !conjunction), origin);
        phi->addIncoming(right, rightBlock);
        return {builder.CreateZExt(phi, type(integerType)), integerType};
      }

      Emitted expressionBlock(const std::vector<Statement> &source, std::size_t offset) {
        if (source.empty() || !source.back().expression) fail({}, offset, "a value block must end with an expression");
        const std::size_t deferDepth = defers.size();
        scopes.emplace_back();
        for (std::size_t index = 0; index + 1 < source.size(); ++index) generate(source[index]);
        Emitted result = expression(*source.back().expression);
        emitDefers(deferDepth);
        defers.resize(deferDepth);
        scopes.pop_back();
        return result;
      }

      Emitted conditionalExpression(const Expression &value) {
        llvm::Function *owner = builder.GetInsertBlock()->getParent();
        llvm::BasicBlock *accepted = llvm::BasicBlock::Create(llvmContext, "value.then", owner);
        llvm::BasicBlock *rejected = llvm::BasicBlock::Create(llvmContext, "value.else", owner);
        llvm::BasicBlock *end = llvm::BasicBlock::Create(llvmContext, "value.end", owner);
        builder.CreateCondBr(truth(expression(*value.body->condition)), accepted, rejected);
        builder.SetInsertPoint(accepted);
        Emitted left = expressionBlock(value.body->accepted, value.offset);
        builder.CreateBr(end);
        accepted = builder.GetInsertBlock();
        builder.SetInsertPoint(rejected);
        Emitted right = coerce(expressionBlock(value.body->rejected, value.offset), left.type, value.offset);
        builder.CreateBr(end);
        rejected = builder.GetInsertBlock();
        builder.SetInsertPoint(end);
        llvm::PHINode *phi = builder.CreatePHI(type(left.type), 2);
        phi->addIncoming(left.value, accepted);
        phi->addIncoming(right.value, rejected);
        return {phi, left.type};
      }

      Emitted propagate(const Expression &value) {
        Emitted result = expression(*value.children[0]);
        const compiler::TypeDescriptor descriptor = context.language().types.get(result.type);
        const compiler::TypeDescriptor returnType = context.language().types.get(signature.function.resultType);
        if (descriptor.kind != compiler::TypeKind::Pointer || returnType.kind != compiler::TypeKind::Pointer)
          fail({}, value.offset, "'?' propagates null pointers from pointer-returning functions");
        llvm::Function *owner = builder.GetInsertBlock()->getParent();
        llvm::BasicBlock *missing = llvm::BasicBlock::Create(llvmContext, "propagate.null", owner);
        llvm::BasicBlock *present = llvm::BasicBlock::Create(llvmContext, "propagate.value", owner);
        builder.CreateCondBr(truth(result), present, missing);
        builder.SetInsertPoint(missing);
        emitDefers(0);
        builder.CreateRet(llvm::ConstantPointerNull::get(llvm::PointerType::getUnqual(llvmContext)));
        builder.SetInsertPoint(present);
        return result;
      }

      std::pair<llvm::Value *, compiler::TypeId> lvalue(const Expression &value, bool requireMutable) {
        if (value.kind == Expression::Kind::Variable) {
          const LlvmLocal &local = findLocal(value.text, value.offset);
          if (requireMutable && !local.mutableValue)
            fail({}, value.offset, "cannot assign to const local '" + value.text + "'");
          return {local.address, local.type};
        }
        if (value.kind == Expression::Kind::Unary && operatorSymbol(value) == "*") {
          Emitted pointer = expression(*value.children[0]);
          const compiler::TypeDescriptor descriptor = context.language().types.get(pointer.type);
          if (descriptor.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "dereference requires a pointer");
          return {pointer.value, descriptor.element};
        }
        if (value.kind == Expression::Kind::Index) {
          Emitted pointer = expression(*value.children[0]);
          const compiler::TypeDescriptor descriptor = context.language().types.get(pointer.type);
          if (descriptor.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "indexing requires a pointer");
          Emitted index = expression(*value.children[1]);
          if (context.language().types.get(index.type).kind != compiler::TypeKind::Integer)
            fail({}, value.offset, "pointer index must be an integer");
          index = coerce(index, integerType, value.offset);
          llvm::Value *address = builder.CreateGEP(type(descriptor.element), pointer.value, index.value);
          return {address, descriptor.element};
        }
        if (value.kind == Expression::Kind::Member) {
          compiler::TypeDescriptor owner = context.language().types.get(infer(*value.children[0]));
          llvm::Value *base = nullptr;
          if (owner.kind == compiler::TypeKind::Pointer) {
            base = expression(*value.children[0]).value;
            owner = context.language().types.get(owner.element);
          } else {
            base = lvalue(*value.children[0], requireMutable).first;
          }
          if (owner.kind != compiler::TypeKind::Structure)
            fail({}, value.offset, "member access requires a record or pointer to a record");
          const auto field =
              std::find_if(owner.fields.begin(), owner.fields.end(),
                           [&](const compiler::TypeField &candidate) { return candidate.name == value.text; });
          if (field == owner.fields.end())
            fail({}, value.offset, "record '" + owner.name + "' has no field '" + value.text + "'");
          llvm::Value *bytes =
              builder.CreateGEP(llvm::Type::getInt8Ty(llvmContext), base,
                                llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), field->offset));
          return {bytes, field->type};
        }
        fail({}, value.offset, "assignment target is not writable");
      }

      compiler::TypeId infer(const Expression &value, compiler::TypeId expected = compiler::InvalidType) {
        switch (value.kind) {
        case Expression::Kind::Integer: return integerType;
        case Expression::Kind::Real: return realType;
        case Expression::Kind::String: return bytePointer;
        case Expression::Kind::BitString: return bitStringPointer;
        case Expression::Kind::FunctionLiteral: {
          const auto function = context.language().findFunction(value.text);
          if (!function) fail({}, value.offset, "inline fn implementation is unavailable: '" + value.text + "'");
          return expected == phraseActionPointer ? phraseActionPointer : context.language().functionType(*function);
        }
        case Expression::Kind::Variable:
          if (const LlvmLocal *local = findLocalOptional(value.text)) return local->type;
          if (const auto function = functionReference(value.text, expected))
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
        case Expression::Kind::Call:
          if (!functions(value.text).empty()) return resolveDirect(value).resultType;
          {
            const compiler::TypeDescriptor callable =
                context.language().types.get(findLocal(value.text, value.offset).type);
            if (callable.kind == compiler::TypeKind::Function) return callable.resultType;
            if (callable.kind == compiler::TypeKind::Pointer) return integerType;
            fail({}, value.offset, "indirect fn call requires a function or pointer local");
          }
        case Expression::Kind::MethodCall: return methodFunction(value).resultType;
        case Expression::Kind::Unary: {
          const std::string operation = operatorSymbol(value);
          if (value.declaredType != compiler::InvalidType || operation == "cast") return value.declaredType;
          if (operation == "!") return integerType;
          if (operation == "&") return context.language().types.pointerTo(infer(*value.children[0], expected));
          if (operation == "*") {
            const compiler::TypeDescriptor pointer = context.language().types.get(infer(*value.children[0]));
            if (pointer.kind != compiler::TypeKind::Pointer) fail({}, value.offset, "dereference requires a pointer");
            return pointer.element;
          }
          return infer(*value.children[0]);
        }
        case Expression::Kind::Binary: {
          const std::string operation = operatorSymbol(value);
          const bool comparison = operation == "==" || operation == "!=" || operation == "<" || operation == "<=" ||
                                  operation == ">" || operation == ">=" || operation == "&&" || operation == "||";
          return comparison ? integerType : infer(*value.children[0]);
        }
        case Expression::Kind::Propagate: return infer(*value.children[0]);
        case Expression::Kind::Block:
        case Expression::Kind::Conditional:
          fail({}, value.offset, "value blocks cannot be inferred before LLVM emission");
        }
        fail({}, value.offset, "invalid LLVM fn expression type");
      }

      std::vector<compiler::TypedFunction> functions(std::string_view name) const {
        return context.language().findFunctions(name, signature.scope);
      }

      std::optional<compiler::TypedFunction> functionReference(const std::string &name, compiler::TypeId expected) {
        std::vector<compiler::TypedFunction> candidates = functions(name);
        if (candidates.empty()) {
          const auto physical = context.language().findFunction(name);
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
        return candidates.size() == 1 ? std::optional<compiler::TypedFunction>(candidates.front()) : std::nullopt;
      }

      std::optional<compiler::TypeId> contextualArgumentType(const Expression &value, compiler::TypeId expected) {
        if (value.kind == Expression::Kind::Variable && findLocalOptional(value.text) == nullptr &&
            !functions(value.text).empty()) {
          const auto function = functionReference(value.text, expected);
          if (!function) return std::nullopt;
          return context.language().functionType(*function);
        }
        return infer(value, expected);
      }

      compiler::TypedFunction resolveDirect(const Expression &value, const std::string &name = {}) {
        const std::string callName = name.empty() ? value.text : name;
        const std::vector<compiler::TypedFunction> candidates = functions(callName);
        const compiler::TypedFunction *best = nullptr;
        std::size_t bestCost = std::numeric_limits<std::size_t>::max();
        bool ambiguous = false;
        for (const compiler::TypedFunction &candidate : candidates) {
          if ((!candidate.signature.variadic && candidate.parameterTypes.size() != value.children.size()) ||
              (candidate.signature.variadic && candidate.parameterTypes.size() > value.children.size()))
            continue;
          std::size_t cost = candidate.signature.variadic ? 2 : 0;
          bool valid = true;
          for (std::size_t index = 0; index < value.children.size(); ++index) {
            const compiler::TypeId wanted =
                index < candidate.parameterTypes.size() ? candidate.parameterTypes[index] : compiler::InvalidType;
            const auto actual = contextualArgumentType(*value.children[index], wanted);
            if (!actual) {
              valid = false;
              break;
            }
            if (wanted == compiler::InvalidType) continue;
            const auto conversion = context.language().conversionCost(wanted, *actual);
            if (!conversion) {
              valid = false;
              break;
            }
            cost += *conversion;
          }
          if (!valid) continue;
          if (cost < bestCost) {
            best = &candidate;
            bestCost = cost;
            ambiguous = false;
          } else if (cost == bestCost)
            ambiguous = true;
        }
        if (ambiguous) fail({}, value.offset, "ambiguous typed function overload: '" + callName + "'");
        if (best == nullptr) fail({}, value.offset, "no matching overload for '" + callName + "'");
        return *best;
      }

      llvm::Function *declare(const compiler::TypedFunction &target) {
        llvm::Function *declared = module.getFunction(target.signature.symbol);
        if (!declared)
          declared = llvm::Function::Create(functionType(target), llvm::GlobalValue::ExternalLinkage,
                                            target.signature.symbol, module);
        if (target.signature.symbol != signature.function.signature.symbol) imports.insert(target.signature.symbol);
        return declared;
      }

      Emitted call(const Expression &value) {
        if (!functions(value.text).empty()) return callResolved(value, resolveDirect(value), nullptr);
        const LlvmLocal &local = findLocal(value.text, value.offset);
        return callResolved(value, std::nullopt, &local);
      }

      Emitted methodCall(const Expression &value) {
        return callResolved(value, methodFunction(value), nullptr);
      }

      compiler::TypedFunction methodFunction(const Expression &value) {
        compiler::TypeDescriptor owner = context.language().types.get(infer(*value.children.front()));
        if (owner.kind == compiler::TypeKind::Pointer) owner = context.language().types.get(owner.element);
        if (owner.kind != compiler::TypeKind::Structure)
          fail({}, value.offset, "method call requires a record or pointer to a record");
        return resolveDirect(value, owner.name + ":" + value.text);
      }

      Emitted callResolved(const Expression &value, std::optional<compiler::TypedFunction> direct,
                           const LlvmLocal *indirect) {
        compiler::TypedFunction callable;
        llvm::Value *target = nullptr;
        if (direct) {
          callable = *direct;
          target = declare(callable);
        } else {
          const compiler::TypeDescriptor descriptor = context.language().types.get(indirect->type);
          if (descriptor.kind == compiler::TypeKind::Function) {
            callable.signature = context.language().functionSignature(indirect->type);
            callable.parameterTypes = descriptor.parameterTypes;
            callable.resultType = descriptor.resultType;
          } else if (descriptor.kind == compiler::TypeKind::Pointer) {
            callable.resultType = integerType;
            callable.parameterTypes.reserve(value.children.size());
            for (const std::unique_ptr<Expression> &argument : value.children) {
              const compiler::TypeId argumentType = infer(*argument);
              const compiler::TypeDescriptor argumentDescriptor = context.language().types.get(argumentType);
              if (argumentDescriptor.kind == compiler::TypeKind::Structure ||
                  argumentDescriptor.kind == compiler::TypeKind::Array ||
                  argumentDescriptor.size > sizeof(std::uint64_t))
                fail({}, value.offset, "raw function pointer calls require scalar arguments up to 64 bits");
              callable.parameterTypes.push_back(argumentType);
            }
          } else {
            fail({}, value.offset, "indirect LLVM fn call requires a function or pointer local");
          }
          target = builder.CreateLoad(type(indirect->type), indirect->address);
        }
        std::vector<llvm::Value *> arguments;
        arguments.reserve(value.children.size());
        for (std::size_t index = 0; index < value.children.size(); ++index) {
          const compiler::TypeId wanted =
              index < callable.parameterTypes.size() ? callable.parameterTypes[index] : compiler::InvalidType;
          Emitted argument = expression(*value.children[index], wanted);
          if (wanted != compiler::InvalidType) argument = coerce(argument, wanted, value.offset);
          arguments.push_back(argument.value);
        }
        llvm::CallInst *result = builder.CreateCall(functionType(callable), target, arguments);
        return {result, callable.resultType};
      }

      LlvmLocal *findLocalOptional(const std::string &name) {
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
          auto found = scope->find(name);
          if (found != scope->end()) return &found->second;
        }
        return nullptr;
      }
      const LlvmLocal *findLocalOptional(const std::string &name) const {
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
          auto found = scope->find(name);
          if (found != scope->end()) return &found->second;
        }
        return nullptr;
      }
      const LlvmLocal &findLocal(const std::string &name, std::size_t offset) const {
        const LlvmLocal *local = findLocalOptional(name);
        if (!local) fail({}, offset, "unknown fn local '" + name + "'");
        return *local;
      }

      [[noreturn]] void incompatible(compiler::TypeId expected, compiler::TypeId actual, std::size_t offset) const {
        fail({}, offset,
             "LLVM expression type '" + context.language().types.get(actual).name + "' is incompatible with '" +
                 context.language().types.get(expected).name + "'");
      }

      context::Context &context;
      const FunctionDefinition &signature;
      llvm::LLVMContext llvmContext;
      llvm::Module module;
      llvm::IRBuilder<> builder;
      std::unique_ptr<llvm::TargetMachine> machine;
      llvm::Function *function = nullptr;
      compiler::TypeId integerType;
      compiler::TypeId realType;
      compiler::TypeId bytePointer;
      compiler::TypeId bitStringPointer;
      compiler::TypeId phraseActionPointer;
      std::string executableEntry;
      std::string triple;
      std::string cpu;
      std::string features;
      std::vector<std::unordered_map<std::string, LlvmLocal>> scopes;
      std::vector<LlvmLoop> loops;
      std::vector<const Expression *> defers;
      std::unordered_set<std::string> imports;
    };
  } // namespace

  LlvmProgram generateLlvmProgram(context::Context &context, const FunctionDefinition &signature,
                                  const std::vector<Statement> &body, std::string_view executableEntry) {
    DiagnosticScope diagnostics(signature.sourceText,
                                {signature.sourcePath, signature.sourceLine, signature.sourceColumn});
    LlvmProgram result = LlvmGenerator(context, signature, executableEntry).generate(body);
    std::unordered_set<std::string> provided(result.providedSymbols.begin(), result.providedSymbols.end());
    std::unordered_set<std::string> imports(result.imports.begin(), result.imports.end());
    std::unordered_set<std::string> visited;
    const std::vector<std::string> excludedList = context.language().excludedModules();
    const std::unordered_set<std::string> excluded(excludedList.begin(), excludedList.end());
    const bool automatic = context.language().automaticModuleLinking();
    std::deque<std::string> pending;
    if (automatic)
      for (const std::string &symbol : result.imports) pending.push_back(symbol);
    for (const std::string &symbol : context.language().includedModules()) pending.push_back(symbol);
    const bool hostTarget = result.triple == llvm::Triple::normalize(llvm::sys::getDefaultTargetTriple());

    while (!pending.empty()) {
      std::string symbol = std::move(pending.front());
      pending.pop_front();
      if (!visited.insert(symbol).second || provided.contains(symbol) || excluded.contains(symbol)) continue;

      const std::optional<compiler::Module> storedModule = context.language().findModule(symbol);
      if (hostTarget && storedModule) {
        for (const compiler::Symbol &candidate : storedModule->symbols())
          if (candidate.imported && automatic) pending.push_back(candidate.name);
        continue;
      }

      const std::optional<compiler::FunctionSource> source = context.language().findFunctionSource(symbol);
      if (source) {
        const std::optional<compiler::TypedFunction> function = context.language().findFunction(symbol);
        if (!function || function->imported)
          fail({}, 0, "stored fn source has no matching definition: '" + symbol + "'");
        FunctionDefinition dependency;
        dependency.function = *function;
        dependency.names = source->parameterNames;
        dependency.scope = source->scope;
        dependency.sourcePath = source->path;
        dependency.sourceText = source->body;
        dependency.sourceLine = source->line;
        dependency.sourceColumn = source->column;
        const std::vector<Statement> statements =
            parseBody(context, source->body, source->scope, source->path, source->line, source->column);
        DiagnosticScope dependencyDiagnostics(source->body, {source->path, source->line, source->column});
        LlvmProgram artifact = LlvmGenerator(context, dependency, {}).generate(statements);
        provided.insert(symbol);
        result.providedSymbols.push_back(symbol);
        result.objects.push_back(std::move(artifact.objects.front()));
        for (const std::string &import : artifact.imports) {
          imports.insert(import);
          if (automatic) pending.push_back(import);
        }
        continue;
      }

      if (!automatic) continue;
      if (!storedModule) continue;
      for (const compiler::Symbol &candidate : storedModule->symbols())
        if (candidate.imported) pending.push_back(candidate.name);
    }

    result.imports.assign(imports.begin(), imports.end());
    std::sort(result.imports.begin(), result.imports.end());
    return result;
  }

  compiler::Module generateLlvmModule(context::Context &context, const FunctionDefinition &signature,
                                      const std::vector<Statement> &body) {
    DiagnosticScope diagnostics(signature.sourceText,
                                {signature.sourcePath, signature.sourceLine, signature.sourceColumn});
    LlvmProgram program =
        LlvmGenerator(context, signature, {}, llvm::sys::getDefaultTargetTriple(), "generic", {}).generate(body);
    if (program.objects.size() != 1) fail({}, 0, "LLVM JIT compilation produced an invalid object set");
    return compiler::ElfReader::read(program.objects.front(),
                                     "LLVM JIT object for '" + signature.function.signature.symbol + "'");
  }

  LlvmPhraseModule generateLlvmPhraseModule(context::Context &context, std::string_view symbol,
                                            std::span<const LlvmPhraseCall> calls) {
    if (symbol.empty()) fail({}, 0, "LLVM compiled phrase requires a symbol");
    static const bool initialized = [] {
      llvm::InitializeAllTargetInfos();
      llvm::InitializeAllTargets();
      llvm::InitializeAllTargetMCs();
      llvm::InitializeAllAsmParsers();
      llvm::InitializeAllAsmPrinters();
      return true;
    }();
    (void)initialized;

    llvm::LLVMContext llvmContext;
    llvm::Module module("recurloop-phrase", llvmContext);
    const std::string triple = llvm::Triple::normalize(llvm::sys::getDefaultTargetTriple());
    module.setTargetTriple(triple);
    std::string targetError;
    const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, targetError);
    if (target == nullptr) fail({}, 0, "LLVM host target is unavailable: " + targetError);
    llvm::TargetOptions options;
    const llvm::CodeGenOptLevel codegenLevel = RECURLOOP_LLVM_OPT_LEVEL == 0   ? llvm::CodeGenOptLevel::None
                                               : RECURLOOP_LLVM_OPT_LEVEL == 1 ? llvm::CodeGenOptLevel::Less
                                               : RECURLOOP_LLVM_OPT_LEVEL == 2 ? llvm::CodeGenOptLevel::Default
                                                                               : llvm::CodeGenOptLevel::Aggressive;
    std::unique_ptr<llvm::TargetMachine> machine(target->createTargetMachine(
        triple, "generic", {}, options, llvm::Reloc::PIC_, llvm::CodeModel::Small, codegenLevel));
    if (!machine)
      fail({}, 0, "LLVM could not create a target machine for compiled phrase '" + std::string(symbol) + "'");
    module.setDataLayout(machine->createDataLayout());

    std::function<llvm::Type *(compiler::TypeId)> type = [&](compiler::TypeId id) -> llvm::Type * {
      const compiler::TypeDescriptor descriptor = context.language().types.get(id);
      switch (descriptor.kind) {
      case compiler::TypeKind::Void: return llvm::Type::getVoidTy(llvmContext);
      case compiler::TypeKind::Integer:
        return llvm::IntegerType::get(llvmContext,
                                      static_cast<unsigned>(std::max<std::size_t>(1, descriptor.size * 8)));
      case compiler::TypeKind::FloatingPoint:
        return descriptor.size == sizeof(float) ? llvm::Type::getFloatTy(llvmContext)
                                                : llvm::Type::getDoubleTy(llvmContext);
      case compiler::TypeKind::Pointer:
      case compiler::TypeKind::Function: return llvm::PointerType::getUnqual(llvmContext);
      case compiler::TypeKind::Array: return llvm::ArrayType::get(type(descriptor.element), descriptor.elementCount);
      case compiler::TypeKind::Structure:
        return llvm::ArrayType::get(llvm::Type::getInt8Ty(llvmContext), descriptor.size);
      }
      fail({}, 0, "LLVM compiled phrase encountered an invalid type");
    };
    const auto functionType = [&](const compiler::TypedFunction &function) {
      std::vector<llvm::Type *> parameters;
      parameters.reserve(function.parameterTypes.size());
      for (compiler::TypeId parameter : function.parameterTypes) parameters.push_back(type(parameter));
      return llvm::FunctionType::get(type(function.resultType), parameters, function.signature.variadic);
    };
    const auto constant = [&](const compiler::TypedValue &value) -> llvm::Constant * {
      const compiler::TypeDescriptor descriptor = context.language().types.get(value.type());
      llvm::Type *output = type(value.type());
      switch (descriptor.kind) {
      case compiler::TypeKind::Integer:
        return llvm::ConstantInt::get(llvm::cast<llvm::IntegerType>(output), value.asUnsigned());
      case compiler::TypeKind::FloatingPoint: {
        llvm::IntegerType *bits = llvm::IntegerType::get(llvmContext, static_cast<unsigned>(descriptor.size * 8));
        return llvm::ConstantExpr::getBitCast(llvm::ConstantInt::get(bits, value.asUnsigned()), output);
      }
      case compiler::TypeKind::Pointer:
      case compiler::TypeKind::Function:
        return llvm::ConstantExpr::getIntToPtr(
            llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), value.asUnsigned()), output);
      default: fail({}, 0, "LLVM compiled phrase cannot lower an aggregate immediate argument");
      }
    };

    llvm::FunctionType *entryType = llvm::FunctionType::get(llvm::Type::getVoidTy(llvmContext), false);
    llvm::Function *entry = llvm::Function::Create(entryType, llvm::GlobalValue::ExternalLinkage, symbol, module);
    llvm::BasicBlock *block = llvm::BasicBlock::Create(llvmContext, "entry", entry);
    llvm::BasicBlock *exit = llvm::BasicBlock::Create(llvmContext, "exit", entry);
    llvm::IRBuilder<> builder(block);
    LlvmPhraseModule result;
    const auto runtimeImport = [&](const std::string &name, std::uintptr_t address) {
      const auto found = std::find_if(result.imports.begin(), result.imports.end(),
                                      [&](const LlvmRuntimeImport &item) { return item.name == name; });
      if (found != result.imports.end()) {
        if (found->address != address) fail({}, 0, "LLVM runtime import has conflicting addresses: '" + name + "'");
        return;
      }
      result.imports.push_back({name, address});
    };
    const auto addressSymbol = [&](const std::string &name, std::uintptr_t address) -> llvm::GlobalVariable * {
      runtimeImport(name, address);
      if (llvm::GlobalVariable *existing = module.getNamedGlobal(name)) return existing;
      return new llvm::GlobalVariable(module, llvm::Type::getInt8Ty(llvmContext), false,
                                      llvm::GlobalValue::ExternalLinkage, nullptr, name);
    };

    for (std::size_t index = 0; index < calls.size(); ++index) {
      const LlvmPhraseCall &call = calls[index];
      if (call.nativeAbi) {
        const std::string targetName =
            call.directEntry == 0 ? call.symbol : "__recurloop_direct_" + std::to_string(index);
        if (call.directEntry != 0) runtimeImport(targetName, call.directEntry);
        llvm::FunctionType *targetType = call.function
                                             ? functionType(*call.function)
                                             : llvm::FunctionType::get(llvm::Type::getVoidTy(llvmContext), false);
        llvm::FunctionCallee targetFunction = module.getOrInsertFunction(targetName, targetType);
        std::vector<llvm::Value *> arguments;
        arguments.reserve(call.arguments.size());
        for (const compiler::TypedValue &argument : call.arguments) arguments.push_back(constant(argument));
        builder.CreateCall(targetType, targetFunction.getCallee(), arguments);
        continue;
      }

      const std::string contextName = "recurloop.context";
      const std::string phraseName = "recurloop.phrase." + std::to_string(index);
      const std::string trampolineName = "recurloop.invoke";
      llvm::GlobalVariable *contextAddress = addressSymbol(contextName, reinterpret_cast<std::uintptr_t>(&context));
      llvm::GlobalVariable *phraseAddress = addressSymbol(phraseName, call.phraseAddress);
      runtimeImport(trampolineName, call.trampoline);
      llvm::FunctionType *trampolineType =
          llvm::FunctionType::get(llvm::Type::getInt32Ty(llvmContext),
                                  {llvm::PointerType::getUnqual(llvmContext), llvm::Type::getInt64Ty(llvmContext),
                                   llvm::Type::getInt64Ty(llvmContext), llvm::Type::getInt64Ty(llvmContext)},
                                  false);
      llvm::FunctionCallee trampoline = module.getOrInsertFunction(trampolineName, trampolineType);
      llvm::Value *status = builder.CreateCall(
          trampolineType, trampoline.getCallee(),
          {contextAddress, builder.CreatePtrToInt(phraseAddress, llvm::Type::getInt64Ty(llvmContext)),
           llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), call.line),
           llvm::ConstantInt::get(llvm::Type::getInt64Ty(llvmContext), call.column)});
      llvm::BasicBlock *next = llvm::BasicBlock::Create(llvmContext, "next", entry);
      builder.CreateCondBr(builder.CreateICmpEQ(status, llvm::ConstantInt::get(status->getType(), 0)), next, exit);
      builder.SetInsertPoint(next);
    }
    builder.CreateBr(exit);
    builder.SetInsertPoint(exit);
    builder.CreateRetVoid();

    std::string verification;
    llvm::raw_string_ostream verificationStream(verification);
    if (llvm::verifyModule(module, &verificationStream))
      fail({}, 0, "LLVM generated invalid compiled phrase IR: " + verificationStream.str());
    llvm::PassBuilder passes(machine.get());
    llvm::LoopAnalysisManager loops;
    llvm::FunctionAnalysisManager functions;
    llvm::CGSCCAnalysisManager callGraph;
    llvm::ModuleAnalysisManager modules;
    passes.registerModuleAnalyses(modules);
    passes.registerCGSCCAnalyses(callGraph);
    passes.registerFunctionAnalyses(functions);
    passes.registerLoopAnalyses(loops);
    passes.crossRegisterProxies(loops, functions, callGraph, modules);
    const llvm::OptimizationLevel level = RECURLOOP_LLVM_OPT_LEVEL == 0   ? llvm::OptimizationLevel::O0
                                          : RECURLOOP_LLVM_OPT_LEVEL == 1 ? llvm::OptimizationLevel::O1
                                          : RECURLOOP_LLVM_OPT_LEVEL == 2 ? llvm::OptimizationLevel::O2
                                                                          : llvm::OptimizationLevel::O3;
    llvm::ModulePassManager pipeline = passes.buildPerModuleDefaultPipeline(level);
    pipeline.run(module, modules);

    llvm::SmallVector<char, 0> bytes;
    llvm::raw_svector_ostream output(bytes);
    llvm::legacy::PassManager emitter;
    if (machine->addPassesToEmitFile(emitter, output, nullptr, llvm::CodeGenFileType::ObjectFile))
      fail({}, 0, "LLVM host target cannot emit a compiled phrase object");
    emitter.run(module);
    result.module = compiler::ElfReader::read(
        std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t *>(bytes.data()), bytes.size()),
        "LLVM compiled phrase object for '" + std::string(symbol) + "'");
    return result;
  }
} // namespace recurloop::function_internal
