/*
COPYRIGHT: 2014, Andreas Zwinkau <qznc@web.de>
LICENSE: http://www.apache.org/licenses/LICENSE-2.0
*/

import vibe.d;
import model;
import std.conv: to;

static immutable host = "127.0.0.1";

shared static this()
{
	auto router = new URLRouter;
	router
		.get("/", &index)
		.get("/about", &about)
		.get("/p/:predID", &prediction)
		.get("/u/:predID", &show_user)
		.post("/login", &verifyPersona)
		.any("/logout", &logout)
	;

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = "/static";
	router.get("/static/*", serveStaticFiles("./public/", fsettings));

	/* protected sites below */
	router
		.any("*", &checkLogin)
		.get("/create", &get_create)
		.post("/create", &post_create)
		.post("/settle", &post_settle)
		.post("/p/:predID", &buy_shares)
	;

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["141.3.44.16", host];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://"~host~":8080/ in your browser.");
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "Prema Prediction Market";
	auto db = getDatabase();
	auto active = db.activePredictions();
	auto toSettle = db.predictionsToSettle();
	res.render!("index.dt", pageTitle, active, toSettle, req);
}

void renderPrediction(
	model.prediction pred,
	database db,
	string[] errors,
	HTTPServerRequest req, HTTPServerResponse res)
{
	auto now = Clock.currTime;
	auto creator = pred.getCreator(db);
	string email = "@@";
	if (req.session)
		email = req.session.get!string("userEmail");
	bool can_settle = email == creator.email;
	auto closed = now > SysTime.fromISOExtString(pred.closes);
	auto settled = pred.settled !is null;
	string pageTitle = pred.statement;
	res.render!("prediction.dt", pageTitle, pred, creator, closed, settled, can_settle, errors, req);
}

void prediction(HTTPServerRequest req, HTTPServerResponse res)
{
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	string[] errors;
	renderPrediction(pred, db, errors, req, res);
}

void get_create(HTTPServerRequest req, HTTPServerResponse res)
{
	auto time = Clock.currTime.toUTC;
	auto suggested_end = (time + dur!"days"(7)).toISOExtString;
	string pageTitle = "Create New Prediction";
	string[] errors;
	res.render!("create.dt", pageTitle, suggested_end, errors, max_loss, req);
}

void post_create(HTTPServerRequest req, HTTPServerResponse res)
{
	auto db = getDatabase();
	auto pred = req.form["prediction"];
	auto end = req.form["end"];
	string[] errors;
	if (pred == "")
		errors ~= "Prediction empty.";
	if (end == "")
		errors ~= "End date empty.";
	SysTime end_parsed;
	try {
		/* HTML5 browsers miss the seconds */
		end_parsed = SysTime.fromISOExtString(end~":00").toUTC;
	} catch(DateTimeException e) try {
		/* Firefox provides a text field */
		end_parsed = SysTime.fromISOExtString(end).toUTC;
	} catch(DateTimeException e) {
		errors ~= "End date in wrong format. Should be like 2015-11-20T19:23:34.118865Z.";
	}
	auto now = Clock.currTime.toUTC;
	if (now > end_parsed) {
		errors ~= "End date must be in the future.";
	}
	if (errors.empty) {
		auto email = req.session.get!string("userEmail");
		auto user = db.getUser(email);
		db.createPrediction(pred,end_parsed,user);
		res.redirect("/");
	} else {
		string pageTitle = "Create New Prediction";
		auto suggested_end = (now + dur!"days"(7)).toISOExtString;
		res.render!("create.dt", pageTitle, suggested_end, errors, max_loss, req);
	}
}

void buy_shares(HTTPServerRequest req, HTTPServerResponse res)
{
	assert (req.method == HTTPMethod.POST);
	string[] errors;
	auto amount = to!int(req.form["amount"]);
	if (amount == 0)
		errors ~= "Cannot buy zero shares";
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	auto email = req.session.get!string("userEmail");
	auto user = db.getUser(email);
	auto type = req.form["type"] == "yes" ? share_type.yes : share_type.no;
	auto count = pred.countShares(db, user, type);
	if (count+amount < 0)
		errors ~= "You only have "~text(count)~" shares.";
	auto price = pred.cost(amount,type);
	if (user.wealth < price)
		errors ~= "That would have cost "~text(price)~"€, but you only have "~text(user.wealth)~"€.";
	if (errors.empty) {
		db.buy(user, pred, amount, type);
		res.redirect(req.path);
	} else {
		renderPrediction(pred, db, errors, req, res);
	}
}

