#include <gtest/gtest.h>

#include <recurloop/Project.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>
#include <recurloop/ProcessControl.hpp>
#include <recurloop/NativeIO.hpp>
#include <compiler/DynamicLinker.hpp>

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <filesystem>
#include <fstream>
#include <future>
#include <map>
#include <set>
#include <sstream>

namespace {
  std::shared_ptr<recurloop::Project> project() {
    char program[] = "recurloop-test";
    char *argv[] = {program};
    auto runtime = std::make_unique<recurloop::Recurloop>();
    runtime->initialize(1, argv);
    return recurloop::Project::create(runtime->getContext(), {program});
  }

  std::map<std::pair<std::size_t, std::size_t>, std::string> inspectionColors(const std::string &output) {
    std::map<std::pair<std::size_t, std::size_t>, std::string> colors;
    std::istringstream rows(output);
    for (std::string row; std::getline(rows, row);) {
      std::istringstream fields(row);
      std::string tag, value;
      std::size_t start = 0, end = 0;
      std::uint64_t group = 0;
      if (!(fields >> tag >> start >> end >> group) || tag != "S") continue;
      fields.get();
      std::getline(fields, value, '\t');
      if (value.empty()) continue;
      const auto [entry, inserted] = colors.emplace(std::pair{start, end}, value);
      EXPECT_TRUE(inserted || entry->second == value) << "Competing colors at " << start;
    }
    return colors;
  }
  std::map<std::size_t, std::string> inspectionDocs(const std::string &output, std::string_view name) {
    std::map<std::size_t, std::string> descriptions;
    std::istringstream rows(output);
    for (std::string row; std::getline(rows, row);) {
      std::istringstream fields(row);
      std::string tag, key, kind, docs;
      std::size_t version = 0;
      if (fields >> tag >> version >> key >> kind >> docs && tag == "P" && key == name)
        descriptions.emplace(version, docs);
    }
    return descriptions;
  }
} // namespace

TEST(RecurloopGeneration, PhraseDocsAcceptIdentifiersContainingGrammarSpellingsAcrossInputChunks) {
  char program[] = "recurloop-test";
  char *argv[] = {program};
  auto runtime = std::make_unique<recurloop::Recurloop>();
  runtime->initialize(1, argv);
  runtime->getContext().config.source.buffer.size = 16;
  auto state = recurloop::Project::create(runtime->getContext(), {program});
  auto session = state->openSession();
  const std::string source = R"(
let Library = phrase { dictionary = true }
let Library:text_equal = fn () -> i64 { return 42 }
let Library:publish = <Library:text_equal>
set Library:text_equal.docs = "Compares text without splitting identifiers into grammar phrases."
set Library:publish.docs = "A qualified name independent of the :publish session command."
set Library:text_equal.color = "#FF8800"
print Library:text_equal()
)";
  const auto evaluated = session->evaluate(source);
  ASSERT_EQ(evaluated.status, 0) << evaluated.error;
  EXPECT_EQ(evaluated.output, "42\n");
  const auto inspected = session->inspect(source, "/tmp/library-docs.rl", true, true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  EXPECT_NE(inspected.output.find("436f6d70617265732074657874"), std::string::npos) << inspected.output;
  EXPECT_NE(inspected.output.find("23464638383030"), std::string::npos) << inspected.output;
}

TEST(RecurloopGeneration, FunctionDocsResolveQualifiedAndScopedCallsWithoutConfusingSameNamedFunctions) {
  auto session = project()->openSession();
  const auto definitions = session->evaluate(R"(
let First = phrase { dictionary = true }
let Second = phrase { dictionary = true }
let First:new = fn () -> i64 { return 1 }
set First:new.docs = "First constructor."
let Second:new = fn () -> i64 { return 2 }
set Second:new.docs = "Second constructor."
)");
  ASSERT_EQ(definitions.status, 0) << definitions.error;
  const std::string source = R"(
fn First:probe() -> i64 {
    let first = First:new()
    let second = Second:new()
    return first + second + new()
}
)";
  const auto inspected = session->inspect(source, "/tmp/qualified-function-docs.rl", true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  std::map<std::size_t, std::string> references;
  std::istringstream rows(inspected.output);
  for (std::string row; std::getline(rows, row);) {
    std::istringstream fields(row);
    std::string tag, name;
    std::size_t start = 0, end = 0, line = 0, version = 0;
    if (fields >> tag >> start >> end >> line >> version >> name && tag == "R") references[start] = name;
  }
  EXPECT_EQ(references[source.find("First:new()") + 6], "46697273743a6e6577");
  EXPECT_EQ(references[source.find("Second:new()") + 7], "5365636f6e643a6e6577");
  EXPECT_EQ(references[source.find("new()", source.find("return first"))], "46697273743a6e6577");
  EXPECT_NE(inspected.output.find("466972737420636f6e7374727563746f722e"), std::string::npos);
  EXPECT_NE(inspected.output.find("5365636f6e6420636f6e7374727563746f722e"), std::string::npos);
}

TEST(RecurloopGeneration, NativeCallsAreStatementsAndStreamOutputToTheCallingSession) {
  auto state = project();
  auto session = state->openSession();
  const auto definitions = session->evaluate(R"(
link shared "c"
extern printf(format:u8*, ...) -> i32 abi sysv-amd64
extern puts(text:u8*) -> i32 abi sysv-amd64
let Probe = phrase { dictionary = true permanent = true }
let Probe:advance = fn (distance:i64, speed:i64) -> i64 { return distance + speed }
let Probe:main = fn () -> i64 {
    var distance:i64 = 0
    var tick:i64 = 1
    set tick.docs = "Example iteration number."
    while tick <= 3 {
        distance = Probe:advance(distance, 10)
        printf("Tick %lld: %lld km\n", tick, distance)
        tick += 1
    }
    return 0
}
let Probe:say = fn (text:u8*) -> void { puts(text) }
fn direct(value:i64) -> void { printf("direct %lld\n", value) }
fn direct_empty() -> void { puts("bare") }
)");
  ASSERT_EQ(definitions.status, 0) << definitions.error;
  const std::string ticks = "Tick 1: 10 km\nTick 2: 20 km\nTick 3: 30 km\n";
  const auto direct = session->evaluate("Probe:main()\n");
  ASSERT_EQ(direct.status, 0) << direct.error;
  EXPECT_EQ(direct.output, ticks);
  EXPECT_EQ(session->evaluate("(Probe:main())").output, ticks);
  EXPECT_EQ(session->evaluate("-Probe:main()").output, ticks);
  EXPECT_EQ(session->evaluate("print str(Probe:main())").output, ticks + "0\n");
  EXPECT_EQ(session->evaluate("Probe:advance(2, Probe:advance(3, 4))").output, "");
  EXPECT_EQ(session->evaluate("Probe:say(\n\"Żółw 😀\"\n) // comment").output, "Żółw 😀\n");
  const auto variadic = session->evaluate("printf(\"%s %lld\\n\", \"direct\", 42)");
  ASSERT_EQ(variadic.status, 0) << variadic.error;
  EXPECT_EQ(variadic.output, "direct 42\n");
  const auto invalid = session->evaluate("Probe:main(42)");
  EXPECT_NE(invalid.status, 0);
  EXPECT_NE(invalid.error.find("expects 0 argument(s)"), std::string::npos);
  EXPECT_EQ(session->evaluate("Probe:main()").output, ticks);
  const auto aliases = session->evaluate("let invoke = <\"(\">\nlet grouping = <\"(\">\nlet qualified = <\":\">\n");
  ASSERT_EQ(aliases.status, 0) << aliases.error;
  const auto aliased = session->evaluate("grouping Probe qualified main invoke ))");
  EXPECT_EQ(aliased.status, 0) << aliased.error;
  EXPECT_EQ(aliased.output, ticks);
  const auto directAlias = session->evaluate("direct invoke\n42\n)");
  EXPECT_EQ(directAlias.status, 0) << directAlias.error;
  EXPECT_EQ(directAlias.output, "direct 42\n");
  const auto externAlias = session->evaluate("printf invoke \"extern alias\\n\")");
  EXPECT_EQ(externAlias.status, 0) << externAlias.error;
  EXPECT_EQ(externAlias.output, "extern alias\n");
  EXPECT_EQ(session->evaluate("direct_empty // comment").output, "bare\n");
  const auto unknown = session->evaluate("Missing:call()");
  EXPECT_EQ(unknown.status, 1);
  EXPECT_NE(unknown.error.find("unknown function"), std::string::npos);
  session->publish();
  auto other = state->openSession();
  auto first = std::async(std::launch::async, [&] { return session->evaluate("Probe:say(\"first\")"); });
  auto second = std::async(std::launch::async, [&] { return other->evaluate("Probe:say(\"second\")"); });
  EXPECT_EQ(first.get().output, "first\n");
  EXPECT_EQ(second.get().output, "second\n");
}

TEST(RecurloopGeneration, ExpressionStatementsUseTheSameGrammarAsExpressionValues) {
  auto session = project()->openSession();
  for (const auto *source : {"2 + 3 * 4", "(2 + 3) * 4", "str(42)", "true && false", "\"text\""}) {
    const auto result = session->evaluate(source);
    EXPECT_EQ(result.status, 0) << source << ": " << result.error;
    EXPECT_EQ(result.output, "");
  }
}

TEST(RecurloopGeneration, ExpressionInspectionValidatesDeclaredAndUndefinedNames) {
  auto session = project()->openSession();
  const auto valid = session->inspect("var known = 2\nprint known + 1\n(known + 1)\n",
                                      "/tmp/expression-inspection.rl", true, true);
  EXPECT_EQ(valid.status, 0) << valid.error;
  EXPECT_EQ(valid.output.find("E\t"), std::string::npos) << valid.output;
  const auto invalid = session->inspect("definitely_missing_phrase\n", "/tmp/expression-inspection.rl", true, true);
  EXPECT_NE(invalid.output.find("E\t"), std::string::npos);
}

