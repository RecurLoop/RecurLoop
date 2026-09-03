#pragma once

#include <utilities/Size.hpp>

#include <string>
#include <ostream>
#include <vector>
#include <unordered_map>
#include <mutex>

#if !defined(NDEBUG)
  #define DEBUG_PROFILER_INIT(Filepath)                                                                                \
      std::filesystem::create_directories(std::filesystem::path(Filepath).parent_path());                              \
      auto _profile_file = std::ofstream(Filepath, std::ios::out | std::ios::trunc);                                   \
      debug::Profiler::start(&_profile_file);                                                                          \
      debug::Profiler::enable();
  #define DEBUG_PROFILER_END() { debug::Profiler::end(); }
  #define DEBUG_PROFILER_ENABLE() { debug::Profiler::enable(); }
  #define DEBUG_PROFILER_DISABLE() { debug::Profiler::disable(); }
  #define DEBUG_PROFILER(Name) { debug::Profiler('-', Name, 0, __PRETTY_FUNCTION__, __FILE__, __LINE__); }
  #define DEBUG_PROFILER_OPEN(Name) { debug::Profiler('O', #Name, debug::Profiler::getFrameId(#Name, __FILE__, __LINE__), __PRETTY_FUNCTION__, __FILE__, __LINE__); }
  #define DEBUG_PROFILER_CLOSE(Name) { debug::Profiler('C', #Name, debug::Profiler::getFrameId(#Name, __FILE__, __LINE__), __PRETTY_FUNCTION__, __FILE__, __LINE__); }
  #define DEBUG_PROFILE_FUNCTION() debug::ProfilerScope _profiler_scope_guard(__PRETTY_FUNCTION__, __PRETTY_FUNCTION__, __FILE__, __LINE__)
  #define DEBUG_PROFILE_SCOPE(Name) debug::ProfilerScope _profiler_scope_guard_##Name(#Name, __PRETTY_FUNCTION__, __FILE__, __LINE__)
#else
  #define DEBUG_PROFILER_INIT(...)
  #define DEBUG_PROFILER_END()
  #define DEBUG_PROFILER_ENABLE()
  #define DEBUG_PROFILER_DISABLE()
  #define DEBUG_PROFILER(...)
  #define DEBUG_PROFILER_OPEN(Tag)
  #define DEBUG_PROFILER_CLOSE(Tag)
  #define DEBUG_PROFILE_FUNCTION()
  #define DEBUG_PROFILE_SCOPE(Name)
#endif

namespace debug {
  class Profiler {
  public:
    Profiler(const Profiler &) = delete;
    Profiler &operator=(const Profiler &) = delete;

    Profiler(Profiler &&) = default;
    Profiler &operator=(Profiler &&) = default;

    explicit Profiler(char type, std::string tag, Size frame, const char *function = "", const char *file = "",
                      const int line = 0);
    ~Profiler();

    static void start(std::ostream *output);
    static void end(std::vector<std::string> frames);
    static void end();

    static void enable();
    static void disable();

    // Dynamic frame registration
    static Size getFrameId(const std::string &name, const std::string &file, const int line);
    static std::vector<std::string> getAllFrames();

  protected:
    static bool _enabled;
    static std::ostream *_output;
    static Size _start;
    static std::unordered_map<std::string, Size> _frameMap;
    static std::vector<std::string> _frameNames;
    static std::mutex _frameMutex;
    static std::mutex _outputMutex;
    static Size _nextFrameId;

    char _type;
    std::string _name;
    Size _frame, _timestamp;

    const char *_function, *_file;
    int _line;

    bool _flushed;
  };

  // RAII profiler scope guard for automatic function profiling
  class ProfilerScope {
  public:
    ProfilerScope(const ProfilerScope &) = delete;
    ProfilerScope &operator=(const ProfilerScope &) = delete;
    ProfilerScope(ProfilerScope &&) = delete;
    ProfilerScope &operator=(ProfilerScope &&) = delete;

    explicit ProfilerScope(const std::string &name, const char *function = "", const char *file = "", int line = 0);
    ~ProfilerScope();

  private:
    std::string _name;
    Size _frame;
    const char *_function;
    const char *_file;
    int _line;
  };
} // namespace debug
