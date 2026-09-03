#include "FunctionsInternal.hpp"

#include <recurloop/Functions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxExtension.hpp>
#include <recurloop/TypeSyntax.hpp>

#include <charconv>
#include <optional>

namespace recurloop {
  namespace function_internal {

    class Parser;

    struct StatementParseFrame {
      Parser *parser = nullptr;
      Token start;
      Statement result;
    };

    struct PrimaryParseFrame {
      Parser *parser = nullptr;
      Token start;
      std::unique_ptr<Expression> result;
    };

    struct PostfixParseFrame {
      Parser *parser = nullptr;
      Token operation;
      std::unique_ptr<Expression> result;
    };

    thread_local StatementParseFrame *currentStatementParse = nullptr;
    thread_local PrimaryParseFrame *currentPrimaryParse = nullptr;
    thread_local PostfixParseFrame *currentPostfixParse = nullptr;

    StatementParseFrame &statementParseFrame() {
      if (currentStatementParse == nullptr) THROW(, "fn statement syntax invoked without a parser frame")
      return *currentStatementParse;
    }

    PrimaryParseFrame &primaryParseFrame() {
      if (currentPrimaryParse == nullptr) THROW(, "fn primary syntax invoked without a parser frame")
      return *currentPrimaryParse;
    }

    PostfixParseFrame &postfixParseFrame() {
      if (currentPostfixParse == nullptr) THROW(, "fn postfix syntax invoked without a parser frame")
      return *currentPostfixParse;
    }

    class Parser : public TypeSyntax::Cursor {
    public:
      Parser(context::Context &context, std::string_view source, std::string scope = {}, std::string sourcePath = {},
             std::size_t sourceLine = 1, std::size_t sourceColumn = 1)
          : context(context), statements(exact(exact(context.lexicon.phrase(), FunctionGrammarName), "statements")),
            assignments(exact(exact(context.lexicon.phrase(), std::string_view{"\0expressions", 12}), "assignments")),
            intrinsics(exact(exact(context.lexicon.phrase(), FunctionGrammarName), IntrinsicDictionaryName)),
            primaries(exact(exact(context.lexicon.phrase(), FunctionGrammarName), "primary")),
            postfixes(exact(exact(context.lexicon.phrase(), FunctionGrammarName), "postfix")),
            lexer(context, source,
                  {exact(exact(context.lexicon.phrase(), FunctionGrammarName), "symbols"), statements,
                   exact(exact(context.lexicon.phrase(), std::string_view{"\0expressions", 12}), "prefix"),
                   exact(exact(context.lexicon.phrase(), std::string_view{"\0expressions", 12}), "infix"), assignments,
                   intrinsics, primaries, postfixes,
                   exact(exact(context.lexicon.phrase(), std::string_view{"\0type-syntax", 12}), "prefix"),
                   exact(exact(context.lexicon.phrase(), std::string_view{"\0type-syntax", 12}), "suffix")},
                  lexerFail, {.preserveNewlines = true, .bitStrings = true}),
            scope(std::move(scope)), sourcePath(std::move(sourcePath)), sourceText(source), sourceLine(sourceLine),
            sourceColumn(sourceColumn) {}

