#include <algorithm>
#define RADIX_REVERSE false
#include <radix/Radix.hpp>
#undef RADIX_REVERSE

#include <gtest/gtest.h>

#include <cstring>
#include <random>
#include <string>
#include <iomanip>
#include <cmath>
#include <stdlib.h>
#include <stdbool.h>

class RadixTest : public radix::Radix {
  public:
    using radix::Radix::Radix;

    radix::Node insertKey(radix::Node node, const char *key) {
      return node.append(Byte((void *)key), 0, strlen(key) * Byte::length);
    }

    radix::Item insertValue(radix::Node node, const char *value) {
        Size valueSize = strlen(value);

        // Radix Check
        if (memoryUnused() < valueSize + sizeof(Size)) return radix::Item(this);

        // Item create
        radix::Item newItem = node.push();
        if (newItem.isNull()) return radix::Item(this);

        // Allocate
        Size *itemSize = (Size *)allocate(sizeof(Size)).toPtr();
        if (!itemSize) return radix::Item(this);

        Byte itemContent = allocate(valueSize);
        if (itemContent.isNull()) return radix::Item(this);

        // Override
        *itemSize = valueSize;
        Byte::copy(Byte((void *)value), itemContent, valueSize);

        return newItem;
    }

    radix::Item insert(radix::Node node, const char *key, const char *value) {
        auto newNode = insertKey(node, key);

        if (newNode.isNull()) return radix::Item(this);

        return insertValue(newNode, value);
    }

    std::string getKey(radix::Node node) {
        Size keyBits = node.keyBits();
        Size keySize = Bit::bytes(keyBits);

        Byte keyCopy = Byte(malloc(keySize + 1));
        node.keyCopy(Bit(keyCopy, 0), keyBits);
        keyCopy.toPtr()[keySize] = '\0';

        std::string keyCopyString((const char *)keyCopy.toPtr());

        free(keyCopy.toPtr());

        return keyCopyString;
    }

    std::string getValue(radix::Item item) {
        Size *size = (Size *)item.content(0, sizeof(Size)).toPtr();
        Byte memory = item.content(sizeof(Size), *size);

        return std::string((const char *)memory.toPtr(), *size);
    }

    std::string getValueHex(radix::Node node) {
        Size *size = (Size *)node.item().content(0, sizeof(Size)).toPtr();
        Byte memory = node.item().content(sizeof(Size), *size);

        std::stringstream hexStream;
        for (std::size_t i = 0; i < *size; i++)
            hexStream << std::hex << std::setw(2) << std::setfill('0')
                      << static_cast<int>(static_cast<unsigned char>(memory.toPtr()[i]));

        return hexStream.str();
    }
};

class RadixTesting : public testing::Test {
  protected:
    struct Config {
        Byte memory = (void *)nullptr;
        Size size = 1024 * 20;
    } config;

    struct Stats {
        struct MemoryUsage {
            Size size;
            Size used;
            Size unused;
        } memoryUsage;

        Size itemCounter;
    } stats;

    RadixTest radix;
    radix::Node head;

    static constexpr radix::match::Filter matchFilter = [](radix::Node *node, radix::Match *candidate) -> bool {
        return !candidate->isEmpty() && node->getAddress() != candidate->getAddress();
    };

    static constexpr radix::node::Filter nodeFilter =
        [](radix::Node *node, radix::Node *candidate) -> bool { return !candidate->isEmpty(); };

    static constexpr radix::item::Filter itemFilter =
        [](radix::Item *node, radix::Item *candidate) -> bool { return !candidate->isNull(); };

    /// Magic functions
    void SetUp() override {
        config.memory = Byte(malloc(config.size));
        ASSERT_NE(config.memory, (void *)nullptr);

        radix = RadixTest(config.memory, config.size);

        ASSERT_EQ(radix.memoryFore(), config.memory);
        ASSERT_EQ(radix.memorySize(), config.size);

        ASSERT_EQ(radix.clear(), true);
        stats.itemCounter = 0;

        ASSERT_EQ(radix.memoryFore(), config.memory);
        ASSERT_EQ(radix.memorySize(), config.size);

        head = radix.node();

        ASSERT_EQ(head.isNull(), false);
        ASSERT_EQ(head.isEmpty(), true);

        stats.memoryUsage.size = radix.memorySize();
        stats.memoryUsage.used = radix.memoryUsed();
        stats.memoryUsage.unused = radix.memoryUnused();
    }

    void TearDown() override {
        free(config.memory.toPtr());
    }

