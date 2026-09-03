#pragma once

#include <utilities/Appender.hpp>

class JitMemory : public Appender {
    Byte executable = (void*)nullptr;

  public:
    DECLARATION JitMemory(Byte memory = (void *)nullptr, Byte executable = (void *)nullptr, Size capacity = 0);
    DECLARATION JitMemory(Byte memory, Byte executable, Size capacity, const char* s);
    DECLARATION JitMemory(Byte memory, Byte executable, Size capacity, const unsigned char* s);
    DECLARATION JitMemory(Byte memory, Byte executable, Size capacity, const std::string& s);
    DECLARATION JitMemory(Byte memory, Byte executable, Size capacity, const Bit src, Size size);
    DECLARATION JitMemory(Byte memory, Byte executable, Size capacity, const Byte src, Size size);

    DECLARATION Byte getExecutable();

    DECLARATION JitMemory &clear();
};

#ifdef INLINE
  #include <utilities/JitMemory.cpp>
#endif
