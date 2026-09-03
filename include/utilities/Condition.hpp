#pragma once

#if !defined(__GNUC__)
  #define LIKELY(...) __builtin_expect(!!(__VA_ARGS__), 1)
  #define UNLIKELY(...) __builtin_expect(!!(__VA_ARGS__), 0)
#else
  #define LIKELY(...) (__VA_ARGS__)
  #define UNLIKELY(...) (__VA_ARGS__)
#endif

#define STATUS_ERROR(...) UNLIKELY(__VA_ARGS__ < 0)
#define STATUS_WARNING(...) UNLIKELY(__VA_ARGS__ > 0)
#define STATUS_SUCCESS(...) LIKELY(__VA_ARGS__ == 0)
