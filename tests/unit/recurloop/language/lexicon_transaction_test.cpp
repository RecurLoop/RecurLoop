#include <gtest/gtest.h>

#include <compiler/LanguageState.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/LexiconTransaction.hpp>
#include <recurloop/Recurloop.hpp>

#include <array>
#include <stdexcept>
#include <utilities/Exception.hpp>

namespace recurloop {
  extern "C" std::uint64_t contextSourceHook(context::Context *context, std::uint64_t hookAddress) noexcept;
}

namespace {
  class LexiconTransactionTesting : public recurloop::Recurloop, public testing::Test {
  protected:
    void SetUp() override {
      char executable[] = "Recurloop";
      char *arguments[] = {executable};
      initialize(1, arguments);
    }

    lexicon::Phrase find(std::string_view name) {
      return recurloop::LanguageGrammar::find(context.lexicon.phrase(), name);
    }
  };
} // namespace

TEST_F(LexiconTransactionTesting, RollsBackLanguageAndCompilerRegistryAtOneWatermark) {
  const Size before = context.lexicon.memoryUsed();
  const std::vector<std::uint8_t> imageBefore = recurloop::EngineImage::encode(context);
  const bool originalEmbedLanguage = context.language().embedsLanguage();
  ASSERT_TRUE(find("stage0_transaction_phrase").isNull());

  {
    recurloop::LexiconTransaction transaction(context.lexicon);
    lexicon::Phrase root = context.lexicon.phrase();
    root.append("stage0_transaction_phrase")
        .make()
        .setType(lexicon::phrase::type::getData(root))
        .save();
    context.language().setEmbedLanguage(!originalEmbedLanguage);

    EXPECT_FALSE(find("stage0_transaction_phrase").isNull());
    EXPECT_EQ(context.language().embedsLanguage(), !originalEmbedLanguage);
    EXPECT_GT(context.lexicon.memoryUsed(), before);
  }

  EXPECT_EQ(context.lexicon.memoryUsed(), before);
  EXPECT_TRUE(find("stage0_transaction_phrase").isNull());
  EXPECT_EQ(context.language().embedsLanguage(), originalEmbedLanguage);
  EXPECT_EQ(recurloop::EngineImage::encode(context), imageBefore);
}

TEST_F(LexiconTransactionTesting, RollsBackOnExceptionByDefault) {
  const Size before = context.lexicon.memoryUsed();

  EXPECT_THROW(
      {
        recurloop::LexiconTransaction transaction(context.lexicon);
        lexicon::Phrase root = context.lexicon.phrase();
        root.append("stage0_exception_phrase")
            .make()
            .setType(lexicon::phrase::type::getData(root))
            .save();
        throw std::runtime_error("transaction test");
      },
      std::runtime_error);

  EXPECT_EQ(context.lexicon.memoryUsed(), before);
  EXPECT_TRUE(find("stage0_exception_phrase").isNull());
}

TEST_F(LexiconTransactionTesting, CommitKeepsTheWholeTransaction) {
  {
    recurloop::LexiconTransaction transaction(context.lexicon);
    lexicon::Phrase root = context.lexicon.phrase();
    root.append("stage0_committed_phrase")
        .make()
        .setType(lexicon::phrase::type::getData(root))
        .save();
    transaction.commit();
  }

  EXPECT_FALSE(find("stage0_committed_phrase").isNull());
}


TEST_F(LexiconTransactionTesting, ExistingLanguageBindingIsIdempotentAndCannotBeReboundInPlace) {
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase phrase = root.append("stage1_language_binding")
                               .make()
                               .setType(lexicon::phrase::type::getData(root))
                               .save();
  compiler::LanguageState::bind(phrase);

  const Size afterFirstBind = context.lexicon.memoryUsed();
  const std::vector<std::uint8_t> imageAfterFirstBind = recurloop::EngineImage::encode(context);
  compiler::LanguageState::bind(phrase);
  EXPECT_EQ(context.lexicon.memoryUsed(), afterFirstBind);
  EXPECT_EQ(recurloop::EngineImage::encode(context), imageAfterFirstBind);

  lexicon::Phrase forged = root.append("stage1_foreign_language_binding")
                                .make()
                                .setType(lexicon::phrase::type::getData(root))
                                .save();
  const compiler::LanguageBinding actual = compiler::LanguageState::binding(context.lexicon);
  const Size foreignAddress = actual.language == root.getAddress() ? root.getAddress() + 1 : root.getAddress();
  forged.store(compiler::LanguageBinding{compiler::LanguageBinding::Magic, foreignAddress}).save();

  EXPECT_THROW(compiler::LanguageState::bind(forged), Exception);
  compiler::LanguageBinding stillForeign;
  forged.fetch(forged.payloadSize() - sizeof(stillForeign), stillForeign);
  EXPECT_EQ(stillForeign.language, foreignAddress);
}


TEST_F(LexiconTransactionTesting, SourceHookShadowingRollsBackToThePreviousHook) {
  lexicon::Phrase first = find("let");
  lexicon::Phrase second = find("var");
  ASSERT_FALSE(first.isNull());
  ASSERT_FALSE(second.isNull());
  ASSERT_TRUE(first.isElaboratable());
  ASSERT_TRUE(second.isElaboratable());

  ASSERT_EQ(recurloop::contextSourceHook(&context, first.getAddress()), first.getAddress());
  const std::vector<std::uint8_t> imageBefore = recurloop::EngineImage::encode(context);

  {
    recurloop::LexiconTransaction transaction(context.lexicon);
    ASSERT_EQ(recurloop::contextSourceHook(&context, second.getAddress()), second.getAddress());
    EXPECT_NE(recurloop::EngineImage::encode(context), imageBefore);
  }

  EXPECT_EQ(recurloop::EngineImage::encode(context), imageBefore);
}

