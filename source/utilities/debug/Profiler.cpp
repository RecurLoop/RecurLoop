
#if !defined(__UTILITIES_PROFILER_CPP)
  #define __UTILITIES_PROFILER_CPP
  #include <utilities/Utilities.hpp>


namespace debug {
  static INLINED Size timestamp() {
    auto now = std::chrono::steady_clock::now();
    auto us = duration_cast<std::chrono::microseconds>(now.time_since_epoch());
    return us.count();
  };

  Profiler::Profiler(char type, std::string tag, Size frame, const char *function, const char *file, const int line)
      : _type(type), _name(tag), _frame(frame), _function(function), _file(file), _line(line), _timestamp(timestamp()), _flushed(false) {
    if (_type == 'O' || _type == 'C') {
      std::lock_guard<std::mutex> lock(_outputMutex);
      if (!_enabled) return;
      *_output << ",{\"type\":\"" << _type << "\",\"at\":" << _timestamp << ",\"frame\":" << _frame << "}";
      //*_output << ",{\"type\":\"" << _type << "\",\"at\":" << _timestamp << ",\"frame\":" << _frame << ",\"file\":\"" << _file << "\",\"line\":" << _line << "}" << std::flush;
    }
  }

  Profiler::~Profiler() {
  }

  void Profiler::start(std::ostream *output) {
    _start = timestamp();
    _output = output;

    {
      std::lock_guard<std::mutex> lock(_frameMutex);
      _frameMap["APPLICATION"] = 0;
      _frameNames.resize(1);
      _frameNames[0] = "APPLICATION";
      _nextFrameId = 1;
    }

    std::lock_guard<std::mutex> lock(_outputMutex);
    *_output << "{\"$schema\":\"https://www.speedscope.app/file-format-schema.json\",\"profiles\":["
            << "{\"type\":\"evented\",\"name\":\"C++ Log Profile\",\"unit\":\"microseconds\",\"events\":["
            << "{\"type\":\"O\",\"at\":" << _start << ",\"frame\":" << 0 << "}";
  }

  void Profiler::end(std::vector<std::string> frames) {
    Size end = timestamp();
    std::lock_guard<std::mutex> lock(_outputMutex);
    if (!_enabled) return;
    *_output << ",{\"type\":\"C\",\"at\":" << end << ",\"frame\":" << 0 << "}";
    *_output << "],\"endValue\":" << end << ",\"startValue\":" << _start << "}],\"shared\":{\"frames\":[";

    if (frames.size() > 0) *_output << "{\"name\":\"" << frames[0] << "\"}";
    for (size_t i = 1; i < frames.size(); ++i) *_output << ",{\"name\":\"" << frames[i] << "\"}";
    *_output << "]},\"activeProfileIndex\":0}" << std::endl;
  }

  Size Profiler::getFrameId(const std::string &name, const std::string &file, const int line) {
    std::lock_guard<std::mutex> lock(_frameMutex);
    auto it = _frameMap.find(name);
    if (it != _frameMap.end()) {
      return it->second;
    }

    Size id = _nextFrameId++;
    _frameMap[name] = id;
    if (id >= _frameNames.size()) {
      _frameNames.resize(id + 1);
    }
    _frameNames[id] = name + " (" + file + ":" + std::to_string(line) + ")";
    return id;
  }

  std::vector<std::string> Profiler::getAllFrames() {
    std::lock_guard<std::mutex> lock(_frameMutex);
    return _frameNames;
  }

  void Profiler::end() {
    end(getAllFrames());
  }

  void Profiler::enable() {
    std::lock_guard<std::mutex> lock(_outputMutex);
    _enabled = true;
  }

  void Profiler::disable() {
    std::lock_guard<std::mutex> lock(_outputMutex);
    _enabled = false;
  }

  ProfilerScope::ProfilerScope(const std::string &name, const char *function, const char *file, int line)
      : _name(name), _function(function), _file(file), _line(line) {
    _frame = Profiler::getFrameId(name, file, line);
    Profiler('O', name, _frame, function, file, line);
  }

  ProfilerScope::~ProfilerScope() {
    Profiler('C', _name, _frame, _function, _file, _line);
  }

  bool Profiler::_enabled = false;
  std::ostream *Profiler::_output = &std::cerr;
  Size Profiler::_start = 0;
  std::unordered_map<std::string, Size> Profiler::_frameMap = {};
  std::vector<std::string> Profiler::_frameNames = {};
  std::mutex Profiler::_frameMutex = {};
  std::mutex Profiler::_outputMutex = {};
  Size Profiler::_nextFrameId = 1;
}

#endif
