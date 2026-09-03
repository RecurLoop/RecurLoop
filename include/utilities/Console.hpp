#pragma once

// Define ANSI escape codes for text colors
#define BLACK_TEXT "\033[30m"
#define RED_TEXT "\033[31m"
#define GREEN_TEXT "\033[32m"
#define YELLOW_TEXT "\033[33m"
#define BLUE_TEXT "\033[34m"
#define MAGENTA_TEXT "\033[35m"
#define CYAN_TEXT "\033[36m"
#define WHITE_TEXT "\033[37m"

// Define ANSI escape codes for bright text colors
#define BRIGHT_BLACK_TEXT "\033[90m"
#define BRIGHT_RED_TEXT "\033[91m"
#define BRIGHT_GREEN_TEXT "\033[92m"
#define BRIGHT_YELLOW_TEXT "\033[93m"
#define BRIGHT_BLUE_TEXT "\033[94m"
#define BRIGHT_MAGENTA_TEXT "\033[95m"
#define BRIGHT_CYAN_TEXT "\033[96m"
#define BRIGHT_WHITE_TEXT "\033[97m"

// Define ANSI escape codes for background colors
#define BLACK_BACKGROUND "\033[40m"
#define RED_BACKGROUND "\033[41m"
#define GREEN_BACKGROUND "\033[42m"
#define YELLOW_BACKGROUND "\033[43m"
#define BLUE_BACKGROUND "\033[44m"
#define MAGENTA_BACKGROUND "\033[45m"
#define CYAN_BACKGROUND "\033[46m"
#define WHITE_BACKGROUND "\033[47m"

// Define ANSI escape codes for bright background colors
#define BRIGHT_BLACK_BACKGROUND "\033[100m"
#define BRIGHT_RED_BACKGROUND "\033[101m"
#define BRIGHT_GREEN_BACKGROUND "\033[102m"
#define BRIGHT_YELLOW_BACKGROUND "\033[103m"
#define BRIGHT_BLUE_BACKGROUND "\033[104m"
#define BRIGHT_MAGENTA_BACKGROUND "\033[105m"
#define BRIGHT_CYAN_BACKGROUND "\033[106m"
#define BRIGHT_WHITE_BACKGROUND "\033[107m"

// Define ANSI escape codes for text formatting
#define BOLD "\033[1m"
#define DIM "\033[2m"
#define ITALIC "\033[3m"
#define UNDERLINE "\033[4m"
#define BLINK "\033[5m"
#define REVERSE "\033[7m"
#define HIDDEN "\033[8m"
#define STRIKETHROUGH "\033[9m"

// Define ANSI escape code to reset all formatting
#define RESET "\033[0m"

// Define a cross-platform newline character sequence
#if defined(_WIN32) || defined(_WIN64)
  #define NEWLINE "\r\n"
#else
  #define NEWLINE "\n"
#endif
