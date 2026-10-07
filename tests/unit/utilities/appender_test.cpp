#include <utilities/Appender.hpp>
#include <utilities/Exception.hpp>
#include <gtest/gtest.h>
#include <limits>

TEST(AppenderTesting, PreservesPartialBytesAcrossAppendCopyAndTruncate) {
  unsigned char memory[8]{}, copied[8]{};
  unsigned char source[] = {0xff, 0xff};
  Appender value(Byte(memory), sizeof(memory));
  value.append(Bit(Byte(source)), 3);
  EXPECT_EQ(value.bits(), 3u);
  EXPECT_EQ(memory[0], 0xe0);
  EXPECT_EQ(memory[1], 0);
  Appender copy(Byte(copied), sizeof(copied));
  copy.append(value);
  EXPECT_EQ(value, copy);
  copy.append(Bit(Byte(source)), 5);
  EXPECT_EQ(copy.bits(), 8u);
  EXPECT_EQ(copied[0], 0xff);
  EXPECT_EQ(copied[1], 0);
  EXPECT_NE(value, copy);
  value.append(Byte(source), 1);
  EXPECT_EQ(memory[0], 0xff);
  EXPECT_EQ(memory[1], 0xe0);
  value.truncate(3);
  EXPECT_EQ(memory[0], 0xe0);
  EXPECT_EQ(memory[1], 0);
}

TEST(AppenderTesting, ComparesBinaryContentsAndBitLengths) {
  unsigned char leftMemory[4]{}, rightMemory[4]{};
  unsigned char leftBytes[] = {0, 1}, rightBytes[] = {0, 2};
  Appender left(Byte(leftMemory), sizeof(leftMemory)), right(Byte(rightMemory), sizeof(rightMemory));
  left.append(Byte(leftBytes), 2);
  right.append(Byte(rightBytes), 2);
  EXPECT_NE(left, right);
  left.clear();
  right.clear();
  left.append(Bit(Byte(leftBytes)), 1);
  EXPECT_NE(left, right);
}

TEST(AppenderTesting, RejectsOversizedAppendsWithoutChangingTheBuffer) {
  unsigned char memory[2]{}, source[] = {0xff};
  Appender value(Byte(memory), sizeof(memory));
  value.append(Byte(source), 1);
  EXPECT_THROW(value.append(Byte(source), 1), Exception);
  EXPECT_THROW(value.append(Byte(source), std::numeric_limits<Size>::max()), Exception);
  EXPECT_THROW(value.append(Bit(Byte(source)), std::numeric_limits<Size>::max()), Exception);
  EXPECT_EQ(value.bits(), 8u);
  EXPECT_EQ(memory[0], 0xff);
  EXPECT_EQ(memory[1], 0);
}
