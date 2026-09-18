#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {
  using Clock = std::chrono::steady_clock;

  [[noreturn]] void fail(const std::string &message) { throw std::runtime_error(message); }

  int connectServer() {
    const auto deadline = Clock::now() + std::chrono::seconds(3);
    while (true) {
      const int socketFd = ::socket(AF_INET, SOCK_STREAM, 0);
      if (socketFd < 0) fail(std::string("socket: ") + std::strerror(errno));

      sockaddr_in address{};
      address.sin_family = AF_INET;
      address.sin_port = htons(18086);
      if (::inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) != 1) {
        ::close(socketFd);
        fail("inet_pton failed");
      }
      if (::connect(socketFd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0) {
        timeval timeout{3, 0};
        ::setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        return socketFd;
      }
      const int error = errno;
      ::close(socketFd);
      if (Clock::now() >= deadline) fail(std::string("connect: ") + std::strerror(error));
      std::this_thread::sleep_for(std::chrono::milliseconds(30));
    }
  }

  void sendAll(int socketFd, std::string_view data) {
    while (!data.empty()) {
      const ssize_t sent = ::send(socketFd, data.data(), data.size(), MSG_NOSIGNAL);
      if (sent <= 0) fail(std::string("send: ") + std::strerror(errno));
      data.remove_prefix(static_cast<std::size_t>(sent));
    }
  }

  std::string receiveAll(int socketFd) {
    std::string result;
    char buffer[65536];
    while (true) {
      const ssize_t received = ::recv(socketFd, buffer, sizeof(buffer), 0);
      if (received == 0) break;
      if (received < 0) {
        if (errno == EINTR) continue;
        fail(std::string("recv: ") + std::strerror(errno));
      }
      result.append(buffer, static_cast<std::size_t>(received));
    }
    return result;
  }

  std::pair<std::string, std::string> exchange(std::string_view request) {
    const int socketFd = connectServer();
    sendAll(socketFd, request);
    std::string response = receiveAll(socketFd);
    ::close(socketFd);

    const std::size_t lineEnd = response.find("\r\n");
    const std::size_t bodyStart = response.find("\r\n\r\n");
    const std::string line = lineEnd == std::string::npos ? response : response.substr(0, lineEnd);
    const std::string body = bodyStart == std::string::npos ? std::string{} : response.substr(bodyStart + 4);
    return {line, body};
  }

  void expect(std::string_view name, std::string_view request, int status,
              const std::string *expectedBody = nullptr) {
    const auto [line, body] = exchange(request);
    const std::string prefix = "HTTP/1.1 " + std::to_string(status) + " ";
    if (!line.starts_with(prefix)) fail(std::string(name) + ": unexpected status line: " + line);
    if (expectedBody != nullptr && body != *expectedBody)
      fail(std::string(name) + ": unexpected body: '" + body + "'");
  }
}

int main() try {
  const std::string ok = "ok";
  const std::string abc = "abc";
  const std::string abcdefg = "abcdefg";

  expect("health", "GET /health HTTP/1.1\r\nHost: x\r\n\r\n", 200, &ok);
  expect("content-length", "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabc", 200, &abc);
  expect("content-length garbage", "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3abc\r\n\r\nabc", 400);
  expect("duplicate content-length",
         "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\nabc", 400);
  expect("overflow content-length",
         "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 999999999999999999999999999999999\r\n\r\n", 413);
  expect("te plus cl",
         "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n0\r\n\r\n", 400);
  expect("unsupported transfer coding",
         "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n", 400);
  expect("chunked",
         "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
         "3;foo=bar\r\nabc\r\n4\r\ndefg\r\n0\r\nX-Trailer: yes\r\n\r\n",
         200, &abcdefg);
  expect("header count",
         "GET /health HTTP/1.1\r\nHost: x\r\nA: 1\r\nB: 1\r\nC: 1\r\nD: 1\r\n"
         "E: 1\r\nF: 1\r\nG: 1\r\nH: 1\r\n\r\n",
         431);

  int socketFd = connectServer();
  sendAll(socketFd, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nabc");
  const auto start = Clock::now();
  const std::string timed = receiveAll(socketFd);
  const auto elapsed = std::chrono::duration<double>(Clock::now() - start).count();
  ::close(socketFd);
  if (!timed.starts_with("HTTP/1.1 408 ")) fail("body timeout: unexpected response");
  if (elapsed > 1.8) fail("body timeout took too long: " + std::to_string(elapsed) + "s");

  std::vector<int> held;
  for (int index = 0; index < 8; ++index) {
    const int client = connectServer();
    sendAll(client, "GET /health HTTP/1.1\r\nHost: x\r\n");
    held.push_back(client);
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  int rejected = 0;
  for (int client : held) {
    timeval timeout{0, 200000};
    ::setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    char buffer[512];
    const ssize_t received = ::recv(client, buffer, sizeof(buffer), 0);
    if (received > 0 && std::string_view(buffer, static_cast<std::size_t>(received)).starts_with("HTTP/1.1 503 "))
      ++rejected;
  }
  for (int client : held) ::close(client);
  if (rejected == 0) fail("bounded worker queue did not reject overload with 503");

  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  expect("post-overload health", "GET /health HTTP/1.1\r\nHost: x\r\n\r\n", 200, &ok);
  return 0;
} catch (const std::exception &exception) {
  std::cerr << exception.what() << '\n';
  return 1;
}
