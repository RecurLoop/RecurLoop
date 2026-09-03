#include <gtest/gtest.h>

#include <compiler/LanguageState.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Recurloop.hpp>

#include <filesystem>
#include <sstream>

#include <unistd.h>

namespace {
  class EngineImageTesting : public recurloop::Recurloop, public testing::Test {
  protected:
    void initializeWith(std::string source) {
      input = std::move(source);
      const char *arguments[] = {"Recurloop", "--string", input.c_str()};
      initialize(static_cast<int>(std::size(arguments)), const_cast<char **>(arguments));
      context.io.out = &output;
      context.io.err = &errors;
      ASSERT_EQ(execute(), 0) << errors.str();
    }

    lexicon::Phrase rootPhrase(std::string_view name) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Match match = root.matchExact(Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length);
      return match.isNull() ? lexicon::Phrase(&context.lexicon) : match.getPhrase();
    }

    std::string input;
    std::ostringstream output;
    std::ostringstream errors;
  };
} // namespace

TEST_F(EngineImageTesting, FlattensShadowedPhrasesAndRelocatesAcrossARebuild) {
  initializeWith("let print = <debug:ping>\n");
  ASSERT_FALSE(rootPhrase("print").older().isNull());
  const Size expanded = context.lexicon.memoryUsed();

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  lexicon::Phrase print = rootPhrase("print");
  ASSERT_FALSE(print.isNull());
  EXPECT_TRUE(print.older().isNull());
  EXPECT_LT(context.lexicon.memoryUsed(), expanded);
  recurloop::executeSource(context, "print\n", "<image-test>", 1);
  EXPECT_EQ(output.str(), "pong\n");
}

TEST_F(EngineImageTesting, OmitsUnserializablePhrasesUnlessTheyAreReferenced) {
  initializeWith("");
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase transient = root.append("transient").make().setType(lexicon::phrase::type::getData(root)).save();
  transient.setSerializable(false).save();

  const std::string source = recurloop::EngineImage::source(context);
  EXPECT_EQ(source.find("key \"transient\""), std::string::npos);

  root.append("exported")
      .make()
      .setPrototype(transient)
      .setType(lexicon::phrase::type::getData(root))
      .save();
  EXPECT_ANY_THROW(recurloop::EngineImage::encode(context));
}

TEST_F(EngineImageTesting, PreservesPermanentAndRewritablePhraseProperties) {
  initializeWith(R"(
let extension = phrase {
  type = <phrase-types:elaborate>
  permanent = true
  rewrite = true
  action = fn (state:Context*, called:Phrase*) -> void {
    context:syntax:emit(state, "42")
  }
}
)");

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  lexicon::Phrase extension = rootPhrase("extension");
  ASSERT_FALSE(extension.isNull());
  EXPECT_TRUE(extension.isPermanent());
  EXPECT_TRUE(extension.isRewritable());
  EXPECT_ANY_THROW(recurloop::executeSource(context, "let extension = <debug:ping>\n", "<image-test>", 1));
}

TEST_F(EngineImageTesting, PersistsCompiledModulesAndRebuildsTheirJitCache) {
  initializeWith("let compiled = asm { ret }\n");
  ASSERT_TRUE(rootPhrase("compiled").isSerializable());
  recurloop::executeSource(context, "compiled\n", "<image-test>", 1);
  EXPECT_NE(rootPhrase("compiled").getActionEntry(), 0u);

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  lexicon::Phrase compiled = rootPhrase("compiled");
  EXPECT_TRUE(compiled.isSerializable());
  EXPECT_EQ(compiled.getActionEntry(), 0u);
  recurloop::executeSource(context, "compiled\n", "<image-test>", 1);
  EXPECT_NE(rootPhrase("compiled").getActionEntry(), 0u);
}

