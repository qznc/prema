import etc.c.sqlite3;
import std.stdio: writeln;
import std.string: toStringz, fromStringz;
import std.conv: text;

/** Wrapper for Sqlite3 connection.
	Ensures that connection is closed at the end of the scope. */
struct sqlite3_db {
	sqlite3* conn;
	string path;

	this(string path) {
		this.path = path;
		immutable(char)* filename = path.toStringz;
		int ret = sqlite3_open(filename, &conn);
		if (SQLITE_OK != ret) {
			throw new Sqlite3Exception(ret, "Could not open: "~path);
		}
	}

	@disable this();
	@disable this(this);

	~this() {
		int ret = sqlite3_close(conn);
		if (SQLITE_OK != ret) {
			throw new Sqlite3Exception(ret, "Could not close: "~path);
		}
	}

	void exec()(string sql) {
		char *err;
		auto ret = sqlite3_exec(conn, sql.toStringz, null, null, &err);
		if (SQLITE_OK != ret) {
			auto msg = err.fromStringz.idup;
			throw new Sqlite3Exception(ret, msg);
		}
	}

	void insert_or_update(U...)(string sql, U values) {
		char *err;
		sqlite3_stmt* ppStmt;
		const(char)* pzTail;
		assert (sql.length <= int.max);
		int ret = sqlite3_prepare_v2(conn, sql.toStringz, cast(int)sql.length, &ppStmt, &pzTail);
		if (SQLITE_OK != ret) {
			throw new Sqlite3Exception(ret, "prepare fail");
		}
		scope (exit) sqlite3_finalize(ppStmt);

		foreach(int i,value; values) {
			static if (is(typeof(value) == double))
				ret = sqlite3_bind_double(ppStmt, i+1, value);
			else static if (is(typeof(value) == int))
				ret = sqlite3_bind_int(ppStmt, i+1, value);
			else static if (is(typeof(value) == long))
				ret = sqlite3_bind_int64(ppStmt, i+1, value);
			else static if (is(typeof(value) == string)) {
				assert (value.length <= int.max);
				ret = sqlite3_bind_text(ppStmt, i+1, value.toStringz, cast(int)value.length, SQLITE_TRANSIENT);
			} else
				throw new Sqlite3Exception(-1, "cannot bind type "~typeof(value));
			if (SQLITE_OK != ret) {
				throw new Sqlite3Exception(ret, "bind fail: "~text(value));
			}
		}

		ret = sqlite3_step(ppStmt);
		if (SQLITE_OK != ret && SQLITE_DONE != ret) {
			throw new Sqlite3Exception(ret, "step fail");
		}
	}
}

class Sqlite3Exception : Exception {
	int errcode;
	public this(int errcode, string msg) {
		super(msg~" [errorcode="~text(errcode)~"]");
		this.errcode = errcode;
	}
}

void foo(ref sqlite3_db db) {
	db.exec("CREATE TABLE foo (a,b,c);");
	db.insert_or_update("INSERT INTO foo (a,b,c) VALUES (?, ?, ?);", 11, "foo", 3.14);
	db.exec("SELECT * FROM foo;");
}

unittest {
	auto db = sqlite3_db(":memory:");
	foo(db);
}
