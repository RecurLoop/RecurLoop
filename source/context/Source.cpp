#if !defined(__CONTEXT_SOURCE_CPP)
  #define __CONTEXT_SOURCE_CPP
  #include <context/Context.hpp>
  #include <algorithm>
  #include <cerrno>
  #include <cctype>
  #include <clocale>
  #include <cstdio>
  #include <cstdlib>
  #include <cwchar>
  #include <ctime>
  #include <fstream>
  #include <memory>
  #include <optional>
  #include <poll.h>
  #include <pwd.h>
  #include <streambuf>
  #include <string_view>
  #include <sys/ioctl.h>
  #include <sys/types.h>
  #include <termios.h>
  #include <unistd.h>
  #include <vector>

namespace context {
  namespace {
    std::string environment(std::string_view name) {
      const std::string key(name);
      const char *value = std::getenv(key.c_str());
      return value ? value : "";
    }

    std::string workingDirectory() {
      std::vector<char> buffer(256);
      while (!getcwd(buffer.data(), buffer.size()) && errno == ERANGE) buffer.resize(buffer.size() * 2);
      return buffer.empty() || !buffer.front() ? "?" : std::string(buffer.data());
    }

    std::string homeAbbreviated(std::string path) {
      const std::string home = environment("HOME");
      if (!home.empty() && path.starts_with(home) && (path.size() == home.size() || path[home.size()] == '/'))
        path.replace(0, home.size(), "~");
      return path;
    }

    std::string formatTime(const char *format) {
      const std::time_t now = std::time(nullptr);
      std::tm local{};
      localtime_r(&now, &local);
      char buffer[256]{};
      return std::strftime(buffer, sizeof(buffer), format, &local) ? buffer : "";
    }

    std::string commandOutput(const std::string &command) {
      std::string result;
      if (FILE *stream = popen(command.c_str(), "r")) {
        char buffer[512];
        while (const std::size_t count = std::fread(buffer, 1, sizeof(buffer), stream)) result.append(buffer, count);
        pclose(stream);
      }
      while (!result.empty() && result.back() == '\n') result.pop_back();
      return result;
    }

    std::string expandPromptCommandsAndVariables(std::string_view input, int status) {
      std::string result;
      for (std::size_t position = 0; position < input.size();) {
        if (input[position] == '`') {
          const std::size_t close = input.find('`', position + 1);
          if (close != std::string_view::npos) {
            result += commandOutput(std::string(input.substr(position + 1, close - position - 1)));
            position = close + 1;
            continue;
          }
        }
        if (input[position] != '$') {
          result += input[position++];
          continue;
        }
        if (position + 1 >= input.size()) {
          result += '$';
          ++position;
          continue;
        }
        if (input[position + 1] == '?') {
          result += std::to_string(status);
          position += 2;
          continue;
        }
        if (input[position + 1] == '$') {
          result += std::to_string(getpid());
          position += 2;
          continue;
        }
        if (input[position + 1] == '(') {
          std::size_t close = position + 2;
          int depth = 1;
          while (close < input.size() && depth > 0) {
            if (input[close] == '(') ++depth;
            else if (input[close] == ')') --depth;
            ++close;
          }
          if (depth == 0) {
            result += commandOutput(std::string(input.substr(position + 2, close - position - 3)));
            position = close;
            continue;
          }
        }
        std::size_t begin = position + 1;
        std::size_t finish = begin;
        if (input[begin] == '{') {
          begin += 1;
          finish = input.find('}', begin);
          if (finish != std::string_view::npos) {
            result += environment(input.substr(begin, finish - begin));
            position = finish + 1;
            continue;
          }
        } else if (std::isalpha(static_cast<unsigned char>(input[begin])) || input[begin] == '_') {
          finish = begin + 1;
          while (finish < input.size() &&
                 (std::isalnum(static_cast<unsigned char>(input[finish])) || input[finish] == '_'))
            ++finish;
          result += environment(input.substr(begin, finish - begin));
          position = finish;
          continue;
        }
        result += '$';
        ++position;
      }
      return result;
    }