TEST_F(EngineImageTesting, KeepsShadowedPhrasesReferencedByPayloadRelocations) {
  initializeWith("");
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase oldTarget = root.append("target").make().setType(lexicon::phrase::type::getData(root)).save();
  root.append("binding")
      .make()
      .setType(lexicon::phrase::type::getData(root))
      .save()
      .store(compiler::LanguageBinding{compiler::LanguageBinding::Magic, oldTarget.getAddress()})
      .save();
  root.append("target").make().setType(lexicon::phrase::type::getData(root)).save();

  oldTarget.setSerializable(false).save();
  EXPECT_ANY_THROW(recurloop::EngineImage::encode(context));
  oldTarget.setSerializable(true).save();

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  lexicon::Phrase binding = rootPhrase("binding");
  compiler::LanguageBinding restored;
  binding.fetch(0, restored);
  lexicon::Phrase relocated(&context.lexicon, restored.language);
  relocated.load();
  ASSERT_FALSE(relocated.isNull());
  EXPECT_EQ(relocated.getKey(), "target");
  EXPECT_NE(relocated.getAddress(), rootPhrase("target").getAddress());
  EXPECT_EQ(rootPhrase("target").older().getAddress(), relocated.getAddress());
}

TEST_F(EngineImageTesting, RoundTripsRuntimeAndCompilerState) {
  initializeWith(R"(
var persisted = 40
set persisted += 2
extern imported(value:i64) -> i64 abi sysv-amd64
)");

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  EXPECT_EQ(context.values().get("persisted").asInteger(), 42);
  const std::optional<compiler::TypedFunction> imported = context.language().findFunction("imported");
  ASSERT_TRUE(imported);
  EXPECT_TRUE(imported->imported);
}

TEST_F(EngineImageTesting, RoundTripsBitPreciseKeysInBinaryAndSourceImages) {
  initializeWith("");
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase group =
      root.append("bit-roundtrip").make().enableSubdictionary().setType(lexicon::phrase::type::getData(root)).save();
  unsigned char packed = 0xa0;
  group.append(Byte(&packed), 0, 3).make().setType(lexicon::phrase::type::getData(root)).save();
  group.append(Byte(&packed), 0, 4).make().setType(lexicon::phrase::type::getData(root)).save();

  const auto verify = [&] {
    lexicon::Phrase restored = rootPhrase("bit-roundtrip");
    lexicon::Match three = restored.matchExact(Byte(&packed), 0, 3);
    lexicon::Match four = restored.matchExact(Byte(&packed), 0, 4);
    ASSERT_FALSE(three.isNull());
    ASSERT_FALSE(four.isNull());
    EXPECT_NE(three.getPhrase().getAddress(), four.getPhrase().getAddress());
    EXPECT_EQ(three.getPhrase().getNode().keyBits(), 3u);
    EXPECT_EQ(four.getPhrase().getNode().keyBits(), 4u);
  };

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);
  verify();

  const std::string source = recurloop::EngineImage::source(context);
  EXPECT_NE(source.find(" bits 3 flags "), std::string::npos);
  ASSERT_NO_THROW(recurloop::executeSource(context, source, "<bit-image>", 1));
  verify();
}

TEST_F(EngineImageTesting, RoundTripsInlinePhraseActionsWithoutPersistingJitEntries) {
  initializeWith(R"(
let persisted-inline-action = phrase {
  type = <phrase-types:callable>
  action = fn (context:Context*, phrase:Phrase*) -> void {
    context.workspace.bssBytes += 1
  }
}
let inherited-inline-action = phrase {
  type = <phrase-types:callable>
  prototype = <persisted-inline-action>
}
)");

  std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);
  recurloop::executeSource(context, "inherited-inline-action\n", "<inline-action-image>", 1);
  EXPECT_EQ(context.workspace.bssBytes, 1u);
  EXPECT_FALSE(rootPhrase("inherited-inline-action").containsAction());

  image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);
  context.workspace.bssBytes = 0;
  recurloop::executeSource(context, "persisted-inline-action\n", "<inline-action-image>", 1);
  EXPECT_EQ(context.workspace.bssBytes, 1u);

  const std::string source = recurloop::EngineImage::source(context);
  recurloop::executeSource(context, source, "<inline-action-source-image>", 1);
  context.workspace.bssBytes = 0;
  recurloop::executeSource(context, "persisted-inline-action\n", "<inline-action-source-image>", 1);
  EXPECT_EQ(context.workspace.bssBytes, 1u);
}

