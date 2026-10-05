#include <recurloop/Server.hpp>
#include <recurloop/ProcessControl.hpp>
#include <poll.h>
#include <future>
#include <chrono>
#include <utilities/LineEditor.hpp>
#include <utilities/Prompt.hpp>

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cctype>
#include <csignal>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <array>
#include <algorithm>
#include <streambuf>
#include <charconv>
#include <sstream>

namespace recurloop {
  namespace {
    constexpr std::string_view streamHandshake = ":transport-stream-v1";
    constexpr std::string_view statusStreamHandshake = ":transport-stream-v2";

    bool sendBytes(int fd, std::string_view text) {
      while (!text.empty()) {
        const ssize_t written = send(fd, text.data(), text.size(), MSG_NOSIGNAL);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return false;
        text.remove_prefix(static_cast<std::size_t>(written));
      }
      return true;
    }

    // Streaming clients use length-delimited output and an explicit completion
    // frame. Output containing the prompt text must never finish a command.
    bool sendFrame(int fd, char kind, std::string_view text) {
      const auto size = static_cast<std::uint32_t>(text.size());
      const char header[] = {kind, static_cast<char>(size >> 24), static_cast<char>(size >> 16),
                             static_cast<char>(size >> 8), static_cast<char>(size)};
      return sendBytes(fd, {header, sizeof(header)}) && sendBytes(fd, text);
    }

    class SocketOutput : public std::streambuf {
    public:
      SocketOutput(int fd, bool framed) : fd_(fd), framed_(framed) {}

    protected:
      std::streamsize xsputn(const char *data, std::streamsize size) override {
        std::streamsize written = 0;
        while (written < size) {
          const auto count = std::min<std::streamsize>(size - written, 4096);
          const std::string_view chunk(data + written, static_cast<std::size_t>(count));
          if (!(framed_ ? sendFrame(fd_, 'O', chunk) : sendBytes(fd_, chunk))) break;
          written += count;
        }
        return written;
      }

      int_type overflow(int_type value) override {
        if (traits_type::eq_int_type(value, traits_type::eof())) return traits_type::not_eof(value);
        const char byte = traits_type::to_char_type(value);
        return xsputn(&byte, 1) == 1 ? value : traits_type::eof();
      }

    private:
      int fd_;
      bool framed_;
    };

    class ConsoleFrames {
    public:
      explicit ConsoleFrames(utilities::LineEditor::Writer writer = [](std::string_view text) {
        return utilities::LineEditor::writeDescriptor(STDOUT_FILENO, text);
      }) : writer_(std::move(writer)) {}

      bool consume(std::string_view bytes) {
        while (!bytes.empty()) {
          if (remaining_ == 0) {
            const auto count = std::min(bytes.size(), header_.size() - headerSize_);
            std::memcpy(header_.data() + headerSize_, bytes.data(), count);
            headerSize_ += count;
            bytes.remove_prefix(count);
            if (headerSize_ != header_.size()) return true;
            remaining_ = (std::uint32_t(header_[1]) << 24) | (std::uint32_t(header_[2]) << 16) |
                         (std::uint32_t(header_[3]) << 8) | std::uint32_t(header_[4]);
            headerSize_ = 0;
            if (header_[0] == 'P' && remaining_ == 0) {
              completed = true;
              return bytes.empty();
            }
            if ((header_[0] != 'O' && header_[0] != 'S') || remaining_ == 0 || remaining_ > 4096) return false;
            if (header_[0] == 'S') statusText_.clear();
          }
          const auto count = std::min<std::size_t>(remaining_, bytes.size());
          if (header_[0] == 'S')
            statusText_.append(bytes.substr(0, count));
          else if (!writer_(bytes.substr(0, count)))
            return false;
          remaining_ -= count;
          if (header_[0] == 'S' && remaining_ == 0) {
            const auto parsed = std::from_chars(statusText_.data(), statusText_.data() + statusText_.size(), status);
            if (parsed.ec != std::errc{} || parsed.ptr != statusText_.data() + statusText_.size()) return false;
          }
          bytes.remove_prefix(count);
        }
        return true;
      }

