#include <gtest/gtest.h>

#include <recurloop/Project.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Session.hpp>

#include <sstream>

namespace {
  std::shared_ptr<recurloop::Project> project() {
    char program[] = "recurloop-test";
    char *argv[] = {program};
    auto runtime = std::make_unique<recurloop::Recurloop>();
    runtime->initialize(1, argv);
    return recurloop::Project::create(runtime->getContext(), {program});
  }
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
