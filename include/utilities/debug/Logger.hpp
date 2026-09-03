#pragma once

#include <utilities/Size.hpp>

#include <string>
#include <ostream>
#include <mutex>

#if !defined(NDEBUG)
  #define DEBUG_LOG_INIT(Filepath)                                                                                     \
      std::filesystem::create_directories(std::filesystem::path(Filepath).parent_path());                              \
      auto _log_file = std::ofstream(Filepath, std::ios::out | std::ios::trunc);                                       \
      debug::Logger::start(&_log_file);                                                                                \
      debug::Logger::enable();
  #define DEBUG_LOG_END(...) { debug::Logger::end(); }
  #define DEBUG_LOG_ENABLE() { debug::Logger::enable(); }
  #define DEBUG_LOG_DISABLE() { debug::Logger::disable(); }
  #define DEBUG_LOG(Type, Message)                                                                                     \
    {                                                                                                                  \
      std::ostringstream oss;                                                                                          \
      oss << Message;                                                                                                  \
      debug::Logger(#Type, oss.str(), __PRETTY_FUNCTION__, __FILE__, __LINE__);                                        \
    }
#else
  #define DEBUG_LOG_INIT(...)
  #define DEBUG_LOG_END(...)
  #define DEBUG_LOG_ENABLE()
  #define DEBUG_LOG_DISABLE()
  #define DEBUG_LOG(...)
#endif

namespace debug {
  class Logger {
  public:
    Logger(const Logger &) = delete;
    Logger &operator=(const Logger &) = delete;

    Logger(Logger &&) = default;
    Logger &operator=(Logger &&) = default;

    explicit Logger(std::string type, std::string message, const char *function = "", const char *file = "",
                      const int line = 0);
    ~Logger();

    static void start(std::ostream *output);
    static void end();

    static void enable();
    static void disable();

    void flush();

  protected:
    static bool _enabled;
    static Size _index;
    static std::ostream *_output;
    static std::mutex _outputMutex;

    std::string _type;
    std::string _message;
    std::string _timestamp;

    const char *_function, *_file;
    int _line;

    bool _flushed;
  };
} // namespace debug