      bool completed = false;
      int status = 0;

    private:
      utilities::LineEditor::Writer writer_;
      std::array<std::uint8_t, 5> header_{};
      std::size_t headerSize_ = 0;
      std::uint32_t remaining_ = 0;
      std::string statusText_;
    };

    class IgnoreInteractiveInterrupt {
    public:
      IgnoreInteractiveInterrupt() {
        struct sigaction ignored{};
        ignored.sa_handler = SIG_IGN;
        sigemptyset(&ignored.sa_mask);
        active_ = sigaction(SIGINT, &ignored, &previous_) == 0;
      }

      ~IgnoreInteractiveInterrupt() {
        if (active_) sigaction(SIGINT, &previous_, nullptr);
      }

    private:
      struct sigaction previous_{};
      bool active_ = false;
    };

    std::string trimLine(std::string line) {
      while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
      return line;
    }

    std::string_view trim(std::string_view value) {
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) value.remove_prefix(1);
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) value.remove_suffix(1);
      return value;
    }

    unsigned hexNibble(char value) {
      if (value >= '0' && value <= '9') return static_cast<unsigned>(value - '0');
      if (value >= 'a' && value <= 'f') return static_cast<unsigned>(value - 'a' + 10);
      if (value >= 'A' && value <= 'F') return static_cast<unsigned>(value - 'A' + 10);
      THROW(, "invalid hexadecimal server payload")
    }

    std::string unhex(std::string_view value) {
      if ((value.size() & 1u) != 0) THROW(, "invalid hexadecimal server payload length")
      std::string result(value.size() / 2, '\0');
      for (std::size_t i = 0; i < result.size(); ++i)
        result[i] = static_cast<char>((hexNibble(value[i * 2]) << 4) | hexNibble(value[i * 2 + 1]));
      return result;
    }

    std::string hex(std::string_view text) {
      constexpr char digits[] = "0123456789abcdef";
      std::string result;
      result.reserve(text.size() * 2);
      for (unsigned char byte : text) {
        result += digits[byte >> 4];
        result += digits[byte & 15];
      }
      return result;
    }

    bool parseSize(std::string_view text, std::size_t &value) {
      const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
      return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
    }

    bool consoleIntegration() {
      const char *program = std::getenv("TERM_PROGRAM");
      return program && std::string_view(program) == "vscode" && isatty(STDIN_FILENO) && isatty(STDOUT_FILENO);
    }

    void consoleStatus(bool integration, int status) {
      if (integration)
        utilities::LineEditor::writeDescriptor(STDOUT_FILENO, "\x1b]633;D;" + std::to_string(status) + "\x07");
    }

    utilities::LineEditor::Highlighter consoleHighlighter(std::function<std::string(std::string_view)> inspect) {
      const char *noColor = std::getenv("NO_COLOR");
      if (noColor && *noColor) return {};
      return [inspect = std::move(inspect)](std::string_view source) {
        std::vector<utilities::LineEditor::ColorSpan> result;
        if (source.empty() || source.size() > 8192) return result;
        // Inspection spans count Unicode code points; rendering uses byte offsets.
        std::vector<std::size_t> offsets;
        for (std::size_t index = 0; index < source.size(); ++index)
          if ((static_cast<unsigned char>(source[index]) & 0xc0) != 0x80) offsets.push_back(index);
        offsets.push_back(source.size());
        std::istringstream input(inspect(source));
        std::string line;
        while (std::getline(input, line)) {
          if (!line.starts_with("S\t")) continue;
          std::istringstream fields(line);
          std::string kind, beginText, endText, group, colorText;
          if (!std::getline(fields, kind, '\t') || !std::getline(fields, beginText, '\t') ||
              !std::getline(fields, endText, '\t') || !std::getline(fields, group, '\t') ||
              !std::getline(fields, colorText, '\t'))
            continue;
          std::size_t begin = 0, end = 0;
          if (!parseSize(beginText, begin) || !parseSize(endText, end) || begin >= end || begin >= offsets.size() - 1)
            continue;
          if (end >= offsets.size()) continue;
          const auto color = unhex(colorText);
          if (color.size() != 7 || color[0] != '#') continue;
          unsigned rgb = 0;
          const auto parsed = std::from_chars(color.data() + 1, color.data() + 7, rgb, 16);
          if (parsed.ec == std::errc{} && parsed.ptr == color.data() + 7)
            result.push_back({offsets[begin], offsets[end], rgb});
        }
        return result;
      };
    }

    std::string remoteHighlight(int fd, std::string_view line) {
      if (!sendBytes(fd, ":highlight\t" + hex(line) + '\n')) return {};
      std::string payload;
      ConsoleFrames response([&](std::string_view bytes) {
        payload += bytes;
        return true;
      });
      char bytes[4096];
      while (!response.completed) {
        const ssize_t count = recv(fd, bytes, sizeof(bytes), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0 || !response.consume({bytes, static_cast<std::size_t>(count)})) return {};
      }
      return payload;
    }

    utilities::Completion remoteCompletion(int fd, std::string_view line, std::size_t cursor) {
      if (!sendBytes(fd, ":complete\t" + std::to_string(cursor) + '\t' + hex(line) + '\n')) return {};
      std::string payload;
      ConsoleFrames response([&](std::string_view bytes) { payload += bytes; return true; });
      char bytes[4096];
      while (!response.completed) {
        const ssize_t count = recv(fd, bytes, sizeof(bytes), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0 || !response.consume({bytes, static_cast<std::size_t>(count)})) return {};
      }
      utilities::Completion result;
      std::istringstream input(payload);
      std::string field;
      if (!std::getline(input, field) || !field.starts_with("completion\t") ||
          !parseSize(std::string_view(field).substr(11), result.start) || result.start > cursor) return {};
      try {
        while (std::getline(input, field)) result.candidates.push_back(unhex(field));
      } catch (...) {
        return {};
      }
      return result;
    }

    bool languageExit(std::string_view line) {
      line = trim(line);
      return line == "exit" ||
             (line.size() > 4 && line.substr(0, 4) == "exit" && std::isspace(static_cast<unsigned char>(line[4])));
    }

    bool connectSocket(int fd, const std::string &path) {
      sockaddr_un address{};
      address.sun_family = AF_UNIX;
      if (path.size() >= sizeof(address.sun_path)) return false;
      std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
      return connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0;
    }

    bool receiveUntilPrompt(int fd, std::string &text) {
      constexpr std::string_view prompt = utilities::prompt::Default;
      char buffer[4096];
      while (true) {
        const ssize_t bytes = recv(fd, buffer, sizeof(buffer), 0);
        if (bytes < 0) {
          if (errno == EINTR) continue;
          return false;
        }
        if (bytes == 0) return false;
        text.append(buffer, static_cast<std::size_t>(bytes));
        if (text.size() >= prompt.size() && std::string_view(text).ends_with(prompt)) {
          text.resize(text.size() - prompt.size());
          return true;
        }
      }
    }
  } // namespace

  Server::~Server() {
    stop();
    const int listener = listener_.exchange(-1);
    if (listener >= 0) close(listener);
    reapClients(true);
    if (!options_.unixPath.empty()) unlink(options_.unixPath.c_str());
  }

  void Server::stop() noexcept {
    stopping_ = true;
    const int listener = listener_.load();
    if (listener >= 0) shutdown(listener, SHUT_RDWR);
    std::lock_guard lock(clientsMutex_);
    for (int fd : clientFds_) shutdown(fd, SHUT_RDWR);
  }

  Server::CommandResult Server::handle(Session &session, std::string_view line, std::ostream *out, std::ostream *err) {
    try {
      constexpr std::string_view loadFilePrefix = ":load-file\t";
      constexpr std::string_view inspectPrefix = ":inspect\t";
      constexpr std::string_view tracePrefix = ":trace\t";
      constexpr std::string_view inspectFilePrefix = ":inspect-file\t";
      constexpr std::string_view traceFilePrefix = ":trace-file\t";
      if (line.starts_with(":highlight\t")) {
        return {session.highlight(unhex(line.substr(11))), false, 0};
      }
      if (line.starts_with(":complete\t")) {
        const std::string_view payload = line.substr(10);
        const auto separator = payload.find('\t');
        std::size_t cursor = 0;
        if (separator == std::string_view::npos || !parseSize(payload.substr(0, separator), cursor))
          return {"completion requires a cursor and source payload\n", false, 1};
        const std::string source = unhex(payload.substr(separator + 1));
        if (cursor > source.size()) return {"completion cursor exceeds source size\n", false, 1};
        const auto completion = session.complete(source, cursor);
        std::string text = "completion\t" + std::to_string(completion.start) + '\n';
        for (const auto &candidate : completion.candidates) text += hex(candidate) + '\n';
        return {std::move(text), false, 0};
      }
      const bool exits = languageExit(line);
      SessionResponse response;
      if (line == ":project-targets" || line == ":targets") {
        response = session.projectTargets();
      } else if (line.starts_with(":target ")) {
        response = session.runTarget(line.substr(8), false, out, err);
      } else if (line.starts_with(":project-run\t")) {
        response = session.runTarget(unhex(line.substr(13)), false, out, err);
      } else if (line.starts_with(":project-debug-prepare\t")) {
        response = session.runTarget(unhex(line.substr(23)), true, out, err);
      } else if (line.starts_with(loadFilePrefix)) {
        const std::string_view path = line.substr(loadFilePrefix.size());
        if (path.empty()) return {"load-file requires a path\nstatus=1\n", false, 1};
        response = session.executeFile(std::string(path), out, err);
      } else if (line.starts_with(inspectPrefix) || line.starts_with(tracePrefix) ||
                 line.starts_with(inspectFilePrefix) || line.starts_with(traceFilePrefix)) {
        const bool standalone = line.starts_with(inspectFilePrefix) || line.starts_with(traceFilePrefix);
        const bool trace = line.starts_with(tracePrefix) || line.starts_with(traceFilePrefix);
        const std::string_view prefix =
            standalone ? (trace ? traceFilePrefix : inspectFilePrefix) : (trace ? tracePrefix : inspectPrefix);
        const std::string_view payload = line.substr(prefix.size());
        const std::size_t separator = payload.find('\t');
        if (separator == std::string_view::npos)
          return {"inspect requires path and source payloads\nstatus=1\n", false, 1};
        response = session.inspect(unhex(payload.substr(separator + 1)), unhex(payload.substr(0, separator)), trace,
                                   standalone);
      } else {
        // Line readers strip Enter's newline. Preserve that source boundary so
        // line-oriented language grammars can finish and execute the command.
        std::string source(line);
        source.push_back('\n');
        response = session.evaluate(source, {}, out, err);
      }
      std::string text = std::move(response.output);
      text += response.error;
      const bool successfulExit = exits && response.error.empty();
      if (response.status != 0 && !successfulExit) {
        if (!text.empty() && text.back() != '\n') text.push_back('\n');
        text += "status=" + std::to_string(response.status) + "\n";
      }
      return {std::move(text), response.quit || successfulExit, response.status};
    } catch (const Exception &error) {
      return {error.description() + "\n", false, error.status()};
    } catch (const std::exception &error) {
      return {std::string("server request failed: ") + error.what() + "\n", false, 1};
    } catch (...) {
      return {"server request failed: unknown internal error\n", false, 1};
    }
  }

  int Server::runStdio() {
    auto session = project_->openSession();
    const bool interactive = isatty(STDIN_FILENO);
    if (!interactive) {
      std::string line;
      int status = 0;
      while (!stopping_ && std::getline(std::cin, line)) {
        CommandResult result = handle(*session, line, &std::cout, &std::cerr);
        if (!result.text.empty()) std::cout << result.text << std::flush;
        status = result.status;
        if (result.quit) break;
      }
      return status;
    }

    const bool integration = consoleIntegration();
    if (integration)
      utilities::LineEditor::writeDescriptor(STDOUT_FILENO, "\x1b]633;P;HasRichCommandDetection=True\x07");
    utilities::LineEditor editor(
        [](int timeout) { return utilities::LineEditor::readDescriptor(STDIN_FILENO, timeout); },
        [](std::string_view text) { return utilities::LineEditor::writeDescriptor(STDOUT_FILENO, text); },
        [] { return utilities::LineEditor::descriptorColumns(STDIN_FILENO); },
        [&session](std::string_view line, std::size_t cursor) { return session->complete(line, cursor); },
        consoleHighlighter([&session](std::string_view line) { return session->highlight(line); }), integration);

    int status = 0;
    while (!stopping_) {
      utilities::LineResult line;
      {
        utilities::TerminalMode terminal(STDIN_FILENO);
        if (!terminal) {
          std::cout << utilities::prompt::Default << std::flush;
          std::string plain;
          if (!std::getline(std::cin, plain)) break;
          line = {utilities::LineStatus::Line, std::move(plain)};
        } else {
          line = editor.readLine(utilities::prompt::Default);
        }
      }

      if (line.status == utilities::LineStatus::Interrupt) {
        consoleStatus(integration, 130);
        continue;
      }
      if (line.status == utilities::LineStatus::End) break;

      CommandResult result;
      {
        IgnoreInteractiveInterrupt interrupt;
        result = handle(*session, line.line, &std::cout, &std::cerr);
      }
      if (!result.text.empty()) std::cout << result.text << std::flush;
      status = result.status;
      consoleStatus(integration, status);
      if (result.quit) break;
    }
    return status;
  }

  bool Server::writeAll(int fd, std::string_view text) {
    return sendBytes(fd, text);
  }

  void Server::serveUnixClient(int fd) {
    auto session = project_->openSession();
    std::string buffer;
    buffer.reserve(4096);
    writeAll(fd, utilities::prompt::Default);

    char chunk[4096];
    bool done = false;
    bool interruptBuffered = false;
    bool framed = false;
    bool framedStatus = false;
    while (!done) {
      const ssize_t bytes = recv(fd, chunk, sizeof(chunk), 0);
      if (bytes < 0) {
        if (errno == EINTR) continue;
        break;
      }
      if (bytes == 0) break;
      for (ssize_t i = 0; i < bytes; ++i) {
        if (chunk[i] == '\x03') {
          if (buffer.find('\n') != std::string::npos) interruptBuffered = true;
        } else {
          buffer.push_back(chunk[i]);
        }
      }

      while (true) {
        const std::size_t newline = buffer.find('\n');
        if (newline == std::string::npos) break;
        const std::string line = trimLine(buffer.substr(0, newline + 1));
        buffer.erase(0, newline + 1);

        if (!framed && (line == streamHandshake || line == statusStreamHandshake)) {
          framed = true;
          framedStatus = line == statusStreamHandshake;
          continue;
        }

        ProcessControl processes;
        SocketOutput socketOutput(fd, framed);
        std::ostream output(&socketOutput);
        if (interruptBuffered) {
          processes.interrupt();
          interruptBuffered = false;
        }
        auto request = std::async(std::launch::async, [&] {
          ProcessControl::Scope scope(processes);
          return handle(*session, line, &output, &output);
        });
        while (request.wait_for(std::chrono::milliseconds(0)) != std::future_status::ready) {
          pollfd input{fd, POLLIN, 0};
          const int ready = poll(&input, 1, 20);
          if (ready < 0 && errno == EINTR) continue;
          if (ready < 0 || (ready > 0 && (input.revents & (POLLERR | POLLHUP | POLLNVAL)))) {
            processes.interrupt();
            done = true;
            break;
          }
          if (ready > 0 && (input.revents & POLLIN)) {
            const ssize_t count = recv(fd, chunk, sizeof(chunk), 0);
            if (count <= 0) {
              processes.interrupt();
              done = true;
              break;
            }
            for (ssize_t i = 0; i < count; ++i) {
              if (chunk[i] == '\x03')
                processes.interrupt();
              else
                buffer.push_back(chunk[i]);
            }
          }
        }
        CommandResult result = request.get();
        if (done) break;
        output << result.text << std::flush;
        if (!output.good()) {
          done = true;
          break;
        }
        if (result.quit && !framedStatus) {
          done = true;
          break;
        }
        if (framedStatus && !sendFrame(fd, 'S', std::to_string(result.status))) { done = true; break; }
        if (!(framed ? sendFrame(fd, 'P', {}) : writeAll(fd, utilities::prompt::Default))) {
          done = true;
          break;
        }
        if (result.quit) { done = true; break; }
      }
    }
    {
      std::lock_guard lock(clientsMutex_);
      clientFds_.erase(fd);
    }
    close(fd);
  }

  void Server::reapClients(bool all) {
    std::vector<std::thread> threads;
    {
      std::lock_guard lock(clientsMutex_);
      auto current = clientThreads_.begin();
      while (current != clientThreads_.end()) {
        if (!all && !current->finished->load(std::memory_order_acquire)) {
          ++current;
          continue;
        }
        threads.push_back(std::move(current->thread));
        current = clientThreads_.erase(current);
      }
    }
    for (std::thread &thread : threads)
      if (thread.joinable()) thread.join();
  }

  void Server::openUnix() {
    if (options_.unixPath.empty()) return;
    if (options_.unixPath.size() >= sizeof(sockaddr_un::sun_path))
      THROW(, "unix socket path is too long: " << options_.unixPath)

    const int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listener < 0) THROW(, "cannot create unix socket: " << std::strerror(errno))

    unlink(options_.unixPath.c_str());
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, options_.unixPath.c_str(), options_.unixPath.size() + 1);
    if (bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
      const int error = errno;
      close(listener);
      THROW(, "cannot bind unix socket '" << options_.unixPath << "': " << std::strerror(error))
    }
    if (chmod(options_.unixPath.c_str(), S_IRUSR | S_IWUSR) != 0) {
      const int error = errno;
      close(listener);
      unlink(options_.unixPath.c_str());
      THROW(, "cannot secure unix socket '" << options_.unixPath << "': " << std::strerror(error))
    }
    if (listen(listener, 64) != 0) {
      const int error = errno;
      close(listener);
      unlink(options_.unixPath.c_str());
      THROW(, "cannot listen on unix socket: " << std::strerror(error))
    }
    listener_ = listener;
  }

  void Server::runUnix() {
    const int listener = listener_.load();
    while (!stopping_) {
      const int fd = accept4(listener, nullptr, nullptr, SOCK_CLOEXEC);
      if (fd < 0) {
        if (errno == EINTR) continue;
        if (stopping_) break;
        continue;
      }
      if (stopping_) {
        close(fd);
        break;
      }
      reapClients();
      auto finished = std::make_shared<std::atomic<bool>>(false);
      std::lock_guard lock(clientsMutex_);
      clientFds_.insert(fd);
      clientThreads_.push_back(ClientThread{std::thread([this, fd, finished] {
                                              serveUnixClient(fd);
                                              finished->store(true, std::memory_order_release);
                                            }),
                                            std::move(finished)});
    }
  }

  int Server::run() {
    std::thread unixThread;
    if (!options_.unixPath.empty()) {
      openUnix();
      unixThread = std::thread([this] { runUnix(); });
    }

    int status = 0;
    if (options_.stdio) {
      status = runStdio();
      stop();
    } else if (unixThread.joinable()) {
      unixThread.join();
    }

    if (unixThread.joinable()) unixThread.join();
    reapClients(true);
    return status;
  }

  int Server::connectUnix(const std::string &path) {
    // Raw-mode Ctrl+C is forwarded below; don't let a signal in a terminal-mode
    // transition terminate the console client.
    IgnoreInteractiveInterrupt interrupt;
    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) THROW(, "cannot create unix client socket: " << std::strerror(errno))
    if (!connectSocket(fd, path)) {
      const int error = errno;
      close(fd);
      THROW(, "cannot connect unix socket '" << path << "': " << std::strerror(error))
    }

    std::string initial;
    if (!receiveUntilPrompt(fd, initial)) {
      if (!initial.empty()) utilities::LineEditor::writeDescriptor(STDOUT_FILENO, initial);
      close(fd);
      return 1;
    }
    if (!initial.empty()) utilities::LineEditor::writeDescriptor(STDOUT_FILENO, initial);

    if (!writeAll(fd, std::string(statusStreamHandshake) + '\n')) {
      close(fd);
      return 1;
    }

    const bool integration = consoleIntegration();
    if (integration)
      utilities::LineEditor::writeDescriptor(STDOUT_FILENO, "\x1b]633;P;HasRichCommandDetection=True\x07");
    utilities::LineEditor editor(
        [](int timeout) { return utilities::LineEditor::readDescriptor(STDIN_FILENO, timeout); },
        [](std::string_view text) { return utilities::LineEditor::writeDescriptor(STDOUT_FILENO, text); },
        [] { return utilities::LineEditor::descriptorColumns(STDIN_FILENO); },
        [fd](std::string_view line, std::size_t cursor) { return remoteCompletion(fd, line, cursor); },
        consoleHighlighter([fd](std::string_view line) { return remoteHighlight(fd, line); }), integration);

    while (true) {
      utilities::LineResult input;
      {
        utilities::TerminalMode terminal(STDIN_FILENO);
        if (!terminal) {
          utilities::LineEditor::writeDescriptor(STDOUT_FILENO, utilities::prompt::Default);
          std::string line;
          if (!std::getline(std::cin, line)) break;
          input = {utilities::LineStatus::Line, std::move(line)};
        } else {
          input = editor.readLine(utilities::prompt::Default);
        }
      }

      if (input.status == utilities::LineStatus::Interrupt) {
        consoleStatus(integration, 130);
        continue;
      }
      if (input.status == utilities::LineStatus::End) break;

      std::string request = std::move(input.line);
      request.push_back('\n');
      if (!writeAll(fd, request)) break;

      ConsoleFrames response;
      bool received = false;
      {
        utilities::TerminalMode terminal(STDIN_FILENO);
        if (!terminal) {
          char bytes[4096];
          while (!response.completed) {
            const ssize_t count = recv(fd, bytes, sizeof(bytes), 0);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0 || !response.consume({bytes, static_cast<std::size_t>(count)})) break;
          }
          received = response.completed;
        } else {
          while (true) {
            pollfd inputs[] = {{fd, POLLIN, 0}, {STDIN_FILENO, POLLIN, 0}};
            const int ready = poll(inputs, 2, -1);
            if (ready < 0 && errno == EINTR) continue;
            if (ready < 0) break;
            if (inputs[1].revents & POLLIN) {
              char bytes[256];
              const ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
              for (ssize_t i = 0; i < count; ++i) {
                if (bytes[i] == '\x03') {
                  writeAll(fd, std::string_view("\x03", 1));
                  utilities::LineEditor::writeDescriptor(STDOUT_FILENO, "^C\n");
                }
              }
            }
            if (inputs[0].revents & POLLIN) {
              char bytes[4096];
              const ssize_t count = recv(fd, bytes, sizeof(bytes), 0);
              if (count <= 0) break;
              if (!response.consume({bytes, static_cast<std::size_t>(count)})) break;
              if (response.completed) {
                received = true;
                break;
              }
            } else if (inputs[0].revents & (POLLERR | POLLHUP | POLLNVAL))
              break;
          }
        }
      }
      if (!received) {
        consoleStatus(integration, 1);
        break;
      }
      consoleStatus(integration, response.status);
    }

    shutdown(fd, SHUT_RDWR);
    close(fd);
    return 0;
  }
} // namespace recurloop
