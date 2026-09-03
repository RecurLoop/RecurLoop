#pragma once

#define MACRO_OPTIONAL_ALL_ARGS_1(_1, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_2(_1, _2, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_3(_1, _2, _3, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_4(_1, _2, _3, _4, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_5(_1, _2, _3, _4, _5, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_6(_1, _2, _3, _4, _5, _6, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_7(_1, _2, _3, _4, _5, _6, _7, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_8(_1, _2, _3, _4, _5, _6, _7, _8, Name, ...) Name
#define MACRO_OPTIONAL_ALL_ARGS_9(_1, _2, _3, _4, _5, _6, _7, _8, _9, Name, ...) Name

#define MACRO_GENERATE_OPTIONAL_ARGS_1(Name, ...) MACRO_OPTIONAL_ALL_ARGS_1(__VA_ARGS__, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_2(Name, ...) MACRO_OPTIONAL_ALL_ARGS_2(__VA_ARGS__, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_3(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_3(__VA_ARGS__, Name##_3, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_4(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_4(__VA_ARGS__, Name##_4, Name##_3, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_5(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_5(__VA_ARGS__, Name##_5, Name##_4, Name##_3, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_6(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_6(__VA_ARGS__, Name##_6, Name##_5, Name##_4, Name##_3, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_7(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_7(__VA_ARGS__, Name##_7, Name##_6, Name##_5, Name##_4, Name##_3, Name##_2, Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_8(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_8(__VA_ARGS__, Name##_8, Name##_7, Name##_6, Name##_5, Name##_4, Name##_3, Name##_2,         \
                            Name##_1, Name##_0)
#define MACRO_GENERATE_OPTIONAL_ARGS_9(Name, ...)                                                                      \
  MACRO_OPTIONAL_ALL_ARGS_9(__VA_ARGS__, Name##_9, Name##_8, Name##_7, Name##_6, Name##_5, Name##_4, Name##_3,         \
                            Name##_2, Name##_1, Name##_0)