TEST(RecurloopGeneration, HelpContractsUseMatchedSyntaxAndSurviveImageRelocation) {
  auto state = project();
  auto session = state->openSession();
  const auto root = std::filesystem::temp_directory_path() / "recurloop-help-contract-test";
  std::filesystem::create_directories(root);
  const auto image = root / "help.rli";
  const auto definitions = R"rl(
syntax choose (fast | safe) <value:number> => print ${value}
let Usage = [
  summary = phrase { payload = "Choose a mode." }
  snippet = phrase { payload = "${phrase} ${1|fast,safe|} ${2:42}" }
  arguments = [ value = phrase { docs = "Number to print." } ]
]
set choose.help = <Usage>
let alternate = <choose>
)rl";
  const auto defined = session->evaluate(definitions);
  ASSERT_EQ(defined.status, 0) << defined.error;
  ASSERT_EQ(session->evaluate("engine export \"" + image.string() + "\"").status, 0);
  auto restored = project()->openSession();
  const auto imported = restored->evaluate("engine import \"" + image.string() + "\"");
  ASSERT_EQ(imported.status, 0) << imported.error;
  const auto inspect = [&](std::string source) { return restored->inspect("engine import \"" + image.string() + "\"\n" + source, (root / "edited.rl").string(), true, true).output; };
  const auto response = inspect("// 😀\nalternate sa");
  EXPECT_NE(response.find("H\t"), std::string::npos);
  EXPECT_NE(response.find("\t616c7465726e617465\t"), std::string::npos); // alternate
  EXPECT_NE(response.find("\t73616665\t73616665\n"), std::string::npos); // safe
  EXPECT_NE(response.find("43686f6f73652061206d6f64652e"), std::string::npos); // serialized summary
  EXPECT_NE(response.find("4e756d62657220746f207072696e742e"), std::string::npos);
  EXPECT_NE(inspect("choose fast ").find("\t76616c7565\t6e756d626572\t\t\n"), std::string::npos);
  // Replacing imported help must update the relocated attachment and survive
  // another export/import, including the contract inherited by an alias.
  const auto updatedImage = root / "updated.rli";
  const auto updated = restored->evaluate(R"rl(
let UpdatedUsage = [
  summary = phrase { payload = "Updated mode." }
  arguments = <Usage:arguments>
]
set choose.help = <UpdatedUsage>
)rl" + std::string("engine export \"") + updatedImage.string() + "\"");
  ASSERT_EQ(updated.status, 0) << updated.error;
  const auto updatedResponse = restored->inspect("engine import \"" + updatedImage.string() + "\"\nalternate sa",
                                                 (root / "updated.rl").string(), true, true);
  EXPECT_NE(updatedResponse.output.find("55706461746564206d6f64652e"), std::string::npos); // Updated mode.
  EXPECT_EQ(updatedResponse.output.find("43686f6f73652061206d6f64652e"), std::string::npos);
  EXPECT_NE(updatedResponse.output.find("4e756d62657220746f207072696e742e"), std::string::npos);
  ASSERT_EQ(restored->evaluate("set alternate.help = none").status, 0);
  const auto cleared = inspect("set alternate.help = none\nalternate sa");
  const auto start = cleared.find("H\t0\t616c7465726e617465\t");
  ASSERT_NE(start, std::string::npos);
  EXPECT_EQ(cleared.substr(start, cleared.find('\n', start) - start).find("43686f6f73652061206d6f64652e"), std::string::npos);
  EXPECT_NE(restored->evaluate("let Bad = [ pattern = phrase { payload = \"<x:unknown>\" } ]\nset choose.help = <Bad>").status, 0);
  std::filesystem::remove_all(root);
}

TEST(RecurloopGeneration, LiteralPhrasesKeepPriorityOverNativeCallStatements) {
  auto session = project()->openSession();
  ASSERT_EQ(session->evaluate(R"rl(
let probe = fn () -> i64 { return 42 }
let "probe()" = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void { context:io:write(state, "literal\n") }
}
)rl").status, 0);
  EXPECT_EQ(session->evaluate("probe()").output, "literal\n");
}

TEST(RecurloopGeneration, NativeStdioSeparatesStreamsPreservesFilesAndRestoresNestedScopes) {
  // Initialize the host binding, then use the same imports as JIT modules.
  auto session = project()->openSession();
  auto &linker = compiler::DynamicLinker::instance();
  const auto print = reinterpret_cast<decltype(&std::fprintf)>(*linker.resolve("fprintf", {"c"}));
  const auto write = reinterpret_cast<decltype(&std::fwrite)>(*linker.resolve("fwrite", {"c"}));
  std::ostringstream output, errors, nested;
  EXPECT_EQ(recurloop::NativeIO::current(), nullptr);
  {
    recurloop::NativeIO::Scope scope({nullptr, &output, &errors});
    EXPECT_EQ(print(stdout, "%s:%d", "out", 42), 6);
    EXPECT_EQ(print(stderr, "error"), 5);
    {
      recurloop::NativeIO::Scope inner({nullptr, &nested, &nested});
      EXPECT_EQ(print(stdout, "inner"), 5);
    }
    const char bytes[] = {'a', '\0', 'b'};
    EXPECT_EQ(write(bytes, 1, sizeof(bytes), stdout), sizeof(bytes));
    FILE *file = std::tmpfile();
    ASSERT_NE(file, nullptr);
    EXPECT_EQ(write(bytes, 1, sizeof(bytes), file), sizeof(bytes));
    std::rewind(file);
    char actual[3]{};
    EXPECT_EQ(std::fread(actual, 1, sizeof(actual), file), sizeof(actual));
    EXPECT_EQ(std::string(actual, sizeof(actual)), std::string(bytes, sizeof(bytes)));
    std::fclose(file);
  }
  EXPECT_EQ(output.str(), std::string("out:42a\0b", 9));
  EXPECT_EQ(errors.str(), "error");
  EXPECT_EQ(nested.str(), "inner");
  EXPECT_EQ(recurloop::NativeIO::current(), nullptr);
}

TEST(RecurloopGeneration, InterruptedRequestsStopSourceProcessingAndLeaveTheSessionUsable) {
  auto session = project()->openSession();
  ASSERT_EQ(session->evaluate("var answer = 41\n").status, 0);
  recurloop::ProcessControl control;
  {
    recurloop::ProcessControl::Scope scope(control);
    EXPECT_FALSE(recurloop::ProcessControl::interrupted());
    control.interrupt();
    EXPECT_TRUE(recurloop::ProcessControl::interrupted());
    const auto result = session->evaluate("answer = 99\n");
    EXPECT_EQ(result.status, 130);
    EXPECT_NE(result.error.find("request cancelled"), std::string::npos);
  }
  EXPECT_FALSE(recurloop::ProcessControl::interrupted());
  EXPECT_EQ(session->evaluate("print answer\n").output, "41\n");
}

TEST(RecurloopGeneration, SessionsSharePublishedBaseButKeepPrivateState) {
  auto state = project();
  auto first = state->openSession();
  auto second = state->openSession();

  ASSERT_EQ(first->evaluate("var answer = 41").status, 0);
  auto local = first->evaluate("print answer + 1");
  ASSERT_EQ(local.status, 0);
  EXPECT_EQ(local.output, "42\n");

  auto isolated = second->evaluate("print answer");
  EXPECT_NE(isolated.status, 0);

  auto published = first->publish();
  EXPECT_EQ(published->id, first->generations().project);

  second->refresh();
  auto shared = second->evaluate("print answer + 1");
  ASSERT_EQ(shared.status, 0);
  EXPECT_EQ(shared.output, "42\n");
}

TEST(RecurloopGeneration, BaselineDiscardsPublishedEnvironmentState) {
  auto state = project();
  auto publisher = state->openSession();
  ASSERT_EQ(publisher->evaluate("var temporary_environment_value = 91").status, 0);
  ASSERT_EQ(publisher->evaluate(":publish").status, 0);

  auto rebuilder = state->openSession();
  ASSERT_EQ(rebuilder->evaluate("print temporary_environment_value").output, "91\n");
  const auto baseline = rebuilder->evaluate(":baseline");
  ASSERT_EQ(baseline.status, 0) << baseline.error;
  EXPECT_NE(baseline.output.find("baseline project="), std::string::npos);
  EXPECT_NE(rebuilder->evaluate("print temporary_environment_value").status, 0);
}

TEST(RecurloopGeneration, FailedRequestRollsBackInPlaceValueWrites) {
  auto state = project();
  auto session = state->openSession();

  ASSERT_EQ(session->evaluate("var value = 7").status, 0);
  auto failed = session->evaluate("value = 99\nprint value\nthis phrase does not exist");
  EXPECT_NE(failed.status, 0);
  EXPECT_EQ(failed.output, "99\n");

  auto after = session->evaluate("print value");
  ASSERT_EQ(after.status, 0);
  EXPECT_EQ(after.output, "7\n");
}

