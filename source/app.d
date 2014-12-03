/*
COPYRIGHT: 2014, Andreas Zwinkau <qznc@web.de>
LICENSE: http://www.apache.org/licenses/LICENSE-2.0
*/

import vibe.d;

shared static this()
{
	auto router = new URLRouter;
	router
		.get("/", &index)
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
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "Prema Prediction Market";
	res.render!("index.dt", pageTitle, req);
}

void protect(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "Internal Prema Prediction Market";
	res.render!("index.dt", pageTitle, req);
}

void login(HTTPServerRequest req, HTTPServerResponse res)
{
	enforceHTTP("username" in req.form && "password" in req.form,
			HTTPStatus.badRequest, "Missing username/password field.");

	// TODO verify user/password here

	auto session = res.startSession();
	session.set("username", req.form["username"]);
	session.set("password", req.form["password"]);
	res.redirect("/");
}

void logout(HTTPServerRequest req, HTTPServerResponse res)
{
	res.terminateSession();
	res.redirect("/");
}

void checkLogin(HTTPServerRequest req, HTTPServerResponse res)
{
	// force a redirect to / for unauthenticated users
	if (req.session)
		res.redirect("/");
}
