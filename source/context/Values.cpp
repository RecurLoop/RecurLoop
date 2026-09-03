#include <context/Values.hpp>

#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <cmath>
#include <cstring>
#include <iomanip>
#include <sstream>

namespace context {
  namespace {
    constexpr std::string_view ValueDictionaryName{"\0runtime-values", 15};
    constexpr std::string_view ScopesDictionaryName{"scopes"};
    constexpr std::string_view ActiveScopeName{"active"};

    enum class StoredValue : std::uint8_t { Null, Boolean, Integer, Real, String };

    struct StoredHeader {
      StoredValue type = StoredValue::Null;
      bool mutableValue = true;
      std::uint16_t reserved = 0;
      std::uint32_t bytes = 0;
    };

    std::vector<std::uint8_t> encode(const Value &value, bool mutableValue) {
      StoredHeader header;
      header.mutableValue = mutableValue;
      if (value.isBoolean()) {
        header.type = StoredValue::Boolean;
        header.bytes = sizeof(bool);
      } else if (value.isInteger()) {
        header.type = StoredValue::Integer;
        header.bytes = sizeof(std::int64_t);
      } else if (value.isReal()) {
        header.type = StoredValue::Real;
        header.bytes = sizeof(double);
      } else if (value.isString()) {
        header.type = StoredValue::String;
        header.bytes = value.asString().size();
      }
      std::vector<std::uint8_t> result(sizeof(header) + header.bytes);
      std::memcpy(result.data(), &header, sizeof(header));
      if (value.isBoolean()) {
        const bool stored = value.asBoolean();
        std::memcpy(result.data() + sizeof(header), &stored, sizeof(stored));
      } else if (value.isInteger()) {
        const std::int64_t stored = value.asInteger();
        std::memcpy(result.data() + sizeof(header), &stored, sizeof(stored));
      } else if (value.isReal()) {
        const double stored = value.asReal();
        std::memcpy(result.data() + sizeof(header), &stored, sizeof(stored));
      } else if (value.isString() && header.bytes != 0) {
        std::memcpy(result.data() + sizeof(header), value.asString().data(), header.bytes);
      }
      return result;
    }

    StoredHeader header(lexicon::Phrase &phrase) {
      if (phrase.payloadSize() < sizeof(StoredHeader)) THROW(, "value phrase has a truncated payload")
      StoredHeader result;
      std::memcpy(&result, phrase.content(0, sizeof(result)).toPtr(), sizeof(result));
      if (phrase.payloadSize() != sizeof(result) + result.bytes) THROW(, "value phrase has an invalid payload size")
      return result;
    }

    Value decode(lexicon::Phrase &phrase) {
      const StoredHeader stored = header(phrase);
      const Byte payload = phrase.content(sizeof(stored), stored.bytes);
      switch (stored.type) {
      case StoredValue::Null: return {};
      case StoredValue::Boolean: {
        if (stored.bytes != sizeof(bool)) THROW(, "boolean value phrase has an invalid payload")
        bool value;
        std::memcpy(&value, payload.toPtr(), sizeof(value));
        return Value(value);
      }
      case StoredValue::Integer: {
        if (stored.bytes != sizeof(std::int64_t)) THROW(, "integer value phrase has an invalid payload")
        std::int64_t value;
        std::memcpy(&value, payload.toPtr(), sizeof(value));
        return Value(value);
      }
      case StoredValue::Real: {
        if (stored.bytes != sizeof(double)) THROW(, "real value phrase has an invalid payload")
        double value;
        std::memcpy(&value, payload.toPtr(), sizeof(value));
        return Value(value);
      }
      case StoredValue::String:
        return Value(std::string(reinterpret_cast<const char *>(payload.toPtr()), stored.bytes));
      }
      THROW(, "value phrase has an unknown type")
    }

    lexicon::Phrase exact(lexicon::Phrase &dictionary, std::string_view name) {
      lexicon::Match match = dictionary.matchExact(
          Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length,
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
      return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
    }

    lexicon::Phrase saveBinding(lexicon::Phrase &scope, std::string_view name, const Value &value, bool mutableValue) {
      lexicon::Phrase phrase = scope.append(std::string(name)).make().setType(scope.getType()).save();
      const std::vector<std::uint8_t> payload = encode(value, mutableValue);
      Byte output = phrase.allocate(payload.size());
      if (!payload.empty()) std::memcpy(output.toPtr(), payload.data(), payload.size());
      return phrase.save();
    }

    lexicon::Phrase dictionary(lexicon::Phrase &parent, std::string_view name) {
      lexicon::Phrase found = exact(parent, name);
      if (!found.isNull()) return found;
      return parent.append(std::string(name))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(parent))
          .save();
    }

    lexicon::Phrase valuesRoot(lexicon::Lexicon &lexicon) {
      lexicon::Phrase root = lexicon.phrase();
      lexicon::Phrase result = exact(root, ValueDictionaryName);
      if (result.isNull()) THROW(, "runtime value phrases are not initialized")
      return result;
    }

    lexicon::Phrase activeScope(lexicon::Lexicon &lexicon) {
      lexicon::Phrase root = valuesRoot(lexicon);
      lexicon::Phrase active = exact(root, ActiveScopeName);
      if (active.isNull() || !active.containsPrototype()) THROW(, "runtime value scope is not initialized")
      return active.getPrototype();
    }

    void activate(lexicon::Phrase &root, lexicon::Phrase scope) {
      root.append(std::string(ActiveScopeName))
          .make()
          .setPrototype(scope)
          .setType(lexicon::phrase::type::getData(root))
          .save();
    }
  } // namespace