TEST(RecurloopGeneration, NativeArithmeticFaultsDoNotTerminateTheHostOrRunLaterStatements) {
  auto state = project();
  auto session = state->openSession();
  ASSERT_EQ(session->evaluate(R"(
link shared "c"
extern puts(text:u8*) -> i32 abi sysv-amd64
fn checked_div(a:i64, b:i64) -> i64 { return a / b }
fn checked_rem(a:i64, b:i64) -> i64 { return a % b }
fn fault_parent(a:i64, b:i64) -> i64 {
  var result = checked_div(a, b)
  puts("must not execute")
  return result
}
)").status, 0);
  for (const auto *source : {"print checked_div(7, 0)", "print checked_rem(7, 0)", "print fault_parent(7, 0)"}) {
    const auto failure = session->evaluate(source);
    EXPECT_NE(failure.status, 0);
    EXPECT_NE(failure.error.find("division by zero"), std::string::npos) << failure.error;
    EXPECT_TRUE(failure.output.empty()) << failure.output;
  }
  const auto overflow = session->evaluate("print checked_div(-9223372036854775807 - 1, -1)");
  EXPECT_NE(overflow.status, 0);
  EXPECT_NE(overflow.error.find("division overflow"), std::string::npos) << overflow.error;
  EXPECT_EQ(session->evaluate("print checked_div(8, 2)").output, "4\n");
}

TEST(RecurloopGeneration, InspectionPreservesPermanentDefinitions) {
  auto state = project();
  auto session = state->openSession();

  constexpr std::string_view source = R"(
let InspectionPermanent = phrase { dictionary = true permanent = true }
let InspectionPermanent:value = fn () -> i64 { return 17 }
)";
  ASSERT_EQ(session->evaluate(source, "/tmp/inspection-permanent.rl").status, 0);
  ASSERT_EQ(session->publish()->id, session->generations().project);

  // Ordinary execution keeps the permanent-phrase invariant.
  EXPECT_NE(session->evaluate(source, "/tmp/inspection-permanent.rl").status, 0);

  // Inspection preserves the same permanent-phrase contract as execution.
  const auto inspected = session->inspect(source, "/tmp/inspection-permanent.rl");
  EXPECT_EQ(inspected.status, 0);
  EXPECT_NE(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  EXPECT_EQ(session->evaluate("print InspectionPermanent:value()").output, "17\n");
}

TEST(RecurloopGeneration, TraceExportsLanguageFactsWithoutPublishingAnIndex) {
  auto state = project();
  auto session = state->openSession();
  const auto before = session->generations().lexicon;
  const auto response = session->inspect("let trace_alias = <debug:ping>\ntrace_alias\n", "/tmp/trace-alias.rl", true);
  ASSERT_EQ(response.status, 0) << response.error;
  EXPECT_EQ(response.output.find("E\t"), std::string::npos) << response.output;
  EXPECT_NE(response.output.find("R\t"), std::string::npos);
  EXPECT_NE(response.output.find("P\t"), std::string::npos);
  // The alias name and prototype are exported as facts, without recognizing
  // any declaration spelling or storing client indexes in the phrase graph.
  EXPECT_NE(response.output.find("74726163655f616c696173"), std::string::npos);
  EXPECT_NE(response.output.find("64656275673a70696e67"), std::string::npos);
  EXPECT_EQ(session->generations().lexicon, before);
  EXPECT_NE(session->evaluate("trace_alias").status, 0);
}

TEST(RecurloopGeneration, TraceDistinguishesChronologicalDefinitions) {
  auto session = project()->openSession();
  const auto response = session->inspect("let traced = <debug:ping>\ntraced\nlet traced = <debug:ping>\ntraced\n",
                                         "/tmp/trace-versions.rl", true);
  EXPECT_EQ(response.output.find("E\t"), std::string::npos) << response.output;
  EXPECT_NE(response.output.find("R\t26\t32\t2\t0\t747261636564\n"), std::string::npos);
  EXPECT_NE(response.output.find("R\t59\t65\t4\t1\t747261636564\n"), std::string::npos);
}

TEST(RecurloopGeneration, TraceResolvesRecordFieldDeclarationsReadsAndWritesWithoutExecutingFunctions) {
  auto session = project()->openSession();
  const std::string source = "let Game = phrase { dictionary = true }\n"
                             "record Game:State { paddle_x:f64 ball_x:f64 }\n"
                             "let reset = fn (state:Game:State*, ball_x:f64) -> void {\n"
                             "    state.ball_x = state.paddle_x\n    let alias = state\n    alias.ball_x = ball_x\n}\n";
  const auto response = session->inspect(source, "/tmp/record-field-trace.rl", true);
  ASSERT_EQ(response.status, 0) << response.error;
  ASSERT_EQ(response.output.find("E\t"), std::string::npos) << response.output;
  const std::string ball = "47616d653a53746174653a62616c6c5f78";
  const std::string paddle = "47616d653a53746174653a706164646c655f78";
  const auto expect = [&](char tag, std::size_t offset, std::size_t size, const std::string &name) {
    const auto line = 1 + std::count(source.begin(), source.begin() + offset, '\n');
    const auto record = std::string(1, tag) + '\t' + std::to_string(offset) + '\t' + std::to_string(offset + size) +
                        '\t' + std::to_string(line) + "\t0\t" + name + '\n';
    EXPECT_NE(response.output.find(record), std::string::npos) << record;
  };
  expect('B', source.find("ball_x:f64"), 6, ball);
  expect('B', source.find("paddle_x:f64"), 8, paddle);
  expect('R', source.find("state.ball_x") + 6, 6, ball);
  expect('R', source.find("state.paddle_x") + 6, 8, paddle);
  expect('R', source.find("alias.ball_x") + 6, 6, ball);
  EXPECT_NE(session->evaluate("reset").status, 0);
}

TEST(RecurloopGeneration, QualifiedPhraseComponentsShareResolvedReferencesAndDeclarations) {
  auto session = project()->openSession();
  const std::string source = "let Game = phrase { dictionary = true }\n"
                             "let Game:Phase = phrase { dictionary = true }\n"
                             "const Game:Phase:Ready = 0\nvar Game:score = 1\n"
                             "record Game:State { phase:i64 }\n"
                             "let Game:read = fn (state:Game:State*) -> i64 {\n"
                             "    if state.phase == Game : Phase : Ready { return Game:score }\n"
                             "    return Game:Phase:Ready\n}\n"
                             "let qualify = <\":\">\n"
                             "let alias_read = fn () -> i64 { return Game qualify Phase qualify Ready }\n";
  const auto inspected = session->inspect(source, "/tmp/qualified-phrase-trace.rl", true, true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  const auto expect = [&](char tag, std::size_t start, std::size_t length, std::string_view name) {
    const auto line = 1 + std::count(source.begin(), source.begin() + start, '\n');
    const auto row = std::string(1, tag) + '\t' + std::to_string(start) + '\t' + std::to_string(start + length) + '\t' +
                     std::to_string(line) + "\t0\t" + std::string(name) + '\n';
    EXPECT_NE(inspected.output.find(row), std::string::npos) << row;
  };
  const auto use = source.find("Game : Phase : Ready");
  expect('R', use, 4, "47616d65");
  expect('R', use + 7, 5, "47616d653a5068617365");
  expect('R', use + 15, 5, "47616d653a50686173653a5265616479");
  expect('B', source.find("Game:Phase =") + 5, 5, "47616d653a5068617365");
  expect('B', source.find("Game:Phase:Ready =") + 11, 5, "47616d653a50686173653a5265616479");
  expect('B', source.find("Game:score =") + 5, 5, "47616d653a73636f7265");
  expect('R', source.rfind("Game:score") + 5, 5, "47616d653a73636f7265");
  expect('B', source.find("Game:State {") + 5, 5, "47616d653a5374617465");
  expect('B', source.find("Game:read =") + 5, 4, "47616d653a72656164");
  const auto alias = source.find("Game qualify Phase qualify Ready");
  expect('R', alias, 4, "47616d65");
  expect('R', alias + 13, 5, "47616d653a5068617365");
  expect('R', alias + 27, 5, "47616d653a50686173653a5265616479");
}

TEST(RecurloopGeneration, DefinitionLocationsFollowPhraseReferencesThroughImages) {
  auto session = project()->openSession();
  const auto root = std::filesystem::temp_directory_path() / "recurloop-definition-reference-test";
  std::filesystem::create_directories(root);
  const auto path = (root / "definitions.rl").string();
  const auto image = root / "definitions.rli";
  const std::string source = "let \"words : with separators\" = phrase { payload = \"text\" }\n"
                             "let alias = <\"words : with separators\">\n"
                             "const answer = 42\nrecord State { value:i64 }\n"
                             "fn read(state:State*) -> i64 { return state.value }\n";
  const auto defined = session->evaluate(source, path);
  ASSERT_EQ(defined.status, 0) << defined.error;
  const auto before = session->inspect(source, path, true, true).output;
  ASSERT_EQ(session->evaluate("engine export \"" + image.string() + "\"").status, 0);
  auto restored = project()->openSession();
  const auto imported = restored->evaluate("engine import \"" + image.string() + "\"");
  ASSERT_EQ(imported.status, 0) << imported.error;
  const auto importSource = "engine import \"" + image.string() + "\"\n";
  const auto after = restored->inspect(importSource, (root / "empty.rl").string(), true, true).output;
  std::string encodedPath;
  constexpr char digits[] = "0123456789abcdef";
  for (const unsigned char ch : path) {
    encodedPath += digits[ch / 16];
    encodedPath += digits[ch % 16];
  }
  const auto definitions = [&](const std::string &trace) {
    std::set<std::string> locations;
    std::istringstream rows(trace);
    for (std::string row; std::getline(rows, row);)
      if (row.starts_with("F\t") && row.contains('\t' + encodedPath + '\t'))
        locations.insert(row.substr(row.find('\t', 2) + 1));
    return locations;
  };
  const auto expected = definitions(before);
  EXPECT_EQ(expected.size(), 6); // phrase, alias, value, record, field, function
  const auto importedDefinitions = definitions(after);
  // Native compilation can add overload phrases inheriting the function's
  // definition; every source declaration must retain its original location.
  EXPECT_TRUE(std::includes(importedDefinitions.begin(), importedDefinitions.end(), expected.begin(), expected.end()));
  // Inspection must roll back new declarations without losing the stored graph.
  const auto edited = restored->inspect("let temporary = phrase {}\n", path, true, true);
  ASSERT_EQ(edited.output.find("E\t"), std::string::npos) << edited.output;
  EXPECT_EQ(definitions(restored->inspect(importSource, path, true, true).output), importedDefinitions);
  std::filesystem::remove_all(root);
}

TEST(RecurloopGeneration, RuntimeVariableDocsHaveDeclarationAndExpressionOccurrences) {
  auto session = project()->openSession();
  const std::string source = "var pi = 3.14\n"
                             "set pi.docs = \"Circle ratio.\"\n"
                             "const tau = pi * 2\n"
                             "set pi = pi + 1\n"
                             "print str(pi)\n"
                             "print \"pi is text\" // pi is a comment\n";
  const auto response = session->inspect(source, "/tmp/runtime-variable-docs.rl", true, true);
  ASSERT_EQ(response.output.find("E\t"), std::string::npos) << response.output;
  std::vector<std::pair<std::size_t, std::size_t>> occurrences;
  std::istringstream rows(response.output);
  for (std::string row; std::getline(rows, row);) {
    std::istringstream fields(row);
    std::string tag, name;
    std::size_t start = 0, end = 0, line = 0, version = 0;
    if (fields >> tag >> start >> end >> line >> version >> name && tag == "R" && name == "7069")
      occurrences.emplace_back(start, end);
  }
  const std::vector<std::pair<std::size_t, std::size_t>> expected{
      {4, 6},
      {source.find("pi.docs"), source.find("pi.docs") + 2},
      {source.find("pi *"), source.find("pi *") + 2},
      {source.find("set pi =") + 4, source.find("set pi =") + 6},
      {source.find("pi +"), source.find("pi +") + 2},
      {source.find("str(pi)") + 4, source.find("str(pi)") + 6}};
  EXPECT_EQ(occurrences, expected);
  EXPECT_NE(response.output.find("P\t0\t7069\t706872617365\t436972636c6520726174696f2e\t"), std::string::npos);
  // Inspection neither evaluates the print nor publishes the binding.
  EXPECT_NE(session->evaluate("print pi").status, 0);
}

TEST(RecurloopGeneration, FunctionLocalDocsFollowLexicalBindingsWithoutChangingValues) {
  auto session = project()->openSession();
  const std::string source = R"(var tick = 99
set tick.docs = "Global tick."
let local_docs = fn () -> i64 {
    var tick:i64 = 1
    set tick.docs = "Outer tick."
    while tick < 2 {
        var tick:i64 = 10
        set tick.docs = "Inner tick."
        tick += 1
        break
    }
    tick += 1
    return tick
}
print local_docs()
print tick
)";
  const auto response = session->inspect(source, "/tmp/function-local-docs.rl", true, true);
  ASSERT_EQ(response.output.find("E\t"), std::string::npos) << response.output;
  std::vector<std::pair<std::size_t, std::uint64_t>> locals;
  std::istringstream rows(response.output);
  for (std::string row; std::getline(rows, row);) {
    std::istringstream fields(row);
    std::string tag, name;
    std::size_t start = 0, end = 0, line = 0;
    std::uint64_t version = 0;
    if (fields >> tag >> start >> end >> line >> version >> name && tag == "R" && version >= (std::uint64_t{1} << 32)) {
      EXPECT_EQ(name, "7469636b");
      EXPECT_EQ(end - start, 4);
      locals.emplace_back(start, version);
    }
  }
  const std::vector<std::pair<std::size_t, std::uint64_t>> expected{
      {source.find("var tick:i64") + 4, 4294967296},
      {source.find("set tick.docs", source.find("let local_docs")) + 4, 4294967296},
      {source.find("while tick") + 6, 4294967296},
      {source.find("var tick:i64 = 10") + 4, 4294967297},
      {source.find("set tick.docs", source.find("var tick:i64 = 10")) + 4, 4294967297},
      {source.find("tick += 1"), 4294967297},
      {source.rfind("tick += 1"), 4294967296},
      {source.find("return tick") + 7, 4294967296}};
  EXPECT_EQ(locals, expected);
  EXPECT_NE(response.output.find("P\t4294967296\t7469636b\t6c6f63616c\t4f75746572207469636b2e\t"), std::string::npos);
  EXPECT_NE(response.output.find("P\t4294967297\t7469636b\t6c6f63616c\t496e6e6572207469636b2e\t"), std::string::npos);
  EXPECT_NE(session->evaluate("print tick").status, 0);
  const auto executed = session->evaluate(source);
  ASSERT_EQ(executed.status, 0) << executed.error;
  EXPECT_EQ(executed.output, "2\n99\n");
  for (const auto *assignment : {"set tick.docs += \"invalid\"", "set tick.docs = tick"}) {
    const auto invalid = session->evaluate(std::string("let invalid_docs = fn () -> i64 {\nvar tick:i64 = 1\n") +
                                           assignment + "\nreturn tick\n}");
    EXPECT_NE(invalid.status, 0);
    EXPECT_NE(invalid.error.find("local docs require"), std::string::npos) << invalid.error;
  }
}

TEST(RecurloopGeneration, LocalFunctionMetadataColorsResolvedOccurrencesWithoutMutatingConstValues) {
  auto session = project()->openSession();
  const std::string source = R"(var exampleFn = 99
set exampleFn.color = "#0000FF"
let main = fn () -> i64 {
    let exampleFn = fn () -> i64 { return 1 }
    set exampleFn.color = "#FF8800"
    set exampleFn.docs = "aaa"
    if 1 {
        let exampleFn = fn () -> i64 { return 5 }
        set exampleFn.color = "#00FF00"
        exampleFn()
    }
    return exampleFn()
}
print main()
print exampleFn
)";
  const auto inspected = session->inspect(source, "/tmp/local-function-metadata.rl", true, true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  EXPECT_NE(inspected.output.find("\t616161\t\t\t\n"), std::string::npos);
  auto colors = inspectionColors(inspected.output);
  std::vector<std::pair<std::size_t, std::size_t>> outer, inner;
  std::istringstream rows(inspected.output);
  for (std::string row; std::getline(rows, row);) {
    std::istringstream fields(row);
    std::string tag, value;
    std::size_t start = 0, end = 0;
    std::uint64_t owner = 0, version = 0;
    if (!(fields >> tag >> start >> end >> owner)) continue;
    if (tag == "R" && fields >> version >> value && value == "6578616d706c65466e") {
      if (version == 4294967296) outer.emplace_back(start, end);
      if (version == 4294967297) inner.emplace_back(start, end);
    }
  }
  ASSERT_EQ(outer.size(), 4);
  ASSERT_EQ(inner.size(), 3);
  for (const auto &range : outer) EXPECT_EQ(colors[range], "23464638383030");
  for (const auto &range : inner) EXPECT_EQ(colors[range], "23303046463030");
  const auto executed = session->evaluate(source);
  ASSERT_EQ(executed.status, 0) << executed.error;
  EXPECT_EQ(executed.output, "1\n99\n");
  const std::string cleared = "let clear_color = fn () -> i64 {\n"
                              "let exampleFn = fn () -> i64 { return 2 }\n"
                              "set exampleFn.color = \"#FF8800\"\n"
                              "set exampleFn.color = \"\"\n"
                              "return exampleFn()\n}\n";
  const auto clearInspection = session->inspect(cleared, "/tmp/clear-local-color.rl", true, true);
  ASSERT_EQ(clearInspection.output.find("E\t"), std::string::npos) << clearInspection.output;
  EXPECT_EQ(clearInspection.output.find("23464638383030"), std::string::npos);
  EXPECT_EQ(clearInspection.output.find("23303030304646"), std::string::npos);
}

TEST(RecurloopGeneration, DocumentationOnlyPhrasesPreserveIdentifierAndExternalFunctionColors) {
  auto session = project()->openSession();
  const auto definitions = session->evaluate("let argument = phrase { docs = \"Describes a root phrase.\" }\n"
                                             "extern described_query(value:i64) -> i64 abi sysv-amd64\n"
                                             "set described_query.docs = \"Describes an external function.\"\n");
  ASSERT_EQ(definitions.status, 0) << definitions.error;
  const std::string source = "let query = fn (argument:i64) -> i64 {\n"
                             "    return described_query(argument)\n}\n"
                             "let read = fn (argument:i64) -> i64 { return argument }\n";
  const auto inspected = session->inspect(source, "/tmp/documentation-only-colors.rl", true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  const auto colors = inspectionColors(inspected.output);
  const auto function = source.find("described_query");
  const auto argument = source.find("argument)", function);
  const auto read = source.rfind("argument");
  EXPECT_EQ(colors.at({function, function + 15}), "23444344434141");
  EXPECT_EQ(colors.at({argument, argument + 8}), "23394344434645");
  EXPECT_EQ(colors.at({read, read + 8}), "23394344434645");
}

TEST(RecurloopGeneration, FunctionCallsRecordPhraseMetadataForDirectNestedAndQualifiedCalls) {
  auto session = project()->openSession();
  const std::string source = R"(let Example = phrase { dictionary = true }
let Example:answer = fn () -> i64 { return 1 }
Example:answer()
set Example:answer.color = "#FF8800"
set Example:answer.docs = "Global function documentation."
Example:answer()
print Example:answer() + Example:answer()
print "Example:answer() is text" // Example:answer() is a comment
)";
  const auto inspected = session->inspect(source, "/tmp/global-function-metadata.rl", true, true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  const std::string name = "4578616d706c653a616e73776572";
  std::istringstream rows(inspected.output);
  std::set<std::pair<std::size_t, std::size_t>> matches;
  const auto colors = inspectionColors(inspected.output);
  for (std::string row; std::getline(rows, row);) {
    std::istringstream fields(row);
    std::string tag, value;
    std::size_t start = 0, end = 0, group = 0, version = 0;
    if (!(fields >> tag >> start >> end >> group)) continue;
    if (tag == "R" && fields >> version >> value && value == name) matches.emplace(start, end);
  }
  for (const auto offset : {source.find("let Example:answer") + 4, source.find("\nExample:answer()") + 1,
                            source.rfind("\nExample:answer()") + 1, source.find("print Example:answer()") + 6,
                            source.find("+ Example:answer()") + 2}) {
    const auto range = std::pair{offset, offset + std::string_view("Example:answer").size()};
    EXPECT_TRUE(matches.contains({offset + 8, range.second})) << offset;
    const auto leafRange = std::pair{offset + 8, range.second};
    ASSERT_TRUE(colors.contains(leafRange)) << offset;
    EXPECT_EQ(colors.at(leafRange), "23464638383030");
  }
  EXPECT_FALSE(
      matches.contains({source.find("Example:answer() is text"), source.find("Example:answer() is text") + 14}));
  const auto executed = session->evaluate(source);
  ASSERT_EQ(executed.status, 0) << executed.error;
  EXPECT_EQ(executed.output, "2\nExample:answer() is text\n");
}

TEST(RecurloopGeneration, FinalMetadataFollowsPrototypesAndPreservesDeclarationVersions) {
  auto session = project()->openSession();
  const std::string source = R"(// Żółw 😀
let style = phrase { color = "#0000FF" docs = "before" }
let metadata_entry = <style>
let "two words" = <style>
let Space = phrase { dictionary = true }
let Space:metadata_entry = <style>
set style.color = "#FF8800"
set style.docs = "after"
let metadata_entry = phrase { color = "#008800" docs = "new" }
)";
  for (const bool crlf : {false, true}) {
    std::string buffer = source;
    if (crlf) {
      for (std::size_t index = 0; (index = buffer.find('\n', index)) != std::string::npos; index += 2)
        buffer.insert(index, 1, '\r');
    }
    const auto range = [&](std::string_view spelling, bool last = false) {
      const auto byte = last ? buffer.rfind(spelling) : buffer.find(spelling);
      // The protocol uses Unicode codepoints, including on CRLF input.
      std::size_t start = 0;
      for (std::size_t index = 0; index < byte; ++index)
        if ((static_cast<unsigned char>(buffer[index]) & 0xc0) != 0x80) ++start;
      return std::pair{start, start + spelling.size()};
    };
    const auto inspect = [&](bool clear) {
      return session->inspect(buffer + (clear ? "set style.color = \"\"\nset style.docs = \"\"\n" : ""),
                              "/tmp/inherited-metadata.rl", true, true);
    };
    const auto inspected = inspect(false);
    ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
    const auto colors = inspectionColors(inspected.output);
    const auto descriptions = inspectionDocs(inspected.output, "6d657461646174615f656e747279");
    EXPECT_EQ(descriptions.at(0), "6166746572");
    EXPECT_EQ(descriptions.at(1), "6e6577");
    const auto cleared = inspect(true);
    ASSERT_EQ(cleared.output.find("E\t"), std::string::npos) << cleared.output;
    const auto clearedColors = inspectionColors(cleared.output);
    for (const auto name : {"style", "metadata_entry", "\"two words\"", "Space:metadata_entry"}) {
      auto expected = range(name);
      if (std::string_view(name) == "Space:metadata_entry") expected.first += std::string_view("Space:").size();
      ASSERT_TRUE(colors.contains(expected)) << name << "\n" << inspected.output;
      EXPECT_EQ(colors.at(expected), "23464638383030") << name;
      EXPECT_FALSE(clearedColors.contains(expected)) << name;
    }
    const auto redefined = range("metadata_entry", true);
    ASSERT_TRUE(colors.contains(redefined));
    EXPECT_EQ(colors.at(redefined), "23303038383030");
    EXPECT_EQ(clearedColors.at(redefined), "23303038383030");
  }
}

TEST(RecurloopGeneration, InspectionKeepsMetadataIdentitiesAcrossEngineImports) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-inspection-image-identities";
  fs::remove_all(root);
  fs::create_directories(root);
  const fs::path image = root / "language.rli";
  auto exporter = project()->openSession();
  ASSERT_EQ(exporter->evaluate("engine export \"" + image.string() + "\"").status, 0);
  const std::string source = "let style = phrase { color = \"#008800\" docs = \"original\" }\n"
                             "let earlier = <style>\n"
                             "let earlier = phrase { color = \"#123456\" docs = \"replacement\" }\n"
                             "let retained = fn () -> i64 { return 1 }\n"
                             "retained()\n"
                             "engine import \"" +
                             image.string() +
                             "\"\n"
                             "set retained.color = \"#FF8800\"\n"
                             "set retained.docs = \"after import\"\n"
                             "retained()\n";
  auto session = project()->openSession();
  for (int repeat = 0; repeat < 2; ++repeat) {
    const auto inspected = session->inspect(source, (root / "edited.rl").string(), true, true);
    ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
    const auto colors = inspectionColors(inspected.output);
    std::size_t offset = 0;
    while ((offset = source.find("retained", offset)) != std::string::npos) {
      ASSERT_TRUE(colors.contains({offset, offset + 8})) << offset;
      EXPECT_EQ(colors.at({offset, offset + 8}), "23464638383030");
      offset += 8;
    }
    const auto first = source.find("earlier");
    const auto second = source.find("earlier", first + 7);
    EXPECT_EQ(colors.at({first, first + 7}), "23303038383030");
    EXPECT_EQ(colors.at({second, second + 7}), "23313233343536");
    // The first alias has no own metadata and need not survive serialization.
    const auto descriptions = inspectionDocs(inspected.output, "6561726c696572");
    EXPECT_EQ(descriptions.at(0), "6f726967696e616c");
    EXPECT_EQ(descriptions.at(1), "7265706c6163656d656e74");
    EXPECT_NE(inspected.output.find("616674657220696d706f7274"), std::string::npos);
    EXPECT_EQ(session->evaluate("print 42").output, "42\n");
  }
  fs::remove_all(root);
}