    /// Helper
    void expectKey(radix::Node node, const char *key) {
        ASSERT_FALSE(node.isNull());
        ASSERT_NE(key, nullptr);

        std::string keyString(key);

        EXPECT_EQ(keyString, radix.getKey(node));
    }

    void expectKey(radix::Item item, const char *key) {
        ASSERT_FALSE(item.isNull());
        expectKey(item.getNode(), key);
    }

    void expectValue(radix::Node node, const char *value) {
        ASSERT_FALSE(node.isNull());
        expectValue(node.item(), value);
    }

    void expectValue(radix::Item item, const char *value) {
        ASSERT_FALSE(item.isNull());
        ASSERT_NE(value, nullptr);

        std::string valueString(value);

        EXPECT_EQ(valueString, radix.getValue(item));
    }

    void expectNode(radix::Node node, const char *key, const char *value) {
        expectKey(node, key);
        expectValue(node, value);
    }

    void expectItem(radix::Item item, const char *key, const char *value) {
        expectKey(item, key);
        expectValue(item, value);
    }
};

TEST_F(RadixTesting, InitContext) {
    EXPECT_EQ(stats.memoryUsage.size, config.size);
    ASSERT_LE(stats.memoryUsage.used, config.size);
    ASSERT_LE(stats.memoryUsage.unused, config.size);
    EXPECT_EQ(stats.memoryUsage.used + stats.memoryUsage.unused, config.size);

    EXPECT_EQ(head.isNull(), false);
    EXPECT_EQ(head.isEmpty(), true);
}

TEST_F(RadixTesting, Insert) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
      ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    auto checkData(data);
    std::ranges::shuffle(checkData, std::mt19937(4));
    for (radix::Node node = radix.lastNode(nodeFilter); !node.isNull(); node = node.earlier(nodeFilter)) {
        std::string key = radix.getKey(node);

        auto search = [key](auto &elem) { return std::string(elem.first) == key; };

        auto dataElement = std::find_if(checkData.begin(), checkData.end(), search);

        if (dataElement != checkData.end()) {
            expectNode(node, dataElement->first, dataElement->second);
            checkData.erase(dataElement);
        }
    }

    EXPECT_EQ(checkData.size(), 0);
}

TEST_F(RadixTesting, ZeroAllocation) {
  std::string key = "append";
  radix::Node node = radix.insertKey(head, key.c_str());
  ASSERT_EQ(node.content(0, 0), node.allocate(0));
}

TEST_F(RadixTesting, InsertNested) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::string nestedKey = "nested-";
    radix::Node node = radix.insertKey(head, nestedKey.c_str());
    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data) {
        ASSERT_FALSE(radix.insert(node, key, value).isNull());
    }

    // Check
    auto checkData(data);
    std::ranges::shuffle(checkData, std::mt19937(4));
    for (radix::Node node = radix.lastNode(nodeFilter); !node.isNull(); node = node.earlier(nodeFilter)) {
        std::string key = radix.getKey(node);

        auto search = [key, nestedKey](auto &elem) { return nestedKey + std::string(elem.first) == key; };

        auto dataElement = std::find_if(checkData.begin(), checkData.end(), search);

        if (dataElement != checkData.end()) {

            expectNode(node, (nestedKey + dataElement->first).c_str(), dataElement->second);
            checkData.erase(dataElement);
        }
    }

    EXPECT_EQ(checkData.size(), 0);
}

TEST_F(RadixTesting, ForeAndNext) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.fore(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "a", "content-a");

    node = node.next(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "aa", "content-aa");

    node = node.next(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ab", "content-ab");

    node = node.next(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "b", "content-b");

    node = node.next(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ba", "content-ba");

    node = node.next(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "bb", "content-bb");

    node = node.next(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, ForeAndPrevReturnsNull) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.fore(nodeFilter);
    ASSERT_FALSE(node.isNull());

    node = node.prev(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, RearAndPrev) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.rear(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "bb", "content-bb");

    node = node.prev(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ba", "content-ba");

    node = node.prev(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "b", "content-b");

    node = node.prev(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ab", "content-ab");

    node = node.prev(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "aa", "content-aa");

    node = node.prev(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "a", "content-a");

    node = node.prev(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, RearAndNextReturnsNull) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.rear(nodeFilter);
    ASSERT_FALSE(node.isNull());

    node = node.next(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, ForeAndNextInverse) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.foreInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "aa", "content-aa");

    node = node.nextInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ab", "content-ab");

    node = node.nextInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "a", "content-a");

    node = node.nextInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ba", "content-ba");

    node = node.nextInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "bb", "content-bb");

    node = node.nextInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "b", "content-b");

    node = node.nextInverse(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, ForeAndPrevInverseReturnsNull) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.foreInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());

    node = node.prevInverse(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, RearAndPrevInverse) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.rearInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "b", "content-b");

    node = node.prevInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "bb", "content-bb");

    node = node.prevInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ba", "content-ba");

    node = node.prevInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "a", "content-a");

    node = node.prevInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "ab", "content-ab");

    node = node.prevInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());
    expectNode(node, "aa", "content-aa");

    node = node.prevInverse(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, RearAndNextInverseReturnsNull) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"ab", "content-ab"},
        {"b", "content-b"}, {"ba", "content-ba"}, {"bb", "content-bb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = head.rearInverse(nodeFilter);
    ASSERT_FALSE(node.isNull());

    node = node.nextInverse(nodeFilter);
    ASSERT_TRUE(node.isNull());
}

