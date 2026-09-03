#pragma once

#include <exception>
#include <cstddef>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>

#include <utilities/Console.hpp>

#if defined(NDEBUG)
  #define EXCEPTION_RENDER()                                                                                           \
    std::ostringstream oss;                                                                                            \
    oss << description;                                                                                                \
    message = oss.str();
#else
  #define EXCEPTION_RENDER()                                                                                           \
    std::ostringstream oss;                                                                                            \
    oss << description << std::endl;                                                                                   \
    oss << BRIGHT_MAGENTA_TEXT << "[" << getHierarchy() << "]" << RESET << " " << file << ":" << line << " @ "         \
        << function;                                                                                                   \
    message = oss.str();
#endif

class Exception : public std::exception {
public:
  Exception(const std::string &file = "?", const int line = -1, const std::string &function = "?",
            const std::string &description = "") {
    descriptionText = description;
    EXCEPTION_RENDER()
  }

  virtual ~Exception() noexcept {}

  const int status() const noexcept {
    return ret;
  }

  const char *what() const noexcept {
    return message.c_str();
  }

  virtual bool hasSourceLocation() const noexcept {
    return false;
  }

  const std::string &description() const noexcept {
    return descriptionText;
  }

protected:
  static std::string getHierarchy() {
    return "Exception";
  }

  int ret = 1;
  std::string descriptionText;
  std::string message;
};

struct SourceLocation {
  std::string path;
  std::size_t line = 1;
  std::size_t column = 1;
};

inline SourceLocation sourceLocationAt(SourceLocation location, std::string_view source, std::size_t offset) {
  if (location.path.empty()) location.path = "<input>";
  if (location.line == 0) location.line = 1;
  if (location.column == 0) location.column = 1;
  if (offset > source.size()) offset = source.size();

  for (std::size_t cursor = 0; cursor < offset;) {
    const unsigned char character = static_cast<unsigned char>(source[cursor]);
    if (character == '\n') {
      ++location.line;
      location.column = 1;
      ++cursor;
      continue;
    }

    // Continuation bytes do not occupy an additional display column. This
    // keeps diagnostics aligned for UTF-8 source without making error
    // reporting depend on the process locale.
    if ((character & 0xc0u) != 0x80u) ++location.column;
    ++cursor;
  }
  return location;
}

class SourceException : public Exception {
public:
  SourceException(const std::string &file, int internalLine, const std::string &function, SourceLocation location,
                  const std::string &description)
      : Exception(file, internalLine, function, render(std::move(location), description)) {}

  bool hasSourceLocation() const noexcept override {
    return true;
  }

private:
  static std::string render(SourceLocation location, const std::string &description) {
    if (location.path.empty()) location.path = "<input>";
    if (location.line == 0) location.line = 1;
    if (location.column == 0) location.column = 1;
    std::ostringstream stream;
    stream << location.path << ':' << location.line << ':' << location.column << ": " << description;
    return stream.str();
  }
};

#define EXCEPTION(Base, New)                                                                                           \
  class New##Exception : public Base##Exception {                                                                      \
  public:                                                                                                              \
    New##Exception(const std::string &file = "?", const int line = -1, const std::string &function = "?",              \
                   const std::string &description = "") {                                                              \
      descriptionText = description;                                                                                  \
      EXCEPTION_RENDER();                                                                                              \
    }                                                                                                                  \
                                                                                                                       \
  protected:                                                                                                           \
    static std::string getHierarchy() {                                                                                \
      return Base##Exception::getHierarchy() + " => " + #New;                                                          \
    }                                                                                                                  \
  }

#define THROW(ExceptionClass, Message, ...)                                                                            \
  {                                                                                                                    \
    std::ostringstream oss;                                                                                            \
    oss << Message;                                                                                                    \
    throw(ExceptionClass##Exception(__FILE__, __LINE__, __PRETTY_FUNCTION__, oss.str(), ##__VA_ARGS__));               \
  }

#define THROW_AT(Location, Message)                                                                                    \
  {                                                                                                                    \
    std::ostringstream oss;                                                                                            \
    oss << Message;                                                                                                    \
    throw(SourceException(__FILE__, __LINE__, __PRETTY_FUNCTION__, Location, oss.str()));                              \
  }
