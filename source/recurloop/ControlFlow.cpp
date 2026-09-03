#include <recurloop/ControlFlow.hpp>

#include <context/Context.hpp>
#include <compiler/LanguageState.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/Expressions.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>

namespace recurloop {
  namespace {
    std::string trim(std::string source) {
      const auto begin =
          std::find_if_not(source.begin(), source.end(), [](unsigned char c) { return std::isspace(c); });
      const auto end =
          std::find_if_not(source.rbegin(), source.rend(), [](unsigned char c) { return std::isspace(c); }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    struct Condition {
      std::string source;
      SourceLocation origin;
    };

    Condition condition(SourceBlock &block, std::string_view keyword) {
      const std::size_t leading = static_cast<std::size_t>(
          std::find_if_not(block.header.begin(), block.header.end(), [](unsigned char character) {
            return std::isspace(character);
          }) -
          block.header.begin());
      SourceLocation origin =
          sourceLocationAt({block.path, block.headerLine, block.headerPosition}, block.header, leading);
      std::string source = trim(std::move(block.header));
      if (source.empty()) THROW_AT(origin, keyword << " requires a boolean expression before '{'")
      return {std::move(source), std::move(origin)};
    }
  } // namespace

  void ControlFlow::conditional(context::Context &context, lexicon::Phrase &) {
    SourceBlock accepted = Blocks::capture(context);
    const Condition expression = condition(accepted, "if");

    SourceBlock rejected;
    const bool hasElse = Blocks::consume(context, "else");
    if (hasElse) {
      rejected = Blocks::capture(context);
      if (!trim(rejected.header).empty()) THROW(, "else must be followed directly by '{'")
    }

    if (Expressions::evaluate(context, expression.source, expression.origin).asBoolean())
      Blocks::execute(context, accepted);
    else if (hasElse)
      Blocks::execute(context, rejected);
  }

  void ControlFlow::loop(context::Context &context, lexicon::Phrase &) {
    SourceBlock block = Blocks::capture(context);
    const Condition expression = condition(block, "while");
    while (Expressions::evaluate(context, expression.source, expression.origin).asBoolean())
      Blocks::execute(context, block);
  }

  void ControlFlow::setup(context::Context &context) {
    context.actions().define("control.if", conditional);
    context.actions().define("control.while", loop);
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase conditionalPhrase =
        root.append("if").make(conditional).setType(lexicon::phrase::type::getElaborate(root)).save();
    compiler::LanguageState::bind(conditionalPhrase);
    lexicon::Phrase loopPhrase =
        root.append("while").make(loop).setType(lexicon::phrase::type::getElaborate(root)).save();
    compiler::LanguageState::bind(loopPhrase);
  }
} // namespace recurloop
