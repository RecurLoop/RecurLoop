#if !defined(__UTILITIES_BYTE_CPP)
  #define __UTILITIES_BYTE_CPP

  #include <utilities/Utilities.hpp>

unsigned char *Byte::toPtr() const {
  return pointer;
}

bool Byte::isNull() {
  return pointer == nullptr;
}

unsigned char Byte::get() const {
  return *toPtr();
}

void Byte::set(unsigned char value) {
  *toPtr() = value;
}

// pre incrementation
Byte &Byte::operator++() {
  ++pointer;

  return *this;
}

// post incrementation
Byte Byte::operator++(int) {
  Byte temp = *this;
  ++(*this);
  return temp;
}

// pre decrementation
Byte &Byte::operator--() {
  --pointer;
  return *this;
}

// post decrementation
Byte Byte::operator--(int) {
  Byte temp = *this;
  --(*this);
  return temp;
}

Size Byte::operator-(const Byte &other) const {
  return pointer - other.pointer;
}

bool Byte::operator==(const Byte &other) const {
  return toPtr() == other.toPtr();
}

bool Byte::operator!=(const Byte &other) const {
  return !(*this == other);
}

Byte &Byte::operator=(unsigned char value) {
  set(value);
  return *this;
}

Byte &Byte::operator+=(Size size) {
  pointer += size;
  return *this;
}

Byte &Byte::operator-=(Size size) {
  pointer -= size;
  return *this;
}

Byte Byte::operator+(Size size) const {
  Byte temp = *this;
  temp += size;
  return temp;
}

Byte Byte::operator-(Size size) const {
  Byte temp = *this;
  temp -= size;
  return temp;
}

bool Byte::operator<(const Byte other) const {
  return toPtr() < other.toPtr();
}

bool Byte::operator>(const Byte other) const {
  return toPtr() > other.toPtr();
}

bool Byte::operator<=(const Byte other) const {
  return toPtr() <= other.toPtr();
}

bool Byte::operator>=(const Byte other) const {
  return toPtr() >= other.toPtr();
}

Byte::operator bool() const noexcept {
  return pointer != nullptr;
}

Size Byte::copy(Byte input, Byte output, Size size) {
  for (Size i = 0; i < size; i++) output++ = input++.get();

  return size;
}
Size Byte::copy(Byte inputFore, Byte inputRear, Byte outputFore, Byte outputRear) {
  Size inputSize = inputRear - inputFore;
  Size outputSize = outputRear - outputFore;

  return copy(inputFore, outputFore, inputSize < outputSize ? inputSize : outputSize);
}

Size Byte::compare(Byte left, Byte right, Size size) {
  for (Size i = 0; i < size; i++) {
    if (left.get() != right.get()) return i;
    left++;
    right++;
  }

  return size;
}

Size Byte::compare(Byte leftFore, Byte leftRear, Byte rightFore, Byte rightRear) {
  Size leftSize = leftRear - leftFore;
  Size rightSize = rightRear - rightFore;

  return compare(leftFore, rightFore, leftSize < rightSize ? leftSize : rightSize);
}

#endif
