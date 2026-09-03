#pragma once

#include <utilities/Declaration.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Bit.hpp>
#include <utilities/Size.hpp>

#include <string>
#include <cstring>

class Appender {
    Byte memory = (void*)nullptr;
    Size capacity = 0;
    Size offset = 0;

  public:
    DECLARATION Appender(Byte memory = (void *)nullptr, Size capacity = 0);
    DECLARATION Appender(Byte memory, Size capacity, const char* s);
    DECLARATION Appender(Byte memory, Size capacity, const unsigned char* s);
    DECLARATION Appender(Byte memory, Size capacity, const std::string& s);
    DECLARATION Appender(Byte memory, Size capacity, const Bit src, Size size);
    DECLARATION Appender(Byte memory, Size capacity, const Byte src, Size size);

    DECLARATION Byte getMemory();
    DECLARATION Size getOffset();
    DECLARATION Size getCapacity();

    DECLARATION Appender &clear();

    DECLARATION void append(char c);
    DECLARATION void append(const char* s);
    DECLARATION void append(const unsigned char* s);
    DECLARATION void append(const char* s, Size len);
    DECLARATION void append(const std::string& s);
    DECLARATION void append(const Appender& other);
    DECLARATION void append(const Byte src, Size size);
    DECLARATION void append(const Bit src, Size size);

    DECLARATION void truncate(Size bits);

    DECLARATION Appender& operator+=(char c);
    DECLARATION Appender& operator+=(const char* s);
    DECLARATION Appender& operator+=(const unsigned char* s);
    DECLARATION Appender& operator+=(const std::string& s);
    DECLARATION Appender& operator+=(const Appender& other);

    DECLARATION bool operator==(const Appender& other) const;
    DECLARATION bool operator!=(const Appender& other) const;
    DECLARATION bool operator==(const char* s) const;
    DECLARATION bool operator!=(const char* s) const;

    DECLARATION const char* c_str() const;
    DECLARATION Size size() const;
    DECLARATION Size bits() const;
    DECLARATION bool empty() const;

    DECLARATION Size memorySize();
    DECLARATION Size memoryUsed();
    DECLARATION Size memoryUnused();

    friend Appender operator+(Appender a, const Appender& b);
    friend Appender operator+(Appender a, const char* b);
    friend Appender operator+(const char* a, Appender b);
    friend Appender operator+(Appender a, const unsigned char* b);
    friend Appender operator+(const unsigned char* a, Appender b);
};

#ifdef INLINE
  #include <utilities/Appender.cpp>
#endif
