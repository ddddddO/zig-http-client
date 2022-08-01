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

const TLS = struct {
    allocator: Allocator,
    tcp_conn: Stream,

    fn init(allocator: Allocator, tcp_conn: Stream) TLS {
        return TLS{
            .allocator = allocator,
            .tcp_conn = tcp_conn,
        };
    }

    fn handshake(self: TLS) !std.ArrayList(u8) {
        std.debug.print("\nIN handshake\n", .{});

        const client_hello = try TLSRecordLayer.init(self.allocator);
        _ = try self.tcp_conn.write(client_hello.bytes);

        var buf = std.ArrayList(u8).init(self.allocator);
        while (true) {
            std.debug.print("\nIN while\n", .{});

            var response_buffer: [2048]u8 = undefined;
            const len = self.tcp_conn.read(&response_buffer) catch 0;
            if (len == 0) {
                std.debug.print("Response end.", .{});
                break;
            }
            std.debug.print("Received\n{s}", .{response_buffer});

            const response = response_buffer[0..len];
            try buf.appendSlice(response);
        }
        return buf;
    }
};

const TLSRecordLayer = struct {
    allocator: Allocator,
    bytes: []u8,

    fn init(allocator: Allocator) !TLSRecordLayer {
        // NOTE:
        // ref: https://realizeznsg.hatenablog.com/entry/2018/09/17/110000
        // 以下は、wiresharkを起動し、curl https://app-dot-tag-mng-243823.appspot.com を実行し、「Client Hello」のパケットを調べて少し手を加えた。
        // 実行するとwiresharkで「[Client Hello Fragment], Ignore Unkown Record」と確認できた。
        var client_hello_buf = std.ArrayList(u8).init(allocator);

        const content_type = [_]u8{'\x16'};
        const tls_v1_0 = [_]u8{ '\x03', '\x01' };
        const content_length = [_]u8{ '\x00', '\x2a' }; // 42
        try client_hello_buf.appendSlice(&content_type);
        try client_hello_buf.appendSlice(&tls_v1_0);
        try client_hello_buf.appendSlice(&content_length);

        const handshake_type = [_]u8{'\x01'};

        // sum 46 bytes?
        const length = [_]u8{ '\x00', '\x00', '\x2e' }; // 3
        const tls_v1_2 = [_]u8{ '\x03', '\x03' }; // 2
        try client_hello_buf.appendSlice(&handshake_type);
        try client_hello_buf.appendSlice(&length);
        try client_hello_buf.appendSlice(&tls_v1_2);

        // random
        const unix_time = [_]u8{ '\x2f', '\xe5', '\xd6', '\xfe' }; // 4
        const random_byte = [_]u8{ '\x45', '\xff', '\x25', '\x51', '\xff', '\x1d', '\xfa', '\xa8', '\x29', '\x39', '\x46', '\x3a', '\x1a', '\xb7', '\x23', '\x7d', '\x42', '\x85', '\x3f', '\xc5', '\xe8', '\x0a', '\x78', '\x57', '\x20', '\x02', '\xfc', '\x1f' }; // 28
        try client_hello_buf.appendSlice(&unix_time);
        try client_hello_buf.appendSlice(&random_byte);

        const session_id_length = [_]u8{'\x00'}; // 1
        try client_hello_buf.appendSlice(&session_id_length);

        const cipher_suites_length = [_]u8{ '\x00', '\x02' }; // 2
        const cipher_suite = [_]u8{ '\xc0', '\x30' }; // 2

        try client_hello_buf.appendSlice(&cipher_suites_length);
        try client_hello_buf.appendSlice(&cipher_suite);

        const compression_methods_length = [_]u8{'\x01'}; // 1
        const compression_method = [_]u8{'\x00'}; // 1
        try client_hello_buf.appendSlice(&compression_methods_length);
        try client_hello_buf.appendSlice(&compression_method);

        const extensions_length = [_]u8{ '\x00', '\x00' }; // 2
        try client_hello_buf.appendSlice(&extensions_length);

        return TLSRecordLayer{
            .allocator = allocator,
            .bytes = client_hello_buf.items,
        };
    }
};

test "check ssl/tls" {
    // const allocator = std.testing.allocator;
    const allocator = std.heap.page_allocator;
    const host = try Host.init(allocator, "https://app-dot-tag-mng-243823.appspot.com");
    defer host.deinit();

    const tcp_conn = try std.net.tcpConnectToHost(allocator, host.domain, host.port);
    defer tcp_conn.close();

    const tls = TLS.init(allocator, tcp_conn);
    var buf = try tls.handshake();
    try std.testing.expect(buf.items.len > 0);
}
