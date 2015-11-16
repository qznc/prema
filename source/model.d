/** Data Model and Persistence **/

import d2sqlite3;
import std.algorithm: findSplitBefore;
import std.stdio: writeln;
import std.math: log, exp, isNaN, abs;
import std.conv: text;
import std.format: formatValue, singleSpec, formattedWrite;
import std.datetime: Clock, SysTime;
import std.exception: enforce;
import std.file: exists;

enum share_type {
	yes = 1,
	no = 2,
	balance = 3,
}

void init_empty_db(Database db) {
	db.execute("CREATE TABLE users (
		id INTEGER PRIMARY KEY,
		name TEXT NOT NULL,
		email TEXT NOT NULL,
		wealth REAL
		);");
	db.execute("INSERT INTO users VALUES (1, 'root', 'root@localhost', 1000);");
	db.execute("INSERT INTO users VALUES (NULL, 'dummy', 'nobody@localhost', 1000);");
	db.execute("CREATE TABLE predictions (
		id INTEGER PRIMARY KEY,
		statement TEXT NOT NULL,
		created TEXT NOT NULL, /* ISO8601 date */
		creator INTEGER, /* id from users */
		closes TEXT NOT NULL, /* ISO8601 date */
		settled TEXT, /* ISO8601 date */
		result TEXT /* yes or no */
		);");
	db.execute("CREATE TABLE orders (
		id INTEGER PRIMARY KEY,
		user INTEGER, /* who traded? */
		prediction INTEGER, /* which prediction? */
		share_count INTEGER, /* amount of shares traded */
		yes_order INTEGER, /* what was bought 1=yes, 2=no */
		date TEXT NOT NULL, /* ISO8601 date */
		price REAL /* might be negative! */
		);");
}

immutable SQL_SELECT_PREDICTION_PREFIX = "SELECT id,statement,created,creator,closes,settled,result FROM predictions ";

struct database {
	Database db;

	@disable this();
	this(string sqlite_path) {
		this.db = Database(sqlite_path);
	}

	user getUser(int id) {
		return user(id, db);
	}

	user getUser(const(string) email) {
		return user(email, db);
	}

	prediction getPrediction(int id) {
		return prediction(id, db);
	}

	user[] users() {
		auto query = db.execute("SELECT id,name,email,wealth FROM users ORDER BY id;");
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

	private auto parsePredictionQuery(ResultRange query) {
		prediction[] ret;
		foreach (row; query) {
			auto i = row.peek!int(0);
			auto s = row.peek!string(1);
			auto created = row.peek!string(2);
			auto creator = row.peek!string(3);
			auto closes  = row.peek!string(4);
			auto settled = row.peek!string(5);
			auto result = row.peek!string(6);
			ret ~= prediction(i,s,created,closes,settled,result,db);
		}
		return ret;
	}

	prediction[] activePredictions() {
		SysTime now = Clock.currTime.toUTC;
		auto query = db.prepare(SQL_SELECT_PREDICTION_PREFIX~"WHERE closes > ? ORDER BY closes;");
		query.bind(1, now.toISOExtString());
		return parsePredictionQuery(query.execute());
	}

	prediction[] predictionsToSettle() {
		SysTime now = Clock.currTime.toUTC;
		auto query = db.prepare(SQL_SELECT_PREDICTION_PREFIX~"WHERE closes < ? AND settled IS NULL ORDER BY closes;");
		query.bind(1, now.toISOExtString());
		return parsePredictionQuery(query.execute());
	}

	void createPrediction(string stmt, SysTime closes, user creator) {
		SysTime now = Clock.currTime.toUTC;
		enforce (closes > now, "closes date must be in the future");
		auto q = db.prepare("INSERT INTO predictions (id,statement,created,creator,closes,settled,result) VALUES (NULL, ?, ?, ?, ?, NULL, NULL);");
		q.bind(1,stmt);
		q.bind(2,now.toISOExtString());
		q.bind(3,creator.id);
		q.bind(4,closes.toUTC.toISOExtString);
		q.execute();
	}

	void buy(ref user u, ref prediction p, int amount, share_type t, real price) {
		enforce (p.cost(amount,t) == price, "assumed the wrong price: "~text(p.cost(amount,t))~" != "~text(price));
		buy(u,p,amount,t);
	}
	void buy(ref user u, ref prediction p, int amount, share_type t) {
		auto price = p.cost(amount,t);
		enforce (u.wealth >= price, "not enough wealth: "~text(u.wealth)~" < "~text(price));
		/* update local data */
		if (t == share_type.yes) {
			p.yes_shares += amount;
		} else {
			assert (t == share_type.no);
			p.no_shares += amount;
		}
		u.wealth -= price;
		/* update database */
		auto now = Clock.currTime.toUTC.toISOExtString;
		auto q = db.prepare("INSERT INTO orders VALUES (NULL, ?, ?, ?, ?, ?, ?);");
		q.bind(1, u.id);
		q.bind(2, p.id);
		q.bind(3, amount);
		q.bind(4, t);
		q.bind(5, now);
		q.bind(6, price);
		q.execute();
		giveWealth(u.id, -price);
	}

	void giveWealth(int userid, real price) {
		auto q = db.prepare("UPDATE users SET wealth = wealth + ? WHERE id = ?;");
		q.bind(1, price);
		q.bind(2, userid);
		q.execute();
	}

	auto usersActivePredictions(int userid) {
		SysTime now = Clock.currTime.toUTC;
		auto query = db.prepare(SQL_SELECT_PREDICTION_PREFIX~"WHERE creator == ? AND closes > ? ORDER BY closes;");
		query.bind(1, userid);
		query.bind(2, now.toISOExtString());
		return parsePredictionQuery(query.execute());
	}

	auto usersClosedPredictions(int userid) {
		SysTime now = Clock.currTime.toUTC;
		auto query = db.prepare(SQL_SELECT_PREDICTION_PREFIX~"WHERE creator == ? AND closes < ? ORDER BY closes;");
		query.bind(1, userid);
		query.bind(2, now.toISOExtString());
		return parsePredictionQuery(query.execute());
	}

	void setUserName(int userid, string name) {
		auto query = db.prepare("UPDATE users SET name=? WHERE id=?;");
		query.bind(1,name);
		query.bind(2,userid);
		query.execute();
	}
}

struct chance_change {
	string date;
	real chance;
	int shares;
	share_type type;
}

struct prediction {
	int id;
	string statement;
	int creator, yes_shares, no_shares;
	string created, closes, settled, result;
	chance_change[] changes;
	@disable this();
	this(int id, Database db) {
		auto query = db.prepare(SQL_SELECT_PREDICTION_PREFIX~"WHERE id = ?;");
		query.bind(1, id);
		foreach (row; query.execute()) {
			this.id = row.peek!int(0);
			assert (this.id == id);
			this.statement = row.peek!string(1);
			this.created = row.peek!string(2);
			this.creator = row.peek!int(3);
			this.closes  = row.peek!string(4);
			this.settled = row.peek!string(5);
			this.result = row.peek!string(6);
			break;
		}
		loadShares(db);
	}
	this(int id, string statement, string created, string closes, string settled, string result, Database db) {
		this.id = id;
		this.statement = statement;
		this.created = created;
		this.closes = closes;
		this.settled = settled;
		this.result = result;
		loadShares(db);
	}