    std::string bashPrompt(std::string_view specification, int status, std::size_t commandNumber) {
      std::string user = environment("USER");
      if (user.empty()) {
        if (const passwd *entry = getpwuid(geteuid())) user = entry->pw_name;
      }
      char hostBuffer[256]{};
      gethostname(hostBuffer, sizeof(hostBuffer) - 1);
      const std::string host(hostBuffer);
      const std::string cwd = workingDirectory();
      std::string decoded;
      for (std::size_t position = 0; position < specification.size(); ++position) {
        if (specification[position] != '\\' || position + 1 >= specification.size()) {
          decoded += specification[position];
          continue;
        }
        const char escape = specification[++position];
        if (escape == 'a') decoded += '\a';
        else if (escape == 'd') decoded += formatTime("%a %b %d");
        else if (escape == 'e') decoded += '\x1b';
        else if (escape == 'h') decoded += host.substr(0, host.find('.'));
        else if (escape == 'H') decoded += host;
        else if (escape == 'j') decoded += '0';
        else if (escape == 'l') {
          const char *terminal = ttyname(STDIN_FILENO);
          const std::string name = terminal ? terminal : "";
          decoded += name.substr(name.find_last_of('/') + 1);
        } else if (escape == 'n') decoded += '\n';
        else if (escape == 'r') decoded += '\r';
        else if (escape == 's') decoded += "Recurloop";
        else if (escape == 't') decoded += formatTime("%H:%M:%S");
        else if (escape == 'T') decoded += formatTime("%I:%M:%S");
        else if (escape == '@') decoded += formatTime("%I:%M %p");
        else if (escape == 'A') decoded += formatTime("%H:%M");
        else if (escape == 'u') decoded += user;
        else if (escape == 'v') decoded += PROJECT_VERSION;
        else if (escape == 'V') decoded += PROJECT_VERSION;
        else if (escape == 'w') decoded += homeAbbreviated(cwd);
        else if (escape == 'W') {
          const std::string abbreviated = homeAbbreviated(cwd);
          decoded += abbreviated == "~" ? abbreviated : abbreviated.substr(abbreviated.find_last_of('/') + 1);
        } else if (escape == '!' || escape == '#') decoded += std::to_string(commandNumber);
        else if (escape == '$') decoded += geteuid() == 0 ? '#' : '$';
        else if (escape == '\\') decoded += '\\';
        else if (escape == '[' || escape == ']') {
          // ANSI sequences are measured directly, so Bash's nonprinting
          // delimiters are metadata and do not belong in terminal output.
        } else if (escape == 'D' && position + 1 < specification.size() && specification[position + 1] == '{') {
          const std::size_t close = specification.find('}', position + 2);
          if (close != std::string_view::npos) {
            decoded += formatTime(std::string(specification.substr(position + 2, close - position - 2)).c_str());
            position = close;
          }
        } else if (escape >= '0' && escape <= '7') {
          int value = escape - '0';
          for (int count = 1; count < 3 && position + 1 < specification.size() && specification[position + 1] >= '0' &&
                                  specification[position + 1] <= '7';
               ++count)
            value = value * 8 + specification[++position] - '0';
          decoded += static_cast<char>(value);
        } else {
          decoded += '\\';
          decoded += escape;
        }
      }
      return expandPromptCommandsAndVariables(decoded, status);
    }

    std::size_t previousCharacter(std::string_view text, std::size_t position) {
      if (position == 0) return 0;
      --position;
      while (position > 0 && (static_cast<unsigned char>(text[position]) & 0xc0) == 0x80) --position;
      return position;
    }

    std::size_t nextCharacter(std::string_view text, std::size_t position) {
      if (position >= text.size()) return text.size();
      ++position;
      while (position < text.size() && (static_cast<unsigned char>(text[position]) & 0xc0) == 0x80) ++position;
      return position;
    }

