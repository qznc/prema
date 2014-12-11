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
	INSERT INTO orders VALUES (NULL, 1, 1, 100, 0, 62.0);
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
		return LMSR_chance(b, yes_shares, no_shares);
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

immutable real b = 100;

real LMSR_C(real b, real yes, real no) pure nothrow @safe {
	return b * log(exp(yes/b) + exp(no/b));
}

real LMSR_cost(real b, real yes, real no, real amount) pure nothrow @safe {
	return LMSR_C(b, yes+amount, no) - LMSR_C(b, yes, no);
}

unittest {
	void assert_roughly(real a, real b) {
		immutable real epsilon = 0.01;
		assert (a+epsilon > b && b > a-epsilon, text(a)~" !~ "~text(b));
	}
	assert_roughly(LMSR_cost(100, 0, 0, 1), 0.50);
	assert_roughly(LMSR_cost(100, 0, 0, 10), 5.12);
	assert_roughly(LMSR_cost(100, 0, 0, 100), 62.01);
	assert_roughly(LMSR_cost(100, 0, 0, 1000), 930.69);
	assert_roughly(LMSR_cost(100, 0, 0, 10000), 9930.69);
	assert_roughly(LMSR_cost(100, 50, 10, -10), -5.87);
	assert_roughly(LMSR_cost(100, 20, 15, 20), 10.75);
}

real LMSR_chance(real b, real yes, real no) pure nothrow @safe {
	const y =  LMSR_cost(b, yes, no, 1);
	const n =  LMSR_cost(b, no, yes, 1);
	return y / (y+n);
}

unittest {
	void assert_roughly(real a, real b) {
		immutable real epsilon = 0.01;
		assert (a+epsilon > b && b > a-epsilon, text(a)~" !~ "~text(b));
	}
	assert_roughly(LMSR_chance(   10, 0, 0), 0.5);
	assert_roughly(LMSR_chance(  100, 0, 0), 0.5);
	assert_roughly(LMSR_chance( 1000, 0, 0), 0.5);
	assert_roughly(LMSR_chance(10000, 0, 0), 0.5);
	assert_roughly(LMSR_chance(100, 50, 10), 0.6);
	assert_roughly(LMSR_chance(100, 10, 50), 0.4);
	assert_roughly(LMSR_chance(100, 20, 15), 0.5122);
	assert_roughly(LMSR_chance(100, 15, 20), 0.4878);
	assert_roughly(LMSR_chance(100,    1, 0), 0.5025);
	assert_roughly(LMSR_chance(100,   10, 0), 0.5244);
	assert_roughly(LMSR_chance(100,  100, 0), 0.7306);
	assert_roughly(LMSR_chance(100, 1000, 0), 1.0000);
}

unittest {
	auto db = get_database();
	writeln(db.users);
	writeln(db.predictions);
}