TEST_F(RadixTesting, Predecessor) {
    // Insert
    radix::Node cursorA = radix.insert(head, "a", "content-a").getNode();
    ASSERT_FALSE(cursorA.isEmpty());
    radix::Node cursorAA = radix.insert(head, "aa", "content-aa").getNode();
    ASSERT_FALSE(cursorA.isEmpty());
    radix::Node cursorB = radix.insert(head, "b", "content-b").getNode();
    ASSERT_FALSE(cursorA.isEmpty());
    radix::Node cursorBA = radix.insert(head, "ba", "content-ba").getNode();
    ASSERT_FALSE(cursorA.isEmpty());

    // Check
    radix::Node predecessorA = cursorA.predecessor(nodeFilter);
    ASSERT_TRUE(predecessorA.isNull());

    radix::Node predecessorAA = cursorAA.predecessor(nodeFilter);
    ASSERT_FALSE(predecessorAA.isNull());
    expectNode(predecessorAA, "a", "content-a");

    radix::Node predecessorB = cursorB.predecessor(nodeFilter);
    ASSERT_TRUE(predecessorB.isNull());

    radix::Node predecessorBA = cursorBA.predecessor(nodeFilter);
    ASSERT_FALSE(predecessorBA.isNull());
    expectNode(predecessorBA, "b", "content-b");
}

TEST_F(RadixTesting, MatchFirst) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchFirst(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = head.matchFirst(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), strlen("a") * Byte::length);
    expectNode(matchAA.node(), "a", "content-a");

    radix::Match matchAAA = head.matchFirst(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("a") * Byte::length);
    expectNode(matchAAA.node(), "a", "content-a");

    radix::Match matchAAAA = head.matchFirst(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAA.getBits(), strlen("a") * Byte::length);
    expectNode(matchAAAA.node(), "a", "content-a");

    radix::Match matchAAAAA = head.matchFirst(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("a") * Byte::length);
    expectNode(matchAAAAA.node(), "a", "content-a");

    radix::Match matchC = head.matchFirst(Byte((void *)"c"), 0, strlen("c") * Byte::length, matchFilter);
    EXPECT_EQ(matchC.getBits(), 0);
    EXPECT_TRUE(matchC.isNull());
}

