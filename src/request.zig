const std = @import("std");
const log = std.log;

const Host = @import("host.zig").Host;
const Response = @import("response.zig").Response;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;

pub const Request = struct {
    allocator: Allocator,
    headers: std.ArrayList(u8),
    body: ?[]const u8,

    pub fn get(self: Request, target: []const u8) !Response {
        const method = "GET";
        const response = self.request(method, target);
        return response;
    }

    pub fn post(self: Request, target: []const u8) !Response {
        const method = "POST";
        const response = try self.request(method, target);
        return response;
    }

    fn request(self: Request, method: []const u8, target: []const u8) !Response {
        const host = try Host.init(self.allocator, target);
        defer host.deinit();

        const tcp_conn = try std.net.tcpConnectToHost(self.allocator, host.domain, host.port);
        defer tcp_conn.close();

        try self.send(tcp_conn, host, method);

        var buf = try self.receive(tcp_conn);

        return Response.init(buf);
    }

    fn send(self: Request, tcp_conn: anytype, host: Host, method: []const u8) !void {
        const request_line = try std.fmt.allocPrint(self.allocator, "{s} {s} HTTP/1.1\r\n", .{ method, host.path });
        defer self.allocator.free(request_line);

        _ = try tcp_conn.write(request_line);
        const host_header = try std.fmt.allocPrint(self.allocator, "Host: {s}\r\n", .{host.domain});
        defer self.allocator.free(host_header);
        _ = try tcp_conn.write(host_header);

        if (self.headers.items.len != 0) {
            _ = try tcp_conn.write(self.headers.items);
            self.allocator.free(self.headers.items);
        }
        _ = try tcp_conn.write("\r\n");

        if (self.body != null) {
            _ = try tcp_conn.write(self.body.?);
            _ = try tcp_conn.write("\r\n");
        }
    }

    fn receive(self: Request, tcp_conn: anytype) !std.ArrayList(u8) {
        // TODO: この辺り要注意
        // もっといい方法あるはず
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
            const end_response_3 = std.mem.eql(u8, "}\n", response_buffer[len - 2 .. len]);
            if (end_response_3) {
                // log.debug("Response end...", .{});
                break;
            }
        }
        return buf;
    }

    // NOTE: error返した方がいいとは思う
    pub fn setHeader(self: *Request, header: []const u8) *Request {
        self.headers.appendSlice(header) catch |err| {
            log.err("setHeader error: {s}", .{err});
            return self;
        };
        self.headers.appendSlice("\r\n") catch |err| {
            log.err("setHeader error: {s}", .{err});
            return self;
        };
        return self;
    }

    pub fn setBody(self: *Request, body: []const u8) *Request {
        self.body = body;
        return self;
    }
};
