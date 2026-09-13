// Unknown top-level lines are claimed by the imported Shell fallback without
// requiring `run`, `shell `, or a shell preference block.
var project = "RecurLoop"

echo direct-shell
echo alpha | tr a-z A-Z
cd /tmp
pwd

// Ordinary RecurLoop root phrases still keep their normal priority.
print 6 * 7
print project