    std::size_t displayWidth(std::string_view text) {
      std::size_t width = 0;
      std::mbstate_t state{};
      for (std::size_t position = 0; position < text.size();) {
        if (text[position] == '\x1b' && position + 1 < text.size()) {
          if (text[position + 1] == '[') {
            position += 2;
            while (position < text.size()) {
              const unsigned char byte = static_cast<unsigned char>(text[position++]);
              if (byte >= 0x40 && byte <= 0x7e) break;
            }
            continue;
          }
          if (text[position + 1] == ']') {
            position += 2;
            while (position < text.size() && text[position] != '\a' &&
                   !(text[position] == '\x1b' && position + 1 < text.size() && text[position + 1] == '\\'))
              ++position;
            if (position < text.size()) position = std::min(text.size(), position + (text[position] == '\a' ? 1 : 2));
            continue;
          }
        }
        wchar_t character = 0;
        const std::size_t bytes = std::mbrtowc(&character, text.data() + position, text.size() - position, &state);
        if (bytes == static_cast<std::size_t>(-1) || bytes == static_cast<std::size_t>(-2) || bytes == 0) {
          ++position;
          ++width;
          state = {};
          continue;
        }
        const int characterWidth = wcwidth(character);
        if (characterWidth > 0) width += static_cast<std::size_t>(characterWidth);
        position += bytes;
      }
      return width;
    }

    class TerminalMode {
    public:
      explicit TerminalMode(int descriptor) : descriptor(descriptor) {
        if (tcgetattr(descriptor, &original) != 0) return;
        termios raw = original;
        raw.c_iflag &= static_cast<tcflag_t>(~(BRKINT | ICRNL | INPCK | ISTRIP | IXON));
        raw.c_lflag &= static_cast<tcflag_t>(~(ECHO | ICANON | IEXTEN | ISIG));
        raw.c_cflag |= CS8;
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;
        active = tcsetattr(descriptor, TCSANOW, &raw) == 0;
      }

      ~TerminalMode() {
        if (active) tcsetattr(descriptor, TCSANOW, &original);
      }

      explicit operator bool() const {
        return active;
      }

    private:
      int descriptor;
      termios original{};
      bool active = false;
    };

    class InteractiveBuffer final : public std::streambuf {
    public:
      explicit InteractiveBuffer(Context &context) : context(context), output(*context.io.err) {
        std::setlocale(LC_CTYPE, "");
      }

    protected:
      int_type underflow() override {
        if (gptr() != nullptr && gptr() < egptr()) return traits_type::to_int_type(*gptr());

        std::optional<std::string> line = readLine();
        if (!line) return traits_type::eof();
        input = std::move(*line);
        input.push_back('\n');
        setg(input.data(), input.data(), input.data() + input.size());
        return traits_type::to_int_type(*gptr());
      }

    private:
      int readByte(int timeout = -1) {
        if (timeout >= 0) {
          pollfd descriptor{STDIN_FILENO, POLLIN, 0};
          int result = 0;
          do {
            result = poll(&descriptor, 1, timeout);
          } while (result < 0 && errno == EINTR);
          if (result <= 0 || !(descriptor.revents & POLLIN)) return -1;
        }

        unsigned char byte = 0;
        ssize_t result = 0;
        do {
          result = read(STDIN_FILENO, &byte, 1);
        } while (result < 0 && errno == EINTR);
        return result == 1 ? byte : -1;
      }

      std::size_t terminalColumns() const {
        winsize size{};
        if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0) return size.ws_col;
        return 80;
      }

      std::string prompt() const {
        if (const char *value = std::getenv("PS1"))
          return bashPrompt(value, context.exec.status, history.size() + 1);
        context::Values values = context.values();
        return values.contains("PS1") ? bashPrompt(values.get("PS1").format(), context.exec.status, history.size() + 1)
                                      : std::string{};
      }

      void refresh(const std::string &line, std::size_t cursor, const std::string &currentPrompt) {
        const std::size_t columns = terminalColumns();
        const std::size_t promptWidth = displayWidth(currentPrompt);
        const std::size_t available = columns > promptWidth + 1 ? columns - promptWidth - 1 : 1;

        std::size_t start = 0;
        while (start < cursor && displayWidth(std::string_view(line).substr(start, cursor - start)) > available)
          start = nextCharacter(line, start);

        std::size_t finish = cursor;
        while (finish < line.size()) {
          const std::size_t next = nextCharacter(line, finish);
          if (displayWidth(std::string_view(line).substr(start, next - start)) > available) break;
          finish = next;
        }

        output << "\r\x1b[2K" << currentPrompt << std::string_view(line).substr(start, finish - start);
        const std::size_t tailWidth = displayWidth(std::string_view(line).substr(cursor, finish - cursor));
        if (tailWidth > 0) output << "\x1b[" << tailWidth << 'D';
        output.flush();
      }

