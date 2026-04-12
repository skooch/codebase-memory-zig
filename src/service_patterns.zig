// service_patterns.zig — Classify resolved call targets into service interaction patterns.
//
// Ported from the C original's service_patterns.c. Recognises HTTP client calls,
// async/message-broker calls, and route-registration calls via case-sensitive
// substring matching against known library patterns.

const std = @import("std");

pub const PatternKind = enum {
    http_client,
    async_broker,
    route_registration,
};

// ---------------------------------------------------------------------------
// Pattern tables (comptime)
// ---------------------------------------------------------------------------

const route_registration_patterns: []const []const u8 = &.{
    "flask.route",
    "flask.add_url_rule",
    "app.route",
    "router.route",
    "express.Router",
    "express.route",
    "fastify.route",
    "fastify.register",
    "koa.router",
    "hono.route",
    "hapi.route",
    "gin.Handle",
    "gin.GET",
    "gin.POST",
    "gin.PUT",
    "gin.DELETE",
    "gin.PATCH",
    "chi.Route",
    "chi.Get",
    "chi.Post",
    "chi.Put",
    "chi.Delete",
    "gorilla/mux.HandleFunc",
    "gorilla/mux.Handle",
    "echo.GET",
    "echo.POST",
    "echo.PUT",
    "echo.DELETE",
    "fiber.Get",
    "fiber.Post",
    "actix_web.route",
    "axum.route",
    "rocket.route",
    "starlette.route",
    "django.path",
    "django.url",
    "laravel.route",
    "symfony.route",
};

const http_client_patterns: []const []const u8 = &.{
    "requests.get",
    "requests.post",
    "requests.put",
    "requests.delete",
    "requests.patch",
    "requests.head",
    "requests.options",
    "requests.request",
    "httpx.get",
    "httpx.post",
    "httpx.put",
    "httpx.delete",
    "httpx.patch",
    "httpx.request",
    "aiohttp.ClientSession",
    "aiohttp.request",
    "urllib.request",
    "urllib3.request",
    "axios.get",
    "axios.post",
    "axios.put",
    "axios.delete",
    "axios.patch",
    "axios.request",
    "axios.create",
    "superagent.get",
    "superagent.post",
    "node-fetch",
    "undici.fetch",
    "undici.request",
    "fetch(",
    "net/http.Get",
    "net/http.Post",
    "net/http.Do",
    "resty.R",
    "resty.New",
    "HttpClient",
    "OkHttpClient",
    "okhttp3",
    "RestTemplate",
    "WebClient",
    "reqwest.get",
    "reqwest.Client",
    "hyper.Client",
    "HTTParty",
    "Faraday",
    "RestClient",
};

const async_broker_patterns: []const []const u8 = &.{
    "cloudtasks",
    "cloud.tasks",
    "pubsub",
    "PubSub",
    "pub_sub",
    "sqs",
    "SQS",
    "sns",
    "SNS",
    "eventbridge",
    "EventBridge",
    "lambda.invoke",
    "Lambda.invoke",
    "step_functions",
    "StepFunctions",
    "kafka",
    "Kafka",
    "rabbitmq",
    "RabbitMQ",
    "amqp",
    "AMQP",
    "nats",
    "NATS",
    "redis.publish",
    "Redis.publish",
    "redis.lpush",
    "redis.rpush",
    "celery.task",
    "celery.send_task",
    "celery.delay",
    "dramatiq.actor",
    "dramatiq.send",
    "huey.task",
    "rq.Queue",
    "rq.enqueue",
    "bullmq",
    "BullMQ",
    "bull.Queue",
    "sidekiq",
    "Sidekiq",
    "resque",
    "Resque",
    "temporal.workflow",
    "temporal.activity",
    "inngest.send",
    "inngest.create_function",
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Classify a resolved qualified name into one of the known service-interaction
/// patterns.  Returns `null` when no pattern matches.
///
/// Route-registration patterns are checked first so that names like "gin.GET"
/// are correctly classified as route registrations rather than HTTP client calls.
pub fn classify(qualified_name: []const u8) ?PatternKind {
    for (route_registration_patterns) |pat| {
        if (std.mem.indexOf(u8, qualified_name, pat) != null)
            return .route_registration;
    }
    for (http_client_patterns) |pat| {
        if (std.mem.indexOf(u8, qualified_name, pat) != null)
            return .http_client;
    }
    for (async_broker_patterns) |pat| {
        if (std.mem.indexOf(u8, qualified_name, pat) != null)
            return .async_broker;
    }
    return null;
}

/// Infer an HTTP method from the trailing component of a qualified name.
///
/// The match is suffix-based: the QN must end with `.<Method>` in one of the
/// three conventional casings (lower, Title, UPPER).  Returns a canonical
/// upper-case method string or `null` if nothing matches.
pub fn httpMethod(qualified_name: []const u8) ?[]const u8 {
    const Method = struct {
        suffixes: []const []const u8,
        canonical: []const u8,
    };

    const methods: []const Method = &.{
        .{ .suffixes = &.{ ".get", ".Get", ".GET" }, .canonical = "GET" },
        .{ .suffixes = &.{ ".post", ".Post", ".POST" }, .canonical = "POST" },
        .{ .suffixes = &.{ ".put", ".Put", ".PUT" }, .canonical = "PUT" },
        .{ .suffixes = &.{ ".delete", ".Delete", ".DELETE" }, .canonical = "DELETE" },
        .{ .suffixes = &.{ ".patch", ".Patch", ".PATCH" }, .canonical = "PATCH" },
        .{ .suffixes = &.{ ".head", ".Head", ".HEAD" }, .canonical = "HEAD" },
        .{ .suffixes = &.{ ".options", ".Options", ".OPTIONS" }, .canonical = "OPTIONS" },
    };

    for (methods) |m| {
        for (m.suffixes) |suffix| {
            if (std.mem.endsWith(u8, qualified_name, suffix))
                return m.canonical;
        }
    }
    return null;
}
