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
		.get("*", serveStaticFiles("./public/"))
	;

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
	auto pageTitle = "Prema Prediction Market";
	res.render!("index.dt", pageTitle, req);
}