      std::optional<std::string> readPlainLine() {
        const std::string currentPrompt = prompt();
        output << currentPrompt;
        output.flush();
        std::string line;
        while (true) {
          const int byte = readByte();
          if (byte < 0) return line.empty() ? std::nullopt : std::optional<std::string>(std::move(line));
          if (byte == '\n' || byte == '\r') return line;
          line.push_back(static_cast<char>(byte));
        }
      }

      void historyMove(std::string &line, std::size_t &cursor, std::size_t &historyPosition, std::string &draft,
                       int direction) {
        if (history.empty()) return;
        if (direction < 0) {
          if (historyPosition == history.size()) draft = line;
          if (historyPosition > 0) --historyPosition;
        } else {
          if (historyPosition >= history.size()) return;
          ++historyPosition;
        }
        line = historyPosition < history.size() ? history[historyPosition] : draft;
        cursor = line.size();
      }

      static void wordBackward(const std::string &line, std::size_t &cursor) {
        while (cursor > 0 && std::isspace(static_cast<unsigned char>(line[previousCharacter(line, cursor)])))
          cursor = previousCharacter(line, cursor);
        while (cursor > 0 && !std::isspace(static_cast<unsigned char>(line[previousCharacter(line, cursor)])))
          cursor = previousCharacter(line, cursor);
      }

      static void wordForward(const std::string &line, std::size_t &cursor) {
        while (cursor < line.size() && std::isspace(static_cast<unsigned char>(line[cursor])))
          cursor = nextCharacter(line, cursor);
        while (cursor < line.size() && !std::isspace(static_cast<unsigned char>(line[cursor])))
          cursor = nextCharacter(line, cursor);
      }

      static void erasePreviousWord(std::string &line, std::size_t &cursor, std::string &yank) {
        const std::size_t finish = cursor;
        wordBackward(line, cursor);
        yank = line.substr(cursor, finish - cursor);
        line.erase(cursor, finish - cursor);
      }

      static void eraseNextWord(std::string &line, std::size_t &cursor, std::string &yank) {
        std::size_t finish = cursor;
        wordForward(line, finish);
        yank = line.substr(cursor, finish - cursor);
        line.erase(cursor, finish - cursor);
      }

      void historySearchBackward(std::string &line, std::size_t &cursor, std::size_t &historyPosition) {
        if (history.empty()) return;
        const std::string query = line;
        std::size_t position = std::min(historyPosition, history.size());
        while (position > 0) {
          --position;
          if (query.empty() || history[position].find(query) != std::string::npos) {
            historyPosition = position;
            line = history[position];
            cursor = line.size();
            return;
          }
        }
      }

      void escapeSequence(std::string &line, std::size_t &cursor, std::size_t &historyPosition, std::string &draft,
                          std::string &yank) {
        int byte = readByte(40);
        if (byte == 'b' || byte == 'B') {
          wordBackward(line, cursor);
          return;
        }
        if (byte == 'f' || byte == 'F') {
          wordForward(line, cursor);
          return;
        }
        if (byte == 'd' || byte == 'D') {
          eraseNextWord(line, cursor, yank);
          return;
        }
        if (byte == 127 || byte == 8) {
          erasePreviousWord(line, cursor, yank);
          return;
        }
        if (byte != '[' && byte != 'O') return;

        byte = readByte(40);
        std::string parameters;
        while ((byte >= '0' && byte <= '9') || byte == ';') {
          parameters.push_back(static_cast<char>(byte));
          byte = readByte(40);
        }

        const bool wordMotion =
            parameters == "3" || parameters == "5" || parameters == "7" || parameters.find(";3") != std::string::npos ||
            parameters.find(";5") != std::string::npos || parameters.find(";7") != std::string::npos;
        if (byte == 'A')
          historyMove(line, cursor, historyPosition, draft, -1);
        else if (byte == 'B')
          historyMove(line, cursor, historyPosition, draft, 1);
        else if (byte == 'C') {
          if (wordMotion)
            wordForward(line, cursor);
          else
            cursor = nextCharacter(line, cursor);
        } else if (byte == 'D') {
          if (wordMotion)
            wordBackward(line, cursor);
          else
            cursor = previousCharacter(line, cursor);
        } else if (byte == 'H')
          cursor = 0;
        else if (byte == 'F')
          cursor = line.size();
        else if (byte == '~' && !parameters.empty()) {
          const int number = std::atoi(parameters.c_str());
          if (number == 1 || number == 7)
            cursor = 0;
          else if (number == 4 || number == 8)
            cursor = line.size();
          else if (number == 3) {
            if (wordMotion)
              eraseNextWord(line, cursor, yank);
            else if (cursor < line.size())
              line.erase(cursor, nextCharacter(line, cursor) - cursor);
          }
        }
      }

