#include <gtest/gtest.h>

#include <utilities/LineEditor.hpp>

#include <deque>
#include <string>

namespace {
  struct ScriptedConsole {
    std::deque<int> input;
    std::string output;

    void push(std::string_view bytes) {
      for (unsigned char byte : bytes) input.push_back(byte);
    }

    utilities::LineEditor editor(
        utilities::LineEditor::Columns columns = [] { return 120; },
        utilities::LineEditor::Highlighter highlighter = {}, bool integration = false) {
      return utilities::LineEditor(
          [this](int) {
            if (input.empty()) return utilities::LineEditor::End;
            const int byte = input.front();
            input.pop_front();
            return byte;
          },
          [this](std::string_view text) {
            output.append(text);
            return true;
          },
          std::move(columns), {}, std::move(highlighter), integration);
    }
  };
} // namespace

TEST(LineEditor, HistoryRestoresDraftAfterNavigation) {
  ScriptedConsole console;
  auto editor = console.editor();

  console.push("first\n");
  EXPECT_EQ(editor.readLine("> ").line, "first");

  console.push("draft\x1b[A\x1b[B\n");
  const auto second = editor.readLine("> ");
  EXPECT_EQ(second.status, utilities::LineStatus::Line);
  EXPECT_EQ(second.line, "draft");
}

TEST(LineEditor, CtrlArrowMovesByCodeWord) {
  ScriptedConsole console;
  auto editor = console.editor();

  console.push("alpha beta\x1b[1;5DX\n");
  EXPECT_EQ(editor.readLine("> ").line, "alpha Xbeta");

  console.push("alpha beta\x01\x1b[1;5CX\n");
  EXPECT_EQ(editor.readLine("> ").line, "alpha Xbeta");
}

TEST(LineEditor, CtrlCInterruptsCurrentLineWithoutAddingHistory) {
  ScriptedConsole console;
  auto editor = console.editor();

  console.push("discard\x03");
  const auto interrupted = editor.readLine("> ");
  EXPECT_EQ(interrupted.status, utilities::LineStatus::Interrupt);
  EXPECT_TRUE(editor.history().empty());
  EXPECT_NE(console.output.find("^C\n"), std::string::npos);

  console.push("kept\n");
  const auto kept = editor.readLine("> ");
  EXPECT_EQ(kept.status, utilities::LineStatus::Line);
  EXPECT_EQ(kept.line, "kept");
  ASSERT_EQ(editor.history().size(), 1u);
  EXPECT_EQ(editor.history().front(), "kept");
}

TEST(LineEditor, TabCompletesAtCursorAndPreservesTail) {
  ScriptedConsole console;
  utilities::LineEditor completing(
      [&console](int) {
        if (console.input.empty()) return utilities::LineEditor::End;
        int byte = console.input.front();
        console.input.pop_front();
        return byte;
      },
      [&console](std::string_view text) {
        console.output += text;
        return true;
      },
      {},
      [](std::string_view line, std::size_t cursor) {
        EXPECT_EQ(line, "echo al tail");
        EXPECT_EQ(cursor, 7u);
        return utilities::LineEditor::Completion{5, {"alpha"}};
      });
  console.push("echo al tail\x1b[D\x1b[D\x1b[D\x1b[D\x1b[D\t\n");
  EXPECT_EQ(completing.readLine("> ").line, "echo alpha tail");
}

TEST(LineEditor, TabExtendsCommonPrefixThenDisplaysAlternatives) {
  ScriptedConsole console;
  utilities::LineEditor editor(
      [&console](int) {
        if (console.input.empty()) return utilities::LineEditor::End;
        int byte = console.input.front();
        console.input.pop_front();
        return byte;
      },
      [&console](std::string_view text) {
        console.output += text;
        return true;
      },
      {},
      [](std::string_view, std::size_t) {
        return utilities::LineEditor::Completion{0, {"alphabet", "alpha", "alpha"}};
      });
  console.push("al\t\t\n");
  EXPECT_EQ(editor.readLine("> ").line, "alpha");
  EXPECT_NE(console.output.find("\nalpha\nalphabet\n"), std::string::npos);
}

TEST(LineEditor, AmbiguousEscapedPathsDoNotLeaveAnIncompleteEscape) {
  ScriptedConsole console;
  utilities::LineEditor editor(
      [&console](int) {
        if (console.input.empty()) return utilities::LineEditor::End;
        int byte = console.input.front();
        console.input.pop_front();
        return byte;
      },
      [&console](std::string_view text) { console.output += text; return true; }, {},
      [](std::string_view, std::size_t) {
        return utilities::LineEditor::Completion{0, {"file\\ name", "file\\!name"}};
      });
  console.push("fi\t\n");
  EXPECT_EQ(editor.readLine("> ").line, "file");
}

