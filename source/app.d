/*
COPYRIGHT: 2014, Andreas Zwinkau <qznc@web.de>
LICENSE: http://www.apache.org/licenses/LICENSE-2.0
*/

import vibe.d;
static import vibe.textfilter.markdown;
import model;
import std.conv : text, to, ConvException;
import std.process : environment;

static immutable host = "127.0.0.1";
static immutable port = 8080;

static immutable WEEKLY_TAX_RATE = 0.05;

shared static this()
{
    auto router = new URLRouter;
    // dfmt off
    router
        .any("*", &weeklyTax)
        .get("/", &index)
        .get("/about", &about)
        .get("/highscores", &highscores)
        .get("/p/:predID", &prediction)
        .get("/u/:userID", &show_user)
        .get("/predictions.atom", &feed_predictions)
        .any("/login", &loginGithub)
        .any("/github_authorized", &githubCallback)
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
    int userId = -1;
    int your_yes_shares = 0;
    int your_no_shares = 0;
    predStats predStats;
    if (req.session)
    {
        userId = req.session.get!int("userId");
        auto user = db.getUser(userId);
        your_yes_shares = db.countPredShares(pred, user, transaction_type.yes);
        your_no_shares = db.countPredShares(pred, user, transaction_type.no);
        predStats = db.getUsersPredStats(user.id, pred.id);
    }
    bool can_settle = userId == creator.id;
    auto closed = now > SysTime.fromISOExtString(pred.closes);
    auto settled = pred.settled != "";
    logInfo("settled: " ~ text(settled) ~ " p/" ~ text(pred.id));
    auto pred_changes = db.getPredChanges(pred);
    string pageTitle = pred.statement;
    res.render!("prediction.dt", pageTitle, pred, creator, closed, settled,
            pred_changes, can_settle, predStats, your_yes_shares, your_no_shares, errors, req);
}

void prediction(HTTPServerRequest req, HTTPServerResponse res)
{
    auto id = to!int(req.params["predID"]);
    auto db = getDatabase();
    try
    {
        auto pred = db.getPrediction(id);
        string[] errors;
        renderPrediction(pred, db, errors, req, res);
    }
    catch (NoSuchPrediction e)
    {
        logInfo("no prediction " ~ text(id));
        auto pageTitle = "No such prediction";
        auto text = "Sorry. Prediction " ~ text(id) ~ " does not exist.";
        res.statusCode = HTTPStatus.badRequest;
        res.render!("plain.dt", pageTitle, text, req);
    }
}

