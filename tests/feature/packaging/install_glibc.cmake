# Exercise the real installer's platform gate without downloading or installing
# anything: an accepted host reaches curl, whose test double exits immediately.
find_program(SH sh REQUIRED)
get_filename_component(root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(work "${CMAKE_CURRENT_BINARY_DIR}/install-glibc")
file(MAKE_DIRECTORY "${work}/bin")
file(WRITE "${work}/bin/curl" "#!${SH}\necho glibc-gate-accepted >&2\nexit 73\n")
file(CHMOD "${work}/bin/curl" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

foreach(version IN ITEMS 2.31 2.34 2.35 2.36 2.39 2.43 2.44)
    file(WRITE "${work}/bin/getconf" "#!${SH}\necho 'glibc ${version}'\n")
    file(CHMOD "${work}/bin/getconf" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    execute_process(COMMAND "${CMAKE_COMMAND}" -E env
        "PATH=${work}/bin:$ENV{PATH}" "RECURLOOP_PREFIX=${work}/prefix" "RECURLOOP_VERSION=1.2.3"
        "${SH}" "${root}/tools/install.sh"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 15)
    if(version VERSION_LESS 2.35)
        if(NOT rc STREQUAL "1" OR NOT err MATCHES "requires glibc >= 2.35" OR
           NOT err MATCHES "found ${version}" OR err MATCHES "glibc-gate-accepted")
            message(FATAL_ERROR "Installer must diagnose glibc ${version} before download: ${rc}\n${out}${err}")
        endif()
    elseif(NOT rc STREQUAL "73" OR NOT err MATCHES "glibc-gate-accepted" OR err MATCHES "requires glibc")
        message(FATAL_ERROR "Installer must accept glibc ${version}: ${rc}\n${out}${err}")
    endif()
    if(EXISTS "${work}/prefix")
        message(FATAL_ERROR "Platform gate test unexpectedly touched the installation prefix")
    endif()
endforeach()
file(REMOVE_RECURSE "${work}")