      FunctionDefinition signature(const std::string &symbol, bool requireEnd = true,
                                   bool parameterNamesOptional = false) {
        lexer.skipNewlines();
        FunctionDefinition result;
        result.function.signature.symbol = symbol;
        result.function.imported = false;
        result.sourcePath = sourcePath;
        result.sourceText = std::string(sourceText);
        result.sourceLine = sourceLine;
        result.sourceColumn = sourceColumn;
        lexer.expect("(");
        lexer.skipNewlines();
        if (!lexer.accept(")")) {
          while (true) {
            if (lexer.accept("...")) {
              result.function.signature.variadic = true;
              lexer.skipNewlines();
              lexer.expect(")");
              break;
            }
            Token name;
            const bool named =
                !parameterNamesOptional || LanguageGrammar::matches(context, lexer.lookahead().text, ":");
            if (named) {
              name = identifier("a parameter name");
              lexer.expect(":");
            }
            const compiler::TypeId typeId = type();
            if (named && std::find(result.names.begin(), result.names.end(), name.text) != result.names.end())
              fail({}, name.offset, "duplicate parameter '" + name.text + "'");
            result.names.push_back(named ? name.text : std::string{});
            result.function.parameterTypes.push_back(typeId);
            result.function.signature.parameters.push_back(context.language().types.abiType(typeId));
            if (!nextListItem(")")) break;
          }
        }
        lexer.skipNewlines();
        lexer.expect("->");
        lexer.skipNewlines();
        result.function.resultType = type();
        result.function.signature.result = context.language().types.abiType(result.function.resultType);
        if (lexer.accept("abi")) result.function.signature.convention = context.language().convention(abiName());
        lexer.skipNewlines();
        if (requireEnd && lexer.current().kind != TokenKind::End)
          fail({}, lexer.current().offset, "unexpected token after fn signature");
        return result;
      }

      std::vector<Statement> body() {
        lexer.skipNewlines();
        std::vector<Statement> result;
        while (lexer.current().kind != TokenKind::End) {
          result.push_back(statement());
          lexer.skipNewlines();
        }
        return result;
      }

      Token identifier(std::string_view description) {
        if (lexer.current().kind != TokenKind::Identifier && lexer.current().kind != TokenKind::Symbol)
          fail({}, lexer.current().offset, "expected " + std::string(description));
        return lexer.take();
      }

      Token qualifiedIdentifier(std::string_view description) {
        Token result = identifier(description);
        while (lexer.accept(":")) result.text += ":" + identifier("a qualified name component").text;
        return result;
      }

      bool nextListItem(std::string_view closing) {
        const bool separatedByLayout = lexer.skipNewlines();
        if (lexer.accept(closing)) return false;
        if (lexer.accept(",")) {
          lexer.skipNewlines();
          return true;
        }
        if (separatedByLayout) return true;
        lexer.expect(",");
        lexer.skipNewlines();
        return true;
      }

      compiler::TypeId type() {
        return TypeSyntax::parse(context, *this, Assembler::dictionarySymbol(context));
      }

      std::string abiName() {
        std::string result = identifier("an ABI name").text;
        while (lexer.accept("-")) result += "-" + identifier("an ABI name component").text;
        return result;
      }

      std::string_view typeCurrent() const override {
        return lexer.current().text;
      }
      bool typeAccept(std::string_view token) override {
        return lexer.accept(token);
      }
      void typeExpect(std::string_view token) override {
        lexer.expect(token);
      }
      bool typeSkipLayout() override {
        return lexer.skipNewlines();
      }
      std::string typeIdentifier(std::string_view description) override {
        if (lexer.current().kind != TokenKind::Identifier && lexer.current().kind != TokenKind::Symbol)
          fail({}, lexer.current().offset, "expected " + std::string(description));
        return lexer.take().text;
      }
      std::size_t typeNumber(std::string_view description) override {
        const Token token = lexer.take();
        std::size_t result = 0;
        const auto [end, error] = std::from_chars(token.text.data(), token.text.data() + token.text.size(), result);
        if (token.kind != TokenKind::Integer || error != std::errc() || end != token.text.data() + token.text.size())
          fail({}, token.offset, "expected " + std::string(description));
        return result;
      }
      [[noreturn]] void typeError(const std::string &message) override {
        fail({}, lexer.current().offset, message);
      }

      std::vector<Statement> block() {
        lexer.skipNewlines();
        lexer.expect("{");
        return blockContents();
      }

      std::vector<Statement> blockContents(std::size_t *closingOffset = nullptr) {
        lexer.skipNewlines();
        std::vector<Statement> result;
        while (!LanguageGrammar::matches(context, lexer.current().text, "}")) {
          if (lexer.current().kind == TokenKind::End) fail({}, lexer.current().offset, "unterminated block");
          result.push_back(statement());
          lexer.skipNewlines();
        }
        if (closingOffset != nullptr) *closingOffset = lexer.current().offset;
        lexer.take();
        return result;
      }