TEST(RecurloopGeneration, ProjectInspectionReplaysSourceEntryAndKeepsTheSessionState) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-source-entry-inspection-test";
  fs::remove_all(root);
  fs::create_directories(root);
  const fs::path entry = root / "main.rl";
  const fs::path module = root / "module.rl";
  {
    std::ofstream out(entry);
    out << "let TraceNamespace = phrase { dictionary = true permanent = true }\n"
           "let cached_color = fn () -> i64 { return 1 }\n"
           "cached_color()\n"
           "include \"module.rl\"\n"
           "set cached_color.color = \"#FF8800\"\n"
           "set cached_color.docs = \"cached color documentation\"\n"
           "cached_color()\n";
  }
  {
    std::ofstream out(module);
    out << "let TraceNamespace:value = fn () -> i64 { return 17 }\n";
  }
  auto state = project();
  state->configureCache((root / "cache").string());
  auto session = state->openSession();
  ASSERT_EQ(session->evaluate(":cache").status, 0);
  const auto loaded = session->executeFile(entry.string());
  ASSERT_EQ(loaded.status, 0) << loaded.error;
  session->publish();
  const auto generation = session->generations().project;
  std::ifstream entryInput(entry);
  const std::string entrySource((std::istreambuf_iterator<char>(entryInput)), {});
  for (int repeat = 0; repeat < 2; ++repeat) {
    const auto rootInspection = session->inspect(entrySource, entry.string(), true, true);
    ASSERT_EQ(rootInspection.output.find("E\t"), std::string::npos) << rootInspection.output;
    const auto colors = inspectionColors(rootInspection.output);
    std::size_t offset = 0;
    while ((offset = entrySource.find("cached_color", offset)) != std::string::npos) {
      ASSERT_TRUE(colors.contains({offset, offset + 12})) << offset;
      EXPECT_EQ(colors.at({offset, offset + 12}), "23464638383030");
      offset += 12;
    }
    EXPECT_NE(rootInspection.output.find("63616368656420636f6c6f7220646f63756d656e746174696f6e"), std::string::npos);
    const auto inspected =
        session->inspect("let TraceNamespace:value = fn () -> i64 { return 23 }\n", module.string(), true);
    EXPECT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
    EXPECT_NE(inspected.output.find("P\t"), std::string::npos);
    EXPECT_EQ(session->generations().project, generation);
    EXPECT_EQ(session->evaluate("print TraceNamespace:value()").output, "17\n");
  }
  auto observer = state->openSession();
  EXPECT_EQ(observer->evaluate("print TraceNamespace:value()").output, "17\n");
  fs::remove_all(root);
}