TEST_F(EngineImageTesting, RoundTripsTypedCallbacksAndAnonymousFunctionModules) {
  initializeWith(R"(
let persisted-typed-callback = phrase {
  type = <phrase-types:callable>
  action = fn (context:Context*, phrase:Phrase*) -> void {
    let callback:fn (i64) -> i64 = fn (value:i64) -> i64 {
      return value + 2
    }
    context.workspace.bssBytes = callback(40)
  }
}
)");

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);
  recurloop::executeSource(context, "persisted-typed-callback\n", "<callback-image>", 1);
  EXPECT_EQ(context.workspace.bssBytes, 42u);
}

TEST_F(EngineImageTesting, RoundTripsFunctionSignaturePhrases) {
  initializeWith(R"(
let PersistedNullary = fn () -> i64
let PersistedUnary = fn (value:i64) -> i64
let PersistedUnaryAlias = <PersistedUnary>
)");

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);
  const std::string source = recurloop::EngineImage::source(context);
  recurloop::executeSource(context, source, "<signature-source-image>", 1);
  recurloop::executeSource(context, R"(
let restored_answer = PersistedNullary {
  return 42
}
let restored_increment = PersistedUnaryAlias {
  return value + 1
}
let restored_apply = fn (callback:PersistedUnary, value:i64) -> i64 {
  return callback(value)
}
let restored_result_fn = fn () -> i64 {
  return restored_answer() + restored_apply(restored_increment, 41)
}
var restored_result = restored_result_fn()
)",
                           "<signature-image>", 1);

  EXPECT_EQ(context.values().get("restored_result").asInteger(), 84);
}

TEST_F(EngineImageTesting, RebuildsTheSameLanguageFromGeneratedRlSource) {
  initializeWith("");
  const std::string source = recurloop::EngineImage::source(context);
  ASSERT_TRUE(source.starts_with("engine define {\n"));

  ASSERT_NO_THROW(recurloop::executeSource(context, source, "<generated-engine>", 1));
  ASSERT_NO_THROW(recurloop::executeSource(context, "var \"generated value\" = 42\n", "<generated-engine-test>", 1));
  ASSERT_NO_THROW(recurloop::executeSource(context, "debug:ping\n", "<image-test>", 1));
  EXPECT_EQ(context.values().get("generated value").asInteger(), 42);
  EXPECT_EQ(output.str(), "pong\n");
}

TEST_F(EngineImageTesting, ImportsAnEngineFromRecurloopSourceWithoutUsingTheReplacedPhrase) {
  initializeWith("");
  const std::filesystem::path image =
      std::filesystem::path("/tmp") / ("recurloop-engine-import-" + std::to_string(getpid()) + ".rli");
  std::filesystem::remove(image);

  EXPECT_NO_THROW(recurloop::executeSource(context,
                                           "engine export \"" + image.string() +
                                               "\"\n"
                                               "engine import \"" +
                                               image.string() +
                                               "\"\n"
                                               "debug:ping\n",
                                           "<engine-import-test>", 1));
  std::filesystem::remove(image);
  EXPECT_EQ(output.str(), "pong\n");
}

TEST_F(EngineImageTesting, ProducesADeterministicBinaryImage) {
  initializeWith("");
  const std::vector<std::uint8_t> first = recurloop::EngineImage::encode(context);

  recurloop::EngineImage::decode(context, first);

  EXPECT_EQ(recurloop::EngineImage::encode(context), first);
  recurloop::executeSource(context, "var \"binary value\" = 40\nset \"binary value\" += 2\n", "<image-test>", 1);
  EXPECT_EQ(context.values().get("binary value").asInteger(), 42);
}