      Statement statement() {
        lexer.skipNewlines();
        const Token start = lexer.current();
        lexicon::Phrase syntax = LanguageGrammar::resolve(context, statements, start.text);
        if (syntax.isNull()) {
          auto target = expression();
          lexicon::Phrase operation = LanguageGrammar::resolve(context, assignments, lexer.current().text);
          if (!operation.isNull()) {
            Statement result;
            result.syntax = exact(statements, AssignmentStatementName);
            result.operationSyntax = operation;
            result.offset = start.offset;
            result.target = std::move(target);
            result.operation = lexer.take().text;
            result.expression = expression();
            return result;
          }
          Statement result;
          result.syntax = exact(statements, ExpressionStatementName);
          result.offset = start.offset;
          result.expression = std::move(target);
          return result;
        }
        lexer.take();
        StatementParseFrame frame{this, start, {}};
        StatementParseFrame *previous = currentStatementParse;
        currentStatementParse = &frame;
        try {
          syntax.invoke(context);
        } catch (...) {
          currentStatementParse = previous;
          throw;
        }
        currentStatementParse = previous;
        if (frame.result.syntax.isNull()) fail({}, start.offset, "fn statement phrase did not produce syntax");
        return std::move(frame.result);
      }

      void parseVariable(Statement &result, const Token &start, lexicon::Phrase syntax) {
        lexicon::Phrase definition = LanguageGrammar::metadata(syntax, sizeof(std::uint8_t));
        if (definition.isNull()) fail({}, start.offset, "variable syntax has no mutability metadata");
        std::uint8_t mutableValue = 0;
        definition.fetch(0, mutableValue);
        result.syntax = syntax;
        result.offset = start.offset;
        result.name = identifier("a local variable name").text;
        result.mutableValue = mutableValue != 0;
        if (lexer.accept(":")) result.declaredType = type();
        lexer.expect("=");
        result.expression = expression();
      }

      void parseAssignment(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
        result.target = expression();
        result.operationSyntax = LanguageGrammar::resolve(context, assignments, lexer.current().text);
        result.operation = lexer.take().text;
        if (result.operationSyntax.isNull()) fail({}, start.offset, "expected an assignment operator");
        result.expression = expression();
      }

      void parseConditional(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
        result.expression = expression();
        result.accepted = block();
        lexer.skipNewlines();
        if (acceptAlias("else")) {
          lexer.skipNewlines();
          if (isAliasOf(lexer.current().text, "if"))
            result.rejected.push_back(statement());
          else
            result.rejected = block();
        }
      }

      void parseLoop(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
        result.expression = expression();
        result.accepted = block();
      }

      void parseControl(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
      }

      void parseReturn(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
        if (lexer.current().kind != TokenKind::Newline && lexer.current().kind != TokenKind::End &&
            !LanguageGrammar::matches(context, lexer.current().text, ";") &&
            !LanguageGrammar::matches(context, lexer.current().text, "}"))
          result.expression = expression();
      }

      void parseDefer(Statement &result, const Token &start, lexicon::Phrase syntax) {
        result.syntax = syntax;
        result.offset = start.offset;
        result.expression = expression();
      }

      std::unique_ptr<Expression> expression(std::uint8_t minimumPrecedence = 1) {
        auto left = unary();
        if (expressionGroupDepth != 0) lexer.skipNewlines();
        while (lexer.current().kind == TokenKind::Symbol) {
          lexicon::Phrase operationPhrase = Expressions::infixOperator(context, lexer.current().text);
          if (operationPhrase.isNull()) break;
          const ExpressionOperator definition = Expressions::operatorDefinition(operationPhrase);
          if (definition.precedence < minimumPrecedence) break;
          Token operation = lexer.take();
          lexer.skipNewlines();
          left = binary(std::move(left), std::move(operation), expression(definition.precedence + 1));
          if (expressionGroupDepth != 0) lexer.skipNewlines();
        }
        return left;
      }