void post_settle(HTTPServerRequest req, HTTPServerResponse res)
{
	assert (req.method == HTTPMethod.POST);
	assert (req.session);
	auto id = to!int(req.form["predid"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	auto email = req.session.get!string("userEmail");
	auto user = db.getUser(email);
	enforceHTTP(user.id == pred.creator,
		HTTPStatus.badRequest, "only creator can settle");
	auto result = req.form["settlement"] == "true";
	pred.settle(db, result);
	res.redirect("/p/"~text(pred.id));
}

void show_user(HTTPServerRequest req, HTTPServerResponse res)
{
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto user = db.getUser(id);
	string pageTitle = user.name;
	auto predsActive = db.usersActivePredictions(id);
	auto predsClosed = db.usersClosedPredictions(id);
	res.render!("user.dt", pageTitle, user, predsActive, predsClosed, req);
}

void verifyPersona(HTTPServerRequest req, HTTPServerResponse res)
{
	enforceHTTP("assertion" in req.form,
			HTTPStatus.badRequest, "Missing assertion field.");
	const ass = req.form["assertion"];
	const audience = "http://"~(req.host)~":8080/";

	requestHTTP("https://verifier.login.persona.org/verify",
		(scope req) {
			req.method = HTTPMethod.POST;
			req.contentType = "application/x-www-form-urlencoded";
			auto bdy = "assertion="~ass~"&audience="~audience;
			req.bodyWriter.write(bdy);
		},
		(scope res2) {
			auto answer = res2.readJson();
			enforceHTTP(answer["status"] == "okay",
				HTTPStatus.badRequest, "Verification failed.");
			enforceHTTP(answer["audience"] == audience,
				HTTPStatus.badRequest, "Verification failed.");
			string expires = answer["expires"].to!string;
			string issuer = answer["issuer"].to!string;
			string email = answer["email"].to!string;
			logInfo("start session for "~email);
			auto session = res.startSession();
			session.set("userEmail", email);
			session.set("persona_expires", expires);
			session.set("persona_issuer", issuer);
			auto db = getDatabase();
			auto user = db.getUser(email);
			session.set("userId", user.id);
			session.set("userName", user.name);
			logInfo("Successfully logged in "~text(user.name));
		});
	res.bodyWriter.write("ok");
}

void logout(HTTPServerRequest req, HTTPServerResponse res)
{
	if (req.session) {
		logInfo("logout: terminate session for "~req.session.get!string("userEmail"));
		res.terminateSession();
		res.redirect("/");
	} else {
		res.statusCode = HTTPStatus.badRequest;
		res.bodyWriter.write("nothing to logout");
	}
}

void checkLogin(HTTPServerRequest req, HTTPServerResponse res)
{
	if (req.session) return;
	/* not authenticated! */
	logInfo("checkLogin failed: "~req.path);
	auto pageTitle = "Authentication Error";
	res.statusCode = HTTPStatus.forbidden;
	res.bodyWriter.write(pageTitle);
}

void about(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "About Prema Prediction Market";
	auto text = vibe.textfilter.markdown.filterMarkdown("
Prema implements a [prediction market](https://en.wikipedia.org/wiki/Prediction_market).
People input predictions and then buy and sell shares on them,
similar to a stock market.
Each prediction has 'yes' and 'no' shares with their prices linked.
When a prediction can be verified,
either yes or no shares get paid.
So, buy those shares which you believe will be true
and become rich (with play money).

The price of the shares corresponds to a probability that the prediction is true.
If many people participate,
those probabilities tend to be very accurate.

## How to Play?

There are various predictions listed in the overview.
Pick one.
Then buy 'yes' or 'no' shares depending on
whether you think the prediction will turn out true or false.
One share costs at most 1.00€.
How much exactly depends on the market.
When the prediction is closed and settled,
you get 1.00€ for each correct share.

For example,
we have a prediction, which is currently at 70%.
You could buy a yes-share for 0.70€.
If it turns out true, you get 1.00€ back,
which is a profit of 0.30€.
In contrast, a no-share costs 0.30€
and promises a profit of 0.70€.
In gambling terms,
these are odds slightly above 1:2.3.

You can sell shares by 'buying' negative amounts.

You can [create your own predictions](/create)
and everybody can then trade on them.
Note that the creator of a prediction has to balance the market,
when it is settled.
So you might lose some money by creating predictions.
You might also win some,
if most traders are wrong.
This also means,
the creator does not gain or lose any money,
if nobody else trades on a prediction.

## How to Interpret the Price?

The price of one share corresponds to the chance
the market considers for the prediction to turn out true.

Apart from being gambling fun,
prediction markets encourage insider trading.
If you know more about certain predictions,
you can profit from this knowledge.
In return, the public gets a more accurate forecast.
	", MarkdownFlags.none);
	res.render!("plain.dt", pageTitle, text, req);
}
