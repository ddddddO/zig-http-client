const std = @import("std");
const log = std.log;
const testing = std.testing;

const Request = @import("request.zig").Request;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;

pub const HttpClient = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) HttpClient {
        return HttpClient{
            .allocator = allocator,
        };
    }

    pub fn req(self: HttpClient) Request {
        return Request{
            .allocator = self.allocator,
            .headers = std.ArrayList(u8).init(self.allocator),
            .body = null,
        };
    }
};

test "usage" {
    const allocator = testing.allocator;

    // TODO: ローカルのサーバーを用意する
    const host = "www.google.com";
    // const host = "www.yahoo.co.jp";

    const client = HttpClient.init(allocator);
    const res = try client.req()
        .setHeader("Accept: text/html")
        .get(host);
    defer res.deinit();

    try testing.expect(std.mem.eql(u8, "HTTP/1.1 200 OK", res.statusLine()));
    try testing.expect(std.mem.eql(u8, "200", res.statusCode()));
    try testing.expect(std.mem.eql(u8, "OK", res.status()));

    try testing.expect(res.raw().len > 0);
    try testing.expect(res.rawHeaders().len > 0);
    try testing.expect(res.rawBody().len > 0);
}

// Launch memo api server!
//   $ cd ~/github.com/ddddddO/memo
//   $ make localcloudpg
//   $ make runapi
test "local server (memo api)" {
    const allocator = testing.allocator;
    const client = HttpClient.init(allocator);

    {
        const host = "localhost:8082";
        const res = try client.req()
            .get(host);
        defer res.deinit();

        try testing.expect(std.mem.eql(u8, "HTTP/1.1 401 Unauthorized", res.statusLine()));
        try testing.expect(std.mem.eql(u8, "401", res.statusCode()));
        try testing.expect(std.mem.eql(u8, "Unauthorized", res.status()));

        try testing.expect(res.raw().len > 0);
        try testing.expect(res.rawHeaders().len > 0);
        try testing.expect(res.rawBody().len > 0);
    }

    {
        const user_name = std.os.getenv("NAME");
        const password = std.os.getenv("PASSWORD");
        var body = try std.fmt.allocPrint(allocator, "name={s}&passwd={s}", .{ user_name, password });
        defer allocator.free(body);
        var content_length_header = try std.fmt.allocPrint(allocator, "Content-Length: {d}", .{body.len});
        defer allocator.free(content_length_header);

        const host = "localhost:8082/auth";
        const res = try client.req()
            .setHeader("Content-Type: application/x-www-form-urlencoded")
            .setHeader(content_length_header) // TODO: ライブラリ側で、bodyから長さを算出してセットする方が良さそう。
            .setBody(body)
            .post(host);
        defer res.deinit();

        try testing.expect(std.mem.eql(u8, "HTTP/1.1 200 OK", res.statusLine()));
        try testing.expect(std.mem.eql(u8, "200", res.statusCode()));
        try testing.expect(std.mem.eql(u8, "OK", res.status()));

        try testing.expect(res.raw().len > 0);
        try testing.expect(res.rawHeaders().len > 0);
        try testing.expect(res.rawBody().len > 0);

        const host_2 = "localhost:8082/memos?userId=1";
        var cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{res.cookie()});
        defer allocator.free(cookie_header);
        const res_2 = try client.req()
            .setHeader(cookie_header)
            .get(host_2);
        defer res_2.deinit();

        try testing.expect(std.mem.eql(u8, "HTTP/1.1 200 OK", res_2.statusLine()));
        try testing.expect(std.mem.eql(u8, "200", res_2.statusCode()));

        try testing.expect(res_2.raw().len > 0);
        try testing.expect(res_2.rawHeaders().len > 0);
        try testing.expect(res_2.rawBody().len > 0);
    }
}

test "Post login -> Get memo list (for README)" {
    const allocator = testing.allocator;
    const client = HttpClient.init(allocator);

    const user_name = std.os.getenv("NAME");
    const password = std.os.getenv("PASSWORD");

    var body = try std.fmt.allocPrint(allocator, "name={s}&passwd={s}", .{ user_name, password });
    defer allocator.free(body);

    var content_length_header = try std.fmt.allocPrint(allocator, "Content-Length: {d}", .{body.len});
    defer allocator.free(content_length_header);

    const host = "localhost:8082/auth";
    const res = try client.req()
        .setHeader("Content-Type: application/x-www-form-urlencoded")
        .setHeader(content_length_header)
        .setBody(body)
        .post(host);
    defer res.deinit();

    var cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{res.cookie()});
    defer allocator.free(cookie_header);

    const host_2 = "localhost:8082/memos?userId=1";
    const res_2 = try client.req()
        .setHeader(cookie_header)
        .get(host_2);
    defer res_2.deinit();

    const writer = std.io.getStdOut().writer();
    try writer.print("Status Line: {s}\n", .{res_2.statusLine()});
    // Output:
    // Status Line: HTTP/1.1 200 OK
}
