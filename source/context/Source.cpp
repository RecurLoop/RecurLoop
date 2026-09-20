#if !defined(__CONTEXT_SOURCE_CPP)
  #define __CONTEXT_SOURCE_CPP
  #include <context/Context.hpp>
  #include <utilities/Prompt.hpp>
  #include <utilities/LineEditor.hpp>
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

    class InteractiveBuffer final : public std::streambuf {
    public:
      explicit InteractiveBuffer(Context &context)
          : context(context), output(*context.io.err),
            editor(
                [](int timeout) { return utilities::LineEditor::readDescriptor(STDIN_FILENO, timeout); },
                [this](std::string_view text) {
                  output.write(text.data(), static_cast<std::streamsize>(text.size()));
                  output.flush();
                  return static_cast<bool>(output);
                },
                [] { return utilities::LineEditor::descriptorColumns(STDIN_FILENO); }) {}

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
      std::string prompt() const {
        context::Values values = context.values();
        if (values.contains("PS1"))
          return bashPrompt(values.get("PS1").format(), context.exec.status, editor.history().size() + 1);
        if (const char *value = std::getenv("PS1"))
          return bashPrompt(value, context.exec.status, editor.history().size() + 1);
        return std::string(utilities::prompt::Default);
      }

      std::optional<std::string> readLine() {
        utilities::TerminalMode terminal(STDIN_FILENO);
        if (!terminal) {
          output << prompt();
          output.flush();
          std::string line;
          if (!std::getline(std::cin, line)) return std::nullopt;
          return line;
        }

        while (true) {
          utilities::LineResult result = editor.readLine(prompt());
          if (result.status == utilities::LineStatus::End) return std::nullopt;
          if (result.status == utilities::LineStatus::Interrupt) continue;
          return std::move(result.line);
        }
      }

      Context &context;
      std::ostream &output;
      utilities::LineEditor editor;
      std::string input;
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

    // Language-state operations are handled by Recurloop before the first
    // source input. Keeping them out of Source makes the public flow explicit:
    // reset/import first, then source files/strings/stdin.
    if (arg == "--reset" || arg == "--import" || arg == "--library" || arg == "--library-path") {
      const SourceLocation location{"<command-line>", 1, 1};
      THROW_AT(location, "option '" << arg << "' must appear before source input")
    }
    if (arg == "--bootstrap" || arg == "--language-image" || arg == "--engine-image") {
      const SourceLocation location{"<command-line>", 1, 1};
      THROW_AT(location, "option '" << arg << "' was removed; use --reset and --import")
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
