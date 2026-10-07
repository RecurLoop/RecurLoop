#pragma once

#include <atomic>
#include <csignal>
#include <cerrno>
#include <sys/wait.h>
#include <mutex>
#include <unordered_set>
#include <unistd.h>
#include <cstdlib>
#include <fcntl.h>
#include <string>
#include <string_view>
#include <termios.h>
#include <sys/ioctl.h>

namespace recurloop {
  // Request-local process groups. The transport may interrupt them without
  // signalling the host or processes belonging to another client session.
  class ProcessControl {
  public:
    class Scope {
    public:
      explicit Scope(ProcessControl &control) : previous_(active_) {
        active_ = &control;
      }
      ~Scope() {
        active_ = previous_;
      }

    private:
      ProcessControl *previous_;
    };

    explicit ProcessControl(bool terminal = false) {
      if (!terminal) return;
      master_ = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC | O_NONBLOCK);
      if (master_ < 0) return;
      char name[256];
      if (grantpt(master_) != 0 || unlockpt(master_) != 0 || ptsname_r(master_, name, sizeof(name)) != 0 ||
          (slave_ = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC)) < 0) {
        close(master_);
        master_ = -1;
      }
    }
    ~ProcessControl() {
      // Native cancellation can unwind before the language-side await/release.
      // Reap only children still owned by this request.
      for (pid_t group : groups_) {
        kill(-group, SIGKILL);
        kill(group, SIGKILL);
        while (waitpid(group, nullptr, 0) < 0 && errno == EINTR) {
        }
      }
      if (slave_ >= 0) close(slave_);
      if (master_ >= 0) close(master_);
    }
    ProcessControl(const ProcessControl &) = delete;
    ProcessControl &operator=(const ProcessControl &) = delete;

    static int terminal() noexcept {
      return active_ ? active_->slave_ : -1;
    }
    int terminalMaster() const noexcept {
      return master_;
    }
    void resize(unsigned rows, unsigned columns) {
      if (slave_ < 0) return;
      winsize size{};
      size.ws_row = static_cast<unsigned short>(rows);
      size.ws_col = static_cast<unsigned short>(columns);
      ioctl(slave_, TIOCSWINSZ, &size);
    }
    void input(std::string_view bytes) {
      if (master_ >= 0) pendingInput_.append(bytes);
    }
    void flushInput() {
      while (!pendingInput_.empty()) {
        const auto count = write(master_, pendingInput_.data(), pendingInput_.size());
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        pendingInput_.erase(0, static_cast<std::size_t>(count));
      }
    }
    static bool active() noexcept {
      return active_ != nullptr;
    }
    static bool interrupted() noexcept {
      return active_ && active_->interrupted_.load(std::memory_order_relaxed);
    }
    static void track(pid_t pid) {
      if (!active_ || pid <= 0) return;
      std::lock_guard lock(active_->mutex_);
      active_->groups_.insert(pid);
      if (active_->interrupted_) {
        kill(-pid, SIGINT);
        kill(pid, SIGINT);
      }
    }
    static void release(pid_t pid) {
      if (!active_) return;
      // Leave the child unreaped until its group is no longer registered.
      siginfo_t status{};
      while (waitid(P_PID, static_cast<id_t>(pid), &status, WEXITED | WNOWAIT) < 0 && errno == EINTR) {
      }
      std::lock_guard lock(active_->mutex_);
      active_->groups_.erase(pid);
    }
    void interrupt(bool force = false) {
      std::lock_guard lock(mutex_);
      // A second explicit Ctrl+C also stops commands that ignore SIGINT.
      const bool repeated = interrupted_.exchange(true);
      const int signal = force || repeated ? SIGKILL : SIGINT;
      pendingInput_.clear();
      if (slave_ >= 0) tcflush(slave_, TCIFLUSH);
      for (pid_t group : groups_) {
        kill(-group, signal);
        kill(group, signal);
        // A terminal reader may already have stopped on SIGTTIN/SIGTTOU.
        kill(-group, SIGCONT);
      }
    }

  private:
    int master_ = -1;
    int slave_ = -1;
    std::string pendingInput_;
    inline static thread_local ProcessControl *active_ = nullptr;
    std::mutex mutex_;
    std::unordered_set<pid_t> groups_;
    std::atomic<bool> interrupted_{false};
  };
} // namespace recurloop