TEST_F(EngineImageTesting, ImportsBinaryImagesByMergingIntoTheExistingLexicon) {
  initializeWith("let first = <debug:ping>\n");
  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);

  recurloop::executeSource(context, "let second = <debug:ping>\n", "<merge-test>", 1);
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase debug = rootPhrase("debug");
  lexicon::Match pingMatch = debug.matchExact(Byte(const_cast<char *>("ping")), 0, 4 * Byte::length);
  ASSERT_FALSE(pingMatch.isNull());
  lexicon::Phrase ping = pingMatch.getPhrase();
  lexicon::Phrase preserved =
      root.append("preserved").make().enableSubdictionary().setType(lexicon::phrase::type::getData(root)).save();
  lexicon::Phrase child = preserved.append("child").make().setType(ping.getType()).setAction(ping.getAction()).save();
  preserved.append("binding")
      .make()
      .setType(lexicon::phrase::type::getData(root))
      .save()
      .store(compiler::LanguageBinding{compiler::LanguageBinding::Magic, child.getAddress()})
      .save();
  recurloop::EngineImage::decode(context, image);

  EXPECT_FALSE(rootPhrase("first").isNull());
  EXPECT_FALSE(rootPhrase("second").isNull());
  EXPECT_FALSE(rootPhrase("preserved").isNull());
  lexicon::Phrase restoredPreserved = rootPhrase("preserved");
  lexicon::Match restoredChild = restoredPreserved.matchExact(Byte(const_cast<char *>("child")), 0, 5 * Byte::length);
  ASSERT_FALSE(restoredChild.isNull());
  lexicon::Match restoredBinding =
      restoredPreserved.matchExact(Byte(const_cast<char *>("binding")), 0, 7 * Byte::length);
  ASSERT_FALSE(restoredBinding.isNull());
  compiler::LanguageBinding binding;
  restoredBinding.getPhrase().fetch(0, binding);
  EXPECT_EQ(binding.language, restoredChild.getPhrase().getAddress());

  output.str("");
  recurloop::executeSource(context, "first\nsecond\n", "<merge-test>", 1);
  restoredChild.getPhrase().invoke(context);
  EXPECT_EQ(output.str(), "pong\npong\npong\n");
}

TEST_F(EngineImageTesting, RejectsAnInvalidManifestBeforeClearingTheLanguage) {
  initializeWith("");
  constexpr std::string_view invalid = "phrase 1 parent 2 key \"child\" bits 40 flags 0 prototype 0 type 0 successor 0 "
                                       "action \"\" action-target 0 payload \"\"\n"
                                       "phrase 2 parent 0 key \"\" bits 0 flags 1 prototype 0 type 0 successor 0 "
                                       "action \"\" action-target 0 payload \"\"\n";

  EXPECT_ANY_THROW(recurloop::EngineImage::define(context, invalid));
  recurloop::executeSource(context, "debug:ping\n", "<image-test>", 1);
  EXPECT_EQ(output.str(), "pong\n");
}

TEST_F(EngineImageTesting, PersistsInvokedCompiledFunctionsWithoutTheirProcessEntries) {
  initializeWith("let twice = fn (value:i64) -> i64 { return value + 1 }\n"
                 "let twice = fn (value:i64) -> i64 { return value * 2 }\n");
  ASSERT_FALSE(rootPhrase("twice").older().isNull());
  recurloop::executeSource(context, "print twice(21)\n", "<binary-image-test>", 1);
  EXPECT_EQ(output.str(), "42\n");

  const std::vector<std::uint8_t> image = recurloop::EngineImage::encode(context);
  recurloop::EngineImage::decode(context, image);

  EXPECT_EQ(rootPhrase("twice").getActionEntry(), 0u);
  output.str("");
  recurloop::executeSource(context, "print twice(21)\n", "<binary-image-test>", 1);
  EXPECT_EQ(output.str(), "42\n");
}
