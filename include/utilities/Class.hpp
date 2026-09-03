#pragma once

#define NONCOPYABLE(Type)                                                                                              \
  Type(const Type &other) = delete;                                                                                    \
  Type &operator=(const Type &other) = delete;

#define NONCONSTRUCTIBLE(Type)                                                                                         \
  Type() = delete;                                                                                                     \
  NONCOPYABLE(Type)

/**
  Example:

*/
#define SINGLETON(Type, Construct, Args)                                                                               \
private:                                                                                                               \
  Type(const Type &other) = delete;                                                                                    \
  Type &operator=(const Type &other) = delete;                                                                         \
  Type Construct;                                                                                                      \
                                                                                                                       \
public:                                                                                                                \
  static Type &getInstance Construct {                                                                                 \
    static Type instance Args;                                                                                         \
    return instance;                                                                                                   \
  }                                                                                                                    \
                                                                                                                       \
private:
