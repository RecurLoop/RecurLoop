#define RADIX_REVERSE false
#include <radix/Radix.hpp>
#undef RADIX_REVERSE

#include <benchmark/benchmark.h>
#include <random>
#include <vector>

struct Config {
    Size size = (Size)1024 * 1024 * 1024;
} config;

static void RadixInsert_InsertAndAllocateTiny(benchmark::State &state) {
    const int N = state.range(0);

    Byte memory = Byte(malloc(config.size));
    radix::Radix radix(memory, config.size);

    std::vector<uint32_t> keys(N);
    std::mt19937 rng(123456);
    for (int i = 0; i < N; ++i)
        keys[i] = rng();

    for (auto _ : state) {
        radix.clear();
        radix::Node head = radix.node();

        for (int i = 0; i < N; ++i) {
            uint32_t k = keys[i];
            head.append(Byte((void *)&k), 0, sizeof(k) * Byte::length).push();

            int *content = (int *)radix.allocate(sizeof(int)).toPtr();
            *content = i;
        }
    }

    const double total_inserts =  double(state.iterations()) * double(N);

    // ---------------- Counters ----------------
    state.counters["Bytes"] = radix.memoryUsed();
    state.counters["BytesPerInsert"] = radix.memoryUsed() / double(N);
    state.counters["Inserts"] = benchmark::Counter(total_inserts, benchmark::Counter::kIsRate);

    free(memory.toPtr());
}

BENCHMARK(RadixInsert_InsertAndAllocateTiny)
    ->RangeMultiplier(2)
    ->Range(1 << 10, 1 << 20)
    ->MinTime(2.0)
    ->Unit(benchmark::kMillisecond);

BENCHMARK_MAIN();
