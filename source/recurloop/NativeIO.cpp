#include <recurloop/NativeIO.hpp>
#include <compiler/DynamicLinker.hpp>

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <limits>
#include <ostream>
#include <unistd.h>

namespace recurloop {
  namespace {
    std::ostream *stream(FILE *file) {
      const auto *io = NativeIO::current();
      if (io == nullptr) return nullptr;
      if (file == stdout) return io->out;
      if (file == stderr) return io->err;
      return nullptr;
    }

    bool write(std::ostream &out, const char *data, std::size_t size) {
      try {
        if (size > static_cast<std::size_t>(std::numeric_limits<std::streamsize>::max())) {
          errno = EOVERFLOW;
          return false;
        }
        out.write(data, static_cast<std::streamsize>(size));
        out.flush();
        if (out.good()) return true;
      } catch (...) {}
      errno = EIO;
      return false;
    }

    int formatted(FILE *file, const char *format, va_list args) {
      auto *out = stream(file);
      if (out == nullptr) return std::vfprintf(file, format, args);
      cookie_io_functions_t io{};
      io.write = [](void *cookie, const char *data, std::size_t size) -> ssize_t {
        return write(*static_cast<std::ostream *>(cookie), data, size) ? static_cast<ssize_t>(size) : -1;
      };
      FILE *proxy = fopencookie(out, "w", io);
      if (proxy == nullptr) return -1;
      const int size = std::vfprintf(proxy, format, args);
      const int closed = std::fclose(proxy);
      return closed == 0 ? size : -1;
    }

    int nativePrintf(const char *format, ...) {
      va_list args;
      va_start(args, format);
      const int result = formatted(stdout, format, args);
      va_end(args);
      return result;
    }

    int nativeFprintf(FILE *file, const char *format, ...) {
      va_list args;
      va_start(args, format);
      const int result = formatted(file, format, args);
      va_end(args);
      return result;
    }

    int nativeVprintf(const char *format, va_list args) { return formatted(stdout, format, args); }

    std::size_t nativeFwrite(const void *data, std::size_t size, std::size_t count, FILE *file) {
      auto *out = stream(file);
      if (out == nullptr) return std::fwrite(data, size, count, file);
      if (size == 0 || count == 0) return 0;
      if (count > std::numeric_limits<std::size_t>::max() / size) {
        errno = EOVERFLOW;
        return 0;
      }
      return write(*out, static_cast<const char *>(data), size * count) ? count : 0;
    }

    int nativeFputs(const char *text, FILE *file) {
      auto *out = stream(file);
      if (out == nullptr) return std::fputs(text, file);
      return write(*out, text, std::char_traits<char>::length(text)) ? 1 : EOF;
    }

    int nativePuts(const char *text) {
      auto *out = stream(stdout);
      if (out == nullptr) return std::puts(text);
      return nativeFputs(text, stdout) != EOF && write(*out, "\n", 1) ? 1 : EOF;
    }

    int nativeFputc(int value, FILE *file) {
      auto *out = stream(file);
      if (out == nullptr) return std::fputc(value, file);
      const unsigned char byte = static_cast<unsigned char>(value);
      return write(*out, reinterpret_cast<const char *>(&byte), 1) ? byte : EOF;
    }

    int nativePutchar(int value) { return nativeFputc(value, stdout); }

  } // namespace

  thread_local NativeIO::Scope *NativeIO::active_ = nullptr;

  NativeIO::Scope::Scope(context::IOStreams streams)
      : streams_(streams), process_(getpid()), previous_(active_) { active_ = this; }

  NativeIO::Scope::~Scope() { active_ = previous_; }

  const context::IOStreams *NativeIO::current() {
    // A forked Shell child owns pipe/file descriptors, not the parent's socket.
    return active_ != nullptr && active_->process_ == getpid() ? &active_->streams_ : nullptr;
  }

  void NativeIO::install() {
    auto &linker = compiler::DynamicLinker::instance();
    const auto bind = [&](auto original, auto function) {
      linker.redirectSymbol(reinterpret_cast<std::uintptr_t>(original), reinterpret_cast<std::uintptr_t>(function));
    };
    bind(std::printf, nativePrintf);
    bind(std::fprintf, nativeFprintf);
    bind(std::vprintf, nativeVprintf);
    bind(std::vfprintf, formatted);
    bind(std::puts, nativePuts);
    bind(std::fputs, nativeFputs);
    bind(std::putchar, nativePutchar);
    bind(std::fputc, nativeFputc);
    bind(std::fwrite, nativeFwrite);
  }
} // namespace recurloop
