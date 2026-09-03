#if !defined(__UTILITIES_APPENDER_CPP)
#define __UTILITIES_APPENDER_CPP

#include <utilities/Utilities.hpp>
#include <cstring>

Appender::Appender(Byte memory, Size capacity)
    : memory(memory), capacity(capacity), offset(0) {
    if (capacity > 0) this->memory.set('\0');
}

Appender::Appender(Byte memory, Size capacity, const char* s)
    : Appender(memory, capacity) {
    append(s);
}

Appender::Appender(Byte memory, Size capacity, const unsigned char* s)
    : Appender(memory, capacity) {
    append(s);
}

Appender::Appender(Byte memory, Size capacity, const std::string& s)
    : Appender(memory, capacity) {
    append(s);
}

Appender::Appender(Byte memory, Size capacity, const Bit src, Size size)
    : Appender(memory, capacity) {
    append(src, size);
}

Appender::Appender(Byte memory, Size capacity, const Byte src, Size size)
    : Appender(memory, capacity) {
    append(src, size);
}

Byte Appender::getMemory() {
    return memory;
}
Size Appender::getOffset() {
    return offset;
}
Size Appender::getCapacity() {
    return capacity;
}

Appender &Appender::clear() {
    offset = 0;
    if (capacity > 0) memory.set('\0');
    return *this;
}

void Appender::append(char c) {
    append(&c, 1);
}

void Appender::append(const char* s) {
    append(s, std::strlen(s));
}

void Appender::append(const unsigned char* s) {
    append(reinterpret_cast<const char*>(s));
}

void Appender::append(const char* s, Size len) {
    append(Byte((unsigned char*)s), len);
}

void Appender::append(const std::string& s) {
    append(s.data(), s.size());
}

void Appender::append(const Appender& other) {
    append(other.c_str(), other.size());
}

void Appender::append(const Byte src, Size size) {
    if (size == 0) return;
    if (offset % Byte::length == 0) {
        Size bytesUsed = offset / Byte::length;
        if (bytesUsed + size + 1 > capacity) THROW(, "Append fails, out of memory.")
        Byte::copy(src, memory + bytesUsed, size);
        offset += size * Byte::length;
        memory.toPtr()[offset / Byte::length] = '\0';
    } else {
        append(Bit(src, 0), size * Byte::length);
    }
}

void Appender::append(const Bit src, Size size) {
    if (size == 0) return;

    Size startBit = offset;
    Size endBitPos = startBit + size;
    Size endBytes = Bit::bytes(endBitPos);

    if (endBytes + 1 > capacity) THROW(, "Append fails, out of memory.")

    Bit dst(Byte(memory), startBit);
    for (Size i = 0; i < size; i++) {
        dst.set((src + i).get());
        ++dst;
    }

    offset += size;
    memory.toPtr()[offset / Byte::length] = '\0';
}

void Appender::truncate(Size bits) {
    if (bits >= offset) return;

    Size bytes = Bit::bytes(bits);
    if (bytes + 1 > capacity) THROW(, "Append fails, out of memory.");

    offset = bits;
    memory.toPtr()[bytes] = '\0';

    Size usedBits = bits % Byte::length;
    if (usedBits != 0) {
        unsigned char mask = (1u << usedBits) - 1u;
        memory.toPtr()[bytes - 1] &= mask;
    }
}

Appender& Appender::operator+=(char c) { append(c); return *this; }
Appender& Appender::operator+=(const char* s) { append(s); return *this; }
Appender& Appender::operator+=(const unsigned char* s) { append(s); return *this; }
Appender& Appender::operator+=(const std::string& s) { append(s); return *this; }
Appender& Appender::operator+=(const Appender& other) { append(other); return *this; }

bool Appender::operator==(const Appender& other) const {
    return std::strcmp(c_str(), other.c_str()) == 0;
}
bool Appender::operator!=(const Appender& other) const { return !(*this == other); }
bool Appender::operator==(const char* s) const { return std::strcmp(c_str(), s) == 0; }
bool Appender::operator!=(const char* s) const { return !(*this == s); }

const char* Appender::c_str() const { return reinterpret_cast<const char*>(memory.toPtr()); }
Size Appender::size() const { return offset / Byte::length; }
Size Appender::bits() const { return offset; }
bool Appender::empty() const { return offset == 0; }

Size Appender::memorySize() {
    return capacity;
}

Size Appender::memoryUsed() {
    return Bit::bytes(offset);
}

Size Appender::memoryUnused() {
return memorySize() - memoryUsed();
}

inline Appender operator+(Appender a, const Appender& b) {
    a += b;
    return a;
}
inline Appender operator+(Appender a, const char* b) {
    a += b;
    return a;
}
inline Appender operator+(const char* a, Appender b) {
    b.clear();
    b += a;
    return b;
}
inline Appender operator+(Appender a, const unsigned char* b) {
    a += b;
    return a;
}
inline Appender operator+(const unsigned char* a, Appender b) {
    b.clear();
    b += a;
    return b;
}

#endif
