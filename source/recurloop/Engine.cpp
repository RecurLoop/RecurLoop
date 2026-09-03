#include <recurloop/Engine.hpp>

#include <context/Context.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <utilities/Exception.hpp>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>

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

    std::string path(context::Context &context, std::string_view operation) {
      const std::string expression = readLine(context);
      if (expression.empty()) THROW(, operation << " requires a path expression")
      const context::Value value = Expressions::evaluate(context, expression);
      if (!value.isString()) THROW(, operation << " path must be a string")
      if (value.asString().find('\0') != std::string::npos) THROW(, operation << " path contains a NUL byte")
      return value.asString();
    }
  } // namespace

  void Engine::registerActions(context::Context &context) {
    context.actions().define("engine.export", exportImage);
    context.actions().define("engine.import", importImage);
    context.actions().define("engine.define", define);
    context.actions().define("source.include", includeSource);
  }

  void Engine::exportImage(context::Context &context, lexicon::Phrase &) {
    EngineImage::save(context, path(context, "engine export"));
  }

  void Engine::importImage(context::Context &context, lexicon::Phrase &) {
    const std::string imagePath = path(context, "engine import");
    // The restore replaces the lexicon that owns the currently invoked phrase.
    context.exec.invoked = nullptr;
    EngineImage::load(context, imagePath);
  }

  void Engine::define(context::Context &context, lexicon::Phrase &) {
    SourceBlock block = Blocks::capture(context);
    if (!trim(std::move(block.header)).empty()) THROW(, "engine define must be followed directly by '{'")
    // The restore replaces the lexicon that owns the currently invoked phrase.
    context.exec.invoked = nullptr;
    EngineImage::define(context, block.body);
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
    const std::string source{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
    if (input.bad()) THROW(, "include: cannot read file '" << includePath.string() << "'")
    executeSource(context, source, includePath.string(), 1);
  }
} // namespace recurloop
