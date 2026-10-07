#include <utilities/LineEditor.hpp>

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <clocale>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <poll.h>
#include <sstream>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <utility>

namespace utilities {
  TerminalMode::TerminalMode(int descriptor) : descriptor_(descriptor) {
    if (descriptor_ < 0 || tcgetattr(descriptor_, &original_) != 0) return;
    termios raw = original_;
    raw.c_iflag &= static_cast<tcflag_t>(~(BRKINT | ICRNL | INPCK | ISTRIP | IXON));
    raw.c_lflag &= static_cast<tcflag_t>(~(ECHO | ICANON | IEXTEN | ISIG));
    raw.c_cflag |= CS8;
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    active_ = tcsetattr(descriptor_, TCSANOW, &raw) == 0;
  }

  TerminalMode::~TerminalMode() {
    if (active_) tcsetattr(descriptor_, TCSANOW, &original_);
  }

  LineEditor::LineEditor(Reader reader, Writer writer, Columns columns, Completer completer, Highlighter highlighter,
                         bool shellIntegration)
      : reader_(std::move(reader)), writer_(std::move(writer)), columns_(std::move(columns)),
        completer_(std::move(completer)), highlighter_(std::move(highlighter)), shellIntegration_(shellIntegration) {
    std::setlocale(LC_CTYPE, "");
  }

  int LineEditor::readDescriptor(int descriptor, int timeoutMilliseconds) {
    if (timeoutMilliseconds >= 0) {
      pollfd pollDescriptor{descriptor, POLLIN, 0};
      int result = 0;
      do {
        result = poll(&pollDescriptor, 1, timeoutMilliseconds);
      } while (result < 0 && errno == EINTR);
      if (result == 0) return Timeout;
      if (result < 0 || !(pollDescriptor.revents & (POLLIN | POLLHUP))) return End;
    }

    unsigned char byte = 0;
    ssize_t result = 0;
    do {
      result = read(descriptor, &byte, 1);
    } while (result < 0 && errno == EINTR);
    return result == 1 ? static_cast<int>(byte) : End;
  }

  bool LineEditor::writeDescriptor(int descriptor, std::string_view text) {
    std::size_t offset = 0;
    while (offset < text.size()) {
      ssize_t written = 0;
      do {
        written = write(descriptor, text.data() + offset, text.size() - offset);
      } while (written < 0 && errno == EINTR);
      if (written <= 0) return false;
      offset += static_cast<std::size_t>(written);
    }
    return true;
  }

  std::size_t LineEditor::descriptorColumns(int descriptor) {
    winsize size{};
    if (descriptor >= 0 && ioctl(descriptor, TIOCGWINSZ, &size) == 0 && size.ws_col > 0) return size.ws_col;
    return 80;
  }

  std::size_t LineEditor::previousCharacter(std::string_view text, std::size_t position) {
    if (position == 0) return 0;
    --position;
    while (position > 0 && (static_cast<unsigned char>(text[position]) & 0xc0) == 0x80) --position;
    return position;
  }

  std::size_t LineEditor::nextCharacter(std::string_view text, std::size_t position) {
    if (position >= text.size()) return text.size();
    ++position;
    while (position < text.size() && (static_cast<unsigned char>(text[position]) & 0xc0) == 0x80) ++position;
    return position;
  }

