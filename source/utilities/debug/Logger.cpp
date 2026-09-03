
#if !defined(__UTILITIES_LOGGER_CPP)
  #define __UTILITIES_LOGGER_CPP

  #include <utilities/Utilities.hpp>

namespace debug {
  static INLINED std::string escape(const std::string &string) {
    std::string escapedString;

    escapedString.reserve(string.size());

    for (char ch : string) {
      switch (ch) {
      case '\n': escapedString += "\\n"; break;
      case '\r': escapedString += "\\r"; break;
      case '\t': escapedString += "\\t"; break;
      case '\v': escapedString += "\\v"; break;
      case '\"': escapedString += "\"\""; break;
      default: escapedString += ch; break;
      }
    }

    return escapedString;
  };

  static INLINED std::string timestamp() {
    auto now = std::chrono::system_clock::now();

    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    auto microseconds = duration_cast<std::chrono::microseconds>(now.time_since_epoch()) % std::chrono::seconds(1);

    std::ostringstream timestamp;
    timestamp << std::put_time(std::localtime(&in_time_t), "%Y-%m-%d %H:%M:%S");
    timestamp << '.' << std::setfill('0') << std::setw(6) << microseconds.count();
    return timestamp.str();
  };

  Logger::Logger(std::string type, std::string message, const char *function, const char *file, const int line)
      : _type(type), _message(message), _function(function), _file(file), _line(line), _timestamp(timestamp()), _flushed(false) {
  }

  Logger::~Logger() {
    if (!_flushed) flush();
  }

  void Logger::start(std::ostream *output) {
    _output = output;
    std::lock_guard<std::mutex> lock(_outputMutex);
    *_output << "\"index\",\"type\",\"message\",\"code\",\"function\",\"timestamp\"" << std::endl;
  }

  void Logger::end() {
  }

  void Logger::enable() {
    std::lock_guard<std::mutex> lock(_outputMutex);
    _enabled = true;
  }

  void Logger::disable() {
    std::lock_guard<std::mutex> lock(_outputMutex);
    _enabled = false;
  }

  void Logger::flush() {
    std::lock_guard<std::mutex> lock(_outputMutex);
    if (!_enabled) return;
    // clang-format off
    *_output << "\"" << _index++
            << "\",\"" << escape(_type)
            << "\",\"" << escape(_message)
            << "\",\"" << escape(_file) << ":" << _line
            << "\",\"" << escape(_function)
            << "\",\"" << escape(_timestamp) << "\""
            << std::endl << std::flush;
    // clang-format on

    _flushed = true;
  }

  bool Logger::_enabled = false;
  Size Logger::_index = 1;
  std::ostream *Logger::_output = &std::cerr;
  std::mutex Logger::_outputMutex = {};
}

#endif
