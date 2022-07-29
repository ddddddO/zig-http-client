const std = @import("std");
const log = std.log;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;

pub const HttpClient = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) HttpClient {
        return HttpClient{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: HttpClient) void {
        _ = self;
    }

    pub fn req(self: HttpClient) Request {
        return Request{
            .allocator = self.allocator,
            .headers = null,
        };
    }
};

pub const Request = struct {
    allocator: Allocator,
    headers: ?[]const u8, // TODO: 複数保持

    fn get(self: Request, target: []const u8) !Response {
        const tcp_conn = try std.net.tcpConnectToHost(self.allocator, target, 80);
        defer tcp_conn.close();

        _ = try tcp_conn.write("GET / HTTP/1.1\r\n");
        const host_header = try std.fmt.allocPrint(self.allocator, "Host: {s}\r\n", .{target});
        defer self.allocator.free(host_header);
        _ = try tcp_conn.write(host_header);

        if ((self.headers != null) and (self.headers.?.len != 0)) {
            _ = try tcp_conn.write(self.headers.?);
            _ = try tcp_conn.write("\r\n");
        }
        _ = try tcp_conn.write("\r\n");

        var buf = std.ArrayList(u8).init(self.allocator);
        while (true) {
            var response_buffer: [2048]u8 = undefined;
            const len = tcp_conn.read(&response_buffer) catch 0;
            if (len == 0) {
                // log.debug("Response end.", .{});
                break;
            }
            const response = response_buffer[0..len];
            try buf.appendSlice(response);

            const end_response_1 = std.mem.eql(u8, "\r\n", response_buffer[len - 2 .. len]);
            if (end_response_1) {
                // log.debug("Response end..", .{});
                break;
            }
            const end_response_2 = std.mem.eql(u8, "\r\n ", response_buffer[len - 3 .. len]);
            if (end_response_2) {
                // log.debug("Response end...", .{});
                break;
            }
        }

        return Response.init(buf);
    }

    fn setHeader(self: *Request, header: []const u8) *Request {
        self.headers = header;
        return self;
    }
};

pub const Response = struct {
    buf: std.ArrayList(u8),
    status_line: []u8,

    pub fn init(buf: std.ArrayList(u8)) Response {
        var status_line: []u8 = undefined;
        for (buf.items) |item, i| {
            if ((item == '\r') and (buf.items[i + 1] == '\n')) {
                status_line = buf.items[0..i];
                break;
            }
        }

        return Response{
            .buf = buf,
            .status_line = status_line,
        };
    }

    pub fn deinit(self: Response) void {
        self.buf.deinit();
    }

    pub fn raw(self: Response) []u8 {
        return self.buf.items;
    }

    pub fn statusLine(self: Response) []u8 {
        return self.status_line;
    }

    pub fn statusCode(self: Response) []u8 {
        return self.statusLine()[9..12];
    }

    pub fn status(self: Response) []u8 {
        return self.statusLine()[13..self.status_line.len];
    }
};

test "usage" {
    const allocator = testing.allocator;
    const host = "www.google.com";
    // const host = "www.yahoo.co.jp";

    const client = HttpClient.init(allocator);
    defer client.deinit();
    const res = try client.req()
        .setHeader("Accept: text/html")
        .get(host);
    defer res.deinit();

    try testing.expect(std.mem.eql(u8, "HTTP/1.1 200 OK", res.statusLine()));
    try testing.expect(std.mem.eql(u8, "200", res.statusCode()));
    try testing.expect(std.mem.eql(u8, "OK", res.status()));
}
