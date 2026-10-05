#include <gtest/gtest.h>

#include <recurloop/Project.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Server.hpp>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <poll.h>

#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <thread>

namespace {
  std::shared_ptr<recurloop::Project> project() {
    char program[] = "recurloop-test";
    char *argv[] = {program};
    auto runtime = std::make_unique<recurloop::Recurloop>();
    runtime->initialize(1, argv);
    return recurloop::Project::create(runtime->getContext(), {program});
  }

  int connectUnix(const std::string &path) {
    for (int attempt = 0; attempt < 100; ++attempt) {
      int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
      if (fd < 0) return -1;
      sockaddr_un address{};
      address.sun_family = AF_UNIX;
      std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
      if (connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0) return fd;
      close(fd);
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return -1;
  }

  void sendLine(int fd, std::string_view line) {
    std::string text(line);
    text.push_back('\n');
    ASSERT_EQ(send(fd, text.data(), text.size(), MSG_NOSIGNAL), static_cast<ssize_t>(text.size()));
  }

  std::string readPrompt(int fd) {
    std::string result;
    char byte = 0;
    constexpr std::string_view prompt = "> ";
    while (result.size() < 65536) {
      const ssize_t count = recv(fd, &byte, 1, 0);
      if (count <= 0) break;
      result.push_back(byte);
      if (result.ends_with(prompt)) break;
    }
    return result;
  }
} // namespace

TEST(RecurloopServer, UnixClientsHaveIndependentSessionsAndCanPublish) {
  const std::string path = "/tmp/recurloop-server-unit-" + std::to_string(getpid()) + ".sock";
  std::filesystem::remove(path);

  recurloop::ServerOptions options;
  options.stdio = false;
  options.unixPath = path;
  recurloop::Server server(project(), options);
  std::thread thread([&] { EXPECT_EQ(server.run(), 0); });

  const int first = connectUnix(path);
  const int second = connectUnix(path);
  EXPECT_GE(first, 0);
  EXPECT_GE(second, 0);
  if (first < 0 || second < 0) {
    if (first >= 0) close(first);
    if (second >= 0) close(second);
    server.stop();
    thread.join();
    std::filesystem::remove(path);
    return;
  }
  EXPECT_EQ(readPrompt(first), "> ");
  EXPECT_EQ(readPrompt(second), "> ");

  sendLine(first, "var shared_value = 123");
  readPrompt(first);

  sendLine(second, "print shared_value");
  EXPECT_NE(readPrompt(second).find("status="), std::string::npos);

  sendLine(first, ":publish");
  EXPECT_NE(readPrompt(first).find("published project="), std::string::npos);
  sendLine(second, ":refresh");
  readPrompt(second);
  sendLine(second, "print shared_value");
  EXPECT_NE(readPrompt(second).find("123"), std::string::npos);

  sendLine(first, ":quit");
  sendLine(second, ":quit");
  close(first);
  close(second);
  server.stop();
  thread.join();
  std::filesystem::remove(path);
}

TEST(RecurloopServer, LanguageExitClosesOnlyTheCallingUnixSession) {
  const std::string path = "/tmp/recurloop-server-exit-unit-" + std::to_string(getpid()) + ".sock";
  std::filesystem::remove(path);

  recurloop::ServerOptions options;
  options.stdio = false;
  options.unixPath = path;
  recurloop::Server server(project(), options);
  std::thread thread([&] { EXPECT_EQ(server.run(), 0); });

  const int first = connectUnix(path);
  EXPECT_GE(first, 0);
  if (first < 0) {
    server.stop();
    thread.join();
    std::filesystem::remove(path);
    return;
  }
  EXPECT_EQ(readPrompt(first), "> ");
  sendLine(first, "exit");

  char byte = 0;
  EXPECT_EQ(recv(first, &byte, 1, 0), 0);
  close(first);

  // Exiting one interactive client is a session exit, not a daemon shutdown.
  const int second = connectUnix(path);
  EXPECT_GE(second, 0);
  if (second >= 0) {
    EXPECT_EQ(readPrompt(second), "> ");
    sendLine(second, ":quit");
    close(second);
  }

  server.stop();
  thread.join();
  std::filesystem::remove(path);
}

TEST(RecurloopServer, LoadFileStreamsOutputBeforeTheRequestCompletes) {
  const auto directory =
      std::filesystem::temp_directory_path() / ("recurloop-server-stream-" + std::to_string(getpid()));
  std::filesystem::create_directories(directory);
  const std::string path = (directory / "server.sock").string();
  const auto release = directory / "release";
  const auto source = directory / "stream.rl";
  std::filesystem::remove(release);
  {
    std::ofstream file(source);
    file << "link shared \"c\"\n"
         << "extern access(path:u8*, mode:i32) -> i32 abi sysv-amd64\n"
         << "extern usleep(time:u32) -> i32 abi sysv-amd64\n"
         << "print \"server-live\"\n"
         << "while access(\"" << release.string() << "\", 0) != 0 { usleep(1000) }\n"
         << "print \"server-done\"\n";
  }

  recurloop::ServerOptions options;
  options.stdio = false;
  options.unixPath = path;
  recurloop::Server server(project(), options);
  std::thread thread([&] { EXPECT_EQ(server.run(), 0); });
  const int client = connectUnix(path);
  EXPECT_GE(client, 0);
  if (client >= 0) {
    EXPECT_EQ(readPrompt(client), "> ");
    sendLine(client, ":load-file\t" + source.string());
    std::string output;
    while (output.find("server-live\n") == std::string::npos) {
      pollfd input{client, POLLIN, 0};
      const int ready = poll(&input, 1, 2000);
      EXPECT_GT(ready, 0) << "output was held until request completion";
      if (ready <= 0) break;
      char bytes[4096];
      const auto count = recv(client, bytes, sizeof(bytes), 0);
      if (count <= 0) break;
      output.append(bytes, static_cast<std::size_t>(count));
      if (output.ends_with("> ")) break;
    }
    EXPECT_NE(output.find("server-live\n"), std::string::npos);
    EXPECT_EQ(output.find("server-done"), std::string::npos);
    EXPECT_FALSE(output.ends_with("> ")) << "request completed before the release gate: " << output;
    std::ofstream(release).close();
    if (!output.ends_with("> ")) EXPECT_NE(readPrompt(client).find("server-done\n"), std::string::npos);
    close(client);
  }
  server.stop();
  thread.join();
  std::filesystem::remove_all(directory);
}

TEST(RecurloopServer, CompletionUsesCallingSessionAndDoesNotExecuteInput) {
  const std::string path = "/tmp/recurloop-server-completion-" + std::to_string(getpid()) + ".sock";
  recurloop::ServerOptions options;
  options.stdio = false;
  options.unixPath = path;
  recurloop::Server server(project(), options);
  std::thread thread([&] { EXPECT_EQ(server.run(), 0); });
  const int first = connectUnix(path);
  const int second = connectUnix(path);
  EXPECT_GE(first, 0);
  EXPECT_GE(second, 0);
  if (first >= 0 && second >= 0) {
    readPrompt(first);
    readPrompt(second);
    sendLine(first, "let unique_completion_phrase = <print>");
    readPrompt(first);
    // Hexadecimal source: unique_completion_ph.
    const std::string request = ":complete\t20\t756e697175655f636f6d706c6574696f6e5f7068";
    sendLine(first, request);
    const auto completed = readPrompt(first);
    EXPECT_NE(completed.find("completion\t0\n"), std::string::npos);
    EXPECT_NE(completed.find("756e697175655f636f6d706c6574696f6e5f706872617365\n"), std::string::npos);
    sendLine(second, request);
    EXPECT_EQ(readPrompt(second), "completion\t0\n> ");
    // A completion request must not run `print 42`.
    sendLine(first, ":complete\t8\t7072696e74203432");
    EXPECT_EQ(readPrompt(first), "completion\t6\n> ");
    sendLine(first, ":complete\t99\t7072696e74");
    EXPECT_NE(readPrompt(first).find("cursor exceeds source size"), std::string::npos);
    sendLine(first, "unique_completion_phrase 42");
    EXPECT_EQ(readPrompt(first), "42\n> ");
  }
  if (first >= 0) close(first);
  if (second >= 0) close(second);
  server.stop();
  thread.join();
}