  Value::Value(bool value) : stored(value) {}
  Value::Value(std::int64_t value) : stored(value) {}
  Value::Value(double value) : stored(value) {}
  Value::Value(std::string value) : stored(std::move(value)) {}
  Value::Value(const char *value) : stored(std::string(value)) {}

  bool Value::isNull() const {
    return std::holds_alternative<std::monostate>(stored);
  }
  bool Value::isBoolean() const {
    return std::holds_alternative<bool>(stored);
  }
  bool Value::isInteger() const {
    return std::holds_alternative<std::int64_t>(stored);
  }
  bool Value::isReal() const {
    return std::holds_alternative<double>(stored);
  }
  bool Value::isNumber() const {
    return isInteger() || isReal();
  }
  bool Value::isString() const {
    return std::holds_alternative<std::string>(stored);
  }

  bool Value::asBoolean() const {
    if (!isBoolean()) THROW(, "value has type '" << typeName() << "', expected 'bool'")
    return std::get<bool>(stored);
  }

  std::int64_t Value::asInteger() const {
    if (!isInteger()) THROW(, "value has type '" << typeName() << "', expected 'int'")
    return std::get<std::int64_t>(stored);
  }

  double Value::asReal() const {
    if (isInteger()) return static_cast<double>(std::get<std::int64_t>(stored));
    if (!isReal()) THROW(, "value has type '" << typeName() << "', expected a number")
    return std::get<double>(stored);
  }

  const std::string &Value::asString() const {
    if (!isString()) THROW(, "value has type '" << typeName() << "', expected 'string'")
    return std::get<std::string>(stored);
  }

  std::string Value::typeName() const {
    if (isNull()) return "null";
    if (isBoolean()) return "bool";
    if (isInteger()) return "int";
    if (isReal()) return "real";
    return "string";
  }

  std::string Value::format() const {
    if (isNull()) return "null";
    if (isBoolean()) return std::get<bool>(stored) ? "true" : "false";
    if (isInteger()) return std::to_string(std::get<std::int64_t>(stored));
    if (isString()) return std::get<std::string>(stored);
    const double number = std::get<double>(stored);
    if (!std::isfinite(number)) THROW(, "cannot format a non-finite real value")
    std::ostringstream output;
    output << std::setprecision(15) << number;
    return output.str();
  }

  const Value::Storage &Value::storage() const {
    return stored;
  }

  bool Value::operator==(const Value &other) const {
    if (isInteger() && other.isInteger()) return asInteger() == other.asInteger();
    if (isNumber() && other.isNumber()) return asReal() == other.asReal();
    return stored == other.stored;
  }

  Values::Values(lexicon::Lexicon &lexicon) : lexicon(&lexicon) {}

  void Values::setup(lexicon::Phrase root) {
    lexicon::Phrase values = dictionary(root, ValueDictionaryName);
    lexicon::Phrase scopes = dictionary(values, ScopesDictionaryName);
    lexicon::Phrase global = dictionary(scopes, "global");
    activate(values, global);
  }

  void Values::pushScope() {
    lexicon::Phrase values = valuesRoot(*lexicon);
    lexicon::Phrase scopes = exact(values, ScopesDictionaryName);
    lexicon::Phrase parent = activeScope(*lexicon);
    lexicon::Phrase scope =
        scopes.append("").make().enableSubdictionary().setPrototype(parent).setType(parent.getType()).save();
    activate(values, scope);
  }

  void Values::popScope() {
    lexicon::Phrase values = valuesRoot(*lexicon);
    lexicon::Phrase scope = activeScope(*lexicon);
    lexicon::Phrase parent = scope.getPrototype();
    if (parent.isNull()) THROW(, "cannot pop the global value scope")
    activate(values, parent);
  }

  std::size_t Values::scopeDepth() const {
    std::size_t result = 1;
    for (lexicon::Phrase scope = activeScope(*lexicon); !scope.getPrototype().isNull(); scope = scope.getPrototype())
      ++result;
    return result;
  }

  void Values::define(std::string name, Value value, bool mutableValue) {
    if (name.empty()) THROW(, "variable name cannot be empty")
    lexicon::Phrase scope = activeScope(*lexicon);
    if (!exact(scope, name).isNull()) THROW(, "variable is already defined in this scope: '" << name << "'")
    saveBinding(scope, name, value, mutableValue);
  }

  void Values::assign(std::string_view name, Value value) {
    for (lexicon::Phrase scope = activeScope(*lexicon); !scope.isNull(); scope = scope.getPrototype()) {
      lexicon::Phrase found = exact(scope, name);
      if (found.isNull()) continue;
      if (!header(found).mutableValue) THROW(, "cannot assign to constant: '" << name << "'")
      saveBinding(scope, name, value, true);
      return;
    }
    THROW(, "undefined variable: '" << name << "'")
  }

  Value Values::get(std::string_view name) const {
    for (lexicon::Phrase scope = activeScope(*lexicon); !scope.isNull(); scope = scope.getPrototype()) {
      lexicon::Phrase found = exact(scope, name);
      if (!found.isNull()) return decode(found);
    }
    THROW(, "undefined variable: '" << name << "'")
  }

  bool Values::contains(std::string_view name) const {
    for (lexicon::Phrase scope = activeScope(*lexicon); !scope.isNull(); scope = scope.getPrototype())
      if (!exact(scope, name).isNull()) return true;
    return false;
  }
} // namespace context
