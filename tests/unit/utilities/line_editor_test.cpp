#include <gtest/gtest.h>

#include <utilities/LineEditor.hpp>

#include <deque>
#include <string>

namespace {
  struct ScriptedConsole {
    std::deque<unsigned char> input;
    std::string output;

    void push(std::string_view bytes) {
      for (unsigned char byte : bytes) input.push_back(byte);
    }

    utilities::LineEditor editor() {
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
          [] { return 120; });
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
