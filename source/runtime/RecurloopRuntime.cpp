#include <recurloop/Recurloop.hpp>
#include <recurloop/EmbeddedCore.hpp>

namespace recurloop {
  Recurloop &Recurloop::initialize(int argc, char **argv) {
    return initializeEmbedded(argc, argv, embedded::coreImage());
  }
} // namespace recurloop