TEST(RecurloopGeneration, CommandLineSourcesExecuteInsideSessionRequests) {
  char program[] = "recurloop-test";
  char stringOption[] = "--string";
  char source[] = "var cli_value = 17\nprint cli_value";
  char *argv[] = {program, stringOption, source};

  auto runtime = std::make_unique<recurloop::Recurloop>();
  runtime->initialize(3, argv);
  const int inputIndex = runtime->getContext().exec.args.index;
  ASSERT_EQ(inputIndex, 1);

  auto state = recurloop::Project::create(runtime->getContext(), {program, stringOption, source});
  auto session = state->openSession();
  std::ostringstream output;
  std::ostringstream errors;
  auto response = session->executeArguments(inputIndex, &output, &errors);

  ASSERT_EQ(response.status, 0);
  EXPECT_TRUE(response.output.empty());
  EXPECT_TRUE(response.error.empty());
  EXPECT_EQ(output.str(), "17\n");
  EXPECT_TRUE(errors.str().empty());
  auto persisted = session->evaluate("print cli_value");
  ASSERT_EQ(persisted.status, 0);
  EXPECT_EQ(persisted.output, "17\n");
}

TEST(RecurloopGeneration, SessionControlsAreOrdinarySourcePhrases) {
  auto state = project();
  auto publisher = state->openSession();
  auto client = state->openSession();

  ASSERT_EQ(publisher->evaluate("const phrase_value = 73").status, 0);
  const auto published = publisher->evaluate(":publish");
  ASSERT_EQ(published.status, 0) << published.error;
  EXPECT_NE(published.output.find("published project="), std::string::npos);

  EXPECT_NE(client->evaluate("print phrase_value").status, 0);
  const auto refreshed = client->evaluate(":refresh");
  ASSERT_EQ(refreshed.status, 0) << refreshed.error;
  EXPECT_NE(refreshed.output.find("refreshed project="), std::string::npos);
  EXPECT_EQ(client->evaluate("print phrase_value").output, "73\n");

  const auto generations = client->evaluate(":generations");
  ASSERT_EQ(generations.status, 0) << generations.error;
  EXPECT_NE(generations.output.find("project="), std::string::npos);

  const auto help = client->evaluate(":help");
  ASSERT_EQ(help.status, 0) << help.error;
  EXPECT_NE(help.output.find(":publish"), std::string::npos);
  EXPECT_NE(help.output.find(":baseline"), std::string::npos);

  const auto quit = client->evaluate(":quit");
  ASSERT_EQ(quit.status, 0) << quit.error;
  EXPECT_TRUE(quit.quit);
}

TEST(RecurloopGeneration, PreparedPublicationCommitsCleanSnapshotAfterLaterSessionWork) {
  auto state = project();
  auto publisher = state->openSession();
  auto observer = state->openSession();

  ASSERT_EQ(publisher->evaluate("var prepared_value = 41").status, 0);
  const auto prepared = publisher->evaluate(":publish-prepare");
  ASSERT_EQ(prepared.status, 0) << prepared.error;
  EXPECT_NE(prepared.output.find("prepared project="), std::string::npos);

  observer->refresh();
  EXPECT_NE(observer->evaluate("print prepared_value").status, 0);
  ASSERT_EQ(publisher->evaluate("prepared_value = 99").status, 0);

  const auto committed = publisher->evaluate(":publish-commit");
  ASSERT_EQ(committed.status, 0) << committed.error;
  EXPECT_NE(committed.output.find("published project="), std::string::npos);
  EXPECT_EQ(publisher->evaluate("print prepared_value").output, "41\n");

  observer->refresh();
  EXPECT_EQ(observer->evaluate("print prepared_value").output, "41\n");
}

TEST(RecurloopGeneration, PreparedPublicationCannotReplaceNewerGeneration) {
  auto state = project();
  auto stale = state->openSession();
  auto newer = state->openSession();

  ASSERT_EQ(stale->evaluate("var stale_prepared_value = 1").status, 0);
  ASSERT_EQ(stale->evaluate(":publish-prepare").status, 0);
  ASSERT_EQ(newer->evaluate("var newer_published_value = 2").status, 0);
  ASSERT_EQ(newer->evaluate(":publish").status, 0);

  const auto rejected = stale->evaluate(":publish-commit");
  EXPECT_NE(rejected.status, 0);
  EXPECT_NE(rejected.error.find("newer project generation"), std::string::npos);

  auto observer = state->openSession();
  EXPECT_EQ(observer->evaluate("print newer_published_value").output, "2\n");
  EXPECT_NE(observer->evaluate("print stale_prepared_value").status, 0);
}

TEST(RecurloopGeneration, ResetKernelStaysEmptyInsideProjectSession) {
  char program[] = "recurloop-test";
  char reset[] = "--reset";
  char stringOption[] = "--string";
  char source[] = "print 1";
  char *argv[] = {program, reset, stringOption, source};

  auto runtime = std::make_unique<recurloop::Recurloop>();
  runtime->initialize(4, argv);
  const int inputIndex = runtime->getContext().exec.args.index;
  ASSERT_EQ(inputIndex, 2);
  ASSERT_TRUE(runtime->getContext().lexicon.phrase().getType().isNull());

  auto state = recurloop::Project::create(runtime->getContext(), {program, reset, stringOption, source});
  auto session = state->openSession();
  std::ostringstream output;
  std::ostringstream errors;
  const auto response = session->executeArguments(inputIndex, &output, &errors);

  EXPECT_NE(response.status, 0);
  EXPECT_TRUE(output.str().empty());
  EXPECT_NE(errors.str().find("undefined phrase"), std::string::npos);
  EXPECT_EQ(errors.str().find("Phrase has no type"), std::string::npos);
}

