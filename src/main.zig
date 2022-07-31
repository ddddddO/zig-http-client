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
            .headers = null,
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

// test "local server (memo api)" {
//     const allocator = testing.allocator;

//     const host = "localhost:8082";

//     const client = HttpClient.init(allocator);
//     const res = try client.req()
//         .get(host);
//     defer res.deinit();

//     try testing.expect(std.mem.eql(u8, "HTTP/1.1 401 Unauthorized", res.statusLine()));
//     try testing.expect(std.mem.eql(u8, "401", res.statusCode()));
//     try testing.expect(std.mem.eql(u8, "Unauthorized", res.status()));

//     try testing.expect(res.raw().len > 0);
//     try testing.expect(res.rawHeaders().len > 0);
//     try testing.expect(res.rawBody().len > 0);

//     std.debug.print("\n", .{});
//     std.debug.print("res.rawHeaders():\n{s}\n", .{res.rawHeaders()});
//     std.debug.print("res.rawBody():\n{s}\n", .{res.rawBody()});
// }
