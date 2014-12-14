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
		.get("/p/:predID", &prediction)
		.post("/login", &verifyPersona)
		.any("/logout", &logout)
	;

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = "/static";
	router.get("/static/*", serveStaticFiles("./public/", fsettings));

	/* protected sites below */
	router
		.any("*", &checkLogin)
		.get("/protect", &protect)
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
	if (req.session) {
		logInfo("index logged in");
	}
	auto db = getDatabase();
	auto predictions = db.predictions;
	res.render!("index.dt", pageTitle, predictions, req);
}

void protect(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "Internal Prema Prediction Market";
	auto db = getDatabase();
	auto predictions = db.predictions;
	res.render!("index.dt", pageTitle, predictions, req);
}

void prediction(HTTPServerRequest req, HTTPServerResponse res)
{
	auto id = to!int(req.params["predID"]);
	auto db = getDatabase();
	auto pred = db.getPrediction(id);
	string pageTitle = pred.statement;
	res.render!("prediction.dt", pageTitle, pred, req);
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