TEST(RecurloopGeneration, ProjectFileCacheWritesAndRestoresLinkedRliModules) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-project-cache-generation-test";
  std::error_code error;
  fs::remove_all(root, error);
  ASSERT_TRUE(fs::create_directories(root / "cache"));

  const fs::path source = root / "source.rl";
  {
    std::ofstream out(source);
    ASSERT_TRUE(out.is_open());
    out << "var cached_value = 17\n"
           "fn cached_increment(value:i64) -> i64 { return value + 1 }\n";
  }

  auto state = project();
  state->configureCache((root / "cache").string());

  auto first = state->openSession();
  ASSERT_EQ(first->evaluate(":baseline").status, 0);
  ASSERT_EQ(first->evaluate(":cache").status, 0);
  const auto firstLoad = first->executeFile(source.string());
  ASSERT_EQ(firstLoad.status, 0) << firstLoad.error;
  EXPECT_EQ(first->evaluate("print cached_value").output, "17\n");
  EXPECT_EQ(first->evaluate("print cached_increment(cached_value)").output, "18\n");
  std::size_t moduleImages = 0;
  std::size_t moduleManifests = 0;
  fs::path moduleImage;
  for (const auto &entry : fs::recursive_directory_iterator(root / "cache" / "modules")) {
    if (entry.path().extension() == ".rli") {
      ++moduleImages;
      moduleImage = entry.path();
    }
    if (entry.path().extension() == ".manifest") ++moduleManifests;
  }
  EXPECT_EQ(moduleImages, 1u);
  EXPECT_EQ(moduleManifests, 1u);
  EXPECT_EQ(state->cacheWrites(), 1u);
  ASSERT_FALSE(moduleImage.empty());
  std::ifstream image(moduleImage, std::ios::binary);
  char magic[6]{};
  ASSERT_TRUE(image.read(magic, sizeof(magic)));
  EXPECT_EQ(std::string_view(magic, sizeof(magic)), "RLLINK");

  auto second = state->openSession();
  ASSERT_EQ(second->evaluate(":baseline").status, 0);
  ASSERT_EQ(second->evaluate(":cache").status, 0);
  const auto secondLoad = second->executeFile(source.string());
  ASSERT_EQ(secondLoad.status, 0) << secondLoad.error;
  EXPECT_EQ(second->evaluate("print cached_value").output, "17\n");
  EXPECT_EQ(second->evaluate("print cached_increment(cached_value)").output, "18\n");
  EXPECT_GE(state->cacheHits(), 1u);

  // A restored timestamp and unchanged size cannot make different source bytes
  // reuse an older module. Also reject a valid image from a different manifest.
  std::ifstream originalImage(moduleImage, std::ios::binary);
  const std::string originalBytes((std::istreambuf_iterator<char>(originalImage)), {});
  const auto sourceTime = fs::last_write_time(source);
  {
    std::ofstream out(source);
    out << "var cached_value = 29\n"
           "fn cached_increment(value:i64) -> i64 { return value + 1 }\n";
  }
  fs::last_write_time(source, sourceTime);
  const auto hitsBeforeChange = state->cacheHits();
  auto changed = state->openSession();
  ASSERT_EQ(changed->evaluate(":cache").status, 0);
  ASSERT_EQ(changed->executeFile(source.string()).status, 0);
  EXPECT_EQ(changed->evaluate("print cached_value").output, "29\n");
  EXPECT_EQ(state->cacheHits(), hitsBeforeChange);

  const auto imageTime = fs::last_write_time(moduleImage);
  {
    std::ofstream out(moduleImage, std::ios::binary | std::ios::trunc);
    out.write(originalBytes.data(), originalBytes.size());
  }
  fs::last_write_time(moduleImage, imageTime);
  auto mismatched = state->openSession();
  ASSERT_EQ(mismatched->evaluate(":cache").status, 0);
  ASSERT_EQ(mismatched->executeFile(source.string()).status, 0);
  EXPECT_EQ(mismatched->evaluate("print cached_value").output, "29\n");
  EXPECT_EQ(state->cacheHits(), hitsBeforeChange);

  fs::remove_all(root, error);
}

TEST(RecurloopGeneration, ProjectFileCacheRestoresChildrenThatDependOnParentSourcePrefixes) {
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() / ("recurloop-cache-source-prefix-" + std::to_string(getpid()));
  fs::remove_all(root);
  ASSERT_TRUE(fs::create_directories(root));
  const auto main = root / "main.rl";
  const auto parent = root / "parent.rl";
  const auto child = root / "child.rl";
  std::ofstream(main) << "include \"parent.rl\"\n";
  std::ofstream(parent) << "let CacheKind = phrase { dictionary = true permanent = true }\n"
                           "const CacheKind:value = 41\n"
                           "include \"child.rl\"\n";
  std::ofstream(child) << "let cached_kind = <CacheKind>\n"
                          "let cached_read = fn () -> i64 { return CacheKind:value + 1 }\n";
  auto state = project();
  state->configureCache((root / "cache").string());
  const auto load = [&] {
    auto session = state->openSession();
    EXPECT_EQ(session->evaluate(":cache-exact").status, 0);
    const auto loaded = session->executeFile(main.string());
    EXPECT_EQ(loaded.status, 0) << loaded.error;
    return session;
  };
  auto cold = load();
  EXPECT_EQ(cold->evaluate("print cached_read()").output, "42\n");
  const auto writes = state->cacheWrites();
  const auto hits = state->cacheHits();
  auto warm = load();
  EXPECT_EQ(warm->evaluate("print cached_read()").output, "42\n");
  EXPECT_EQ(state->cacheHits(), hits + 1);
  EXPECT_EQ(state->cacheWrites(), writes);

  // Changing a descendant must rebuild its ancestors, retaining the prefix.
  std::ofstream(child) << "let cached_kind = <CacheKind>\n"
                          "let cached_read = fn () -> i64 { return CacheKind:value + 2 }\n";
  auto changed = load();
  EXPECT_EQ(changed->evaluate("print cached_read()").output, "43\n");
  const auto changedWrites = state->cacheWrites();
  auto changedWarm = load();
  EXPECT_EQ(changedWarm->evaluate("print cached_read()").output, "43\n");
  EXPECT_EQ(state->cacheWrites(), changedWrites);

  // A child snapshot must not restore an obsolete version of the parent prefix.
  std::ofstream(parent) << "let CacheKind = phrase { dictionary = true permanent = true }\n"
                           "const CacheKind:value = 61\n"
                           "include \"child.rl\"\n";
  auto changedParent = load();
  EXPECT_EQ(changedParent->evaluate("print CacheKind:value").output, "61\n");
  EXPECT_EQ(changedParent->evaluate("print cached_read()").output, "63\n");

  // The same source path can also be entered twice with distinct prefixes.
  std::ofstream(parent) << "var cache_prefix:i64 = 1\n"
                           "include \"child.rl\"\n"
                           "cache_prefix = 2\n"
                           "include \"child.rl\"\n";
  std::ofstream(child) << "let cached_prefix = cache_prefix\n";
  auto repeated = load();
  EXPECT_EQ(repeated->evaluate("print cached_prefix").output, "2\n");
  auto repeatedWarm = load();
  EXPECT_EQ(repeatedWarm->evaluate("print cached_prefix").output, "2\n");
  fs::remove_all(root);
}

TEST(RecurloopGeneration, FailedCacheRestoreRollsBackRebuiltDependencyLexicons) {
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() / ("recurloop-cache-restore-rollback-" + std::to_string(getpid()));
  fs::remove_all(root);
  ASSERT_TRUE(fs::create_directories(root));
  const auto source = root / "source.rl";
  const std::string body = "let cached_alias = <uncached_prerequisite>\n";
  std::ofstream(source) << body;
  char program[] = "recurloop-test";
  char *argv[] = {program};
  recurloop::Recurloop producer;
  producer.initialize(1, argv);
  auto &context = producer.getContext();
  auto state = recurloop::Project::create(context, {program});
  state->configureCache((root / "cache").string());

  // The dependency rebuilds the graph before resolution of a later external
  // reference fails. A radix append watermark cannot undo that replacement.
  recurloop::executeSource(context, "let CacheDependency = <debug:ping>\n"
                                    "set CacheDependency.docs = \"Dependency metadata.\"\n", "<dependency>", 1);
  const auto dependency = root / "dependency.rli";
  recurloop::EngineImage::saveFull(context, dependency.string());
  recurloop::EngineImage::rememberDependency(context, dependency.string());
  recurloop::executeSource(context, "let uncached_prerequisite = <debug:ping>\n", "<prerequisite>", 1);
  recurloop::ProjectCacheState cache;
  state->beginCache(cache);
  state->beginCacheStep(cache, source.string(), context);
  recurloop::executeSource(context, body, source.string(), 1);
  state->commitCacheStep(cache, context);
  ASSERT_EQ(state->cacheWrites(), 1u);

  recurloop::Recurloop consumer;
  consumer.initialize(1, argv);
  auto &restored = consumer.getContext();
  recurloop::executeSource(restored, "let CacheSentinel = <debug:ping>\n"
                                     "set CacheSentinel.docs = \"Must survive a cache miss.\"\n", "<sentinel>", 1);
  const auto before = recurloop::EngineImage::encode(restored);
  const auto used = restored.lexicon.memoryUsed();
  std::vector<std::uint8_t> bytes(used);
  std::memcpy(bytes.data(), restored.lexicon.getMemory().toPtr(), used);
  state->beginCache(cache);
  EXPECT_FALSE(state->restoreCacheStep(cache, restored, source.string()));
  EXPECT_EQ(restored.lexicon.memoryUsed(), used);
  EXPECT_EQ(std::memcmp(bytes.data(), restored.lexicon.getMemory().toPtr(), used), 0);
  EXPECT_EQ(recurloop::EngineImage::encode(restored), before);
  EXPECT_NO_THROW(recurloop::executeSource(restored, "CacheSentinel\n", "<after-cache-miss>", 1));
  fs::remove_all(root);
}

TEST(RecurloopGeneration, ProjectFileCacheExactUsesLinkedModuleOverlay) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-project-cache-exact-generation-test";
  std::error_code error;
  fs::remove_all(root, error);
  ASSERT_TRUE(fs::create_directories(root / "cache"));

  const fs::path source = root / "source.rl";
  {
    std::ofstream out(source);
    ASSERT_TRUE(out.is_open());
    out << "var cached_exact_value = 41\n";
  }

  auto state = project();
  state->configureCache((root / "cache").string());

  auto warm = state->openSession();
  ASSERT_EQ(warm->evaluate(":baseline").status, 0);
  ASSERT_EQ(warm->evaluate(":cache-exact").status, 0);
  ASSERT_EQ(warm->executeFile(source.string()).status, 0);
  EXPECT_EQ(warm->evaluate("print cached_exact_value").output, "41\n");

  auto restored = state->openSession();
  ASSERT_EQ(restored->evaluate(":baseline").status, 0);
  ASSERT_EQ(restored->evaluate(":cache-exact").status, 0);
  ASSERT_EQ(restored->evaluate("var cache_walk_only = 99").status, 0);
  const std::uint64_t hitsBefore = state->cacheHits();
  ASSERT_EQ(restored->executeFile(source.string()).status, 0);
  EXPECT_GT(state->cacheHits(), hitsBefore);
  EXPECT_EQ(restored->evaluate("print cached_exact_value").output, "41\n");
  // Linked module cache hits have the same composable semantics as ordinary
  // image imports. :cache-exact remains accepted by IDE clients, but no longer
  // turns append-only source modules into cumulative replacement snapshots.
  EXPECT_EQ(restored->evaluate("print cache_walk_only").output, "99\n");

  fs::remove_all(root, error);
}

