#include <recurloop/Engine.hpp>

#include <context/Context.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/TranslationUnits.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>

namespace recurloop {
  namespace {
    std::string trim(std::string value) {
      const auto begin = std::find_if_not(value.begin(), value.end(), [](unsigned char c) { return std::isspace(c); });
      const auto end =
          std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) { return std::isspace(c); }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits == 0 ? '\0'
                                             : context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    std::string readLine(context::Context &context) {
      std::string result;
      while (peek(context) != '\0' && peek(context) != '\n') {
        result.push_back(peek(context));
        context::Source::progress(context, Byte::length);
      }
      return trim(std::move(result));
    }

    std::string pathExpression(context::Context &context, std::string_view expression, std::string_view operation) {
      if (expression.empty()) THROW(, operation << " requires a path expression")
      const context::Value value = Expressions::evaluate(context, expression);
      if (!value.isString()) THROW(, operation << " path must be a string")
      if (value.asString().find('\0') != std::string::npos) THROW(, operation << " path contains a NUL byte")
      return value.asString();
    }

    std::string path(context::Context &context, std::string_view operation) {
      return pathExpression(context, readLine(context), operation);
    }
  } // namespace

  void Engine::registerActions(context::Context &context) {
    context.actions().define("engine.export", exportImage);
    context.actions().define("engine.import", importImage);
    context.actions().define("engine.define", define);
    context.actions().define("source.include", includeSource);
  }

  void Engine::exportImage(context::Context &context, lexicon::Phrase &) {
    const std::string source = readLine(context);
    if (source.empty() || source.front() != '<') {
      EngineImage::save(context, pathExpression(context, source, "engine export"));
      return;
    }

    const std::size_t close = source.find('>');
    if (close == std::string::npos) THROW(, "engine export lexicon reference is missing '>'")
    const std::string reference = trim(source.substr(1, close - 1));
    const std::string output = pathExpression(context, trim(source.substr(close + 1)), "engine export lexicon");
    const lexicon::Phrase phrase = TranslationUnitRegistry::reference(context, reference);
    TranslationUnitRegistry translationUnits(context);
    EngineImage::write(translationUnits.image(phrase), output);
  }

  void Engine::importImage(context::Context &context, lexicon::Phrase &) {
    const std::string imagePath = path(context, "engine import");
    // The restore replaces the lexicon that owns the currently invoked phrase.
    context.exec.invoked = nullptr;
    EngineImage::load(context, imagePath);

    // Loading a new image resets lookup to the restored root. Loading an image
    // that is already present is intentionally a no-op, however, and therefore
    // used to leave source execution inside the `engine` dictionary entered by
    // the `engine import` phrase. Make duplicate imports observationally match
    // real imports: the next top-level form always resumes from root.
    lexicon::Phrase root = context.lexicon.phrase();
    if (context::Lookup::current(context).getAddress() != root.getAddress()) {
      context.lookup = {};
      context::Lookup::in(context, root);
    }
  }

  void Engine::define(context::Context &context, lexicon::Phrase &) {
    SourceBlock block = Blocks::capture(context);
    if (!trim(std::move(block.header)).empty()) THROW(, "engine define must be followed directly by '{'")
    // The restore replaces the lexicon that owns the currently invoked phrase.
    context.exec.invoked = nullptr;
    EngineImage::define(context, block.body, block.path);
  }

  void Engine::includeSource(context::Context &context, lexicon::Phrase &) {
    std::filesystem::path includePath(path(context, "include"));
    if (includePath.is_relative() && !context.source.path.empty() && context.source.path.front() != '<')
      includePath = std::filesystem::path(context.source.path).parent_path() / includePath;
    std::error_code error;
    includePath = std::filesystem::absolute(includePath, error).lexically_normal();
    if (error) THROW(, "include: cannot resolve path: " << error.message())

    std::ifstream input(includePath, std::ios::binary);
    if (!input.is_open()) THROW(, "include: cannot open file '" << includePath.string() << "'")
    executeStream(context, input, includePath.string(), 1);
    if (input.bad()) THROW(, "include: cannot read file '" << includePath.string() << "'")
  }
} // namespace recurloop
