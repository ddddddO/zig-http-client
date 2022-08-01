const std = @import("std");

const Host = @import("host.zig").Host;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;

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