TEST(RecurloopGeneration, ProjectFileCachePreservesAssignmentsToBaselineValues) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-project-cache-baseline-assignment-test";
  std::error_code error;
  fs::remove_all(root, error);
  ASSERT_TRUE(fs::create_directories(root / "cache"));

  char program[] = "recurloop-test";
  char *argv[] = {program};
  auto runtime = std::make_unique<recurloop::Recurloop>();
  runtime->initialize(1, argv);
  ASSERT_NO_THROW(recurloop::executeSource(runtime->getContext(), "var cached_probe = 1\n", "<cache-baseline>", 1));
  auto state = recurloop::Project::create(runtime->getContext(), {program});
  state->configureCache((root / "cache").string());

  const fs::path source = root / "source.rl";
  {
    std::ofstream out(source);
    ASSERT_TRUE(out.is_open());
    out << "cached_probe = 24\n";
  }

  auto first = state->openSession();
  ASSERT_EQ(first->evaluate(":baseline").status, 0);
  ASSERT_EQ(first->evaluate(":cache").status, 0);
  const auto firstLoad = first->executeFile(source.string());
  ASSERT_EQ(firstLoad.status, 0) << firstLoad.error;
  EXPECT_EQ(first->evaluate("print cached_probe").output, "24\n");
  EXPECT_EQ(state->cacheWrites(), 1u);

  auto second = state->openSession();
  ASSERT_EQ(second->evaluate(":baseline").status, 0);
  ASSERT_EQ(second->evaluate(":cache").status, 0);
  const auto secondLoad = second->executeFile(source.string());
  ASSERT_EQ(secondLoad.status, 0) << secondLoad.error;
  EXPECT_EQ(second->evaluate("print cached_probe").output, "24\n");
  EXPECT_GE(state->cacheHits(), 1u);

  fs::remove_all(root, error);
}

TEST(RecurloopGeneration, ProjectFileCacheRestoresUnchangedSourceModulesAndReportsDependencies) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-project-fragment-cache-generation-test";
  std::error_code error;
  fs::remove_all(root, error);
  ASSERT_TRUE(fs::create_directories(root / "cache"));

  const fs::path main = root / "main.rl";
  const fs::path firstSource = root / "first.rl";
  const fs::path secondSource = root / "second.rl";
  const fs::path unrelated = root / "unrelated.rl";
  {
    std::ofstream out(main);
    out << "include \"first.rl\"\ninclude \"second.rl\"\n";
  }
  {
    std::ofstream out(firstSource);
    out << "var fragment_first = 11\n";
  }
  {
    std::ofstream out(secondSource);
    out << "var fragment_second = 22\n";
  }
  {
    std::ofstream out(unrelated);
    out << "var unrelated_value = 99\n";
  }

  auto state = project();
  state->configureCache((root / "cache").string());
  auto first = state->openSession();
  ASSERT_EQ(first->evaluate(":baseline").status, 0);
  ASSERT_EQ(first->evaluate(":cache").status, 0);
  ASSERT_EQ(first->executeFile(main.string()).status, 0);
  EXPECT_EQ(first->evaluate("print fragment_first + fragment_second").output, "33\n");
  EXPECT_GE(state->cacheWrites(), 3u);
  std::size_t moduleImages = 0;
  for (const auto &entry : fs::recursive_directory_iterator(root / "cache" / "modules"))
    if (entry.path().extension() == ".rli") ++moduleImages;
  // main.rl, first.rl and second.rl each own exactly one cache image.
  EXPECT_EQ(moduleImages, 3u);

  const auto dependencies = first->evaluate(":cache-dependencies");
  ASSERT_EQ(dependencies.status, 0) << dependencies.error;
  EXPECT_NE(dependencies.output.find(main.string()), std::string::npos);
  EXPECT_NE(dependencies.output.find(firstSource.string()), std::string::npos);
  EXPECT_NE(dependencies.output.find(secondSource.string()), std::string::npos);
  EXPECT_EQ(dependencies.output.find(unrelated.string()), std::string::npos);

  {
    std::ofstream out(secondSource);
    out << "var fragment_second = 310\n";
  }
  auto second = state->openSession();
  ASSERT_EQ(second->evaluate(":baseline").status, 0);
  ASSERT_EQ(second->evaluate(":cache").status, 0);
  const std::uint64_t hitsBefore = state->cacheHits();
  ASSERT_EQ(second->executeFile(main.string()).status, 0);
  EXPECT_EQ(second->evaluate("print fragment_first + fragment_second").output, "321\n");
  EXPECT_GT(state->cacheHits(), hitsBefore);

  {
    std::ofstream out(unrelated);
    out << "var unrelated_value = 1000\n";
  }
  auto third = state->openSession();
  ASSERT_EQ(third->evaluate(":baseline").status, 0);
  ASSERT_EQ(third->evaluate(":cache").status, 0);
  const std::uint64_t unrelatedHitsBefore = state->cacheHits();
  ASSERT_EQ(third->executeFile(main.string()).status, 0);
  EXPECT_EQ(third->evaluate("print fragment_first + fragment_second").output, "321\n");
  EXPECT_GT(state->cacheHits(), unrelatedHitsBefore);

  fs::remove_all(root, error);
}

TEST(RecurloopGeneration, RuntimeNativeCallsPassScalarArgumentsBeyondRegisters) {
  auto state = project();
  auto session = state->openSession();

  const auto definitions = session->evaluate(R"(
let runtime_sum7 = fn (a:i64, b:i64, c:i64, d:i64, e:i64, f:i64, g:i64) -> i64 {
  return a + b + c + d + e + f + g
}
let runtime_sum16 = fn (a:i64, b:i64, c:i64, d:i64, e:i64, f:i64, g:i64, h:i64,
                        i:i64, j:i64, k:i64, l:i64, m:i64, n:i64, o:i64, p:i64) -> i64 {
  return a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p
}
)");
  ASSERT_EQ(definitions.status, 0) << definitions.error;

  const auto seven = session->evaluate("print runtime_sum7(1, 2, 3, 4, 5, 6, 7)");
  ASSERT_EQ(seven.status, 0) << seven.error;
  EXPECT_EQ(seven.output, "28\n");

  const auto sixteen = session->evaluate("print runtime_sum16(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)");
  ASSERT_EQ(sixteen.status, 0) << sixteen.error;
  EXPECT_EQ(sixteen.output, "136\n");
}

TEST(RecurloopGeneration, CompletionUsesCurrentSessionPhrases) {
  auto state = project();
  auto session = state->openSession();
  ASSERT_EQ(session->evaluate("let unique_completion_phrase = <print>\n").status, 0);
  auto completion = session->complete("unique_completion_ph", 20);
  EXPECT_EQ(completion.start, 0u);
  EXPECT_NE(std::find(completion.candidates.begin(), completion.candidates.end(), "unique_completion_phrase"),
            completion.candidates.end());
  auto isolated = state->openSession()->complete("unique_completion_ph", 20);
  EXPECT_TRUE(isolated.candidates.empty());
}

TEST(RecurloopGeneration, CompletionEscapesPathsAndMarksDirectories) {
  auto session = project()->openSession();
  ASSERT_EQ(session->evaluate("engine import \"" RECURLOOP_TEST_LANGUAGE_KIT_IMAGE "\"\n"
                              "engine import \"" RECURLOOP_TEST_SHELL_IMAGE "\"\n").status, 0);
  const auto directory = std::filesystem::temp_directory_path() / ("recurloop-completion-" + std::to_string(getpid()));
  std::filesystem::create_directories(directory / "folder");
  std::ofstream(directory / "file with spaces.txt").close();
  const std::string prefix = "echo " + directory.string() + "/fi";
  auto completion = session->complete(prefix, prefix.size());
  EXPECT_EQ(completion.start, 5u);
  ASSERT_EQ(completion.candidates.size(), 1u);
  EXPECT_EQ(completion.candidates.front(), directory.string() + "/file\\ with\\ spaces.txt");
  const std::string quoted = "echo \"" + directory.string() + "/fi";
  auto inQuote = session->complete(quoted, quoted.size());
  ASSERT_EQ(inQuote.candidates.size(), 1u);
  EXPECT_EQ(inQuote.candidates.front(), "\"" + directory.string() + "/file with spaces.txt");
  const std::string folder = "cd " + directory.string() + "/fo";
  auto folders = session->complete(folder, folder.size());
  ASSERT_EQ(folders.candidates.size(), 1u);
  EXPECT_EQ(folders.candidates.front(), directory.string() + "/folder/");
  std::filesystem::remove_all(directory);
}

TEST(RecurloopGeneration, CompletionWithoutShellOnlyUsesLexicon) {
  auto session = project()->openSession();
  ASSERT_EQ(session->evaluate("let unique_completion_phrase = <print>\n").status, 0);
  const std::string expression = "print unique_completion_ph";
  auto phrases = session->complete(expression, expression.size());
  EXPECT_EQ(phrases.start, 6u);
  EXPECT_EQ(phrases.candidates, (std::vector<std::string>{"unique_completion_phrase"}));

  const auto directory = std::filesystem::temp_directory_path() / ("recurloop-lexicon-completion-" + std::to_string(getpid()));
  std::filesystem::create_directories(directory);
  const auto executable = directory / "unique_completion_command";
  std::ofstream(executable).close();
  std::filesystem::permissions(executable, std::filesystem::perms::owner_all);
  const char *previousPath = std::getenv("PATH");
  const bool hadPath = previousPath != nullptr;
  const std::string savedPath = previousPath ? previousPath : "";
  setenv("PATH", directory.c_str(), 1);
  auto commands = session->complete("unique_completion_", 18);
  const std::string path = directory.string() + "/unique";
  auto files = session->complete(path, path.size());
  auto arguments = session->complete("print unique_completion_", 24);
  const auto enabled = session->evaluate("engine import \"" RECURLOOP_TEST_LANGUAGE_KIT_IMAGE "\"\n"
                                         "engine import \"" RECURLOOP_TEST_SHELL_IMAGE "\"\n");
  auto shellCommands = session->complete("unique_completion_", 18);
  auto shellFiles = session->complete(path, path.size());
  if (hadPath) setenv("PATH", savedPath.c_str(), 1);
  else unsetenv("PATH");
  std::filesystem::remove_all(directory);

  ASSERT_EQ(enabled.status, 0) << enabled.error;
  EXPECT_NE(std::find(shellCommands.candidates.begin(), shellCommands.candidates.end(), "unique_completion_command"),
            shellCommands.candidates.end());
  EXPECT_EQ(shellFiles.candidates, (std::vector<std::string>{executable.string()}));
  EXPECT_EQ(commands.candidates, (std::vector<std::string>{"unique_completion_phrase"}));
  // Core treats '/' as an expression separator: the trailing "unique" can
  // complete a lexicon phrase, but must not produce the filesystem path.
  EXPECT_EQ(files.start, directory.string().size() + 1);
  EXPECT_EQ(files.candidates, (std::vector<std::string>{"unique_completion_phrase"}));
  EXPECT_EQ(arguments.candidates, (std::vector<std::string>{"unique_completion_phrase"}));
}

