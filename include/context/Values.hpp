#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <unordered_map>
#include <vector>
#include <utilities/Size.hpp>

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
    struct Binding {
      std::string name;
      Value value;
      bool mutableValue = true;
      bool knownValue = true;
    };
    using Bindings = std::unordered_map<std::string, Binding>;
    struct ScopeFrame {
      Size checkpoint = 0, scope = 0, marker = 0;
    };
    explicit Values(lexicon::Lexicon &lexicon, std::vector<ScopeFrame> *frames = nullptr);
    static void setup(lexicon::Phrase root);

    void pushScope();
    void popScope();
    std::size_t scopeDepth() const;

    void define(std::string name, Value value, bool mutableValue = true);
    void assign(std::string_view name, Value value);
    Value get(std::string_view name) const;
    std::optional<Binding> find(std::string_view name, std::string_view scope = {},
                                const Bindings *overlay = nullptr) const;
    bool contains(std::string_view name) const;

  private:
    lexicon::Lexicon *lexicon;
    std::vector<ScopeFrame> *frames;
  };
} // namespace context
