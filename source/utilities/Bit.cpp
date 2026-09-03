#if !defined(__UTILITIES_BIT_CPP)
  #define __UTILITIES_BIT_CPP

  #include <utilities/Utilities.hpp>

Byte Bit::getByte() const {
  return byte;
}

void Bit::setByte(Byte _byte) {
  byte = _byte;
}

int Bit::getOffset() const {
  return offset;
}

void Bit::setOffset(int _offset) {
  offset = _offset;
}

bool Bit::get() const {
  return getByte().toPtr()[offset / Byte::length] & (1 << (Byte::length - 1 - (offset % Byte::length)));
}

void Bit::set(bool value) {
  unsigned char *ptr = &getByte().toPtr()[offset / Byte::length];

  auto block = (1 << (Byte::length - 1 - (offset % Byte::length)));

  if (value)
    *ptr |= block;
  else
    *ptr &= ~block;
}

// pre incrementation
Bit &Bit::operator++() {
  if (++offset >= Byte::length) {
    offset = 0;
    ++byte;
  }

  return *this;
}

// post incrementation
Bit Bit::operator++(int) {
  Bit temp = *this;
  ++(*this);
  return temp;
}

// pre decrementation
Bit &Bit::operator--() {
  if (offset <= 0) {
    offset = Byte::length - 1;
    --byte;
  } else {
    --offset;
  }

  return *this;
}

// post decrementation
Bit Bit::operator--(int) {
  Bit temp = *this;
  --(*this);
  return temp;
}

Size Bit::operator-(const Bit &other) const {
  Size byteDiff = byte - other.byte;
  Size bitDiff = byteDiff * Byte::length + (offset - other.offset);
  return bitDiff;
}

bool Bit::operator==(Bit &other) {
  return getByte() == other.getByte() && getOffset() == other.getOffset();
}

bool Bit::operator!=(Bit &other) {
  return !(*this == other);
}

Bit &Bit::operator=(bool value) {
  set(value);
  return *this;
}

Bit &Bit::operator+=(Size shift) {
  Size totalOffset = offset + shift;
  byte += totalOffset / Byte::length;
  offset = totalOffset % Byte::length;
  return *this;
}

Bit &Bit::operator-=(Size shift) {
  Size shiftBytes = shift / Byte::length;
  Size shiftBits = shift % Byte::length;

  if (offset < shiftBits) {
    offset += Byte::length;
    byte -= 1;
  }

  offset -= shiftBits;
  byte -= shiftBytes;

  return *this;
}

Bit Bit::operator+(Size shift) const {
  Bit temp = *this;
  temp += shift;
  return temp;
}

Bit Bit::operator-(Size shift) const {
  Bit temp = *this;
  temp -= shift;
  return temp;
}

bool Bit::operator<(Bit other) const {
  auto byte = getByte();
  auto otherByte = other.getByte();

  if (byte < otherByte) return true;
  if (byte > otherByte) return false;

  return getOffset() < other.getOffset();
}

bool Bit::operator>(Bit other) const {
  auto byte = getByte();
  auto otherByte = other.getByte();

  if (byte > otherByte) return true;
  if (byte < otherByte) return false;

  return getOffset() > other.getOffset();
}

bool Bit::operator<=(Bit other) const {
  auto byte = getByte();
  auto otherByte = other.getByte();

  if (byte < otherByte) return true;
  if (byte > otherByte) return false;

  return getOffset() <= other.getOffset();
}

bool Bit::operator>=(Bit other) const {
  auto byte = getByte();
  auto otherByte = other.getByte();

  if (byte > otherByte) return true;
  if (byte < otherByte) return false;

  return getOffset() >= other.getOffset();
}

Bit::operator bool() noexcept {
  return (bool)getByte();
}

Size Bit::copy(Bit input, Bit output, Size size) {
  for (Size i = 0; i < size; i++) output++ = input++.get();

  return size;
}

Size Bit::copy(Bit inputFore, Bit inputRear, Bit outputFore, Bit outputRear) {
  Size inputSize = inputRear - inputFore;
  Size outputSize = outputRear - outputFore;

  return copy(inputFore, outputFore, inputSize < outputSize ? inputSize : outputSize);
}

Size Bit::compare(Bit left, Bit right, Size size) {
  Size limit = size;

  for (Size i = 0; i < limit; i++)
    if (left++.get() != right++.get()) return i;

  return limit;
}

Size Bit::compare(Bit leftFore, Bit leftRear, Bit rightFore, Bit rightRear) {
  Size leftSize = leftRear - leftFore;
  Size rightSize = rightRear - rightFore;

  return compare(leftFore, rightFore, leftSize < rightSize ? leftSize : rightSize);
}

Size Bit::bytes(Size bits) {
  return (bits + Byte::length - 1) / Byte::length;
}

#endif
