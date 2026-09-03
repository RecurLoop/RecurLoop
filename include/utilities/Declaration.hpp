#if defined(_MSC_VER)
  #define INLINED __forceinline
#elif defined(__GNUC__) || defined(__clang__)
  #define INLINED __attribute__((always_inline)) inline
#else
  #define INLINED inline
#endif

#ifdef INLINE
  #define DECLARATION INLINED
#else
  #define DECLARATION
#endif
