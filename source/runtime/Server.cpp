#include <recurloop/Server.hpp>
#include <utilities/LineEditor.hpp>
#include <utilities/Prompt.hpp>

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cctype>
#include <cstring>
#include <iostream>
#include <thread>

namespace recurloop {
  namespace {
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

  Server::CommandResult Server::handle(Session &session, std::string_view line) {
    try {
      constexpr std::string_view loadFilePrefix = ":load-file\t";
      constexpr std::string_view inspectPrefix = ":inspect\t";
      constexpr std::string_view tracePrefix = ":trace\t";
      constexpr std::string_view inspectFilePrefix = ":inspect-file\t";
      constexpr std::string_view traceFilePrefix = ":trace-file\t";
      const bool exits = languageExit(line);
      SessionResponse response;
      if (line.starts_with(loadFilePrefix)) {
        const std::string_view path = line.substr(loadFilePrefix.size());
        if (path.empty()) return {"load-file requires a path\nstatus=1\n", false, 1};
        response = session.executeFile(std::string(path));
      } else if (line.starts_with(inspectPrefix) || line.starts_with(tracePrefix) ||
                 line.starts_with(inspectFilePrefix) || line.starts_with(traceFilePrefix)) {
        const bool standalone = line.starts_with(inspectFilePrefix) || line.starts_with(traceFilePrefix);
        const bool trace = line.starts_with(tracePrefix) || line.starts_with(traceFilePrefix);
        const std::string_view prefix = standalone ? (trace ? traceFilePrefix : inspectFilePrefix)
                                                   : (trace ? tracePrefix : inspectPrefix);
        const std::string_view payload = line.substr(prefix.size());
        const std::size_t separator = payload.find('\t');
        if (separator == std::string_view::npos) return {"inspect requires path and source payloads\nstatus=1\n", false, 1};
        response = session.inspect(unhex(payload.substr(separator + 1)), unhex(payload.substr(0, separator)),
                                   trace, standalone);
      } else {
        // Line readers strip Enter's newline. Preserve that source boundary so
        // line-oriented language grammars can finish and execute the command.
        std::string source(line);
        source.push_back('\n');
        response = session.evaluate(source);
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
        CommandResult result = handle(*session, line);
        if (!result.text.empty()) std::cout << result.text << std::flush;
        status = result.status;
        if (result.quit) break;
      }
      return status;
    }

    utilities::LineEditor editor(
        [](int timeout) { return utilities::LineEditor::readDescriptor(STDIN_FILENO, timeout); },
        [](std::string_view text) { return utilities::LineEditor::writeDescriptor(STDOUT_FILENO, text); },
        [] { return utilities::LineEditor::descriptorColumns(STDIN_FILENO); });

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

      if (line.status == utilities::LineStatus::Interrupt) continue;
      if (line.status == utilities::LineStatus::End) break;

      CommandResult result = handle(*session, line.line);
      if (!result.text.empty()) std::cout << result.text << std::flush;
      status = result.status;
      if (result.quit) break;
    }
    return status;
  }

  bool Server::writeAll(int fd, std::string_view text) {
    std::size_t offset = 0;
    while (offset < text.size()) {
      const ssize_t written = send(fd, text.data() + offset, text.size() - offset, MSG_NOSIGNAL);
      if (written < 0) {
        if (errno == EINTR) continue;
        return false;
      }
      if (written == 0) return false;
      offset += static_cast<std::size_t>(written);
    }
    return true;
  }

  void Server::serveUnixClient(int fd) {
    auto session = project_->openSession();
    std::string buffer;
    buffer.reserve(4096);
    writeAll(fd, utilities::prompt::Default);

    char chunk[4096];
    bool done = false;
    while (!done) {
      const ssize_t bytes = recv(fd, chunk, sizeof(chunk), 0);
      if (bytes < 0) {
        if (errno == EINTR) continue;
        break;
      }
      if (bytes == 0) break;
      buffer.append(chunk, static_cast<std::size_t>(bytes));

      while (true) {
        const std::size_t newline = buffer.find('\n');
        if (newline == std::string::npos) break;
        const std::string line = trimLine(buffer.substr(0, newline + 1));
        buffer.erase(0, newline + 1);

        CommandResult result = handle(*session, line);
        if (!result.text.empty() && !writeAll(fd, result.text)) {
          done = true;
          break;
        }
        if (result.quit) {
          done = true;
          break;
        }
        if (!writeAll(fd, utilities::prompt::Default)) {
          done = true;
          break;
        }
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

    utilities::LineEditor editor(
        [](int timeout) { return utilities::LineEditor::readDescriptor(STDIN_FILENO, timeout); },
        [](std::string_view text) { return utilities::LineEditor::writeDescriptor(STDOUT_FILENO, text); },
        [] { return utilities::LineEditor::descriptorColumns(STDIN_FILENO); });

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

      if (input.status == utilities::LineStatus::Interrupt) continue;
      if (input.status == utilities::LineStatus::End) break;

      std::string request = std::move(input.line);
      request.push_back('\n');
      if (!writeAll(fd, request)) break;

      std::string response;
      if (!receiveUntilPrompt(fd, response)) {
        if (!response.empty()) utilities::LineEditor::writeDescriptor(STDOUT_FILENO, response);
        break;
      }
      if (!response.empty()) utilities::LineEditor::writeDescriptor(STDOUT_FILENO, response);
    }

    shutdown(fd, SHUT_RDWR);
    close(fd);
    return 0;
  }
} // namespace recurloop