      std::optional<std::string> readLine() {
        TerminalMode terminal(STDIN_FILENO);
        if (!terminal) return readPlainLine();

        std::string line;
        std::string draft;
        std::string yank;
        std::size_t cursor = 0;
        std::size_t historyPosition = history.size();
        const std::string currentPrompt = prompt();
        refresh(line, cursor, currentPrompt);

        while (true) {
          const int byte = readByte();
          if (byte < 0) {
            output << '\n';
            output.flush();
            return std::nullopt;
          }

          bool redraw = true;
          if (byte == '\r' || byte == '\n') {
            output << '\n';
            output.flush();
            if (!line.empty() && (history.empty() || history.back() != line)) history.push_back(line);
            return line;
          } else if (byte == 3) {
            output << "^C\n";
            output.flush();
            return std::string{};
          } else if (byte == 4) {
            if (line.empty()) {
              output << '\n';
              output.flush();
              return std::nullopt;
            }
            if (cursor < line.size()) line.erase(cursor, nextCharacter(line, cursor) - cursor);
          } else if (byte == 1) {
            cursor = 0;
          } else if (byte == 5) {
            cursor = line.size();
          } else if (byte == 2) {
            cursor = previousCharacter(line, cursor);
          } else if (byte == 6) {
            cursor = nextCharacter(line, cursor);
          } else if (byte == 11) {
            yank = line.substr(cursor);
            line.erase(cursor);
          } else if (byte == 12) {
            output << "\x1b[H\x1b[2J";
          } else if (byte == 14) {
            historyMove(line, cursor, historyPosition, draft, 1);
          } else if (byte == 16) {
            historyMove(line, cursor, historyPosition, draft, -1);
          } else if (byte == 18) {
            historySearchBackward(line, cursor, historyPosition);
          } else if (byte == 20) {
            if (cursor > 0 && line.size() > 1) {
              const std::size_t right = cursor == line.size() ? previousCharacter(line, cursor) : cursor;
              const std::size_t left = previousCharacter(line, right);
              const std::size_t rightEnd = nextCharacter(line, right);
              const std::string leftCharacter = line.substr(left, right - left);
              const std::string rightCharacter = line.substr(right, rightEnd - right);
              line.replace(left, rightEnd - left, rightCharacter + leftCharacter);
              cursor = rightEnd;
            }
          } else if (byte == 21) {
            yank = line.substr(0, cursor);
            line.erase(0, cursor);
            cursor = 0;
          } else if (byte == 23) {
            erasePreviousWord(line, cursor, yank);
          } else if (byte == 25) {
            line.insert(cursor, yank);
            cursor += yank.size();
          } else if (byte == 127 || byte == 8) {
            if (cursor > 0) {
              const std::size_t previous = previousCharacter(line, cursor);
              line.erase(previous, cursor - previous);
              cursor = previous;
            }
          } else if (byte == 27) {
            escapeSequence(line, cursor, historyPosition, draft, yank);
          } else if (byte >= 32) {
            line.insert(cursor, 1, static_cast<char>(byte));
            ++cursor;
          } else {
            redraw = false;
          }

          if (redraw) refresh(line, cursor, currentPrompt);
        }
      }

      Context &context;
      std::ostream &output;
      std::string input;
      std::vector<std::string> history;
    };

    class InteractiveInput final : public std::istream {
    public:
      explicit InteractiveInput(Context &context) : std::istream(nullptr), buffer(context) {
        rdbuf(&buffer);
      }

