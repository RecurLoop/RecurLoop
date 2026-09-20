#pragma once

#include <recurloop/Project.hpp>
#include <recurloop/Session.hpp>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

namespace recurloop {
  struct ServerOptions {
    bool stdio = true;
    std::string unixPath;
  };

  // Thin transport layer over Project/Session.  Stdio and every accepted Unix
  // socket get independent sessions; transports never share Context objects.
  class Server {
  public:
    Server(std::shared_ptr<Project> project, ServerOptions options)
        : project_(std::move(project)), options_(std::move(options)) {}
    Server(const Server &) = delete;
    Server &operator=(const Server &) = delete;
    ~Server();

    int run();
    void stop() noexcept;

    static int connectUnix(const std::string &path);

  private:
    struct CommandResult {
      std::string text;
      bool quit = false;
      int status = 0;
    };

    struct ClientThread {
      std::thread thread;
      std::shared_ptr<std::atomic<bool>> finished;
    };

    static CommandResult handle(Session &session, std::string_view line);
    int runStdio();
    void openUnix();
    void runUnix();
    void serveUnixClient(int fd);
    void reapClients(bool all = false);
    static bool writeAll(int fd, std::string_view text);

    std::shared_ptr<Project> project_;
    ServerOptions options_;
    std::atomic<bool> stopping_{false};
    std::atomic<int> listener_{-1};
    std::mutex clientsMutex_;
    std::unordered_set<int> clientFds_;
    std::vector<ClientThread> clientThreads_;
  };
} // namespace recurloop
