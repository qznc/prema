/** Data Model and Persistence **/

import d2sqlite3;
import std.stdio: writeln;
import std.math: log, exp, isNaN;
import std.conv: text;
import std.format: formatValue, singleSpec, formattedWrite;
import std.datetime: Clock, SysTime;

void init_empty_db(Database db) {
	db.execute("
	CREATE TABLE users (
		id INTEGER PRIMARY KEY,
		name TEXT NOT NULL,
		email TEXT NOT NULL,
		wealth REAL
		);
	INSERT INTO users VALUES (NULL, 'root', 'root@localhost', 1000);
	INSERT INTO users VALUES (NULL, 'dummy', 'nobody@localhost', 1000);
	CREATE TABLE predictions (
		id INTEGER PRIMARY KEY,
		statement TEXT NOT NULL,
		created TEXT NOT NULL, /* ISO8601 date */
		closes TEXT NOT NULL, /* ISO8601 date */
		settled TEXT /* ISO8601 date */
		);
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

	user getUser(int id) {
		return user(id, db);
	}

	user[] users() {
		auto query = db.query("SELECT id,name,email,wealth FROM users ORDER BY id;");
		user[] result;
		foreach (row; query) {
			auto id = row.peek!int(0);
			auto name = row.peek!string(1);
			auto email = row.peek!string(2);
			auto wealth = row.peek!real(3);
			assert (!isNaN(wealth));
			result ~= user(id,name,email,wealth);
		}
		return result;
	}

	prediction[] predictions() {
		auto query = db.query("SELECT id,statement,created,closes,settled FROM predictions;");
		prediction[] result;
		foreach (row; query) {
			auto i = row.peek!int(0);
			auto s = row.peek!string(1);
			auto created = row.peek!string(2);
			auto closes  = row.peek!string(3);
			auto settled = row.peek!string(4);
			result ~= prediction(i,s,created,closes,settled,db);
		}
		return result;
	}

	void createPrediction(string stmt, string closes) {
		SysTime now = Clock.currTime;
		auto q = db.query("INSERT INTO predictions VALUES (NULL, ?, ?, ?, NULL);");
		q.bind(1,stmt);
		q.bind(2,now.toISOExtString());
		assert (SysTime.fromISOExtString(closes) > now);
		q.bind(3,closes);
		q.execute();
	}
}

struct prediction {
	int id;
	string statement;
	int yes_shares, no_shares;
	string created, closes, settled;
	@disable this();
	this(int id, string statement, string created, string closes, string settled, Database db) {
		this.id = id;
		this.statement = statement;
		this.created = created;
		this.closes = closes;
		this.settled = settled;
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

struct user {
	int id;
	string name, email;
	real wealth;
	@disable this();
	this(int id, string name, string email, real wealth) {
		assert (!isNaN(wealth));
		this.id = id;
		this.name = name;
		this.email = email;
		this.wealth = wealth;
	}
	this(int id, Database db) {
		this.id = id;
		auto query = db.query("SELECT id, name, email, wealth FROM users WHERE id = ?");
		query.bind(1, id);
		foreach (row; query) {
			assert (id == row.peek!int(0));
			name = row.peek!string(1);
			email = row.peek!string(2);
			wealth = row.peek!double(3);
		}
	}

	void toString(scope void delegate(const(char)[]) sink) const {
		sink("user(");
		sink(email);
		sink(")");
	}
}

unittest {
	const id = 1;
	auto db = get_database();
	auto admin = db.getUser(id);
	assert (admin.id == id);
	assert (admin.name == "root");
	assert (admin.email == "root@localhost");
	assert (admin.wealth > 0);
	foreach (u; db.users) {
		assert (admin.id == u.id);
		assert (admin.name == u.name);
		assert (admin.email == u.email);
		assert (admin.wealth == u.wealth, text(admin.wealth)~" != "~text(u.wealth));
		break;
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
	db.createPrediction("This app will actually be used.", "2015-02-02T05:45:55+00:00");
	db.createPrediction("Michelle Obama becomes president.", "2015-12-12T05:45:55+00:00");
	SysTime now = Clock.currTime;
	foreach (p; db.predictions) {
		assert (p.statement);
		assert (p.chance >= 0.0);
		assert (p.chance <= 1.0);
		assert (SysTime.fromISOExtString(p.created) != now);
		assert (SysTime.fromISOExtString(p.closes)  != now);
		if (p.settled != "")
			assert (SysTime.fromISOExtString(p.settled)  < now);
	}
}