	user getCreator(database db) {
		return db.getUser(this.creator);
	}

	private void loadShares(Database db) {
		changes ~= chance_change(created,0.5,0,share_type.balance);
		auto query = db.prepare("SELECT share_count, yes_order, date FROM orders WHERE prediction = ? ORDER BY date;");
		query.bind(1, id);
		foreach (row; query.execute()) {
			auto amount = row.peek!int(0);
			auto y = row.peek!int(1);
			share_type type;
			auto date = row.peek!string(2);
			if (y == 1) {
				yes_shares += amount;
				type = share_type.yes;
			} else {
				assert (y == 2);
				no_shares += amount;
				type = share_type.no;
			}
			changes ~= chance_change(date,this.chance,amount,type);
		}
		if (this.settled != "") {
			/* last element is the balancing of the creator during settlement */
			changes.length -= 1;
		}
	}

	int countShares(database db, user u, share_type t) {
		auto query = db.db.prepare("SELECT SUM(share_count) FROM orders WHERE prediction = ? AND user = ? AND yes_order = ?;");
		query.bind(1, this.id);
		query.bind(2, u.id);
		query.bind(3, t);
		return query.execute().oneValue!int;
	}

	void settle(database db, bool result) {
		//writeln("settle "~text(this.id)~" as "~text(result));
		/* mark prediction as settled now */
		{
			auto now = Clock.currTime.toUTC.toISOExtString;
			auto query = db.db.prepare("UPDATE predictions SET settled=?, result=? WHERE id=?;");
			query.bind(1, now);
			query.bind(2, result ? "yes" : "no");
			query.bind(3, this.id);
			query.execute();
			this.settled = now;
		}
		/* The market maker/creator has to balance the shares,
		   which means he buys shares until yes==no. */
		{
			auto amount = abs(yes_shares - no_shares);
			if (amount > 0) {
				auto t = yes_shares < no_shares ? share_type.yes : share_type.no;
				auto c = db.getUser(creator);
				db.buy(c, this, amount, t);
				//writeln("creator buys "~text(amount)~" shares of "~text(t));
			}
		}
		/* payout */
		{
			auto query = db.db.prepare("SELECT user, share_count FROM orders WHERE prediction=? AND yes_order=?;");
			query.bind(1, this.id);
			query.bind(2, result ? 1 : 2);
			int[int] shares;
			foreach (row; query.execute()) {
				auto userid = row.peek!int(0);
				auto amount = row.peek!int(1);
				//writeln("order "~text(amount)~" shares for "~text(userid));
				auto count = (userid in shares);
				if (count is null) {
					shares[userid] = amount;
				} else {
					*count  += amount;
				}
			}
			foreach (userid,amount; shares) {
				//writeln("payout: "~text(amount)~" to "~text(userid));
				db.giveWealth(userid, amount);
			}
		}
	}