    private:
      InteractiveBuffer buffer;
    };
  } // namespace

  static INLINED void loadInput(Context &context, bool slide) {
    char character = 0;
    std::string source;
    source.reserve(context.config.source.buffer.size);

    while (source.size() < context.config.source.buffer.size && context.io.in->get(character)) {
      source.push_back(character);
      if (character == '\n') break;
    }

    if (!source.empty()) {
      if (slide) {
        char *str = context.source.buffer.str.data() + (context.source.buffer.offset / Byte::length);
        context.source.buffer.str = (str ? std::string(str, Bit::bytes(context.source.buffer.bits)) : "") + source;
        context.source.buffer.offset %= Byte::length;
      } else {
        context.source.buffer.str += source;
      }
      context.source.buffer.bits += source.size() * Byte::length;
    }

    context.source.more = (context.io.in && !context.io.in->eof()) || (context.exec.args.index < context.exec.args.count);

    DEBUG_LOG(LOAD, source);
  }

  static INLINED void openFile(Context& context, std::unique_ptr<std::istream>& input, const std::string& path) {
    auto stream = std::make_unique<std::ifstream>(path, std::ios::binary);
    if (!stream->is_open()) {
      const SourceLocation location{path, 1, 1};
      THROW_AT(location, "cannot open source file")
    }

    input = std::move(stream);
    context.io.in = input.get();
    context.source.path = path;
  }

  static INLINED void openString(Context& context,  std::unique_ptr<std::istream>& input, const std::string& value) {
    auto stream = std::make_unique<std::istringstream>(value);
    input = std::move(stream);
    context.io.in = input.get();
  }

  static INLINED void openStdin(Context &context, std::unique_ptr<std::istream> &input) {
    #if defined(_WIN32)
      const bool interactive = _isatty(_fileno(stdin));
    #else
      const bool interactive = isatty(fileno(stdin));
    #endif
    context.config.exception.continues = interactive;
    if (interactive) {
      input = std::make_unique<InteractiveInput>(context);
      context.io.in = input.get();
    } else {
      input.reset();
      context.io.in = &std::cin;
    }
  }

  static INLINED void nextInput(Context& context) {
    static std::unique_ptr<std::istream> input;

    std::string arg = context.exec.args.ptr[context.exec.args.index++];

    context.source.path = "";
    context.source.line = 1;
    context.source.position = 1;
    context.source.more = context.exec.args.index < context.exec.args.count;
    context.config.exception.continues = false;

    // End of options
    if (context.exec.args.options && arg == "--") {
      context.exec.args.options = false;

      if (context.source.more) {
        arg = context.exec.args.ptr[context.exec.args.index++];
        openFile(context, input, arg);
      }

      return;
    }

    // After '--' everything is a file
    if (!context.exec.args.options) {
      openFile(context, input, arg);
      return;
    }

    // stdin
    if (arg == "-") {
      openStdin(context, input);
      return;
    }

    // string
    if (arg == "-s" || arg == "--string") {
      if (!context.source.more) {
        const SourceLocation location{"<command-line>", 1, 1};
        THROW_AT(location, "option '" << arg << "' requires source code")
      }
      std::string value = context.exec.args.ptr[context.exec.args.index++];
      openString(context, input, value);
      return;
    }

    // explicit file
    if (arg == "-f" || arg == "--file") {
      if (!context.source.more) {
        const SourceLocation location{"<command-line>", 1, 1};
        THROW_AT(location, "option '" << arg << "' requires a path")
      }
      std::string path = context.exec.args.ptr[context.exec.args.index++];
      openFile(context, input, path);
      return;
    }

    // default: file
    openFile(context, input, arg);
  }

  void Source::load(Context &context, bool slide) {
    DEBUG_PROFILE_FUNCTION();
    if (context.io.in && !context.io.in->eof()) {
      loadInput(context, slide);
      return;
    }

    if (context.exec.args.index < context.exec.args.count) {
      nextInput(context);
      if (context.io.in && !context.io.in->eof()) {
        loadInput(context, slide);
        return;
      }
    }

    context.source.more = false;
  }

  static INLINED size_t utf8_display_width(const char *str, size_t bytes) {
    // should be called once per program
    std::setlocale(LC_CTYPE, "");

    size_t width = 0;
    const char *end = str + bytes;
    mbstate_t state{};

    while (str < end && *str) {
      wchar_t wc;
      size_t len = mbrtowc(&wc, str, end - str, &state);

      if (len == static_cast<size_t>(-1) || len == static_cast<size_t>(-2) || len == 0) {
        ++str;
        width += 1;
        std::memset(&state, 0, sizeof(state));
        continue;
      }

      int w = wcwidth(wc);
      width += (w > 0) ? w : 0;

      str += len;
    }

    return width;
  }

  void Source::progress(Context &context, Size bits) {
    DEBUG_PROFILE_FUNCTION();
    if (context.source.buffer.bits < bits) bits = context.source.buffer.bits;

    char *start = context.source.buffer.str.data() + (context.source.buffer.offset / Byte::length);
    char *from = start;
    char *to = start + (bits / Byte::length);

    Size newLines = 0;
    char *afterLastNewline = start;
    while (from < to) {
      if (*from++ == '\n') {
        ++newLines;
        afterLastNewline = from;
      }
    }

    if (newLines > 0)
      context.source.position = 1 + utf8_display_width(afterLastNewline, static_cast<size_t>(to - afterLastNewline));
    else
      context.source.position += utf8_display_width(start, bits / Byte::length);

    context.source.line += newLines;
    context.source.buffer.offset += bits;
    context.source.buffer.bits -= bits;

    DEBUG_LOG(PROGRESS, bits);
  }

  lexicon::Phrase Source::matchFirst(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide) {
    DEBUG_PROFILE_FUNCTION();
    auto *lexicon = dictionary.getLexicon();

    if (dictionary.isNull()) {
        lexicon::Phrase null = lexicon::Phrase(lexicon);
        return null;
    }

    auto result = lexicon::Match(lexicon, 0, 0, false);

    radix::node::Data *current = radix::node::Data::get(lexicon, dictionary.getAddress());
    Byte key = context.source.buffer.str.data();
    Size keyOffset = context.source.buffer.offset;
    Size keyBits = context.source.buffer.bits;
    Size keyProgress = keyOffset;

    while (true) {
        while (true) {
            lexicon::Match candidate(lexicon, current->address(lexicon), keyProgress - keyOffset, true);
            if (filter == nullptr || filter(&dictionary, &candidate)) {
                result = candidate;
                break;
            }

            if (keyBits <= keyProgress - keyOffset) {
                result.wantsMore(current->getChildGreater(lexicon) || current->getChildSmaller(lexicon));
                break;
            }

            radix::node::Data *child = nullptr;
            if (Bit(key, keyProgress).get())
                child = current->getChildGreater(lexicon);
            else
                child = current->getChildSmaller(lexicon);

            if (!child) {
                result.wantsMore(false);
                break;
            }

            Bit keyFore = Bit(key, keyProgress);
            Bit keyRear = Bit(key, keyBits + keyOffset);
            Bit childFore = child->getKeyFore(lexicon);
            Bit childRear = child->getKeyRear(lexicon);

            Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

            if (matchedBits < childRear - childFore) {
                result.wantsMore(keyRear - keyFore <= matchedBits);
                break;
            }

            current = child;
            keyProgress += matchedBits;
        }

        if (!result.wantsMore() || !context.source.more)
            break;

        Source::load(context, slide);

        keyProgress += context.source.buffer.offset - keyOffset;

        key = context.source.buffer.str.data();
        keyOffset = context.source.buffer.offset;
        keyBits = context.source.buffer.bits;
    }

    context.source.buffer.match = context.source.buffer.offset;
    Source::progress(context, result.getBits());

    lexicon::Phrase matched = lexicon::Phrase(result.item()).load();
    DEBUG_LOG(MATCH, matched.getKeyEscaped());

    return matched;
  }

  lexicon::Phrase Source::matchLongest(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide) {
    DEBUG_PROFILE_FUNCTION();
    auto *lexicon = dictionary.getLexicon();

    if (dictionary.isNull()) {
        lexicon::Phrase null = lexicon::Phrase(lexicon);
        return null;
    }

    auto result = lexicon::Match(lexicon, 0, 0, false);

    radix::node::Data *current = radix::node::Data::get(lexicon, dictionary.getAddress());
    Byte key = context.source.buffer.str.data();
    Size keyOffset = context.source.buffer.offset;
    Size keyBits = context.source.buffer.bits;
    Size keyProgress = keyOffset;

    while (true) {
        while (true) {
            lexicon::Match candidate(lexicon, current->address(lexicon), keyProgress - keyOffset, true);
            if (filter == nullptr || filter(&dictionary, &candidate)) {
                result = candidate;
            }

            if (keyBits <= keyProgress - keyOffset) {
                result.wantsMore(current->getChildGreater(lexicon) || current->getChildSmaller(lexicon));
                break;
            }

            radix::node::Data *child = nullptr;
            if (Bit(key, keyProgress).get())
                child = current->getChildGreater(lexicon);
            else
                child = current->getChildSmaller(lexicon);

            if (!child) {
                result.wantsMore(false);
                break;
            }

            Bit keyFore = Bit(key, keyProgress);
            Bit keyRear = Bit(key, keyBits + keyOffset);
            Bit childFore = child->getKeyFore(lexicon);
            Bit childRear = child->getKeyRear(lexicon);

            Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

            if (matchedBits < childRear - childFore) {
                result.wantsMore(keyRear - keyFore <= matchedBits);
                break;
            }

            current = child;
            keyProgress += matchedBits;
        }

        if (!result.wantsMore() || !context.source.more)
            break;

        Source::load(context, slide);

        keyProgress += context.source.buffer.offset - keyOffset;

        key = context.source.buffer.str.data();
        keyOffset = context.source.buffer.offset;
        keyBits = context.source.buffer.bits;
    }

    context.source.buffer.match = context.source.buffer.offset;
    Source::progress(context, result.getBits());

    lexicon::Phrase matched = lexicon::Phrase(result.item()).load();
    DEBUG_LOG(MATCH, matched.getKeyEscaped());

    return matched;
  }

  lexicon::Phrase Source::matchExact(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide) {
    DEBUG_PROFILE_FUNCTION();
    auto *lexicon = dictionary.getLexicon();

    if (dictionary.isNull()) {
        lexicon::Phrase null = lexicon::Phrase(lexicon);
        return null;
    }

    auto result = lexicon::Match(lexicon, 0, 0, false);

    radix::node::Data *current = radix::node::Data::get(lexicon, dictionary.getAddress());
    Byte key = context.source.buffer.str.data();
    Size keyOffset = context.source.buffer.offset;
    Size keyBits = context.source.buffer.bits;
    Size keyProgress = keyOffset;

    while (true) {
        while (true) {
            if (keyBits <= keyProgress - keyOffset) {
                lexicon::Match candidate(lexicon, current->address(lexicon), keyProgress - keyOffset, true);
                if (filter == nullptr || filter(&dictionary, &candidate)) {
                    result = candidate;
                    result.wantsMore(false);
                    break;
                }
            }

            if (keyBits <= keyProgress - keyOffset) {
                result.wantsMore(current->getChildGreater(lexicon) || current->getChildSmaller(lexicon));
                break;
            }

            radix::node::Data *child = nullptr;
            if (Bit(key, keyProgress).get())
                child = current->getChildGreater(lexicon);
            else
                child = current->getChildSmaller(lexicon);

            if (!child) {
                result.wantsMore(false);
                break;
            }

            Bit keyFore = Bit(key, keyProgress);
            Bit keyRear = Bit(key, keyBits + keyOffset);
            Bit childFore = child->getKeyFore(lexicon);
            Bit childRear = child->getKeyRear(lexicon);

            Size matchedBits = Bit::compare(keyFore, keyRear, childFore, childRear);

            if (matchedBits < childRear - childFore) {
                result.wantsMore(keyRear - keyFore <= matchedBits);
                break;
            }

            current = child;
            keyProgress += matchedBits;
        }

        if (!result.wantsMore() || !context.source.more)
            break;

        Source::load(context, slide);

        keyProgress += context.source.buffer.offset - keyOffset;

        key = context.source.buffer.str.data();
        keyOffset = context.source.buffer.offset;
        keyBits = context.source.buffer.bits;
    }

    context.source.buffer.match = context.source.buffer.offset;
    Source::progress(context, result.getBits());

    lexicon::Phrase matched = lexicon::Phrase(result.item()).load();
    DEBUG_LOG(MATCH, matched.getKeyEscaped());

    return matched;
  }
} // namespace context

#endif