      std::unique_ptr<Expression> binary(std::unique_ptr<Expression> left, Token operation,
                                         std::unique_ptr<Expression> right) {
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Binary;
        result->text = std::move(operation.text);
        result->syntax = Expressions::infixOperator(context, result->text);
        result->offset = operation.offset;
        result->children.push_back(std::move(left));
        result->children.push_back(std::move(right));
        return result;
      }

      std::unique_ptr<Expression> unary() {
        lexicon::Phrase intrinsic = LanguageGrammar::resolve(context, intrinsics, lexer.current().text);
        lexicon::Phrase intrinsicMetadata = LanguageGrammar::metadata(intrinsic, sizeof(IntrinsicKind));
        if (!intrinsicMetadata.isNull()) {
          IntrinsicKind kind = IntrinsicKind::Cast;
          intrinsicMetadata.fetch(0, kind);
          if (kind == IntrinsicKind::Address || kind == IntrinsicKind::Dereference) {
            Token operation = lexer.take();
            auto result = std::make_unique<Expression>();
            result->kind = Expression::Kind::Unary;
            result->text = std::move(operation.text);
            result->syntax = intrinsic;
            result->offset = operation.offset;
            result->children.push_back(unary());
            return result;
          }
        }
        lexicon::Phrase operationPhrase = Expressions::prefixOperator(context, lexer.current().text);
        if (!operationPhrase.isNull()) {
          Token operation = lexer.take();
          auto result = std::make_unique<Expression>();
          result->kind = Expression::Kind::Unary;
          result->text = std::move(operation.text);
          result->syntax = operationPhrase;
          result->offset = operation.offset;
          result->children.push_back(unary());
          return result;
        }
        return postfix();
      }

      std::unique_ptr<Expression> invokePrimary(lexicon::Phrase syntax, Token start) {
        PrimaryParseFrame frame{this, std::move(start), {}};
        PrimaryParseFrame *previous = currentPrimaryParse;
        currentPrimaryParse = &frame;
        try {
          syntax.invoke(context);
        } catch (...) {
          currentPrimaryParse = previous;
          throw;
        }
        currentPrimaryParse = previous;
        if (!frame.result) fail({}, frame.start.offset, "fn primary phrase did not produce an expression");
        return std::move(frame.result);
      }

      std::unique_ptr<Expression> invokePostfix(lexicon::Phrase syntax, Token operation,
                                                std::unique_ptr<Expression> base) {
        PostfixParseFrame frame{this, std::move(operation), std::move(base)};
        PostfixParseFrame *previous = currentPostfixParse;
        currentPostfixParse = &frame;
        try {
          syntax.invoke(context);
        } catch (...) {
          currentPostfixParse = previous;
          throw;
        }
        currentPostfixParse = previous;
        if (!frame.result) fail({}, frame.operation.offset, "fn postfix phrase did not produce an expression");
        return std::move(frame.result);
      }

      std::unique_ptr<Expression> postfix() {
        auto result = primary();
        while (true) {
          lexicon::Phrase syntax = LanguageGrammar::resolve(context, postfixes, lexer.current().text);
          if (syntax.isNull()) return result;
          result = invokePostfix(syntax, lexer.take(), std::move(result));
        }
      }

      std::unique_ptr<Expression> primary() {
        Token token = lexer.take();
        auto result = std::make_unique<Expression>();
        result->offset = token.offset;
        result->text = token.text;
        if (token.kind == TokenKind::Integer) {
          result->kind = Expression::Kind::Integer;
          return result;
        }
        if (token.kind == TokenKind::Real) {
          result->kind = Expression::Kind::Real;
          return result;
        }
        if (token.kind == TokenKind::String) {
          result->kind = Expression::Kind::String;
          return result;
        }
        if (token.kind == TokenKind::BitString) {
          result->kind = Expression::Kind::BitString;
          return result;
        }
        lexicon::Phrase syntax = LanguageGrammar::resolve(context, primaries, token.text);
        if (!syntax.isNull()) return invokePrimary(syntax, std::move(token));
        if (token.kind != TokenKind::Identifier && token.kind != TokenKind::Symbol)
          fail({}, token.offset, "expected an expression");
        while (lexer.accept(":")) token.text += ":" + identifier("a qualified name component").text;
        result->text = token.text;
        result->kind = Expression::Kind::Variable;
        return result;
      }