TEST_F(RadixTesting, MatchFirstNested) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchFirst(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = matchA.matchFirst(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());

    radix::Match matchAAA = matchA.matchFirst(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAA = matchA.matchFirst(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAAA = matchA.matchFirst(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAAAA = matchA.matchFirst(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAAAAA.node(), "aaa", "content-aaa");
}

TEST_F(RadixTesting, MatchLongest) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchLongest(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = head.matchLongest(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), strlen("a") * Byte::length);
    expectNode(matchAA.node(), "a", "content-a");

    radix::Match matchAAA = head.matchLongest(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("aaa") * Byte::length);
    expectNode(matchAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAA = head.matchLongest(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAA.getBits(), strlen("aaa") * Byte::length);
    expectNode(matchAAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAAA = head.matchLongest(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("aaaaa") * Byte::length);
    expectNode(matchAAAAA.node(), "aaaaa", "content-aaaaa");

    radix::Match matchB = head.matchLongest(Byte((void *)"c"), 0, strlen("c") * Byte::length, matchFilter);
    EXPECT_EQ(matchB.getBits(), 0);
    EXPECT_TRUE(matchB.isNull());
}

TEST_F(RadixTesting, MatchLongestNested) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchLongest(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = matchA.matchLongest(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());

    radix::Match matchAAA = matchA.matchLongest(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAA = matchA.matchLongest(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAAA = matchA.matchLongest(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("aaaa") * Byte::length);
    expectNode(matchAAAAA.node(), "aaaaa", "content-aaaaa");

    radix::Match matchAAAAAA =
        matchA.matchLongest(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAAA.getBits(), strlen("aaaa") * Byte::length);
    expectNode(matchAAAAAA.node(), "aaaaa", "content-aaaaa");
}

TEST_F(RadixTesting, MatchExact) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchExact(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = head.matchExact(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());

    radix::Match matchAAA = head.matchExact(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("aaa") * Byte::length);
    expectNode(matchAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAA = head.matchExact(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAA.getBits(), 0);
    EXPECT_TRUE(matchAAAA.isNull());

    radix::Match matchAAAAA = head.matchExact(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("aaaaa") * Byte::length);
    expectNode(matchAAAAA.node(), "aaaaa", "content-aaaaa");

    radix::Match matchB = head.matchExact(Byte((void *)"c"), 0, strlen("c") * Byte::length, matchFilter);
    EXPECT_EQ(matchB.getBits(), 0);
    EXPECT_TRUE(matchB.isNull());
}

TEST_F(RadixTesting, MatchExactNested) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"}, {"aaa", "content-aaa"}, {"aaaaa", "content-aaaaa"},
        {"b", "content-b"}, {"bbb", "content-bbb"}, {"bbbbb", "content-bbbbb"},
    };

    std::ranges::shuffle(data, std::mt19937(0));
    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Match matchA = head.matchExact(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchA.getBits(), strlen("a") * Byte::length);
    expectNode(matchA.node(), "a", "content-a");

    radix::Match matchAA = matchA.matchExact(Byte((void *)"a"), 0, strlen("a") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());

    radix::Match matchAAA = matchA.matchExact(Byte((void *)"aa"), 0, strlen("aa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAA.getBits(), strlen("aa") * Byte::length);
    expectNode(matchAAA.node(), "aaa", "content-aaa");

    radix::Match matchAAAA = matchA.matchExact(Byte((void *)"aaa"), 0, strlen("aaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());

    radix::Match matchAAAAA = matchA.matchExact(Byte((void *)"aaaa"), 0, strlen("aaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAAAAA.getBits(), strlen("aaaa") * Byte::length);
    expectNode(matchAAAAA.node(), "aaaaa", "content-aaaaa");

    radix::Match matchAAAAAA = matchA.matchExact(Byte((void *)"aaaaa"), 0, strlen("aaaaa") * Byte::length, matchFilter);
    EXPECT_EQ(matchAA.getBits(), 0);
    EXPECT_TRUE(matchAA.isNull());
}

TEST_F(RadixTesting, Checkpoint) {
    // Insert
    radix::Checkpoint checkpointBegin = radix.checkpoint();

    std::vector<std::pair<const char *, const char *>> dataBegin = {
        {"a", "content-a"},
        {"aa", "content-aa"},
        {"c", "content-c-1"},
    };

    std::ranges::shuffle(dataBegin, std::mt19937(0));
    for (const auto &[key, value] : dataBegin) {
        ASSERT_FALSE(radix.insert(head, key, value).isNull());
    }

    radix::Checkpoint checkpointMiddle = radix.checkpoint();

    std::vector<std::pair<const char *, const char *>> dataMiddle = {
        {"b", "content-b"},
        {"bb", "content-bb"},
        {"c", "content-c-2"},
    };

    std::ranges::shuffle(dataMiddle, std::mt19937(0));
    for (const auto &[key, value] : dataMiddle) {
        ASSERT_FALSE(radix.insert(head, key, value).isNull());
    }

    radix::Checkpoint checkpointEnd = radix.checkpoint();

    // Check
    checkpointEnd.restore();

    std::vector<std::pair<const char *, const char *>> checkDataEnd = {
        {"a", "content-a"}, {"aa", "content-aa"}, {"b", "content-b"}, {"bb", "content-bb"}, {"c", "content-c-2"},
    };

    std::ranges::shuffle(checkDataEnd, std::mt19937(4));
    for (radix::Node node = radix.lastNode(nodeFilter); !node.isNull(); node = node.earlier(nodeFilter)) {
        std::string key = radix.getKey(node);

        auto search = [key](auto &elem) { return std::string(elem.first) == key; };

        auto dataElement = std::find_if(checkDataEnd.begin(), checkDataEnd.end(), search);

        if (dataElement != checkDataEnd.end()) {
            expectNode(node, dataElement->first, dataElement->second);
            checkDataEnd.erase(dataElement);
        }
    }

    EXPECT_EQ(checkDataEnd.size(), 0);

    checkpointMiddle.restore();

    std::vector<std::pair<const char *, const char *>> checkDataMiddle = {
        {"a", "content-a"},
        {"aa", "content-aa"},
        {"c", "content-c-1"},
    };

    std::ranges::shuffle(checkDataMiddle, std::mt19937(4));
    for (radix::Node node = radix.lastNode(nodeFilter); !node.isNull(); node = node.earlier(nodeFilter)) {
        std::string key = radix.getKey(node);

        auto search = [key](auto &elem) { return std::string(elem.first) == key; };

        auto dataElement = std::find_if(checkDataMiddle.begin(), checkDataMiddle.end(), search);

        if (dataElement != checkDataMiddle.end()) {
            expectNode(node, dataElement->first, dataElement->second);
            checkDataMiddle.erase(dataElement);
        }
    }

    EXPECT_EQ(checkDataMiddle.size(), 0);

    checkpointBegin.restore();
    EXPECT_TRUE(radix.lastNode(nodeFilter).isNull());
    EXPECT_TRUE(head.fore(nodeFilter).isNull());
    EXPECT_TRUE(head.rear(nodeFilter).isNull());
    EXPECT_TRUE(head.foreInverse(nodeFilter).isNull());
    EXPECT_TRUE(head.rearInverse(nodeFilter).isNull());
}

TEST_F(RadixTesting, NodeEarlier) {
    // Insert
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a"},   {"b", "content-b-1"}, {"b", "content-b-2"},
        {"c", "content-c-1"}, {"d", "content-d"},   {"c", "content-c-2"},
    };

    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node node = radix.lastNode(nodeFilter);
    expectNode(node, "d", "content-d");

    node = node.earlier(nodeFilter);
    expectNode(node, "c", "content-c-2");

    node = node.earlier(nodeFilter);
    expectNode(node, "b", "content-b-2");

    node = node.earlier(nodeFilter);
    expectNode(node, "a", "content-a");

    node = node.earlier(nodeFilter);
    EXPECT_TRUE(node.isNull());
}

TEST_F(RadixTesting, ItemPrev) {
    // Insert
    // clang-format off
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a-1"},
        {"c", "content-c-1"},
        {"a", "content-a-2"},
        {"a", "content-a-3"},
        {"b", "content-b-1"},
        {"b", "content-b-2"},
    };
    // clang-format on

    for (const auto &[key, value] : data)
        ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Node nodeA = head.fore(nodeFilter);
    expectNode(nodeA, "a", "content-a-3");

    radix::Item itemA = nodeA.item();
    expectItem(itemA, "a", "content-a-3");
    itemA = itemA.prev();
    expectItem(itemA, "a", "content-a-2");
    itemA = itemA.prev();
    expectItem(itemA, "a", "content-a-1");
    itemA = itemA.prev();
    EXPECT_TRUE(itemA.isNull());

    radix::Node nodeB = nodeA.next(nodeFilter);
    expectNode(nodeB, "b", "content-b-2");

    radix::Item itemB = nodeB.item();
    expectItem(itemB, "b", "content-b-2");
    itemB = itemB.prev();
    expectItem(itemB, "b", "content-b-1");
    itemB = itemB.prev();
    EXPECT_TRUE(itemB.isNull());

    radix::Node nodeC = nodeB.next(nodeFilter);
    expectNode(nodeC, "c", "content-c-1");

    radix::Item itemC = nodeC.item();
    expectItem(itemC, "c", "content-c-1");
    itemC = itemC.prev();
    EXPECT_TRUE(itemC.isNull());
}

TEST_F(RadixTesting, ItemEarlier) {
    // Insert
    // clang-format off
    std::vector<std::pair<const char *, const char *>> data = {
        {"a", "content-a-1"},
        {"c", "content-c-1"},
        {"a", "content-a-2"},
        {"a", "content-a-3"},
        {"b", "content-b-1"},
        {"b", "content-b-2"},
    };
    // clang-format on

    for (const auto &[key, value] : data)
    ASSERT_FALSE(radix.insert(head, key, value).isNull());

    // Check
    radix::Item item = radix.lastItem(itemFilter);
    expectItem(item, "b", "content-b-2");

    item = item.earlier(itemFilter);
    expectItem(item, "b", "content-b-1");

    item = item.earlier(itemFilter);
    expectItem(item, "a", "content-a-3");

    item = item.earlier(itemFilter);
    expectItem(item, "a", "content-a-2");

    item = item.earlier(itemFilter);
    expectItem(item, "c", "content-c-1");

    item = item.earlier(itemFilter);
    expectItem(item, "a", "content-a-1");

    item = item.earlier(itemFilter);
    EXPECT_TRUE(item.isNull());
}

int main(int argc, char **argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
