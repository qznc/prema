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
		.post("/p/:predID", &change_prediction)
	;

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = [host];
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

void prediction(HTTPServerRequest req, HTTPServerResponse res)
{
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	string pageTitle = pred.statement;
	res.render!("prediction.dt", pageTitle, pred, req);
}

void get_create(HTTPServerRequest req, HTTPServerResponse res)
{
	auto time = Clock.currTime;
	auto suggested_end = (time + dur!"days"(7)).toISOExtString;
	string pageTitle = "Create New Prediction";
	string[] errors;
	res.render!("create.dt", pageTitle, suggested_end, errors, req);
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
	try {
		auto end_dt = SysTime.fromISOExtString(end);
		auto time = Clock.currTime;
		if (time > end_dt) {
			errors ~= "End date must be in the future.";
		}
	} catch (DateTimeException e) {
		errors ~= "End date in wrong format. Should be like 2015-11-20T19:23:34.1188658.";
	}
	if (errors.empty) {
		db.createPrediction(pred,end);
		res.redirect("/");
	} else {
		string pageTitle = "Create New Prediction";
		auto time = Clock.currTime;
		auto suggested_end = (time + dur!"days"(7)).toISOExtString;
		res.render!("create.dt", pageTitle, suggested_end, errors, req);
	}
}

void change_prediction(HTTPServerRequest req, HTTPServerResponse res)
{
	assert (req.method == HTTPMethod.POST);
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	auto email = req.session.get!string("userEmail");
	auto user = db.getUser(email);
	logInfo("change user="~to!string(user));
	auto amount = to!int(req.form["amount"]);
	auto type = req.form["type"] == "yes" ? share_type.yes : share_type.no;
	db.buy(user, pred, amount, type);
	string pageTitle = pred.statement;
	res.render!("prediction.dt", pageTitle, pred, req);
}

void show_user(HTTPServerRequest req, HTTPServerResponse res)
{
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto user = db.getUser(id);
	string pageTitle = user.name;
	res.render!("user.dt", pageTitle, user, req);
}

void verifyPersona(HTTPServerRequest req, HTTPServerResponse res)
{
	enforceHTTP("assertion" in req.form,
			HTTPStatus.badRequest, "Missing assertion field.");
	const ass = req.form["assertion"];
	const audience = "http://"~host~":8080/";
	logInfo("verifyPersona");

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
			string expires = answer["expires"].toString();
			string issuer = answer["issuer"].toString();
			string email = answer["email"].toString();
			auto session = res.startSession();
			session.set("userEmail", email);
			session.set("persona_expires", expires);
			session.set("persona_issuer", issuer);
			auto db = getDatabase();
			auto user = db.getUser(email);
			session.set("userId", user.id);
			session.set("userName", user.name);
			logInfo("Successfully logged in");
		});
	res.bodyWriter.write("ok");
}

void logout(HTTPServerRequest req, HTTPServerResponse res)
{
	if (req.session) {
		logInfo("logout: terminate session");
		res.terminateSession();
		res.redirect("/");
	} else {
		logInfo("nothing to logout");
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
	", MarkdownFlags.none);
	res.render!("plain.dt", pageTitle, text, req);
}
