/*
COPYRIGHT: 2014, Andreas Zwinkau <qznc@web.de>
LICENSE: http://www.apache.org/licenses/LICENSE-2.0
*/

import vibe.d;
import model;
import std.conv : to, ConvException;

static immutable host = "127.0.0.1";
static immutable port = 8080;

shared static this()
{
    auto router = new URLRouter;
    // dfmt off
    router
        .get("/", &index)
        .get("/about", &about)
        .get("/highscores", &highscores)
        .get("/p/:predID", &prediction)
        .get("/u/:userID", &show_user)
        .post("/login", &verifyPersona)
        .any("/logout", &logout)
    ;
    // dfmt on

    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("/static/*", serveStaticFiles("./public/", fsettings));

    /* protected sites below */
    // dfmt off
    router
        .any("*", &checkLogin)
        .get("/create", &get_create)
        .post("/create", &post_create)
        .post("/settle", &post_settle)
        .post("/seen", &message_seen)
        .post("/p/:predID", &buy_shares)
        .post("/u/:userID", &show_user)
    ;
    // dfmt on

    version (unittest)
    {
        /* do not start server if unittesting */
    }
    else
    {
        auto settings = new HTTPServerSettings;
        settings.port = port;
        settings.bindAddresses = ["141.3.44.16", host];
        settings.sessionStore = new MemorySessionStore;
        listenHTTP(settings, router);
    }
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
    auto pageTitle = "Prema Prediction Market";
    auto db = getDatabase();
    auto active = db.activePredictions();
    auto toSettle = db.predictionsToSettle();
    res.render!("index.dt", pageTitle, active, toSettle, req);
}

void renderPrediction(model.prediction pred, database db, string[] errors,
    HTTPServerRequest req, HTTPServerResponse res)
{
    auto now = Clock.currTime;
    auto creator = db.getUser(pred.creator);
    string email = "@@";
    int your_yes_shares = 0;
    int your_no_shares = 0;
    predStats predStats;
    if (req.session)
    {
        email = req.session.get!string("userEmail");
        auto user = db.getUser(email);
        your_yes_shares = db.countPredShares(pred, user, share_type.yes);
        your_no_shares = db.countPredShares(pred, user, share_type.no);
        predStats = db.getUsersPredStats(user.id, pred.id);
    }
    bool can_settle = email == creator.email;
    auto closed = now > SysTime.fromISOExtString(pred.closes);
    auto settled = pred.settled !is null;
    auto pred_changes = db.getPredChanges(pred);
    string pageTitle = pred.statement;
    res.render!("prediction.dt", pageTitle, pred, creator, closed, settled,
        pred_changes, can_settle, predStats, your_yes_shares, your_no_shares, errors,
        req);
}

void prediction(HTTPServerRequest req, HTTPServerResponse res)
{
    auto id = to!int(req.params["predID"]);
    auto db = getDatabase();
    auto pred = db.getPrediction(id);
    string[] errors;
    renderPrediction(pred, db, errors, req, res);
}

void highscores(HTTPServerRequest req, HTTPServerResponse res)
{
    string pageTitle = "Highscores";
    auto db = getDatabase();
    res.render!("highscores.dt", pageTitle, req);
}

