#pragma once

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

#include <termios.h>

namespace utilities {
  enum class LineStatus {
    Line,
    End,
    Interrupt,
  };

  struct LineResult {
    LineStatus status = LineStatus::End;
    std::string line;
  };

  // Temporarily puts a local terminal into byte-oriented mode. The previous
  // settings are restored before user code executes, so terminal signals keep
  // their ordinary process semantics outside line editing.
  class TerminalMode {
  public:
    explicit TerminalMode(int descriptor);
    TerminalMode(const TerminalMode &) = delete;
    TerminalMode &operator=(const TerminalMode &) = delete;
    ~TerminalMode();

    explicit operator bool() const { return active_; }

  private:
    int descriptor_ = -1;
    termios original_{};
    bool active_ = false;
  };

  // Small transport-independent line editor. The transport only supplies one
  // byte reader, one writer and optionally terminal width. History belongs to
  // the editor instance, so every Session/console client gets independent
  // navigation without putting terminal state into Context.
  class LineEditor {
  public:
    static constexpr int End = -1;
    static constexpr int Timeout = -2;

    using Reader = std::function<int(int timeoutMilliseconds)>;
    using Writer = std::function<bool(std::string_view)>;
    using Columns = std::function<std::size_t()>;

    LineEditor(Reader reader, Writer writer, Columns columns = {});

    LineResult readLine(std::string_view prompt);
    const std::vector<std::string> &history() const { return history_; }
    void clearHistory() { history_.clear(); }

    static int readDescriptor(int descriptor, int timeoutMilliseconds = -1);
    static bool writeDescriptor(int descriptor, std::string_view text);
    static std::size_t descriptorColumns(int descriptor);

  private:
    void refresh(const std::string &line, std::size_t cursor, std::string_view prompt);
    void historyMove(std::string &line, std::size_t &cursor, std::size_t &historyPosition,
                     std::string &draft, int direction);
    void historySearchBackward(std::string &line, std::size_t &cursor, std::size_t &historyPosition);
    void escapeSequence(std::string &line, std::size_t &cursor, std::size_t &historyPosition,
                        std::string &draft, std::string &yank);
    void remember(const std::string &line);

    static std::size_t previousCharacter(std::string_view text, std::size_t position);
    static std::size_t nextCharacter(std::string_view text, std::size_t position);
    static std::size_t displayWidth(std::string_view text);
    static bool wordCharacter(unsigned char byte);
    static void wordBackward(const std::string &line, std::size_t &cursor);
    static void wordForward(const std::string &line, std::size_t &cursor);
    static void erasePreviousWord(std::string &line, std::size_t &cursor, std::string &yank);
    static void eraseNextWord(std::string &line, std::size_t &cursor, std::string &yank);

    Reader reader_;
    Writer writer_;
    Columns columns_;
    std::vector<std::string> history_;
  };
} // namespace utilities