void feed_predictions(HTTPServerRequest req, HTTPServerResponse res)
{
    auto pageTitle = "Prema Active Predictions";
    auto db = getDatabase();
    auto preds = db.activePredictions();
    string last_update;
    foreach (pred; preds)
    {
        if (pred.created > last_update)
            last_update = pred.created;
    }
    res.render!("atom.dt", pageTitle, preds, req, last_update);
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
        auto userId = req.session.get!int("userId");
        auto user = db.getUser(userId);
        auto last = db.lastPredCreateDateBy(user);
        db.createPrediction(b_parsed, pred, end_parsed, user);
        auto diff = now - last;
        if (diff.total!"hours" >= 24 * 6 + 23)
        {
            db.cashBonus(user, credits(5),
                    "Bonus is given every week if you create a prediction.");
        }
        else
        {
            logInfo("no create cash bonus for " ~ text(
                    user.id) ~ " because diff=" ~ text(diff.total!"hours") ~ "h");
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
    enforceHTTP(pred.settled == "", HTTPStatus.badRequest,
            "Cannot buy shares of settled predictions");
    auto userId = req.session.get!int("userId");
    auto user = db.getUser(userId);
    auto type = req.form["type"] == "yes" ? transaction_type.yes : transaction_type.no;
    auto count = db.countPredShares(pred, user, type);
    if (count + amount < 0)
        errors ~= "You only have " ~ text(count) ~ " shares.";
    auto price = pred.cost(amount, type);
    import std.math : abs;

    auto tax = millicredits(abs(price.amount * 1 / 100));
    auto full_price = millicredits(price.amount + tax.amount);
    auto cash = db.getCash(user.id);
    if (cash < full_price)
        errors ~= "That would have cost " ~ text(
                price + tax) ~ ", but you only have " ~ text(cash) ~ ".";
    if (errors.empty)
    {
        auto last = db.lastTransactionDateBy(user);
        db.buy(user.id, id, amount, type, price);
        if (user.id != pred.creator)
        {
            logInfo("tax " ~ text(tax) ~ " from " ~ text(user.id) ~ " to " ~ text(pred.creator));
            db.transferMoney(user.id, pred.creator, tax, pred.id, transaction_type.share_tax);
        }
        auto now = Clock.currTime.toUTC;
        auto diff = now - last;
        if (diff.total!"hours" >= 23)
        {
            db.cashBonus(user, credits(1),
                    "Bonus is given every days if you buy or sell something.");
        }
        else
        {
            logInfo("no buy cash bonus for " ~ text(
                    user.id) ~ " because diff=" ~ text(diff.total!"hours") ~ "h");
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
    auto userId = req.session.get!int("userId");
    auto user = db.getUser(userId);
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
    try
    {
        auto user = db.getUser(id);
        string pageTitle = user.name;
        auto cash = db.getCash(id);
        auto predsActive = db.usersActivePredictions(id);
        auto predsClosed = db.usersClosedPredictions(id);
        res.render!("user.dt", pageTitle, user, cash, predsActive, predsClosed, req);
    }
    catch (NoSuchUser e)
    {
        logInfo("no user " ~ text(id));
        auto pageTitle = "No such user";
        auto text = "Sorry. User " ~ text(id) ~ " does not exist.";
        res.statusCode = HTTPStatus.badRequest;
        res.render!("plain.dt", pageTitle, text, req);
    }
}

/* Github Auth 1: Send user to Github */
void loginGithub(HTTPServerRequest req, HTTPServerResponse res)
{
    auto url = "https://github.com/login/oauth/authorize?scope=user:email&client_id="
        ~ environment.get("GH_BASIC_CLIENT_ID", "id-unknown");
    logInfo("redirect to github auth");
    res.redirect(url);
}

/* Github Auth 2: User comes back from Github with token */
void githubCallback(HTTPServerRequest req, HTTPServerResponse res)
{
    auto code = req.query.get("code", "nope");
    auto url = "https://github.com/login/oauth/access_token";
    requestHTTP(url, (scope req) {
        logInfo("check token with Github");
        req.method = HTTPMethod.POST;
        req.headers["Accept"] = "application/json";
        req.contentType = "application/x-www-form-urlencoded";
        auto bdy = "client_id=" ~ environment.get("GH_BASIC_CLIENT_ID",
            "id-unknown") ~ "&client_secret=" ~ environment.get("GH_BASIC_CLIENT_SECRET",
            "secret-unknown") ~ "&code=" ~ code;
        req.bodyWriter.write(bdy);
    }, (scope res2) {
        logInfo("got answer from Github");
        if (!res2.statusCode == 200)
        {
            logWarn("Error: " ~ text(res2.statusCode));
            return;
        }
        assert(res2.contentType == "application/json; charset=utf-8");
        auto json = res2.readJson();
        if ("error" in json)
        {
            logInfo(text(json["error_description"]));
            logInfo(text(json["error_uri"]));
            return;
        }
        logInfo("authenticated :)");
        auto access_token = json["access_token"].get!string;
        auto session = res.startSession();
        session.set("github_access_token", access_token);
        requestHTTP("https://api.github.com/user?access_token=" ~ access_token, (scope req) {
            req.method = HTTPMethod.GET;
            req.headers["Accept"] = "application/json";
        }, (scope res3) {
            logInfo("got info from Github");
            if (!res3.statusCode == 200)
            {
                logWarn("Error: " ~ text(res3.statusCode));
                res.terminateSession();
                return;
            }
            assert(res3.contentType == "application/json; charset=utf-8");
            logInfo("... successfully");
            auto json = res3.readJson();
            auto nick = json["login"].get!string;
            auto db = getDatabase();
            auto user = db.getUser(nick);
            session.set("userId", user.id);
            session.set("userName", user.name);
        });
    });
    res.redirect("/");
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
One share costs at most 1.00¢ plus 1% tax.
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
If others buy shares on your prediction you get the tax.
Note that the creator of a prediction has to balance the market,
when it is settled.
So you might lose some money by creating predictions.
You might also win some,
if most traders are wrong
or you get enough taxes.
This also means,
the creator does not gain or lose any money,
if nobody else trades on a prediction.

There is a **weekly tax** of 5%.
Cash above 900¢ is taxes.
You can also receive a (negative) tax,
if your cash is below 500¢.
Notice that only cash is taxed, but not shares.
This means, you should invest your money instead of keeping the cash.

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

void weeklyTax(HTTPServerRequest req, HTTPServerResponse res)
{
    // TODO cache decision to avoid database accesses?
    doWeeklyTax(WEEKLY_TAX_RATE);
}