TEST(LineEditor, WrappedCommandsRemainCompleteInScrollback) {
  ScriptedConsole console;
  auto editor = console.editor([] { return 8; });
  console.push("abcdefghijk");
  console.input.push_back(utilities::LineEditor::Timeout);
  console.push("l\x01Z\x05\n");
  EXPECT_EQ(editor.readLine("> ").line, "Zabcdefghijkl");
  EXPECT_NE(console.output.find("Zabcdefghijkl"), std::string::npos);
  EXPECT_NE(console.output.find("\x1b[1A"), std::string::npos);
}

TEST(LineEditor, HighlightsInputWithoutChangingSourceOrHistory) {
  ScriptedConsole console;
  auto editor = console.editor(
      [] { return 8; },
      [](std::string_view line) { return std::vector<utilities::LineEditor::ColorSpan>{{0, line.size(), 0x123456}}; });
  console.push("hello\n");
  EXPECT_EQ(editor.readLine("> ").line, "hello");
  EXPECT_EQ(editor.history(), (std::vector<std::string>{"hello"}));
  EXPECT_NE(console.output.find("\x1b[38;2;18;52;86mhello\x1b[0m"), std::string::npos);
}

TEST(LineEditor, ReportsEscapedCommandForVSCodeShellIntegration) {
  ScriptedConsole console;
  auto editor = console.editor([] { return 120; }, {}, true);
  console.push("print 1;\\name\n");
  EXPECT_EQ(editor.readLine("> ").line, "print 1;\\name");
  const auto prompt = console.output.find("\x1b]633;A\x07");
  const auto input = console.output.find("\x1b]633;B\x07", prompt);
  const auto command = console.output.find("\x1b]633;E;print\\x201\\x3b\\\\name\x07", input);
  const auto execution = console.output.find("\x1b]633;C\x07", command);
  ASSERT_NE(prompt, std::string::npos);
  ASSERT_NE(input, std::string::npos);
  ASSERT_NE(command, std::string::npos);
  ASSERT_NE(execution, std::string::npos);
  EXPECT_LT(prompt, input);
  EXPECT_LT(input, command);
  EXPECT_LT(command, execution);
}

TEST(LineEditor, PastedInputIsHighlightedOnce) {
  ScriptedConsole console;
  int requests = 0;
  auto editor = console.editor([] { return 80; },
                               [&](std::string_view line) {
                                 ++requests;
                                 EXPECT_EQ(line, "print 123456789");
                                 return std::vector<utilities::LineEditor::ColorSpan>{{0, line.size(), 0x123456}};
                               });
  console.push("print 123456789\n");
  EXPECT_EQ(editor.readLine("> ").line, "print 123456789");
  EXPECT_EQ(requests, 1);
}

TEST(LineEditor, BracketedPastePreservesWholeBlockUntilEnter) {
  ScriptedConsole console;
  auto editor = console.editor();
  console.push("\x1b[200~first\nsecond\n\x1b[201~X\n");
  const auto input = editor.readLine("> ");
  EXPECT_EQ(input.status, utilities::LineStatus::Line);
  EXPECT_EQ(input.line, "first\nsecond\nX");
  ASSERT_EQ(editor.history().size(), 1u);
  EXPECT_EQ(editor.history().front(), input.line);
  EXPECT_NE(console.output.find("\x1b[?2004h"), std::string::npos);
  EXPECT_TRUE(console.output.ends_with("\x1b[?2004l"));
}

TEST(LineEditor, BracketedPasteNormalizesLineEndingsAndKeepsTabsLiteral) {
  ScriptedConsole console;
  int completions = 0;
  utilities::LineEditor editor(
      [&console](int) {
        if (console.input.empty()) return utilities::LineEditor::End;
        const int byte = console.input.front();
        console.input.pop_front();
        return byte;
      },
      [&console](std::string_view text) { console.output.append(text); return true; }, {},
      [&completions](std::string_view, std::size_t) { ++completions; return utilities::Completion{}; });
  console.push("\x1b[200~one\r\ntwo\rthree\tvalue\x1b[201~\n");
  EXPECT_EQ(editor.readLine("> ").line, "one\ntwo\nthree\tvalue");
  EXPECT_EQ(completions, 0);
}

TEST(LineEditor, CtrlCAfterPasteDiscardsEntireBlock) {
  ScriptedConsole console;
  auto editor = console.editor();
  console.push("\x1b[200~first\nsecond\x1b[201~\x03");
  EXPECT_EQ(editor.readLine("> ").status, utilities::LineStatus::Interrupt);
  EXPECT_TRUE(editor.history().empty());
  EXPECT_TRUE(console.output.ends_with("\x1b[?2004l"));
}
