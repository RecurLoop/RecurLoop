#pragma once

#include <utilities/Declaration.hpp>
#include <utilities/Size.hpp>

class Byte {
protected:
  unsigned char *pointer = nullptr;

public:
  using Offset = unsigned char;
  static inline constexpr unsigned int offsetBits = 3;
  static inline constexpr unsigned int length = 8;

  DECLARATION Byte(unsigned char *pointer = nullptr) : pointer(pointer) {}
  DECLARATION Byte(char *pointer) : pointer((unsigned char *)pointer) {}
  DECLARATION Byte(void *pointer) : pointer((unsigned char *)pointer) {}

  DECLARATION unsigned char *toPtr() const;
  DECLARATION bool isNull();

  DECLARATION unsigned char get() const;
  DECLARATION void set(unsigned char value);

  DECLARATION Byte &operator++();
  DECLARATION Byte operator++(int);

  DECLARATION Byte &operator--();
  DECLARATION Byte operator--(int);

  DECLARATION Size operator-(const Byte &other) const;

  DECLARATION bool operator==(const Byte &other) const;
  DECLARATION bool operator!=(const Byte &other) const;

  DECLARATION Byte &operator=(unsigned char value);

  DECLARATION Byte &operator+=(Size shift);
  DECLARATION Byte &operator-=(Size shift);

  DECLARATION Byte operator+(Size shift) const;
  DECLARATION Byte operator-(Size shift) const;

  DECLARATION bool operator<(const Byte other) const;
  DECLARATION bool operator>(const Byte other) const;

  DECLARATION bool operator<=(const Byte other) const;
  DECLARATION bool operator>=(const Byte other) const;

  DECLARATION explicit operator bool() const noexcept;

  DECLARATION static Size copy(Byte input, Byte output, Size size);
  DECLARATION static Size copy(Byte inputFore, Byte inputRear, Byte outputFore, Byte outputRear);

  DECLARATION static Size compare(Byte left, Byte right, Size size);
  DECLARATION static Size compare(Byte leftFore, Byte leftRear, Byte rightFore, Byte rightRear);
};

#ifdef INLINE
  #include <utilities/Byte.cpp>
#endif
