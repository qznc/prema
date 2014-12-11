/** Data Model and Persistence **/

import d2sqlite3;
import std.stdio: writeln;
import std.math: log, exp;
import std.conv: text;
import std.format: formatValue, singleSpec, formattedWrite;

void init_empty_db(Database db) {
	db.execute("
	CREATE TABLE users (
		id INTEGER PRIMARY KEY,
		name TEXT NOT NULL,
		email TEXT NOT NULL
		);
	INSERT INTO users VALUES (NULL, 'root', 'root@localhost');
	INSERT INTO users VALUES (NULL, 'dummy', 'nobody@localhost');
	CREATE TABLE predictions (
		id INTEGER PRIMARY KEY,
		statement TEXT NOT NULL
		);
	INSERT INTO predictions VALUES (NULL, 'This app will actually be used.');
	CREATE TABLE orders (
		id INTEGER PRIMARY KEY,
		user INTEGER, /* who traded? */
		prediction INTEGER, /* which prediction? */
		share_count INTEGER, /* amount of shares traded */
		yes_order INTEGER, /* what was bought 1=yes, 0=no */
		price REAL /* might be negative! */
		);
	INSERT INTO orders VALUES (NULL, 1, 1, 10, 1, 5.0);
	");
}

struct database {
	Database db;

	@disable this();
	this(string sqlite_path) {
		this.db = Database(sqlite_path);
	}

	string[] users() {
		auto query = db.query("SELECT name FROM users;");
		string[] result;
		foreach (row; query) {
			result ~= row.peek!string(0);
		}
		return result;
	}

	prediction[] predictions() {
		auto query = db.query("SELECT id,statement FROM predictions;");
		prediction[] result;
		foreach (row; query) {
			auto i = row.peek!int(0);
			auto s = row.peek!string(1);
			result ~= prediction(i,s,db);
		}
		return result;
	}
}

struct prediction {
	int id;
	string statement;
	int yes_shares, no_shares;
	@disable this();
	this(int id, string statement, Database db) {
		this.id = id;
		this.statement = statement;
		auto query = db.query("SELECT share_count, yes_order FROM orders WHERE prediction = ?");
		query.bind(1, id);
		foreach (row; query) {
			auto y = row.peek!int(1);
			if (y == 1) {
				yes_shares += row.peek!int(0);
			} else {
				assert (y == 0);
				no_shares += row.peek!int(0);
			}
		}
	}
	/* chance that statement happens according to current market */
	real chance() const pure @safe nothrow {
		return LMSR_cost(b, yes_shares+1, no_shares) - LMSR_cost(b, yes_shares, no_shares);
	}

	void toString(scope void delegate(const(char)[]) sink) const {
		sink("prediction(");
		sink(statement);
		sink(" ");
		sink.formattedWrite("%.2f%%", chance*100);
		sink(")");
	}
}

database get_database() {
	auto db = database(":memory:");
	init_empty_db(db.db);
	return db;
}

immutable real b = 10;

real LMSR_cost(real b, real yes, real no) pure nothrow @safe {
	return b + log(exp(yes/b) + exp(no/b));
}

unittest {
	auto db = get_database();
	writeln(db.users);
	writeln(db.predictions);
}
