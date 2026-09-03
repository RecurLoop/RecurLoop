#if !defined(__UTILITIES_JIT_MEMORY_CPP)
#define __UTILITIES_JIT_MEMORY_CPP

#include <utilities/Utilities.hpp>
#include <cstring>

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity)
    : Appender(memory, capacity), executable(executable) {
}

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity, const char* s)
    : JitMemory(memory, executable, capacity) {
    append(s);
}

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity, const unsigned char* s)
    : JitMemory(memory, executable, capacity) {
    append(s);
}

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity, const std::string& s)
    : JitMemory(memory, executable, capacity) {
    append(s);
}

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity, const Bit src, Size size)
    : JitMemory(memory, executable, capacity) {
    append(src, size);
}

JitMemory::JitMemory(Byte memory, Byte executable, Size capacity, const Byte src, Size size)
    : JitMemory(memory, executable, capacity) {
    append(src, size);
}

Byte JitMemory::getExecutable() {
    return executable;
}

JitMemory &JitMemory::clear() {
    Appender::clear();
    return *this;
}

#endif