      std::unique_ptr<Expression> parseGrouped(const Token &) {
        ++expressionGroupDepth;
        lexer.skipNewlines();
        auto result = expression();
        lexer.skipNewlines();
        --expressionGroupDepth;
        lexer.expect(")");
        return result;
      }

      std::unique_ptr<Expression> parseValueBlock(const Token &start) {
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Block;
        result->offset = start.offset;
        result->body = std::make_shared<ExpressionBody>();
        result->body->accepted = blockContents();
        return result;
      }

      std::unique_ptr<Expression> parseFunctionLiteral(const Token &start) {
        const std::string symbol = "__recurloop_action_" + std::to_string(context.lexicon.checkpoint().getAddress()) +
                                   "_" + std::to_string(start.offset);
        FunctionDefinition definition = signature(symbol, false);
        definition.scope = scope;
        lexer.skipNewlines();
        const Token opening = lexer.current();
        lexer.expect("{");
        std::size_t closing = opening.offset + opening.text.size();
        const std::vector<Statement> statements = blockContents(&closing);
        const std::size_t bodyBegin = opening.offset + opening.text.size();
        const SourceLocation bodyOrigin =
            sourceLocationAt({sourcePath, sourceLine, sourceColumn}, sourceText, bodyBegin);
        definition.sourceText = std::string(sourceText.substr(bodyBegin, closing - bodyBegin));
        definition.sourceLine = bodyOrigin.line;
        definition.sourceColumn = bodyOrigin.column;
        const compiler::TypedFunction implementation =
            compileFunctionDefinition(context, std::move(definition), statements, symbol);
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::FunctionLiteral;
        result->offset = start.offset;
        result->text = implementation.signature.symbol;
        return result;
      }

      std::unique_ptr<Expression> parseConditionalExpression(const Token &start) {
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Conditional;
        result->offset = start.offset;
        result->body = std::make_shared<ExpressionBody>();
        result->body->condition = expression();
        result->body->accepted = block();
        lexer.skipNewlines();
        if (!acceptAlias("else")) fail({}, start.offset, "an if expression requires else");
        lexer.skipNewlines();
        result->body->rejected = block();
        return result;
      }

      std::unique_ptr<Expression> parseCast(const Token &start, lexicon::Phrase) {
        lexer.expect("(");
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Unary;
        result->syntax = exact(intrinsics, "cast");
        result->text = start.text;
        result->offset = start.offset;
        result->declaredType = type();
        lexer.expect(",");
        result->children.push_back(expression());
        lexer.expect(")");
        return result;
      }

      std::unique_ptr<Expression> parseIndex(Token operation, std::unique_ptr<Expression> base,
                                             lexicon::Phrase syntax) {
        ++expressionGroupDepth;
        lexer.skipNewlines();
        auto index = expression();
        lexer.skipNewlines();
        --expressionGroupDepth;
        lexer.expect("]");
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Index;
        result->syntax = syntax;
        result->offset = operation.offset;
        result->children.push_back(std::move(base));
        result->children.push_back(std::move(index));
        return result;
      }

      std::unique_ptr<Expression> parseMember(Token operation, std::unique_ptr<Expression> base,
                                              lexicon::Phrase syntax) {
        Token field = identifier("a field name");
        auto result = std::make_unique<Expression>();
        result->syntax = syntax;
        result->text = std::move(field.text);
        result->offset = field.offset;
        result->children.push_back(std::move(base));
        if (!lexer.accept("(")) {
          result->kind = Expression::Kind::Member;
          return result;
        }
        result->kind = Expression::Kind::MethodCall;
        lexer.skipNewlines();
        if (!lexer.accept(")")) {
          while (true) {
            result->children.push_back(expression());
            if (!nextListItem(")")) break;
          }
        }
        return result;
      }

