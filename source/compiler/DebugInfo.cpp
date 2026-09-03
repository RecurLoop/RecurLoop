#include <compiler/DebugInfo.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <limits>
#include <type_traits>

namespace compiler {
  namespace {
    constexpr std::uint64_t ModuleRecordMagic = 0x314D4742444C52ull; // RLDBGM1
    constexpr std::uint64_t ExecutableMagic = 0x31454742444C52ull;   // RLDBGE1
    constexpr std::uint64_t ExecutableFooter = 0x31464742444C52ull;  // RLDBGF1
    constexpr std::uint32_t Version = 1;

    class Writer {
    public:
      template <typename Type> void number(Type value) {
        static_assert(std::is_integral_v<Type>);
        for (std::size_t index = 0; index < sizeof(Type); ++index)
          bytes.push_back(static_cast<std::uint8_t>(value >> (index * 8)));
      }

      void text(std::string_view value) {
        if (value.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "debug string is too large")
        number(static_cast<std::uint32_t>(value.size()));
        bytes.insert(bytes.end(), value.begin(), value.end());
      }

      std::vector<std::uint8_t> bytes;
    };

    class Reader {
    public:
      explicit Reader(std::span<const std::uint8_t> bytes) : bytes(bytes) {}

      template <typename Type> Type number() {
        static_assert(std::is_integral_v<Type>);
        require(sizeof(Type));
        Type result = 0;
        for (std::size_t index = 0; index < sizeof(Type); ++index)
          result |= static_cast<Type>(bytes[cursor++]) << (index * 8);
        return result;
      }

      std::string text() {
        const std::uint32_t size = number<std::uint32_t>();
        require(size);
        const char *data = reinterpret_cast<const char *>(bytes.data() + cursor);
        cursor += size;
        return std::string(data, size);
      }

      std::span<const std::uint8_t> take(std::size_t size) {
        require(size);
        const std::span<const std::uint8_t> result = bytes.subspan(cursor, size);
        cursor += size;
        return result;
      }

      bool done() const {
        return cursor == bytes.size();
      }
      std::size_t remaining() const {
        return bytes.size() - cursor;
      }

    private:
      void require(std::size_t size) const {
        if (size > bytes.size() - cursor) THROW(, "RecurLoop debug metadata is truncated")
      }

      std::span<const std::uint8_t> bytes;
      std::size_t cursor = 0;
    };

    void writePoint(Writer &writer, const DebugPoint &point, bool resolved) {
      writer.number(resolved ? point.address : point.offset);
      writer.number(point.line);
      writer.number(point.column);
      writer.text(resolved ? std::string_view{} : std::string_view(point.symbol));
      writer.text(point.path);
      writer.text(point.function);
      writer.text(point.phrase);
      if (point.locals.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "too many debug locals")
      writer.number(static_cast<std::uint32_t>(point.locals.size()));
      for (const DebugLocal &local : point.locals) {
        writer.text(local.name);
        writer.text(local.type);
        writer.number(local.frameOffset);
        writer.number(local.size);
        writer.number(local.kind);
        writer.number(static_cast<std::uint8_t>(local.signedValue));
      }
    }

    DebugPoint readPoint(Reader &reader, bool resolved) {
      constexpr std::size_t MinimumLocalBytes = sizeof(std::uint32_t) * 2 + sizeof(std::uint64_t) +
                                                sizeof(std::uint32_t) + sizeof(std::uint8_t) * 2;
      DebugPoint point;
      if (resolved)
        point.address = reader.number<std::uint64_t>();
      else
        point.offset = reader.number<std::uint64_t>();
      point.line = reader.number<std::uint64_t>();
      point.column = reader.number<std::uint64_t>();
      point.symbol = reader.text();
      point.path = reader.text();
      point.function = reader.text();
      point.phrase = reader.text();
      const std::uint32_t count = reader.number<std::uint32_t>();
      if (count > reader.remaining() / MinimumLocalBytes) THROW(, "invalid RecurLoop debug local count")
      point.locals.reserve(count);
      for (std::uint32_t index = 0; index < count; ++index) {
        DebugLocal local;
        local.name = reader.text();
        local.type = reader.text();
        local.frameOffset = reader.number<std::uint64_t>();
        local.size = reader.number<std::uint32_t>();
        local.kind = reader.number<std::uint8_t>();
        local.signedValue = reader.number<std::uint8_t>() != 0;
        point.locals.push_back(std::move(local));
      }
      return point;
    }
  } // namespace