TEST_F(LexiconTransactionTesting, NestedTransactionsRestoreTheExactParentSemanticImage) {
  const std::vector<std::uint8_t> imageBefore = recurloop::EngineImage::encode(context);
  const bool originalEmbedLanguage = context.language().embedsLanguage();

  {
    recurloop::LexiconTransaction outer(context.lexicon);
    lexicon::Phrase root = context.lexicon.phrase();
    root.append("stage2_outer_phrase")
        .make()
        .setType(lexicon::phrase::type::getData(root))
        .save();
    const std::vector<std::uint8_t> outerImage = recurloop::EngineImage::encode(context);

    {
      recurloop::LexiconTransaction inner(context.lexicon);
      root.append("stage2_inner_phrase")
          .make()
          .setType(lexicon::phrase::type::getData(root))
          .save();
      context.language().setEmbedLanguage(!originalEmbedLanguage);
      EXPECT_FALSE(find("stage2_inner_phrase").isNull());
      EXPECT_NE(recurloop::EngineImage::encode(context), outerImage);
    }

    EXPECT_TRUE(find("stage2_inner_phrase").isNull());
    EXPECT_FALSE(find("stage2_outer_phrase").isNull());
    EXPECT_EQ(context.language().embedsLanguage(), originalEmbedLanguage);
    EXPECT_EQ(recurloop::EngineImage::encode(context), outerImage);
  }

  EXPECT_TRUE(find("stage2_outer_phrase").isNull());
  EXPECT_EQ(recurloop::EngineImage::encode(context), imageBefore);
}

TEST_F(LexiconTransactionTesting, StoredWatermarkCanBeRestoredAcrossParserCallbacks) {
  const std::vector<std::uint8_t> imageBefore = recurloop::EngineImage::encode(context);
  const Size watermark = recurloop::LexiconTransaction::capture(context.lexicon);

  lexicon::Phrase root = context.lexicon.phrase();
  root.append("stage2_callback_phrase")
      .make()
      .setType(lexicon::phrase::type::getData(root))
      .save();
  ASSERT_FALSE(find("stage2_callback_phrase").isNull());
  ASSERT_NE(recurloop::EngineImage::encode(context), imageBefore);

  recurloop::LexiconTransaction::restore(context.lexicon, watermark);

  EXPECT_TRUE(find("stage2_callback_phrase").isNull());
  EXPECT_EQ(recurloop::EngineImage::encode(context), imageBefore);
}

TEST_F(LexiconTransactionTesting, SelectivePromotionKeepsOnlyChosenSemanticGraph) {
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase data = lexicon::phrase::type::getData(root);
  lexicon::Phrase schema = root.append("stage3_promotion_schema").make().setType(data).save();
  recurloop::EngineImage::declarePayloadField(context, schema, 0,
                                               recurloop::EngineImage::PayloadFieldKind::PhraseReference);
  const std::vector<std::uint8_t> parentImage = recurloop::EngineImage::encode(context);

  recurloop::LexiconTransaction transaction(context.lexicon);
  root.append("stage3_discarded").make().setType(data).save();
  lexicon::Phrase promoted = root.append("stage3_promoted")
                                  .make()
                                  .enableSubdictionary()
                                  .setPrototype(schema)
                                  .setType(data)
                                  .save();
  promoted.store(Size{0}).save();
  lexicon::Phrase child = promoted.append("child").make().setType(data).save();
  promoted.update(0, child.getAddress()).save();

  const std::array<lexicon::Phrase, 1> selected{promoted};
  transaction.promote(context, selected);

  EXPECT_FALSE(transaction.isActive());
  EXPECT_TRUE(find("stage3_discarded").isNull());
  lexicon::Phrase restored = find("stage3_promoted");
  ASSERT_FALSE(restored.isNull());
  lexicon::Match restoredChild = restored.matchExact(Byte(const_cast<char *>("child")), 0, 5 * Byte::length);
  ASSERT_FALSE(restoredChild.isNull());
  Size reference = 0;
  restored.fetch(0, reference);
  EXPECT_EQ(reference, restoredChild.getPhrase().getAddress());
  EXPECT_NE(recurloop::EngineImage::encode(context), parentImage);
}

TEST_F(LexiconTransactionTesting, PromotionRejectsDependencyOnUnselectedTransactionState) {
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase data = lexicon::phrase::type::getData(root);
  recurloop::LexiconTransaction transaction(context.lexicon);
  lexicon::Phrase dependency = root.append("stage3_unselected_dependency").make().setType(data).save();
  lexicon::Phrase promoted = root.append("stage3_invalid_promotion")
                                  .make()
                                  .setPrototype(dependency)
                                  .setType(data)
                                  .save();
  const std::array<lexicon::Phrase, 1> selected{promoted};
  EXPECT_THROW(transaction.promote(context, selected), Exception);
  transaction.rollback();
  EXPECT_TRUE(find("stage3_unselected_dependency").isNull());
  EXPECT_TRUE(find("stage3_invalid_promotion").isNull());
}