      std::unique_ptr<Expression> parsePropagation(Token operation, std::unique_ptr<Expression> base,
                                                   lexicon::Phrase syntax) {
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Propagate;
        result->syntax = syntax;
        result->offset = operation.offset;
        result->children.push_back(std::move(base));
        return result;
      }

      std::unique_ptr<Expression> parseCall(Token operation, std::unique_ptr<Expression> base, lexicon::Phrase syntax) {
        if (base->kind != Expression::Kind::Variable)
          fail({}, operation.offset, "a direct fn call requires a named function or local");
        auto result = std::make_unique<Expression>();
        result->kind = Expression::Kind::Call;
        result->syntax = syntax;
        result->text = std::move(base->text);
        result->offset = base->offset;
        lexer.skipNewlines();
        if (!lexer.accept(")")) {
          while (true) {
            result->children.push_back(expression());
            if (!nextListItem(")")) break;
          }
        }
        return result;
      }

      bool isAliasOf(std::string_view name, std::string_view canonical) const {
        return LanguageGrammar::inherits(LanguageGrammar::find(context.lexicon.phrase(), name),
                                         LanguageGrammar::find(context.lexicon.phrase(), canonical));
      }

      bool acceptAlias(std::string_view canonical) {
        if (!isAliasOf(lexer.current().text, canonical)) return false;
        lexer.take();
        return true;
      }

      context::Context &context;
      lexicon::Phrase statements;
      lexicon::Phrase assignments;
      lexicon::Phrase intrinsics;
      lexicon::Phrase primaries;
      lexicon::Phrase postfixes;
      Lexer lexer;
      std::string scope;
      std::string sourcePath;
      std::string_view sourceText;
      std::size_t sourceLine = 1;
      std::size_t sourceColumn = 1;
      std::size_t expressionGroupDepth = 0;
    };

    namespace {
      void parseVariableSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseVariable(frame.result, frame.start, syntax);
      }

      void parseAssignmentSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseAssignment(frame.result, frame.start, syntax);
      }

