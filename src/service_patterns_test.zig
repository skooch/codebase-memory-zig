const std = @import("std");
const service_patterns = @import("service_patterns.zig");
const PatternKind = service_patterns.PatternKind;

test "classify http client" {
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("myproject:requests.get").?);
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("myproject:axios.post").?);
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("pkg:net/http.Get").?);
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("myproject:reqwest.Client.new").?);
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("lib:HttpClient.send").?);
    try std.testing.expectEqual(PatternKind.http_client, service_patterns.classify("myproject:HTTParty.get").?);
}

test "classify async broker" {
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("myproject:celery.delay").?);
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("myproject:pubsub.publish").?);
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("infra:kafka.Producer.send").?);
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("myproject:redis.publish").?);
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("workers:bullmq.Queue.add").?);
    try std.testing.expectEqual(PatternKind.async_broker, service_patterns.classify("myproject:SQS.sendMessage").?);
}

test "classify route registration" {
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("myproject:flask.route").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("myproject:gin.GET").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("web:express.Router.use").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:django.path").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("web:axum.route.post").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("myproject:gorilla/mux.HandleFunc").?);
}

test "route registration takes priority" {
    // "gin.GET" contains "GET" which could match http_client heuristics, but
    // route_registration patterns are checked first.
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:gin.GET").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:gin.POST").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:echo.DELETE").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:chi.Get").?);
    try std.testing.expectEqual(PatternKind.route_registration, service_patterns.classify("api:fiber.Post").?);
}

test "no match returns null" {
    try std.testing.expectEqual(@as(?PatternKind, null), service_patterns.classify("myproject:utils.formatDate"));
    try std.testing.expectEqual(@as(?PatternKind, null), service_patterns.classify("pkg:models.User.save"));
    try std.testing.expectEqual(@as(?PatternKind, null), service_patterns.classify("std.mem.indexOf"));
    try std.testing.expectEqual(@as(?PatternKind, null), service_patterns.classify(""));
}

test "httpMethod extraction" {
    try std.testing.expectEqualStrings("GET", service_patterns.httpMethod("requests.get").?);
    try std.testing.expectEqualStrings("GET", service_patterns.httpMethod("chi.Get").?);
    try std.testing.expectEqualStrings("GET", service_patterns.httpMethod("gin.GET").?);
    try std.testing.expectEqualStrings("POST", service_patterns.httpMethod("axios.post").?);
    try std.testing.expectEqualStrings("POST", service_patterns.httpMethod("echo.POST").?);
    try std.testing.expectEqualStrings("PUT", service_patterns.httpMethod("httpx.put").?);
    try std.testing.expectEqualStrings("DELETE", service_patterns.httpMethod("requests.delete").?);
    try std.testing.expectEqualStrings("PATCH", service_patterns.httpMethod("httpx.patch").?);
    try std.testing.expectEqualStrings("HEAD", service_patterns.httpMethod("requests.head").?);
    try std.testing.expectEqualStrings("OPTIONS", service_patterns.httpMethod("requests.options").?);
}

test "httpMethod no match" {
    try std.testing.expectEqual(@as(?[]const u8, null), service_patterns.httpMethod("myproject:utils.formatDate"));
    try std.testing.expectEqual(@as(?[]const u8, null), service_patterns.httpMethod("myproject:celery.delay"));
    try std.testing.expectEqual(@as(?[]const u8, null), service_patterns.httpMethod(""));
    // "fetch(" does not end with a method suffix
    try std.testing.expectEqual(@as(?[]const u8, null), service_patterns.httpMethod("globalThis.fetch("));
}
