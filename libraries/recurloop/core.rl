// Canonical core image export.
//
// A clean build creates the first image with the private core builder. The
// final recurloop executable embeds that image, so running this file with the
// normal executable snapshots the currently embedded core again:
//
//   recurloop --file libraries/recurloop/core.rl
//
// The same file also closes the self-hosting loop explicitly:
//
//   recurloop --reset --import core.rli --file libraries/recurloop/core.rl
engine export "core.rli"