  std::size_t LineEditor::displayWidth(std::string_view text) {
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

  bool LineEditor::wordCharacter(unsigned char byte) {
    return byte >= 0x80 || std::isalnum(byte) || byte == '_';
  }

  void LineEditor::wordBackward(const std::string &line, std::size_t &cursor) {
    while (cursor > 0) {
      const std::size_t previous = previousCharacter(line, cursor);
      if (wordCharacter(static_cast<unsigned char>(line[previous]))) break;
      cursor = previous;
    }
    while (cursor > 0) {
      const std::size_t previous = previousCharacter(line, cursor);
      if (!wordCharacter(static_cast<unsigned char>(line[previous]))) break;
      cursor = previous;
    }
  }

  void LineEditor::wordForward(const std::string &line, std::size_t &cursor) {
    while (cursor < line.size() && wordCharacter(static_cast<unsigned char>(line[cursor])))
      cursor = nextCharacter(line, cursor);
    while (cursor < line.size() && !wordCharacter(static_cast<unsigned char>(line[cursor])))
      cursor = nextCharacter(line, cursor);
  }

  void LineEditor::erasePreviousWord(std::string &line, std::size_t &cursor, std::string &yank) {
    const std::size_t finish = cursor;
    wordBackward(line, cursor);
    yank = line.substr(cursor, finish - cursor);
    line.erase(cursor, finish - cursor);
  }

  void LineEditor::eraseNextWord(std::string &line, std::size_t &cursor, std::string &yank) {
    std::size_t finish = cursor;
    wordForward(line, finish);
    yank = line.substr(cursor, finish - cursor);
    line.erase(cursor, finish - cursor);
  }

  std::string LineEditor::colored(const std::string &line, std::size_t start, std::size_t end) {
    if (!highlighter_) return line.substr(start, end - start);
    if (line != highlightedLine_) {
      highlightedLine_ = line;
      colors_.clear();
      try {
        colors_ = highlighter_(line);
      } catch (...) { /* Editing remains usable on inspection failure. */
      }
    }
    std::vector<unsigned> colors(end - start, 0x1000000);
    for (const auto &span : colors_) {
      if (span.start >= span.end || span.rgb > 0xffffff) continue;
      const auto begin = std::max(start, span.start);
      const auto finish = std::min(end, span.end);
      for (auto index = begin; index < finish; ++index) colors[index - start] = span.rgb;
    }
    std::ostringstream output;
    unsigned previous = 0x1000000;
    for (auto index = start; index < end; ++index) {
      const unsigned color = colors[index - start];
      if (color != previous) {
        if (color == 0x1000000)
          output << "\x1b[0m";
        else
          output << "\x1b[38;2;" << (color >> 16) << ';' << ((color >> 8) & 255) << ';' << (color & 255) << 'm';
        previous = color;
      }
      if (line[index] == '\n')
        output << "\r\n";
      else if (line[index] == '\t')
        output << "    ";
      else
        output << line[index];
    }
    if (previous != 0x1000000) output << "\x1b[0m";
    return output.str();
  }

  void LineEditor::submit(const std::string &line, std::string_view prompt) {
    // Put the cursor after the complete command before saving it in scrollback.
    refresh(line, line.size(), prompt);
    if (shellIntegration_) {
      constexpr char digits[] = "0123456789abcdef";
      std::string escaped;
      for (unsigned char byte : line) {
        if (byte <= 32 || byte == ';' || byte == 127) {
          escaped += "\\x";
          escaped += digits[byte >> 4];
          escaped += digits[byte & 15];
        } else if (byte == '\\')
          escaped += "\\\\";
        else
          escaped += static_cast<char>(byte);
      }
      writer_("\x1b]633;E;" + escaped + "\x07");
    }
    writer_("\n");
    if (shellIntegration_) writer_("\x1b]633;C\x07");
  }

  void LineEditor::refresh(const std::string &line, std::size_t cursor, std::string_view prompt) {
    const std::size_t columns = std::max<std::size_t>(1, columns_ ? columns_() : 80);
    const std::size_t promptWidth = displayWidth(prompt);
    // Track terminal rows, including wide Unicode characters wrapping before
    // the right margin. ANSI colors are added only after measuring plain text.
    const auto position = [&](std::size_t end) {
      std::size_t row = promptWidth / columns;
      std::size_t column = promptWidth % columns;
      for (std::size_t index = 0; index < end;) {
        const auto next = std::min(end, nextCharacter(line, index));
        if (line[index] == '\n') {
          ++row;
          column = 0;
        } else {
          const auto width = line[index] == '\t' ? 4 : displayWidth(std::string_view(line).substr(index, next - index));
          if (width && column + width > columns) {
            ++row;
            column = 0;
          }
          column += width;
        }
        index = next;
      }
      return row * columns + column;
    };
    const auto finish = position(line.size());
    const auto target = position(cursor);
    std::ostringstream output;
    output << "\r";
    if (cursorRow_) output << "\x1b[" << cursorRow_ << 'A';
    output << "\x1b[J" << prompt;
    if (shellIntegration_) output << "\x1b]633;B\x07";
    output << colored(line, 0, line.size());
    // At the exact right margin terminals defer wrapping until the next byte.
    if (finish && finish % columns == 0) output << " \r";
    const auto endRow = finish / columns;
    const auto targetRow = target / columns;
    if (endRow > targetRow) output << "\x1b[" << endRow - targetRow << 'A';
    output << "\r";
    if (target % columns) output << "\x1b[" << target % columns << 'C';
    cursorRow_ = targetRow;
    writer_(output.str());
  }

  void LineEditor::historyMove(std::string &line, std::size_t &cursor, std::size_t &historyPosition, std::string &draft,
                               int direction) {
    if (history_.empty()) return;
    if (direction < 0) {
      if (historyPosition == history_.size()) draft = line;
      if (historyPosition > 0) --historyPosition;
    } else {
      if (historyPosition >= history_.size()) return;
      ++historyPosition;
    }
    line = historyPosition < history_.size() ? history_[historyPosition] : draft;
    cursor = line.size();
  }

  void LineEditor::historySearchBackward(std::string &line, std::size_t &cursor, std::size_t &historyPosition) {
    if (history_.empty()) return;
    const std::string query = line;
    std::size_t position = std::min(historyPosition, history_.size());
    while (position > 0) {
      --position;
      if (query.empty() || history_[position].find(query) != std::string::npos) {
        historyPosition = position;
        line = history_[position];
        cursor = line.size();
        return;
      }
    }
  }

  void LineEditor::escapeSequence(std::string &line, std::size_t &cursor, std::size_t &historyPosition,
                                  std::string &draft, std::string &yank) {
    int byte = reader_(40);
    if (byte == Timeout || byte == End) return;

    // Readline-compatible Meta bindings also cover terminals that encode
    // Alt/Ctrl word movement as ESC-b / ESC-f.
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

    byte = reader_(40);
    if (byte == Timeout || byte == End) return;
    std::string parameters;
    while ((byte >= '0' && byte <= '9') || byte == ';' || byte == ':') {
      parameters.push_back(static_cast<char>(byte));
      byte = reader_(40);
      if (byte == Timeout || byte == End) return;
    }

    int modifier = 0;
    if (!parameters.empty()) {
      const std::size_t separator = parameters.find_last_of(";:");
      const std::string_view tail = separator == std::string::npos ? std::string_view(parameters)
                                                                   : std::string_view(parameters).substr(separator + 1);
      if (!tail.empty()) modifier = std::atoi(std::string(tail).c_str());
    }
    const bool wordMotion = modifier == 3 || modifier == 5 || modifier == 6 || modifier == 7 || modifier == 8 ||
                            parameters == "5" || parameters == "3";

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
      if (number == 200) {
        constexpr std::string_view finish = "\x1b[201~";
        std::string pending;
        std::string pasted;
        bool carriageReturn = false;
        while (true) {
          const int next = reader_(-1);
          if (next == End) break;
          if (next == Timeout) continue;
          pending.push_back(static_cast<char>(next));
          if (pending == finish) break;
          while (!pending.empty() && !finish.starts_with(pending)) {
            const unsigned char value = pending.front();
            pending.erase(0, 1);
            if (value == '\r')
              pasted.push_back('\n');
            else if (value == '\n') {
              if (!carriageReturn) pasted.push_back('\n');
            } else if (value == '\t' || value >= 32)
              pasted.push_back(static_cast<char>(value));
            carriageReturn = value == '\r';
          }
        }
        line.insert(cursor, pasted);
        cursor += pasted.size();
      } else if (number == 1 || number == 7)
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

  void LineEditor::remember(const std::string &line) {
    const bool meaningful =
        std::any_of(line.begin(), line.end(), [](unsigned char byte) { return !std::isspace(byte); });
    if (!meaningful || (!history_.empty() && history_.back() == line)) return;
    constexpr std::size_t MaxHistory = 1000;
    if (history_.size() == MaxHistory) history_.erase(history_.begin());
    history_.push_back(line);
  }

  LineResult LineEditor::readLine(std::string_view prompt) {
    // Keep newlines inside bracketed paste in the edit buffer until Enter.
    struct PasteMode {
      Writer &writer;
      ~PasteMode() {
        writer("\x1b[?2004l");
      }
    } pasteMode{writer_};
    writer_("\x1b[?2004h");
    std::string line;
    std::string draft;
    std::string yank;
    std::size_t cursor = 0;
    std::size_t historyPosition = history_.size();
    cursorRow_ = 0;
    if (shellIntegration_) writer_("\x1b]633;A\x07");
    refresh(line, cursor, prompt);

    int queued = Timeout;
    while (true) {
      const int byte = queued != Timeout ? std::exchange(queued, Timeout) : reader_(-1);
      if (byte == End) {
        if (line.empty()) {
          writer_("\n");
          return {LineStatus::End, {}};
        }
        submit(line, prompt);
        remember(line);
        return {LineStatus::Line, std::move(line)};
      }
      if (byte == Timeout) continue;

      bool redraw = true;
      if (byte == '\r' || byte == '\n') {
        submit(line, prompt);
        remember(line);
        return {LineStatus::Line, std::move(line)};
      } else if (byte == '\t' && completer_) {
        auto completion = completer_(line, cursor);
        auto &candidates = completion.candidates;
        if (completion.start <= cursor && !candidates.empty()) {
          std::sort(candidates.begin(), candidates.end());
          candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());
          std::string common = candidates.front();
          for (const auto &candidate : candidates) {
            std::size_t length = 0;
            while (length < common.size() && length < candidate.size() && common[length] == candidate[length]) ++length;
            common.resize(length);
          }
          // Do not insert a partial UTF-8 character from a common byte prefix.
          while (!common.empty() && common.size() < candidates.front().size() &&
                 (static_cast<unsigned char>(candidates.front()[common.size()]) & 0xc0) == 0x80)
            common.pop_back();
          // An escaped filename prefix must not end halfway through an escape.
          std::size_t backslashes = 0;
          for (std::size_t index = common.size(); index > 0 && common[index - 1] == '\\'; --index) ++backslashes;
          if (candidates.size() > 1 && backslashes % 2 != 0) common.pop_back();
          if (common.size() > cursor - completion.start) {
            line.replace(completion.start, cursor - completion.start, common);
            cursor = completion.start + common.size();
          } else if (candidates.size() > 1) {
            refresh(line, line.size(), prompt);
            writer_("\n");
            for (const auto &candidate : candidates) {
              writer_(candidate);
              writer_("\n");
            }
            cursorRow_ = 0;
            if (shellIntegration_) writer_("\x1b]633;A\x07");
          }
        }
      } else if (byte == 3) {
        refresh(line, line.size(), prompt);
        writer_("^C\n");
        return {LineStatus::Interrupt, {}};
      } else if (byte == 4) {
        if (line.empty()) {
          writer_("\n");
          return {LineStatus::End, {}};
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
        writer_("\x1b[H\x1b[2J");
        cursorRow_ = 0;
        if (shellIntegration_) writer_("\x1b]633;A\x07");
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

      // Drain already queued keystrokes before coloring/redrawing. This
      // coalesces pasted text and avoids requests for partial UTF-8 bytes.
      if (redraw) {
        queued = reader_(0);
        if (queued == Timeout) refresh(line, cursor, prompt);
      }
    }
  }
} // namespace utilities
