#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace lexicon {
  class Lexicon;
  class Phrase;
} // namespace lexicon

namespace context {
  class Value {
  public:
    using Storage = std::variant<std::monostate, bool, std::int64_t, double, std::string>;

    Value() = default;
    Value(bool value);
    Value(std::int64_t value);
    Value(double value);
    Value(std::string value);
    Value(const char *value);

    bool isNull() const;
    bool isBoolean() const;
    bool isInteger() const;
    bool isReal() const;
    bool isNumber() const;
    bool isString() const;

    bool asBoolean() const;
    std::int64_t asInteger() const;
    double asReal() const;
    const std::string &asString() const;
    std::string typeName() const;
    std::string format() const;
    const Storage &storage() const;

    bool operator==(const Value &other) const;

  private:
    Storage stored;
  };

  class Values {
  public:
    explicit Values(lexicon::Lexicon &lexicon);
    static void setup(lexicon::Phrase root);

    void pushScope();
    void popScope();
    std::size_t scopeDepth() const;

    void define(std::string name, Value value, bool mutableValue = true);
    void assign(std::string_view name, Value value);
    Value get(std::string_view name) const;
    bool contains(std::string_view name) const;

  private:
    lexicon::Lexicon *lexicon;
  };
} // namespace context
