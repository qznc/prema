import std.process;

static string VER;

static this() {
	VER = loadVersion();
}

string loadVersion() {
	auto res = executeShell("git describe --abbrev=4 --dirty --always --tags");
	return res.output;
}
