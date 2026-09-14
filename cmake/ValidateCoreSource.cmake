if(NOT DEFINED ROOT)
  message(FATAL_ERROR "ROOT is required")
endif()

file(GLOB CORE_MODULES "${ROOT}/core/*.rl")
set(CORE_SOURCES "${ROOT}/core.rl" ${CORE_MODULES})

foreach(FILE IN LISTS CORE_SOURCES)
  file(READ "${FILE}" SOURCE)

  # Source core must be a semantic declaration, not EngineImage::source()
  # output disguised as .rl. Ordinary semantic numbers (widths, precedence,
  # alignment, etc.) remain legal.
  if(SOURCE MATCHES "(^|\n)[ \t]*phrase[ \t]+[0-9]+([ \t]|$)")
    message(FATAL_ERROR "source core contains numeric phrase ids: ${FILE}")
  endif()
  if(SOURCE MATCHES "(^|\n)[ \t]*(parent|prototype|successor)[ \t]+[0-9]+([ \t]|$)")
    message(FATAL_ERROR "source core contains numeric phrase references: ${FILE}")
  endif()
  if(SOURCE MATCHES "payload[ \t]+\"[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    message(FATAL_ERROR "source core contains a serialized payload dump: ${FILE}")
  endif()
endforeach()
