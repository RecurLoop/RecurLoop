#pragma once

#include <utilities/Declaration.hpp>
#include <utilities/Byte.hpp>
#include <utilities/Size.hpp>

class Bit {
protected:
  Byte byte;
  int offset = 0;

public:
  DECLARATION Bit(Byte byte, Size offset = 0) : byte(byte + (offset / Byte::length)), offset(offset % Byte::length) {};

  DECLARATION Byte getByte() const;
  DECLARATION void setByte(Byte byte);
  DECLARATION int getOffset() const;
  DECLARATION void setOffset(int offset);

  DECLARATION bool get() const;
  DECLARATION void set(bool value);

  DECLARATION Bit &operator++();
  DECLARATION Bit operator++(int);

  DECLARATION Bit &operator--();
  DECLARATION Bit operator--(int);

  DECLARATION Size operator-(const Bit &other) const;

  DECLARATION bool operator==(Bit &other);
  DECLARATION bool operator!=(Bit &other);

  DECLARATION Bit &operator=(bool value);

  DECLARATION Bit &operator+=(Size shift);
  DECLARATION Bit &operator-=(Size shift);

  DECLARATION Bit operator+(Size shift) const;
  DECLARATION Bit operator-(Size shift) const;

  DECLARATION bool operator<(const Bit other) const;
  DECLARATION bool operator>(const Bit other) const;

  DECLARATION bool operator<=(const Bit other) const;
  DECLARATION bool operator>=(const Bit other) const;

  DECLARATION explicit operator bool() noexcept;

  DECLARATION static Size copy(Bit input, Bit output, Size size);
  DECLARATION static Size copy(Bit inputFore, Bit inputRear, Bit outputFore, Bit outputRear);

  DECLARATION static Size compare(Bit left, Bit right, Size size);
  DECLARATION static Size compare(Bit leftFore, Bit leftRear, Bit rightFore, Bit rightRear);

  DECLARATION static Size bytes(Size bits);
};

#ifdef INLINE
  #include <utilities/Bit.cpp>
#endif