      void parseConditionalSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseConditional(frame.result, frame.start, syntax);
      }

      void parseLoopSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseLoop(frame.result, frame.start, syntax);
      }

      void parseControlSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseControl(frame.result, frame.start, syntax);
      }

      void parseReturnSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseReturn(frame.result, frame.start, syntax);
      }

      void parseDeferSyntax(context::Context &, lexicon::Phrase &syntax) {
        StatementParseFrame &frame = statementParseFrame();
        frame.parser->parseDefer(frame.result, frame.start, syntax);
      }

      void parseGroupedSyntax(context::Context &, lexicon::Phrase &) {
        PrimaryParseFrame &frame = primaryParseFrame();
        frame.result = frame.parser->parseGrouped(frame.start);
      }

      void parseValueBlockSyntax(context::Context &, lexicon::Phrase &) {
        PrimaryParseFrame &frame = primaryParseFrame();
        frame.result = frame.parser->parseValueBlock(frame.start);
      }

      void parseFunctionLiteralSyntax(context::Context &, lexicon::Phrase &) {
        PrimaryParseFrame &frame = primaryParseFrame();
        frame.result = frame.parser->parseFunctionLiteral(frame.start);
      }

      void parseConditionalExpressionSyntax(context::Context &, lexicon::Phrase &) {
        PrimaryParseFrame &frame = primaryParseFrame();
        frame.result = frame.parser->parseConditionalExpression(frame.start);
      }

      void parseCastSyntax(context::Context &, lexicon::Phrase &syntax) {
        PrimaryParseFrame &frame = primaryParseFrame();
        frame.result = frame.parser->parseCast(frame.start, syntax);
      }

      void parseIndexSyntax(context::Context &, lexicon::Phrase &syntax) {
        PostfixParseFrame &frame = postfixParseFrame();
        frame.result = frame.parser->parseIndex(std::move(frame.operation), std::move(frame.result), syntax);
      }

      void parseMemberSyntax(context::Context &, lexicon::Phrase &syntax) {
        PostfixParseFrame &frame = postfixParseFrame();
        frame.result = frame.parser->parseMember(std::move(frame.operation), std::move(frame.result), syntax);
      }

      void parsePropagationSyntax(context::Context &, lexicon::Phrase &syntax) {
        PostfixParseFrame &frame = postfixParseFrame();
        frame.result = frame.parser->parsePropagation(std::move(frame.operation), std::move(frame.result), syntax);
      }

      void parseCallSyntax(context::Context &, lexicon::Phrase &syntax) {
        PostfixParseFrame &frame = postfixParseFrame();
        frame.result = frame.parser->parseCall(std::move(frame.operation), std::move(frame.result), syntax);
      }
    } // namespace

    void setupStatementSyntax(context::Context &context, lexicon::Phrase grammar) {
      context.actions().define("fn.statement.parse-variable", parseVariableSyntax);
      context.actions().define("fn.statement.parse-assignment", parseAssignmentSyntax);
      context.actions().define("fn.statement.parse-conditional", parseConditionalSyntax);
      context.actions().define("fn.statement.parse-loop", parseLoopSyntax);
      context.actions().define("fn.statement.parse-control", parseControlSyntax);
      context.actions().define("fn.statement.parse-return", parseReturnSyntax);
      context.actions().define("fn.statement.parse-defer", parseDeferSyntax);
      context.actions().define("fn.primary.group", parseGroupedSyntax);
      context.actions().define("fn.primary.block", parseValueBlockSyntax);
      context.actions().define("fn.primary.function", parseFunctionLiteralSyntax);
      context.actions().define("fn.primary.conditional", parseConditionalExpressionSyntax);
      context.actions().define("fn.primary.cast", parseCastSyntax);
      context.actions().define("fn.postfix.index", parseIndexSyntax);
      context.actions().define("fn.postfix.member", parseMemberSyntax);
      context.actions().define("fn.postfix.propagate", parsePropagationSyntax);
      context.actions().define("fn.postfix.call", parseCallSyntax);

      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
      lexicon::Phrase data = lexicon::phrase::type::getData(root);
      lexicon::Phrase statements = grammar.append("statements").make().enableSubdictionary().setType(data).save();
      const auto define = [&](std::string_view name, lexicon::Phrase::Action parser,
                              std::optional<bool> mutableValue = std::nullopt) {
        lexicon::Draft draft =
            statements.append(std::string(name)).make(parser).enableSubdictionary().setType(callable);
        lexicon::Phrase topLevel = exact(root, name);
        draft.setPrototype(topLevel);
        lexicon::Phrase syntax = draft.save();
        if (mutableValue) syntax.store(static_cast<std::uint8_t>(*mutableValue)).save();
        return syntax;
      };
      const auto internal = [&](std::string_view name) {
        return statements.append(Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(data)
            .save();
      };

      define("var", parseVariableSyntax, true);
      define("let", parseVariableSyntax, false);
      define("const", parseVariableSyntax, false);
      define("set", parseAssignmentSyntax);
      define("if", parseConditionalSyntax);
      define("while", parseLoopSyntax);
      define("break", parseControlSyntax);
      define("continue", parseControlSyntax);
      define("return", parseReturnSyntax);
      define("defer", parseDeferSyntax);
      internal(ExpressionStatementName);
      internal(AssignmentStatementName);

      lexicon::Phrase intrinsics =
          grammar.append(std::string(IntrinsicDictionaryName)).make().enableSubdictionary().setType(data).save();
      const auto intrinsic = [&](std::string_view name, IntrinsicKind kind) {
        intrinsics.append(std::string(name))
            .make()
            .enableSubdictionary()
            .setType(data)
            .setPrototype(LanguageGrammar::ensureMarker(root, name))
            .save()
            .store(kind);
      };
      intrinsic("cast", IntrinsicKind::Cast);
      intrinsic("&", IntrinsicKind::Address);
      intrinsic("*", IntrinsicKind::Dereference);

      lexicon::Phrase primaries = grammar.append("primary").make().enableSubdictionary().setType(data).save();
      const auto primary = [&](std::string_view name, lexicon::Phrase::Action parser,
                               lexicon::Phrase prototype = lexicon::Phrase{}) {
        if (prototype.isNull()) prototype = LanguageGrammar::ensureMarker(root, name);
        return primaries.append(std::string(name)).make(parser).setType(callable).setPrototype(prototype).save();
      };
      primary("(", parseGroupedSyntax);
      primary("{", parseValueBlockSyntax);
      primary("fn", parseFunctionLiteralSyntax);
      primary("if", parseConditionalExpressionSyntax);
      primary("cast", parseCastSyntax, exact(intrinsics, "cast"));

      lexicon::Phrase postfixes = grammar.append("postfix").make().enableSubdictionary().setType(data).save();
      const auto postfix = [&](std::string_view name, lexicon::Phrase::Action parser) {
        postfixes.append(std::string(name))
            .make(parser)
            .setType(callable)
            .setPrototype(LanguageGrammar::ensureMarker(root, name))
            .save();
      };
      postfix("[", parseIndexSyntax);
      postfix(".", parseMemberSyntax);
      postfix("?", parsePropagationSyntax);
      postfix("(", parseCallSyntax);
    }

    void bindSyntaxPrototypes(context::Context &context) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase grammar = exact(root, FunctionGrammarName);
      const auto bind = [&](lexicon::Phrase dictionary, std::initializer_list<std::string_view> names) {
        for (std::string_view name : names) {
          lexicon::Phrase syntax = exact(dictionary, name);
          lexicon::Phrase topLevel = exact(root, name);
          if (topLevel.isNull()) topLevel = LanguageGrammar::ensureMarker(context, name);
          if (!syntax.isNull() && !topLevel.isNull()) syntax.setPrototype(topLevel).save();
        }
      };
      bind(exact(grammar, "statements"),
           {"var", "let", "const", "set", "if", "while", "break", "continue", "return", "defer"});
      bind(exact(grammar, IntrinsicDictionaryName), {"cast", "&", "*"});
      bind(exact(grammar, "primary"), {"(", "{", "fn", "if", "cast"});
      bind(exact(grammar, "postfix"), {"[", ".", "?", "("});
    }

    FunctionDefinition parseSignature(context::Context &context, std::string_view source, const std::string &symbol,
                                      bool parameterNamesOptional, std::string sourcePath, std::size_t sourceLine,
                                      std::size_t sourceColumn) {
      if (sourcePath.empty()) {
        sourcePath = context.source.path;
        sourceLine = context.source.line;
        sourceColumn = context.source.position;
      }
      const SourceLocation origin{sourcePath, sourceLine, sourceColumn};
      const ExpandedSyntax expanded = SyntaxExtension::expand(context, source, origin);
      DiagnosticScope diagnostics(expanded.source, origin, source, expanded.originalOffsets);
      Parser parser(context, expanded.source, {}, std::move(sourcePath), sourceLine, sourceColumn);
      return parser.signature(symbol, true, parameterNamesOptional);
    }

    std::vector<Statement> parseBody(context::Context &context, std::string_view source, std::string scope,
                                     std::string sourcePath, std::size_t sourceLine, std::size_t sourceColumn) {
      if (sourcePath.empty()) {
        sourcePath = context.source.path;
        sourceLine = context.source.line;
        sourceColumn = context.source.position;
      }
      const SourceLocation origin{sourcePath, sourceLine, sourceColumn};
      const ExpandedSyntax expanded = SyntaxExtension::expand(context, source, origin);
      DiagnosticScope diagnostics(expanded.source, origin, source, expanded.originalOffsets);
      Parser parser(context, expanded.source, std::move(scope), std::move(sourcePath), sourceLine, sourceColumn);
      return parser.body();
    }

  } // namespace function_internal
} // namespace recurloop
