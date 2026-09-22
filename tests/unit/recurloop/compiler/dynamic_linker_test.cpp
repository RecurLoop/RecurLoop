#include <gtest/gtest.h>

#include <compiler/DynamicLinker.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>

#include <sys/wait.h>
#include <unistd.h>

namespace {
  class DynamicLinkerTesting : public testing::Test {
  protected:
    void SetUp() override {
      compiler::DynamicLinker::instance().clear();
      root = std::filesystem::temp_directory_path() /
             ("recurloop-dynamic-linker-" + std::to_string(getpid()) + "-" +
              std::to_string(testing::UnitTest::GetInstance()->current_test_info()->line()));
      std::filesystem::remove_all(root);
      std::filesystem::create_directories(root);
    }

    void TearDown() override {
      compiler::DynamicLinker::instance().clear();
      std::filesystem::remove_all(root);
    }

    std::filesystem::path buildShared(const std::filesystem::path &directory, std::string_view filename,
                                      std::string_view body) {
      std::filesystem::create_directories(directory);
      const std::filesystem::path source = directory / "library.c";
      const std::filesystem::path output = directory / filename;
      {
        std::ofstream stream(source);
        stream << body;
      }

      const pid_t process = fork();
      EXPECT_NE(process, -1);
      if (process == 0) {
        execlp("cc", "cc", "-shared", "-fPIC", source.c_str(), "-o", output.c_str(),
               static_cast<char *>(nullptr));
        _exit(127);
      }
      int status = 0;
      EXPECT_EQ(waitpid(process, &status, 0), process);
      EXPECT_TRUE(WIFEXITED(status));
      EXPECT_EQ(WEXITSTATUS(status), 0);
      return output;
    }

    std::filesystem::path root;
  };

  TEST_F(DynamicLinkerTesting, LoadsVersionedSharedLibraryWithoutDevelopmentSymlink) {
    buildShared(root, "librecurloop-versioned.so.7", "long recurloop_versioned_value(void) { return 47; }\n");

    const auto address = compiler::DynamicLinker::instance().resolve(
        "recurloop_versioned_value", {"recurloop-versioned"}, {root.string()});

    ASSERT_TRUE(address.has_value());
    EXPECT_EQ(reinterpret_cast<long (*)()>(*address)(), 47);
  }

  TEST_F(DynamicLinkerTesting, FindsVersionedSharedLibraryFromRuntimeLibraryPath) {
    buildShared(root, "librecurloop-runtime-only.so.3", "long recurloop_runtime_value(void) { return 63; }\n");

    const char *previous = std::getenv("LD_LIBRARY_PATH");
    const std::string saved = previous == nullptr ? std::string() : std::string(previous);
    ASSERT_EQ(setenv("LD_LIBRARY_PATH", root.c_str(), 1), 0);

    const auto address =
        compiler::DynamicLinker::instance().resolve("recurloop_runtime_value", {"recurloop-runtime-only"}, {});

    if (previous == nullptr)
      unsetenv("LD_LIBRARY_PATH");
    else
      setenv("LD_LIBRARY_PATH", saved.c_str(), 1);

    ASSERT_TRUE(address.has_value());
    EXPECT_EQ(reinterpret_cast<long (*)()>(*address)(), 63);
  }


  TEST_F(DynamicLinkerTesting, ExposesVersionedRuntimePathForNativeLinking) {
    const std::filesystem::path library =
        buildShared(root, "librecurloop-native-runtime.so.9", "long recurloop_native_runtime(void) { return 91; }\n");

    const auto path = compiler::DynamicLinker::libraryPath("recurloop-native-runtime", {root.string()});

    ASSERT_TRUE(path.has_value());
    EXPECT_EQ(std::filesystem::path(*path), library);
  }

  TEST_F(DynamicLinkerTesting, ScopesHandlesAndSymbolsBySearchPath) {
    const std::filesystem::path first = root / "first";
    const std::filesystem::path second = root / "second";
    buildShared(first, "librecurloop-scope.so", "long recurloop_scope_value(void) { return 11; }\n");
    buildShared(second, "librecurloop-scope.so", "long recurloop_scope_value(void) { return 22; }\n");

    const std::string decorated = "recurloop_scope_value-not-part-of-the-symbol";
    const std::string_view symbol(decorated.data(), std::string_view("recurloop_scope_value").size());
    const auto firstAddress =
        compiler::DynamicLinker::instance().resolve(symbol, {"recurloop-scope"}, {first.string()});
    ASSERT_TRUE(firstAddress.has_value());
    EXPECT_EQ(reinterpret_cast<long (*)()>(*firstAddress)(), 11);

    const auto secondAddress = compiler::DynamicLinker::instance().resolve(
        "recurloop_scope_value", {"recurloop-scope"}, {second.string()});
    ASSERT_TRUE(secondAddress.has_value());
    EXPECT_EQ(reinterpret_cast<long (*)()>(*secondAddress)(), 22);
  }
} // namespace
