#include <compiler/Abi.hpp>

#include <utilities/Exception.hpp>

#include <algorithm>
#include <unordered_set>

namespace compiler {
  ValueType ValueType::voidType() { return {"void", ValueKind::Void, 0, 0}; }
  ValueType ValueType::integer(std::string name, std::uint16_t bits) {
    return {std::move(name), ValueKind::Integer, bits, 0};
  }
  ValueType ValueType::floating(std::string name, std::uint16_t bits) {
    return {std::move(name), ValueKind::FloatingPoint, bits, 0};
  }
  ValueType ValueType::pointer(std::string pointee, std::uint16_t depth, std::uint16_t bits) {
    if (depth == 0) THROW(, "ABI pointer depth must be greater than zero")
    return {std::move(pointee), ValueKind::Pointer, bits, depth};
  }

  CallingConvention CallingConvention::systemVAMD64() {
    return {"sysv-amd64", {"rdi", "rsi", "rdx", "rcx", "r8", "r9"},
            {"xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7"}, "rax", "xmm0", 16, 0,
            true, true};
  }
  CallingConvention CallingConvention::microsoftX64() {
    return {"microsoft-x64", {"rcx", "rdx", "r8", "r9"}, {"xmm0", "xmm1", "xmm2", "xmm3"}, "rax", "xmm0",
            16, 32, true, true};
  }
  CallingConvention CallingConvention::cdeclX86() {
    return {"cdecl-x86", {}, {}, "eax", "st0", 4, 0, true, true};
  }
  CallingConvention CallingConvention::stdcallX86() {
    CallingConvention result = cdeclX86();
    result.name = "stdcall-x86";
    result.callerCleansStack = false;
    return result;
  }
  CallingConvention CallingConvention::fastcallX86() {
    CallingConvention result = stdcallX86();
    result.name = "fastcall-x86";
    result.integerRegisters = {"ecx", "edx"};
    return result;
  }

  void Abi::validate(const CallingConvention &convention) {
    if (convention.name.empty()) THROW(, "ABI convention name cannot be empty")
    if (convention.stackAlignment == 0 || (convention.stackAlignment & (convention.stackAlignment - 1)) != 0)
      THROW(, "ABI stack alignment must be a non-zero power of two")
    std::unordered_set<std::string> registers;
    for (const std::string &name : convention.integerRegisters) {
      if (name.empty() || !registers.insert(name).second) THROW(, "ABI integer argument register is empty or duplicated")
    }
    registers.clear();
    for (const std::string &name : convention.floatingRegisters) {
      if (name.empty() || !registers.insert(name).second) THROW(, "ABI floating argument register is empty or duplicated")
    }
  }

  void Abi::validateCall(const FunctionSignature &signature, const std::vector<ValueType> &arguments) {
    validate(signature.convention);
    if (signature.symbol.empty()) THROW(, "ABI function symbol cannot be empty")
    if ((!signature.variadic && arguments.size() != signature.parameters.size()) ||
        (signature.variadic && arguments.size() < signature.parameters.size()))
      THROW(, "ABI call to '" << signature.symbol << "' has an invalid argument count")
    for (std::size_t index = 0; index < signature.parameters.size(); ++index) {
      const ValueType &expected = signature.parameters[index];
      const ValueType &actual = arguments[index];
      if (expected.kind == ValueKind::Void || actual.kind == ValueKind::Void)
        THROW(, "ABI call argument cannot have void type")
      if (expected.kind != actual.kind || expected.bits != actual.bits || expected.pointerDepth != actual.pointerDepth)
        THROW(, "ABI argument " << index << " of '" << signature.symbol << "' has type '" << actual.name
                                 << "', expected '" << expected.name << "'")
    }
  }

  std::vector<ArgumentLocation> Abi::lowerArguments(const FunctionSignature &signature) {
    validate(signature.convention);
    std::vector<ArgumentLocation> result;
    result.reserve(signature.parameters.size());
    std::size_t integerIndex = 0;
    std::size_t floatingIndex = 0;
    std::size_t stack = signature.convention.shadowSpace;
    for (const ValueType &parameter : signature.parameters) {
      const bool floating = parameter.kind == ValueKind::FloatingPoint;
      const auto &registers = floating ? signature.convention.floatingRegisters : signature.convention.integerRegisters;
      std::size_t &index = floating ? floatingIndex : integerIndex;
      if (index < registers.size()) {
        result.push_back({ArgumentLocationKind::Register, registers[index++], 0});
      } else {
        const std::size_t bytes = std::max<std::size_t>(1, (parameter.bits + 7) / 8);
        const std::size_t slot = std::max<std::size_t>(bytes, signature.convention.stackAlignment >= 8 ? 8 : 4);
        result.push_back({ArgumentLocationKind::Stack, {}, stack});
        stack += slot;
      }
    }
    if (!signature.convention.stackGrowsDown) {
      const std::size_t stackEnd = stack;
      for (std::size_t argument = 0; argument < result.size(); ++argument) {
        if (result[argument].kind != ArgumentLocationKind::Stack) continue;
        const std::size_t bytes = std::max<std::size_t>(1, (signature.parameters[argument].bits + 7) / 8);
        const std::size_t slot =
            std::max<std::size_t>(bytes, signature.convention.stackAlignment >= 8 ? 8 : 4);
        const std::size_t relative = result[argument].stackOffset - signature.convention.shadowSpace;
        result[argument].stackOffset =
            signature.convention.shadowSpace + (stackEnd - signature.convention.shadowSpace - relative - slot);
      }
    }
    return result;
  }
} // namespace compiler
