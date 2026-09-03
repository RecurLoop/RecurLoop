#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  enum class ValueKind : std::uint8_t { Void, Integer, FloatingPoint, Pointer, Aggregate };

  struct ValueType {
    std::string name;
    ValueKind kind = ValueKind::Void;
    std::uint16_t bits = 0;
    std::uint16_t pointerDepth = 0;

    static ValueType voidType();
    static ValueType integer(std::string name, std::uint16_t bits);
    static ValueType floating(std::string name, std::uint16_t bits);
    static ValueType pointer(std::string pointee, std::uint16_t depth = 1, std::uint16_t bits = 64);

    bool operator==(const ValueType &) const = default;
  };

  struct CallingConvention {
    std::string name;
    std::vector<std::string> integerRegisters;
    std::vector<std::string> floatingRegisters;
    std::string resultRegister = "rax";
    std::string floatingResultRegister = "xmm0";
    std::size_t stackAlignment = 16;
    std::size_t shadowSpace = 0;
    bool stackGrowsDown = true;
    bool callerCleansStack = true;

    static CallingConvention systemVAMD64();
    static CallingConvention microsoftX64();
    static CallingConvention cdeclX86();
    static CallingConvention stdcallX86();
    static CallingConvention fastcallX86();
  };

  struct FunctionSignature {
    std::string symbol;
    CallingConvention convention = CallingConvention::systemVAMD64();
    ValueType result = ValueType::voidType();
    std::vector<ValueType> parameters;
    bool variadic = false;
  };

  enum class ArgumentLocationKind : std::uint8_t { Register, Stack };

  struct ArgumentLocation {
    ArgumentLocationKind kind = ArgumentLocationKind::Stack;
    std::string registerName;
    std::size_t stackOffset = 0;
  };

  class Abi {
  public:
    Abi() = delete;

    static void validate(const CallingConvention &convention);
    static void validateCall(const FunctionSignature &signature, const std::vector<ValueType> &arguments);
    static std::vector<ArgumentLocation> lowerArguments(const FunctionSignature &signature);
  };
} // namespace compiler