void get_create(HTTPServerRequest req, HTTPServerResponse res)
{
    auto time = Clock.currTime.toUTC;
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
    auto b = req.form["b"];
    string[] errors;
    if (pred == "")
        errors ~= "Prediction empty.";
    if (end == "")
        errors ~= "End date empty.";
    int b_parsed;
    try
    {
        b_parsed = b.to!int;
    }
    catch (ConvException e)
    {
        errors ~= "Parameter b has wrong format.";
    }
    if (b_parsed < 10)
        errors ~= "Parameter b must be at least 10.";
    if (b_parsed > 200)
        errors ~= "Parameter b must be at most 200.";
    SysTime end_parsed;
    try
    {
        /* HTML5 browsers miss the seconds */
        end_parsed = SysTime.fromISOExtString(end ~ ":00").toUTC;
    }
    catch (DateTimeException e)
    {
        try
        {
            /* Firefox provides a text field */
            end_parsed = SysTime.fromISOExtString(end).toUTC;
        }
        catch (DateTimeException e)
        {
            errors ~= "End date in wrong format. Should be like 2015-11-20T19:23:34.118865Z.";
        }
    }
    auto now = Clock.currTime.toUTC;
    if (now > end_parsed)
    {
        errors ~= "End date must be in the future.";
    }
    if (errors.empty)
    {
        auto email = req.session.get!string("userEmail");
        auto user = db.getUser(email);
        auto last = db.lastPredCreateDateBy(user);
        db.createPrediction(b_parsed, pred, end_parsed, user);
        auto diff = now - last;
        if (diff.total!"hours" >= 24*2 + 23)
        {
            db.cashBonus(user, credits(5), "Bonus is given every three days if you create a prediction.");
        } else {
            logInfo("no cash bonus for "~text(user)~" because diff="~text(diff.total!"hours")~"h");
        }
        res.redirect("/");
    }
    else
    {
        string pageTitle = "Create New Prediction";
        auto suggested_end = (now + dur!"days"(7)).toISOExtString;
        res.render!("create.dt", pageTitle, suggested_end, errors, req);
    }
}

void buy_shares(HTTPServerRequest req, HTTPServerResponse res)
{
    assert(req.method == HTTPMethod.POST);
    string[] errors;
    int amount;
    try
    {
        amount = to!int(req.form["amount"]);
        if (amount == 0)
            errors ~= "Cannot buy zero shares";
    }
    catch (ConvException)
    {
        amount = 0;
        errors ~= "Wrong format for amount of shares. Must be integer.";
    }
    auto id = to!int(req.params["predID"]);
    auto db = getDatabase();
    auto pred = db.getPrediction(id);
    auto email = req.session.get!string("userEmail");
    auto user = db.getUser(email);
    auto type = req.form["type"] == "yes" ? share_type.yes : share_type.no;
    auto count = db.countPredShares(pred, user, type);
    if (count + amount < 0)
        errors ~= "You only have " ~ text(count) ~ " shares.";
    auto price = pred.cost(amount, type);
    auto cash = db.getCash(user.id);
    if (cash < price)
        errors ~= "That would have cost " ~ text(price) ~ ", but you only have " ~ text(cash) ~ ".";
    if (errors.empty)
    {
        auto last = db.lastTransactionDateBy(user);
        db.buy(user.id, id, amount, type, price);
        auto now = Clock.currTime.toUTC;
        auto diff = now - last;
        if (diff.total!"hours" >= 23)
        {
            db.cashBonus(user, credits(10), "Bonus is given once per day if you order something.");
        } else {
            logInfo("no cash bonus for "~text(user)~" because diff="~text(diff.total!"hours")~"h");
        }
        res.redirect(req.path);
    }
    else
    {
        renderPrediction(pred, db, errors, req, res);
    }
}

void post_settle(HTTPServerRequest req, HTTPServerResponse res)
{
    assert(req.method == HTTPMethod.POST);
    assert(req.session);
    auto id = to!int(req.form["predid"]);
    auto db = getDatabase();
    auto pred = db.getPrediction(id);
    auto email = req.session.get!string("userEmail");
    auto user = db.getUser(email);
    enforceHTTP(user.id == pred.creator, HTTPStatus.badRequest, "only creator can settle");
    auto result = req.form["settlement"] == "true";
    db.settle(pred.id, result);
    res.redirect("/p/" ~ text(pred.id));
}

void message_seen(HTTPServerRequest req, HTTPServerResponse res)
{
    enforceHTTP(req.method == HTTPMethod.POST, HTTPStatus.badRequest, "only POST accepted");
    assert(req.session);
    auto mid = to!int(req.form["mid"]);
    auto db = getDatabase();
    db.markMessageSeen(mid);
    res.redirect("/");
}

