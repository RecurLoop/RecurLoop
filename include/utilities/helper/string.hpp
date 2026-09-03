#pragma once

#include <string>

#include <utilities/Declaration.hpp>

namespace helper {
  namespace string {
    DECLARATION std::string escape(const std::string &string);
    DECLARATION std::string unescape(const std::string &string);
  } // namespace string
} // namespace helper

#ifdef INLINE
  #include <utilities/helper/string.cpp>
#endif
