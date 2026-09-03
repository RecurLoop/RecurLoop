#pragma once

#include <compiler/Assembler.hpp>
#include <compiler/LanguageState.hpp>
#include <compiler/Module.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Assembler.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxCursor.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace recurloop {
  namespace function_internal {

    constexpr std::string_view FunctionGrammarName{"\0fn-grammar", 11};
    constexpr std::string_view IntrinsicDictionaryName{"intrinsics"};
    constexpr std::string_view StatementEmitName{"\0fn-emit", 8};
    constexpr std::string_view StatementValueName{"\0fn-value", 9};
    constexpr std::string_view ExpressionStatementName{"\0expression", 11};
    constexpr std::string_view AssignmentStatementName{"\0assignment", 11};
    constexpr std::string_view AssignmentEmitName{"\0fn-assign", 10};

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key);
    char peek(context::Context &context);
    std::string readLine(context::Context &context);
    std::string trim(std::string value);
    [[noreturn]] void fail(std::string_view source, std::size_t offset, const std::string &message);

    struct DiagnosticSource {
      std::string_view source;
      SourceLocation origin;
      std::string_view originalSource;
      std::span<const std::size_t> originalOffsets;
    };

    class DiagnosticScope {
    public:
      DiagnosticScope(std::string_view source, SourceLocation origin, std::string_view originalSource = {},
                      std::span<const std::size_t> originalOffsets = {});
      ~DiagnosticScope();

      DiagnosticScope(const DiagnosticScope &) = delete;
      DiagnosticScope &operator=(const DiagnosticScope &) = delete;

    private:
      DiagnosticSource current;
      DiagnosticSource *previous = nullptr;
    };

    using TokenKind = SyntaxTokenKind;
    using Token = SyntaxToken;
    using Lexer = SyntaxCursor;
    [[noreturn]] void lexerFail(const context::Context &context, std::size_t offset, const std::string &message);

    enum class IntrinsicKind : std::uint8_t { Cast, Address, Dereference };

    struct ExpressionBody;

    struct Expression {
      enum class Kind : std::uint8_t {
        Integer,
        Real,
        String,
        BitString,
        FunctionLiteral,
        Variable,
        Index,
        Member,
        Call,
        MethodCall,
        Unary,
        Binary,
        Block,
        Conditional,
        Propagate
      } kind;
      lexicon::Phrase syntax;
      std::string text;
      std::vector<std::unique_ptr<Expression>> children;
      std::shared_ptr<ExpressionBody> body;
      std::size_t offset = 0;
      compiler::TypeId declaredType = compiler::InvalidType;
    };

    struct Statement {
      lexicon::Phrase syntax;
      lexicon::Phrase operationSyntax;
      std::string name;
      std::string operation;
      compiler::TypeId declaredType = compiler::InvalidType;
      std::unique_ptr<Expression> expression;
      std::unique_ptr<Expression> target;
      std::vector<Statement> accepted;
      std::vector<Statement> rejected;
      std::size_t offset = 0;
      bool mutableValue = true;
    };

    struct ExpressionBody {
      std::unique_ptr<Expression> condition;
      std::vector<Statement> accepted;
      std::vector<Statement> rejected;
    };

    struct FunctionDefinition {
      compiler::TypedFunction function;
      std::vector<std::string> names;
      // Full source-level phrase path used as the start of lexical lookup.
      std::string scope;
      std::string sourcePath;
      std::string sourceText;
      std::size_t sourceLine = 1;
      std::size_t sourceColumn = 1;
    };

    struct Local {
      compiler::TypeId type = compiler::InvalidType;
      std::size_t offset = 0;
      bool mutableValue = true;
    };

    FunctionDefinition parseSignature(context::Context &context, std::string_view source, const std::string &symbol,
                                      bool parameterNamesOptional = false, std::string sourcePath = {},
                                      std::size_t sourceLine = 1, std::size_t sourceColumn = 1);
    std::vector<Statement> parseBody(context::Context &context, std::string_view source, std::string scope = {},
                                     std::string sourcePath = {}, std::size_t sourceLine = 1,
                                     std::size_t sourceColumn = 1);
    compiler::Module generateModule(context::Context &context, const FunctionDefinition &signature,
                                    const std::vector<Statement> &body);
    compiler::TypedFunction compileFunctionDefinition(context::Context &context, FunctionDefinition definition,
                                                      const std::vector<Statement> &body, std::string hint = {});
    lexicon::Phrase compileActionDefinition(context::Context &context, FunctionDefinition definition,
                                            const std::vector<Statement> &body, std::string hint = {});
    void setupCompilerSyntax(context::Context &context);
    void setupStatementSyntax(context::Context &context, lexicon::Phrase grammar);
    void bindSyntaxPrototypes(context::Context &context);

  } // namespace function_internal
} // namespace recurloop