TEST(RecurloopGeneration, PhrasePalettePreservesEachKeywordColor) {
  auto session = project()->openSession();
  const std::string source = "let palette_probe = fn () -> i64 { var value:i64 = 1; return value }\n";
  const auto expectColors = [&](const std::string &output) {
    for (const auto &[token, color] : {std::pair{"let", "23353639434436"},
                                      std::pair{"fn", "23353639434436"},
                                      std::pair{"var", "23353639434436"},
                                      std::pair{"return", "23433538364330"}}) {
      const auto start = source.find(token);
      const auto end = start + std::strlen(token);
      bool found = false;
      std::istringstream rows(output);
      for (std::string row; std::getline(rows, row);) {
        std::istringstream fields(row);
        std::string tag, actualColor;
        std::size_t spanStart = 0, spanEnd = 0, group = 0;
        if (!(fields >> tag >> spanStart >> spanEnd >> group >> actualColor) || tag != "S") continue;
        if (spanStart <= start && spanEnd >= end) {
          EXPECT_EQ(actualColor, color) << token << ": " << row;
          found = true;
        }
      }
      EXPECT_TRUE(found) << token << ": " << output;
    }
  };
  expectColors(session->highlight(source));
  const auto inspected = session->inspect(source, "/tmp/palette-inspection.rl", false, true);
  ASSERT_EQ(inspected.output.find("E\t"), std::string::npos) << inspected.output;
  expectColors(inspected.output);
}

TEST(RecurloopGeneration, ConsoleHighlightingDoesNotCommitInput) {
  auto session = project()->openSession();
  ASSERT_EQ(session->evaluate("var console_answer = 41\n").status, 0);
  const auto before = session->generations();
  const auto spans = session->highlight("console_answer = 42");
  EXPECT_NE(spans.find("S\t"), std::string::npos);
  EXPECT_EQ(session->generations().request, before.request);
  EXPECT_EQ(session->generations().session, before.session);
  EXPECT_EQ(session->evaluate("print console_answer\n").output, "41\n");
  session->highlight("var console_uncommitted = 99");
  EXPECT_NE(session->evaluate("print console_uncommitted\n").status, 0);
}

TEST(RecurloopGeneration, ConsolePaletteUpdatesAfterRequestsAndRefresh) {
  auto session = project()->openSession();
  const auto original = session->highlight("ConsolePaletteType");
  ASSERT_EQ(session->evaluate("record ConsolePaletteType { value:i64 }\n").status, 0);
  const auto updated = session->highlight("ConsolePaletteType");
  EXPECT_NE(updated, original);
  EXPECT_EQ(session->highlight("ConsolePaletteType"), updated);
  session->refresh();
  EXPECT_EQ(session->highlight("ConsolePaletteType"), original);
}

TEST(RecurloopGeneration, InspectionFoldsConstantArrayLengthsWithoutExecutingUserFunctions) {
  auto state = project();
  auto session = state->openSession();
  const std::string source = R"(
const columns = 5
const rows = 2
const count = columns * rows
record Grid { cells:u8[count] }
let read = fn (grid:Grid*) -> u8 { return grid.cells[count - 1] }
let grid_size = fn () -> i64 { return sizeof(Grid) }
extern puts(text:u8*) -> i32 abi sysv-amd64
let side_effect = fn () -> i64 { puts("constant-side-effect"); return 7 }
const dynamic_value = side_effect()
)";
  const auto inspected = session->inspect(source, "<constant-array-inspection>", true, true);
  ASSERT_EQ(inspected.status, 0) << inspected.error;
  EXPECT_EQ(inspected.output.find("constant-side-effect"), std::string::npos);
  EXPECT_NE(session->evaluate("print count").status, 0);
  const auto defined = session->evaluate(source);
  ASSERT_EQ(defined.status, 0) << defined.error;
  EXPECT_EQ(defined.output, "constant-side-effect\n");
  EXPECT_EQ(session->evaluate("print grid_size()").output, "10\n");
}

TEST(RecurloopGeneration, EmbeddedSourceEvaluationCapturesOutputAndRecoversWithoutLosingCallerState) {
  auto session = project()->openSession();
  const auto setup = session->evaluate(R"rl(
extern malloc(bytes:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
extern strstr(text:u8*, needle:u8*) -> u8* abi sysv-amd64
let api = phrase { dictionary = true }
let api:inner = phrase {
  type = <phrase-types:elaborate>
  action = fn (state:Context*, called:Phrase*) -> void {
    if context:io:active() != state { context:diagnostic:error(state, "missing active context"); return }
    let bytes = malloc(8)
    defer free(bytes)
    let status = context:source:evaluate(state, "print 42", "<inner>", &bytes[0], 8)
    if status != 0 || strcmp(&bytes[0], "42\n") != 0 || context:io:active() != state {
      context:diagnostic:error(state, "nested evaluation did not restore its caller")
    }
    context:source:root(state)
  }
}
let "api:inner" = <api:inner>
let api:check = phrase {
  type = <phrase-types:elaborate>
  action = fn (state:Context*, called:Phrase*) -> void {
    let bytes = malloc(512)
    defer free(bytes)
    if context:io:active() != cast(Context*, 0) { context:diagnostic:error(state, "leaked active context"); return }
    let before = state.exec.status
    if context:source:evaluate(state, "var embedded_value = 41\napi:inner", "<embedded>", &bytes[0], 512) != 0 || strcmp(&bytes[0], "42\n") != 0 {
      context:diagnostic:error(state, "embedded output or definitions failed"); return
    }
    if context:source:evaluate(state, "print embedded_value + 2", "<embedded>", &bytes[0], 512) != 0 || strcmp(&bytes[0], "43\n") != 0 {
      context:diagnostic:error(state, "embedded value did not persist"); return
    }
    if context:source:evaluate(state, "print missing_embedded_value", "<bad-input>", &bytes[0], 512) == 0 || !strstr(&bytes[0], "<bad-input>") {
      context:diagnostic:error(state, "error did not carry source origin"); return
    }
    if context:source:evaluate(state, "print 44", "<recovered>", &bytes[0], 512) != 0 || strcmp(&bytes[0], "44\n") != 0 {
      context:diagnostic:error(state, "evaluation did not recover"); return
    }
    let tail = malloc(4)
    defer free(tail)
    if context:source:evaluate(state, "print \"abcdefgh\"", "<bounded>", &tail[0], 4) != 0 || strcmp(&tail[0], "gh\n") != 0 {
      context:diagnostic:error(state, "capture did not bound its tail"); return
    }
    var empty:u8 = 99
    if context:source:evaluate(state, "print 45", "<empty>", &empty, 1) != 0 || empty != 0 {
      context:diagnostic:error(state, "one-byte capture failed"); return
    }
    if state.exec.status != before || context:io:active() != cast(Context*, 0) {
      context:diagnostic:error(state, "evaluation leaked execution state"); return
    }
    context:io:write(state, "SOURCE API OK\n")
    context:source:root(state)
  }
}
let "api:check" = <api:check>
)rl");
  ASSERT_EQ(setup.status, 0) << setup.error;
  const auto result = session->evaluate("api:check\nprint embedded_value\n");
  ASSERT_EQ(result.status, 0) << result.error << result.output;
  EXPECT_NE(result.output.find("SOURCE API OK\n41\n"), std::string::npos);
  EXPECT_EQ(session->evaluate("print embedded_value + 1\n").output, "42\n");
  EXPECT_NE(project()->openSession()->evaluate("print embedded_value\n").status, 0);
}

TEST(RecurloopGeneration, EmbeddedCompletionOwnsCandidatesAndContainsProviderErrors) {
  auto session = project()->openSession();
  const auto setup = session->evaluate(R"rl(
extern malloc(bytes:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern strcmp(left:u8*, right:u8*) -> i32 abi sysv-amd64
let api = phrase { dictionary = true }
let api:provider = phrase {
  type = <phrase-types:elaborate>
  action = fn (state:Context*, called:Phrase*) -> void {
    if strcmp(context:completion:source(state), "hello wo") != 0 || context:completion:cursor(state) != 8 {
      context:diagnostic:error(state, "wrong completion input"); return
    }
    context:completion:start(state, 6)
    context:completion:add(state, "world")
    context:completion:add(state, "work")
    context:io:write(state, "provider noise")
  }
}
let api:broken = phrase {
  type = <phrase-types:elaborate>
  action = fn (state:Context*, called:Phrase*) -> void { context:diagnostic:error(state, "provider failed") }
}
let api:check = phrase {
  type = <phrase-types:elaborate>
  action = fn (state:Context*, called:Phrase*) -> void {
    let owner = context:phrase:find(state, "api")
    let provider = context:phrase:find:exact(state, owner, "provider")
    let broken = context:phrase:find:exact(state, owner, "broken")
    if context:completion:request(state, broken, "hello wo", 8) {
      context:diagnostic:error(state, "broken provider succeeded"); return
    }
    let request = context:completion:request(state, provider, "hello wo", 99)
    if !request { context:diagnostic:error(state, "completion failed after provider error"); return }
    defer context:completion:result:release(request)
    if context:completion:result:start(request) != 6 || context:completion:result:count(request) != 2 || strcmp(context:completion:result:candidate(request, 0), "world") != 0 || context:completion:result:candidate(request, 2) {
      context:diagnostic:error(state, "completion results failed"); return
    }
    let bytes = malloc(16)
    defer free(bytes)
    if context:source:evaluate(state, "print 42", "<after-completion>", &bytes[0], 16) != 0 || strcmp(context:completion:result:candidate(request, 1), "work") != 0 {
      context:diagnostic:error(state, "completion ownership failed"); return
    }
    context:io:write(state, "COMPLETION API OK\n")
    context:source:root(state)
  }
}
let "api:check" = <api:check>
)rl");
  ASSERT_EQ(setup.status, 0) << setup.error;
  const auto result = session->evaluate("api:check\nprint 7\n");
  ASSERT_EQ(result.status, 0) << result.error;
  EXPECT_EQ(result.output, "42\nCOMPLETION API OK\n7\n");
  EXPECT_TRUE(result.error.empty());
}
