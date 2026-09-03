#include <compiler/ArchiveReader.hpp>

#include <compiler/ElfReader.hpp>
#include <utilities/Exception.hpp>

#include <charconv>
#include <cstring>
#include <string>

namespace compiler {
  namespace {
    constexpr std::string_view MAGIC = "!<arch>\n";
    constexpr std::size_t HEADER_SIZE = 60;

    std::string trim(std::string_view value) {
      while (!value.empty() && value.back() == ' ') value.remove_suffix(1);
      return std::string(value);
    }

    std::size_t decimal(std::string_view value, std::string_view origin, std::string_view description) {
      while (!value.empty() && value.front() == ' ') value.remove_prefix(1);
      while (!value.empty() && value.back() == ' ') value.remove_suffix(1);
      std::size_t result = 0;
      const auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), result);
      if (value.empty() || error != std::errc() || end != value.data() + value.size())
        THROW(, "archive '" << origin << "' has an invalid " << description)
      return result;
    }

    std::string gnuLongName(std::string_view table, std::size_t offset, std::string_view origin) {
      if (offset >= table.size()) THROW(, "archive '" << origin << "' has an invalid long-name offset")
      std::size_t end = table.find("/\n", offset);
      if (end == std::string_view::npos) end = table.find('\n', offset);
      if (end == std::string_view::npos) THROW(, "archive '" << origin << "' has an unterminated long name")
      return std::string(table.substr(offset, end - offset));
    }
  } // namespace

  Module ArchiveMember::load() const { return ElfReader::read(bytes, origin); }

  std::vector<ArchiveMember> ArchiveReader::read(std::span<const std::uint8_t> bytes, std::string_view origin) {
    if (bytes.size() < MAGIC.size() ||
        std::memcmp(bytes.data(), reinterpret_cast<const std::uint8_t *>(MAGIC.data()), MAGIC.size()) != 0)
      THROW(, "file '" << origin << "' is not a regular Unix archive")

    std::vector<ArchiveMember> result;
    std::string longNames;
    std::size_t cursor = MAGIC.size();
    while (cursor < bytes.size()) {
      if (cursor + HEADER_SIZE > bytes.size()) THROW(, "archive '" << origin << "' has a truncated member header")
      const char *header = reinterpret_cast<const char *>(bytes.data() + cursor);
      if (std::string_view(header + 58, 2) != "`\n")
        THROW(, "archive '" << origin << "' has an invalid member header")
      std::string name = trim(std::string_view(header, 16));
      const std::size_t storedSize = decimal(std::string_view(header + 48, 10), origin, "member size");
      cursor += HEADER_SIZE;
      if (storedSize > bytes.size() - cursor) THROW(, "archive '" << origin << "' has a truncated member")
      std::span<const std::uint8_t> contents = bytes.subspan(cursor, storedSize);

      if (name == "//") {
        longNames.assign(reinterpret_cast<const char *>(contents.data()), contents.size());
      } else if (name == "/" || name == "/SYM64/") {
        // GNU symbol indices are an optimization; lazy extraction below uses
        // the parsed member symbol tables and does not depend on them.
      } else {
        if (name.starts_with("#1/")) {
          const std::size_t nameBytes = decimal(std::string_view(name).substr(3), origin, "BSD name length");
          if (nameBytes > contents.size()) THROW(, "archive '" << origin << "' has a truncated BSD member name")
          name.assign(reinterpret_cast<const char *>(contents.data()), nameBytes);
          contents = contents.subspan(nameBytes);
        } else if (name.starts_with('/') && name.size() > 1) {
          if (longNames.empty()) THROW(, "archive '" << origin << "' references a missing long-name table")
          const std::size_t offset = decimal(std::string_view(name).substr(1), origin, "long-name offset");
          name = gnuLongName(longNames, offset, origin);
        } else if (name.ends_with('/')) {
          name.pop_back();
        }
        if (name.empty()) THROW(, "archive '" << origin << "' has a member without a name")
        const std::string memberOrigin = std::string(origin) + "(" + name + ")";
        std::vector<std::uint8_t> memberBytes(contents.begin(), contents.end());
        std::vector<std::string> definitions = ElfReader::definitions(memberBytes, memberOrigin);
        result.push_back({std::move(name), memberOrigin, std::move(memberBytes), std::move(definitions)});
      }

      cursor += storedSize;
      if ((cursor & 1u) != 0) {
        if (cursor >= bytes.size()) THROW(, "archive '" << origin << "' is missing member padding")
        ++cursor;
      }
    }
    return result;
  }
} // namespace compiler
