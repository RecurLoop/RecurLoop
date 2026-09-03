#include <gtest/gtest.h>
#include <recurloop/Recurloop.hpp>

#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

class RecurloopTesting : public recurloop::Recurloop, public testing::Test {
public:
  void SetUp() override {}

  void TearDown() override {}

  int execute(int argc, char **argv) {
    return Recurloop::initialize(argc, argv).execute();
  }
};

TEST_F(RecurloopTesting, LetParseWorkspace) {
  const char *argv[] = {"Recurloop", "--string", "let Hello, Recurloop!"};

  int result = execute(countof(argv), (char **)argv);

  EXPECT_EQ(std::string((char *)context.workspace.key.getMemory().toPtr()), "Hello, Recurloop!");
  EXPECT_EQ(result, 0);
}

TEST_F(RecurloopTesting, LetParseStaging) {
  const char *argv[] = {"Recurloop", "--string", "let Hello, Recurloop! ="};

  int result = execute(countof(argv), (char **)argv);

  EXPECT_EQ(context.staging.phrase.getKey(), "Hello, Recurloop!");
  EXPECT_EQ(result, 0);
}

TEST_F(RecurloopTesting, InterpolatesStringExpressionsIntoPhraseNamesAndReferences) {
  const char *argv[] = {"Recurloop", "--string", R"(
const subject = "world"
const identifier = 42
const dynamic_part = "runtime"

let "hello ${upper(subject)}" = <debug:ping>
let command-${str(identifier)} = <debug:ping>
let ${dynamic_part}-phrase = <debug:ping>
let literal-\${subject} = <debug:ping>
let group = [
  "${subject} command" = <debug:ping>
  world = []
]
let group:${subject}:generated = <debug:ping>
let generated_alias = <"hello ${upper(subject)}">
let nested_alias = <group:"${subject} command">
let path_alias = <group:"${subject}":generated>

hello WORLD
command-42
runtime-phrase
literal-${subject}
group world command
group:world:generated
generated_alias
nested_alias
path_alias
)"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, RejectsNonStringPhraseNameInterpolation) {
  const char *argv[] = {"Recurloop", "--string", "const number = 42\nlet item-${number} = <debug:ping>\n"};
  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, RejectsUnterminatedPhraseNameInterpolation) {
  const char *argv[] = {"Recurloop", "--string", "const name = \"broken\"\nlet item-${name = <debug:ping>\n"};
  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, StructUsesPhraseTemplatesAndInheritedSubdictionaries) {
  const char *argv[] = {"Recurloop", "--string",
                        "struct Example = [ field = hex { c3 } method = asm { ret } ] "
                        "struct ExamplePointer = <Example> "
                        "let item = <Example> let pointer = <ExamplePointer>\n"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  lexicon::Phrase root = context.lexicon.phrase();
  const auto child = [](lexicon::Phrase &dictionary, const char *name) {
    return dictionary.matchExact(Byte((unsigned char *)name), 0, std::strlen(name) * Byte::length).getPhrase();
  };
  lexicon::Phrase example = child(root, "Example");
  lexicon::Phrase item = child(root, "item");
  lexicon::Phrase pointerType = child(root, "ExamplePointer");
  lexicon::Phrase pointer = child(root, "pointer");
  ASSERT_FALSE(example.isNull());
  ASSERT_FALSE(item.isNull());
  EXPECT_EQ(item.getPrototype().getAddress(), example.getAddress());
  EXPECT_FALSE(child(item, "field").isNull());
  EXPECT_TRUE(child(item, "method").isInvokable());
  EXPECT_EQ(pointer.getPrototype().getAddress(), pointerType.getAddress());
  EXPECT_EQ(pointerType.getPrototype().getAddress(), example.getAddress());
  EXPECT_FALSE(child(pointer, "field").isNull());
}

TEST_F(RecurloopTesting, PhraseDescriptorUsesTypeBehaviorAndPrototypeAction) {
  const char *argv[] = {"Recurloop", "--string", R"(
let alias = phrase {
  prototype = <debug:ping>
  dictionary = true
  payload = "data"
  serializable = false
}
alias
)"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase alias = root.matchExact(Byte((unsigned char *)"alias"), 0, 5 * Byte::length).getPhrase();
  ASSERT_FALSE(alias.isNull());
  EXPECT_EQ(alias.getPrototype().getKey(), "ping");
  EXPECT_EQ(alias.getType().getAddress(), alias.getPrototype().getType().getAddress());
  EXPECT_FALSE(alias.containsType());
  EXPECT_FALSE(alias.containsAction());
  EXPECT_TRUE(alias.containsSubdictionary());
  EXPECT_EQ(alias.payloadSize(), 4u);
  EXPECT_FALSE(alias.isSerializable());
}

TEST_F(RecurloopTesting, PermanentPhraseRejectsRedefinition) {
  const char *argv[] = {"Recurloop", "--string", R"(
let protected = phrase {
  type = <phrase-types:data>
  permanent = true
}
let protected = <debug:ping>
)"};

  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, PermanentPhraseRejectsMutation) {
  const char *argv[] = {"Recurloop", "--string", R"(
let protected = phrase {
  type = <phrase-types:data>
  permanent = true
}
set protected.serializable = false
)"};

  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, RootRewriteUsesTheMarkedPhraseDirectly) {
  const char *argv[] = {"Recurloop", "--string", R"(
let answer = phrase {
  type = <phrase-types:elaborate>
  rewrite = true
  action = fn (state:Context*, called:Phrase*) -> void {
    context:syntax:emit(state, "42")
  }
}
let read_answer = fn () -> i64 { return answer }
assert read_answer() == 42
)"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase answer = root.matchExact(Byte((unsigned char *)"answer"), 0, 6 * Byte::length).getPhrase();
  ASSERT_FALSE(answer.isNull());
  EXPECT_TRUE(answer.isRewritable());
}

TEST_F(RecurloopTesting, PhraseDescriptorSupportsInlineActionsAndStructuralMutationSugar) {
  const char *argv[] = {"Recurloop", "--string", R"(
let mutable-action = phrase {
  type = <phrase-types:callable>
  prototype = none
  successor = none
  action = fn (context:Context*, phrase:Phrase*) -> void {
    context.workspace.bssBytes += 1
  }
}
set mutable-action.prototype = <debug:ping>
set mutable-action.successor = <debug:ping>
mutable-action
set mutable-action.action = <debug:ping>
mutable-action
)"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  EXPECT_EQ(context.workspace.bssBytes, 1u);
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase phrase = root.matchExact(Byte((unsigned char *)"mutable-action"), 0, 14 * Byte::length).getPhrase();
  ASSERT_FALSE(phrase.isNull());
  EXPECT_EQ(phrase.getPrototype().getKey(), "ping");
  EXPECT_EQ(phrase.getSuccessor().getKey(), "ping");
}

TEST_F(RecurloopTesting, PhraseMutationSugarRejectsMissingSlots) {
  const char *argv[] = {"Recurloop", "--string",
                        "let no-slot = phrase { type = <phrase-types:data> }\n"
                        "set no-slot.prototype = <debug:ping>\n"};
  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, PhraseMutationSugarRejectsParentMutation) {
  const char *argv[] = {"Recurloop", "--string",
                        "let child = phrase { prototype = none }\n"
                        "set child.parent = <debug>\n"};
  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, InlinePhraseActionRequiresTheExactActionAbi) {
  const char *argv[] = {"Recurloop", "--string", R"(
let invalid-action = phrase {
  action = fn (context:Context*) -> void { return }
}
)"};
  EXPECT_NE(execute(countof(argv), (char **)argv), 0);
}

TEST_F(RecurloopTesting, ParsesPhysicalRecordsAndTypedExternalSignatures) {
  const char *argv[] = {"Recurloop", "--string",
                        "record Point(tag:u8[3], x:i32, y:i64)\n"
                        "extern draw(point:Point*, scale:f64) -> i32 abi sysv-amd64\n"
                        "extern visit(callback:fn (Point*, ...) -> i32, point:Point*) -> i32\n"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  const compiler::TypeDescriptor &point = context.language().types.get("Point");
  EXPECT_EQ(point.size, 16u);
  EXPECT_EQ(point.fields[1].offset, 4u);
  EXPECT_EQ(point.fields[2].offset, 8u);

  const std::optional<compiler::TypedFunction> draw = context.language().findFunction("draw");
  ASSERT_TRUE(draw);
  ASSERT_EQ(draw->parameterTypes.size(), 2u);
  EXPECT_EQ(context.language().types.get(draw->parameterTypes[0]).pointerDepth, 1u);
  EXPECT_EQ(draw->signature.convention.name, "sysv-amd64");

  const std::optional<compiler::TypedFunction> visit = context.language().findFunction("visit");
  ASSERT_TRUE(visit);
  const compiler::TypeDescriptor callback = context.language().types.get(visit->parameterTypes.front());
  ASSERT_EQ(callback.kind, compiler::TypeKind::Function);
  EXPECT_EQ(callback.parameterTypes, (std::vector<compiler::TypeId>{context.language().types.find("Point*")}));
  EXPECT_EQ(callback.resultType, context.language().types.find("i32"));
  EXPECT_TRUE(callback.variadic);

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase phrase = root.matchExact(Byte((unsigned char *)"draw"), 0, 4 * Byte::length).getPhrase();
  EXPECT_TRUE(phrase.isInvokable());
}

TEST_F(RecurloopTesting, DeclaresCustomCallingConventionsInSource) {
  const char *argv[] = {"Recurloop", "--string",
                        "let downward = <down>\n"
                        "let caller_side = <caller>\n"
                        "abi vector-call(integer(r10,r11), floating(xmm4), result(r11), floating-result(xmm5), "
                        "align(32), shadow(64), stack(downward), cleanup(caller_side))\n"
                        "extern blend(left:u64, right:u64, weight:f64) -> u64 abi vector-call\n"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  const std::optional<compiler::TypedFunction> blend = context.language().findFunction("blend");
  ASSERT_TRUE(blend);
  const compiler::CallingConvention &convention = blend->signature.convention;
  EXPECT_EQ(convention.name, "vector-call");
  EXPECT_EQ(convention.integerRegisters, (std::vector<std::string>{"r10", "r11"}));
  EXPECT_EQ(convention.floatingRegisters, (std::vector<std::string>{"xmm4"}));
  EXPECT_EQ(convention.resultRegister, "r11");
  EXPECT_EQ(convention.floatingResultRegister, "xmm5");
  EXPECT_EQ(convention.stackAlignment, 32u);
  EXPECT_EQ(convention.shadowSpace, 64u);
  EXPECT_TRUE(convention.stackGrowsDown);
  EXPECT_TRUE(convention.callerCleansStack);
}

TEST_F(RecurloopTesting, CreatesTypedPhraseInstancesMethodsAndPointerChains) {
  const char *argv[] = {"Recurloop", "--string",
                        "record Point(x:i32, y:i32)\n"
                        "method Point reset(self:Point*, value:i32) -> void abi sysv-amd64\n"
                        "Point origin\n"
                        "pointer Point** indirect\n"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  lexicon::Phrase root = context.lexicon.phrase();
  const auto child = [](lexicon::Phrase &dictionary, const char *name) {
    return dictionary.matchExact(Byte((unsigned char *)name), 0, std::strlen(name) * Byte::length).getPhrase();
  };
  lexicon::Phrase point = child(root, "Point");
  lexicon::Phrase origin = child(root, "origin");
  lexicon::Phrase indirect = child(root, "indirect");
  ASSERT_FALSE(point.isNull());
  ASSERT_FALSE(origin.isNull());
  ASSERT_FALSE(indirect.isNull());
  EXPECT_EQ(origin.getPrototype().getAddress(), point.getAddress());
  EXPECT_EQ(indirect.getPrototype().getAddress(), point.getAddress());
  EXPECT_FALSE(child(origin, "x").isNull());
  EXPECT_TRUE(child(origin, "reset").isInvokable());
  EXPECT_TRUE(context.language().findFunction("Point:reset"));
  EXPECT_EQ(context.language().types.get("Point**").pointerDepth, 2u);
  EXPECT_EQ(context.language().types.get("Point").methods.size(), 1u);
}

TEST_F(RecurloopTesting, CompletesSelfReferentialRecordsAfterResolvingPointerFields) {
  const char *argv[] = {"Recurloop", "--string", R"(
record Node {
  value:i64
  next:Node*
}
)"};

  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  const compiler::TypeDescriptor node = context.language().types.get("Node");
  ASSERT_EQ(node.fields.size(), 2u);
  EXPECT_EQ(node.size, 16u);
  EXPECT_EQ(node.fields[1].type, context.language().types.find("Node*"));
  EXPECT_EQ(context.language().types.get(node.fields[1].type).element, node.id);
}

int main(int argc, char **argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
