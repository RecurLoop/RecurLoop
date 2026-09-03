#if !defined(__UTILITIES_HELPER_STRING_CPP)
  #define __UTILITIES_HELPER_STRING_CPP

  #include <utilities/Utilities.hpp>
  #include <utilities/helper/string.hpp>

namespace helper::string {
  std::string escape(const std::string &key) {
    std::ostringstream oss;

    if (key.empty() || key.front() == ' ')
        oss << "\\";

    for (char c : key) {
        switch (c) {
            case '\r': oss << "\\r"; break;
            case '\n': oss << "\\n"; break;
            case '\t': oss << "\\t"; break;
            case '\v': oss << "\\v"; break;
            case '\\':
            case ':':
            case '"':
            case '\'':
                oss << '\\' << c;
                break;
            default:
                oss << c;
                break;
        }
    }

    if (key.empty() || key.back() == ' ')
        oss << "\\";

    return oss.str();
  }

  std::string unescape(const std::string &string) {
    std::string originalString;
    originalString.reserve(string.size());

    for (size_t i = 0; i < string.size(); ++i) {
      if (string[i] == '\\' && i + 1 < string.size()) {
        switch (string[++i]) {
        case 'n': originalString += '\n'; break;
        case 'r': originalString += '\r'; break;
        case 't': originalString += '\t'; break;
        case 'v': originalString += '\v'; break;
        default: originalString += string[i]; break;
        }
      } else {
        originalString += string[i];
      }
    }

    return originalString;
  }
} // namespace helper::string

#endif