void show_user(HTTPServerRequest req, HTTPServerResponse res)
{
    auto id = to!int(req.params["userID"]);
    auto db = getDatabase();
    auto user = db.getUser(id);
    if (req.method == HTTPMethod.POST)
    {
        enforceHTTP(req.session, HTTPStatus.badRequest, "must be logged in to change name");
        auto email = req.session.get!string("userEmail");
        enforceHTTP(email == user.email, HTTPStatus.badRequest,
            "you can only change your own name");
        auto new_name = req.form["new_name"];
        db.setUserName(id, new_name);
    }
    string pageTitle = user.name;
    auto cash = db.getCash(id);
    auto predsActive = db.usersActivePredictions(id);
    auto predsClosed = db.usersClosedPredictions(id);
    res.render!("user.dt", pageTitle, user, cash, predsActive, predsClosed, req);
}

void verifyPersona(HTTPServerRequest req, HTTPServerResponse res)
{
    enforceHTTP("assertion" in req.form, HTTPStatus.badRequest, "Missing assertion field.");
    const ass = req.form["assertion"];
    const audience = "http://" ~ (req.host) ~ "/";
    if (req.session)
    {
        logInfo("session already started for " ~ req.session.get!string("userEmail"));
        return;
    }
    logInfo("verifyPersona");

    requestHTTP("https://verifier.login.persona.org/verify", (scope req) {
        req.method = HTTPMethod.POST;
        req.contentType = "application/x-www-form-urlencoded";
        auto bdy = "assertion=" ~ ass ~ "&audience=" ~ audience;
        req.bodyWriter.write(bdy);
        logInfo("verifying login at persona.org. audience="~text(audience));
    }, (scope res2) {
        logInfo("persona server responded");
        auto answer = res2.readJson();
        logInfo("json read: "~text(answer));
        enforceHTTP(answer["status"] == "okay", HTTPStatus.badRequest, "Verification failed.");
        logInfo("persona status: "~text(answer["status"]));
        enforceHTTP(answer["audience"] == audience, HTTPStatus.badRequest, "Verification failed.");
        logInfo("persona audience: "~text(answer["audience"]));
        string expires = answer["expires"].to!string;
        string issuer = answer["issuer"].to!string;
        string email = answer["email"].to!string;
        logInfo("start session for " ~ email);
        auto session = res.startSession();
        session.set("userEmail", email);
        session.set("persona_expires", expires);
        session.set("persona_issuer", issuer);
        auto db = getDatabase();
        auto user = db.getUser(email);
        session.set("userId", user.id);
        session.set("userName", user.name);
        logInfo("Successfully logged in " ~ text(user.name));
    });
    res.bodyWriter.write("ok");
}

void logout(HTTPServerRequest req, HTTPServerResponse res)
{
    if (req.session)
    {
        logInfo("logout: terminate session for " ~ req.session.get!string("userEmail"));
        res.terminateSession();
        res.redirect("/");
    }
    else
    {
        res.statusCode = HTTPStatus.badRequest;
        res.bodyWriter.write("nothing to logout");
    }
}

void checkLogin(HTTPServerRequest req, HTTPServerResponse res)
{
    if (req.session)
        return;
    /* not authenticated! */
    logInfo("checkLogin failed: " ~ req.path);
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
One share costs at most 1.00¢.
How much exactly depends on the market.
When the prediction is closed and settled,
you get 1.00¢ for each correct share.

For example,
we have a prediction, which is currently at 70%.
You could buy a yes-share for 0.70¢.
If it turns out true, you get 1.00¢ back,
which is a profit of 0.30¢.
In contrast, a no-share costs 0.30¢
and promises a profit of 0.70¢.
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
	",
        MarkdownFlags.none);
    res.render!("plain.dt", pageTitle, text, req);
}