  void DebugInfo::add(Module &module, const DebugPoint &point) {
    Writer payload;
    writePoint(payload, point, false);
    Writer record;
    record.number(ModuleRecordMagic);
    record.number(Version);
    if (payload.bytes.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "debug record is too large")
    record.number(static_cast<std::uint32_t>(payload.bytes.size()));
    record.bytes.insert(record.bytes.end(), payload.bytes.begin(), payload.bytes.end());
    const SectionId *section = module.findSection(SectionName);
    const SectionId id =
        section == nullptr ? module.addSection(std::string(SectionName), SectionType::ProgramBits, SectionFlag::None, 1)
                           : *section;
    module.append(id, record.bytes);
  }

  std::vector<DebugPoint> DebugInfo::readModule(const Module &module) {
    const SectionId *id = module.findSection(SectionName);
    if (id == nullptr) return {};
    Reader input(module.section(*id).bytes);
    std::vector<DebugPoint> result;
    while (!input.done()) {
      if (input.number<std::uint64_t>() != ModuleRecordMagic) THROW(, "invalid RecurLoop module debug magic")
      if (input.number<std::uint32_t>() != Version) THROW(, "unsupported RecurLoop module debug version")
      Reader record(input.take(input.number<std::uint32_t>()));
      result.push_back(readPoint(record, false));
      if (!record.done()) THROW(, "RecurLoop module debug record has trailing bytes")
    }
    return result;
  }

  void DebugInfo::appendExecutable(std::vector<std::uint8_t> &executable, const Module &module,
                                   const SymbolResolver &resolve) {
    std::vector<DebugPoint> points = readModule(module);
    if (points.empty()) return;
    Writer payload;
    payload.number(ExecutableMagic);
    payload.number(Version);
    if (points.size() > std::numeric_limits<std::uint32_t>::max()) THROW(, "too many executable debug points")
    payload.number(static_cast<std::uint32_t>(points.size()));
    for (DebugPoint &point : points) {
      const std::optional<std::uint64_t> symbol = resolve(point.symbol);
      if (!symbol) THROW(, "debug point refers to an unresolved symbol: '" << point.symbol << "'")
      if (point.offset > std::numeric_limits<std::uint64_t>::max() - *symbol)
        THROW(, "debug point address overflows for symbol: '" << point.symbol << "'")
      point.address = *symbol + point.offset;
      writePoint(payload, point, true);
    }
    executable.insert(executable.end(), payload.bytes.begin(), payload.bytes.end());
    Writer footer;
    footer.number(static_cast<std::uint64_t>(payload.bytes.size()));
    footer.number(ExecutableFooter);
    executable.insert(executable.end(), footer.bytes.begin(), footer.bytes.end());
  }

  std::vector<DebugPoint> DebugInfo::readExecutable(std::span<const std::uint8_t> executable) {
    constexpr std::size_t FooterBytes = sizeof(std::uint64_t) * 2;
    if (executable.size() < FooterBytes) THROW(, "executable has no RecurLoop debug metadata")
    Reader footer(executable.last(FooterBytes));
    const std::uint64_t payloadBytes = footer.number<std::uint64_t>();
    if (footer.number<std::uint64_t>() != ExecutableFooter || payloadBytes > executable.size() - FooterBytes)
      THROW(, "executable has no RecurLoop debug metadata")
    Reader input(executable.subspan(executable.size() - FooterBytes - payloadBytes, payloadBytes));
    if (input.number<std::uint64_t>() != ExecutableMagic) THROW(, "invalid RecurLoop executable debug magic")
    if (input.number<std::uint32_t>() != Version) THROW(, "unsupported RecurLoop executable debug version")
    const std::uint32_t count = input.number<std::uint32_t>();
    constexpr std::size_t MinimumPointBytes = sizeof(std::uint64_t) * 3 + sizeof(std::uint32_t) * 5;
    if (count > input.remaining() / MinimumPointBytes) THROW(, "invalid RecurLoop executable debug point count")
    std::vector<DebugPoint> result;
    result.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index) result.push_back(readPoint(input, true));
    if (!input.done()) THROW(, "RecurLoop executable debug metadata has trailing bytes")
    std::sort(result.begin(), result.end(), [](const DebugPoint &left, const DebugPoint &right) {
      if (left.address != right.address) return left.address < right.address;
      if (left.path != right.path) return left.path < right.path;
      return left.line < right.line;
    });
    return result;
  }
} // namespace compiler
