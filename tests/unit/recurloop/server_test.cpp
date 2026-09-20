#include <gtest/gtest.h>

#include <recurloop/Project.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Server.hpp>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <filesystem>
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
}

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
