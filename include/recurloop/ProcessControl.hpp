#pragma once

#include <csignal>
#include <cerrno>
#include <sys/wait.h>
#include <mutex>
#include <unordered_set>
#include <unistd.h>

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

    static bool active() noexcept {
      return active_ != nullptr;
    }
    static void track(pid_t pid) {
      if (!active_ || pid <= 0) return;
      std::lock_guard lock(active_->mutex_);
      active_->groups_.insert(pid);
      if (active_->interrupted_) kill(-pid, SIGINT);
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
    void interrupt() {
      std::lock_guard lock(mutex_);
      interrupted_ = true;
      for (pid_t group : groups_) kill(-group, SIGINT);
    }

  private:
    inline static thread_local ProcessControl *active_ = nullptr;
    std::mutex mutex_;
    std::unordered_set<pid_t> groups_;
    bool interrupted_ = false;
  };
} // namespace recurloop