	/* chance that statement happens according to current market */
	real chance() const pure @safe nothrow {
		return LMSR_chance(b, yes_shares, no_shares);
	}

	/* cost of buying a certain amount of shares */
	real cost(int amount, share_type t) pure const @safe nothrow {
		if (t == share_type.yes) {
			return LMSR_cost(b, yes_shares, no_shares, amount);
		} else {
			assert (t == share_type.no);
			return LMSR_cost(b, no_shares, yes_shares, amount);
		}
	}

	void toString(scope void delegate(const(char)[]) sink) const {
		sink("prediction(");
		sink(statement);
		sink(" ");
		sink.formattedWrite("%.2f%%", chance*100);
		sink(")");
	}
}

string emailPrefix(const(string) email) {
	auto r = findSplitBefore(email, "@");
	return r[0];
}

struct user {
	int id;
	string name, email;
	real wealth;
	@disable this();
	this(int id, string name, string email, real wealth) {
		assert (!isNaN(wealth));
		assert (wealth >= 0);
		this.id = id;
		this.name = name;
		this.email = email;
		this.wealth = wealth;
	}
	this(int id, Database db) {
		this.id = id;
		auto query = db.prepare("SELECT id, name, email, wealth FROM users WHERE id = ?");
		query.bind(1, id);
		foreach (row; query.execute()) {
			assert (id == row.peek!int(0));
			name = row.peek!string(1);
			email = row.peek!string(2);
			wealth = row.peek!double(3);
		}
	}
	this(const(string) email, Database db) {
		this.email = email;
		auto query = db.prepare("SELECT id, name, email, wealth FROM users WHERE email = ?");
		query.bind(1, email);
		foreach (row; query.execute()) {
			assert (email == row.peek!string(2));
			id = row.peek!int(0);
			name = row.peek!string(1);
			wealth = row.peek!double(3);
		}
		if (wealth != wealth) { // query returned zero rows
			wealth = 1000;
			name = emailPrefix(email);
			auto q = db.prepare("INSERT INTO users VALUES (NULL, ?, ?, ?);");
			q.bind(1, name);
			q.bind(2, email);
			q.bind(3, wealth);
			q.execute();
			//writeln("create user in db");
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
	auto db = getMemoryDatabase();
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

database getDatabase() {
	auto path = "prema.sqlite3";
	bool init = !exists(path);
	auto db = database(path);
	if (init) {
		init_empty_db(db.db);
		//auto user = db.getUser(1);
		//db.createPrediction("This app will actually be used.", "2016-02-02T05:45:55+00:00", user);
	}
	return db;
}

database getMemoryDatabase() {
	auto db = database(":memory:");
	init_empty_db(db.db);
	return db;
}

immutable real b = 100;
immutable real max_loss = b * log(2);

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
	auto db = getMemoryDatabase();
	auto user = db.getUser(1);
	auto end1 = SysTime.fromISOExtString("2015-02-02T05:45:55  +00:00");
	db.createPrediction("This app will actually be used.", end1, user);
	auto end2 = SysTime.fromISOExtString("2015-12-12T05:45:  55+00:00");
	db.createPrediction("Michelle Obama becomes president.", end2, user);
	SysTime now = Clock.currTime.toUTC;
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

unittest {
	auto db = getMemoryDatabase();
	auto user = db.getUser(1);
	auto stmt = "This app will be actually used.";
	db.createPrediction(stmt, "2015-02-02T05:45:55+00:00", user);
	auto admin = db.getUser(1);
	assert (admin.email == "root@localhost");
	auto pred = db.getPrediction(1);
	assert (pred.statement == stmt);
	void assert_roughly(real a, real b) {
		immutable real epsilon = 0.001;
		assert (a+epsilon > b && b > a-epsilon, text(a)~" !~ "~text(b));
	}
	assert (pred.yes_shares == 0, text(pred.yes_shares));
	assert (pred.no_shares == 0, text(pred.no_shares));
	assert_roughly (pred.chance, 0.5);
	auto price = pred.cost(10, share_type.no);
	assert_roughly (price, 5.1249);
	assert (pred.cost(10, share_type.yes) == price);
	db.buy(admin, pred, 10, share_type.no, price);
	assert (pred.cost(10, share_type.no) > price, text(pred.cost(10, share_type.no))~" !> "~text(price));
	/* check for database state */
	auto admin2 = db.getUser(1);
	auto pred2 = db.getPrediction(1);
	assert (pred.yes_shares == 0, text(pred.yes_shares));
	assert (pred.no_shares == 10, text(pred.no_shares));
	auto price2 = pred.cost(10, share_type.no);
	assert_roughly (price2, 5.37422);
}

