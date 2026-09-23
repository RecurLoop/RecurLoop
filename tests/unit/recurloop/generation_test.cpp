#include <gtest/gtest.h>

#include <recurloop/Project.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>

#include <filesystem>
#include <fstream>
#include <sstream>

namespace {
  std::shared_ptr<recurloop::Project> project() {
    char program[] = "recurloop-test";
    char *argv[] = {program};
    auto runtime = std::make_unique<recurloop::Recurloop>();
    runtime->initialize(1, argv);
    return recurloop::Project::create(runtime->getContext(), {program});
  }
} // namespace

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
  auto failed = session->evaluate("value = 99\nthis phrase does not exist");
  EXPECT_NE(failed.status, 0);

  auto after = session->evaluate("print value");
  ASSERT_EQ(after.status, 0);
  EXPECT_EQ(after.output, "7\n");
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

TEST(RecurloopGeneration, ProjectFileCacheWritesAndRestoresRliSteps) {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / "recurloop-project-cache-generation-test";
  std::error_code error;
  fs::remove_all(root, error);
  ASSERT_TRUE(fs::create_directories(root / "cache"));

  const fs::path source = root / "source.rl";
  {
    std::ofstream out(source);
    ASSERT_TRUE(out.is_open());
    out << "var cached_value = 17\n";
  }

  auto state = project();
  state->configureCache((root / "cache").string());

  auto first = state->openSession();
  ASSERT_EQ(first->evaluate(":baseline").status, 0);
  ASSERT_EQ(first->evaluate(":cache").status, 0);
  const auto firstLoad = first->executeFile(source.string());
  ASSERT_EQ(firstLoad.status, 0) << firstLoad.error;
  EXPECT_EQ(first->evaluate("print cached_value").output, "17\n");
  EXPECT_TRUE(fs::is_regular_file(root / "cache" / "steps" / "000000.rli"));
  EXPECT_TRUE(fs::is_regular_file(root / "cache" / "steps" / "000000.manifest"));
  EXPECT_EQ(state->cacheWrites(), 1u);

  auto second = state->openSession();
  ASSERT_EQ(second->evaluate(":baseline").status, 0);
  ASSERT_EQ(second->evaluate(":cache").status, 0);
  const auto secondLoad = second->executeFile(source.string());
  ASSERT_EQ(secondLoad.status, 0) << secondLoad.error;
  EXPECT_EQ(second->evaluate("print cached_value").output, "17\n");
  EXPECT_GE(state->cacheHits(), 1u);

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

TEST(RecurloopGeneration, ProjectFileCacheRestoresUnchangedIncludeFragmentsAndReportsDependencies) {
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
  std::size_t fragmentImages = 0;
  for (const auto &entry : fs::directory_iterator(root / "cache" / "fragments"))
    if (entry.path().extension() == ".rli") ++fragmentImages;
  EXPECT_EQ(fragmentImages, 2u);

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
