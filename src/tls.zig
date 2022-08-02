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

    fn handshake(self: TLS) !void {
        std.debug.print("\nIN handshake\n", .{});

        const tls_record = TLSRecordLayer.init(self.allocator);

        _ = try self.tcp_conn.write(try tls_record.clientHello());

        const server_hello = try self.receive();
        std.debug.print("Server Hello:\n{s}\n", .{server_hello});
        std.debug.print("Server Hello Length: {d}\n", .{server_hello.len});

        std.debug.print("\nEND handshake\n", .{});
    }

    fn receive(self: TLS) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        while (true) {
            // std.debug.print("\nIN while\n", .{});
            var response_buffer: [2048]u8 = undefined;
            const len = self.tcp_conn.read(&response_buffer) catch 0;
            if (len == 0) {
                // std.debug.print("Response end.", .{});
                break;
            }

            // FIXME: ?長さが異なる
            std.debug.print("Received:\n{s}", .{response_buffer});
            std.debug.print("Received Length: {d}\n", .{response_buffer.len});
            const response = response_buffer[0..len];
            std.debug.print("Response Length: {d}\n", .{response.len});
            try buf.appendSlice(response);
        }
        std.debug.print("Buf Length: {s}\n", .{buf.items});
        return buf.items;
    }
};

const ContentType = enum {
    handshake,

    fn bytes(self: ContentType) [1]u8 {
        return switch (self) {
            ContentType.handshake => [1]u8{'\x16'},
        };
    }
};

const TLSVersion = enum {
    v1_0,
    v1_2,

    fn bytes(self: TLSVersion) [2]u8 {
        return switch (self) {
            TLSVersion.v1_0 => [2]u8{ '\x03', '\x01' },
            TLSVersion.v1_2 => [2]u8{ '\x03', '\x03' },
        };
    }
};

const HandshakeType = enum {
    client_hello,

    fn bytes(self: HandshakeType) [1]u8 {
        return switch (self) {
            HandshakeType.client_hello => [1]u8{'\x01'},
        };
    }
};

const CipherSuite = enum {
    TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,
    TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,

    fn bytes(self: CipherSuite) [2]u8 {
        return switch (self) {
            CipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 => [2]u8{ '\xc0', '\x30' },
            CipherSuite.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 => [2]u8{ '\xc0', '\x2c' },
            CipherSuite.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384 => [2]u8{ '\xc0', '\x28' },
            CipherSuite.TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 => [2]u8{ '\xc0', '\x24' },
        };
    }
};

const TLSRecordLayer = struct {
    allocator: Allocator,

    fn init(allocator: Allocator) TLSRecordLayer {
        return TLSRecordLayer{
            .allocator = allocator,
        };
    }

    fn clientHello(self: TLSRecordLayer) ![]u8 {
        // NOTE:
        // ref: https://realizeznsg.hatenablog.com/entry/2018/09/17/110000
        // 以下は、wiresharkを起動し、curl https://app-dot-tag-mng-243823.appspot.com を実行し、「Client Hello」のパケットを調べて少し手を加えた。
        // 実行するとwiresharkで「[Client Hello Fragment], Ignore Unkown Record」と確認できた。
        var client_hello_buf = std.ArrayList(u8).init(self.allocator);

        const content_type = ContentType.handshake.bytes();
        const version = TLSVersion.v1_2.bytes();
        const content_length = [_]u8{ '\x00', '\x2a' }; // 42
        try client_hello_buf.appendSlice(&content_type);
        try client_hello_buf.appendSlice(&version);
        try client_hello_buf.appendSlice(&content_length);

        const handshake_type = HandshakeType.client_hello.bytes();
        // sum 46 bytes?
        const length = [_]u8{ '\x00', '\x00', '\x2e' }; // 3
        try client_hello_buf.appendSlice(&handshake_type);
        try client_hello_buf.appendSlice(&length);
        try client_hello_buf.appendSlice(&version);

        // random
        const unix_time = [_]u8{ '\x2f', '\xe5', '\xd6', '\xfe' }; // 4
        const random_bytes = [_]u8{ '\x45', '\xff', '\x25', '\x51', '\xff', '\x1d', '\xfa', '\xa8', '\x29', '\x39', '\x46', '\x3a', '\x1a', '\xb7', '\x23', '\x7d', '\x42', '\x85', '\x3f', '\xc5', '\xe8', '\x0a', '\x78', '\x57', '\x20', '\x02', '\xfc', '\x1f' }; // 28
        try client_hello_buf.appendSlice(&unix_time);
        try client_hello_buf.appendSlice(&random_bytes);

        const session_id_length = [_]u8{'\x00'}; // 1
        try client_hello_buf.appendSlice(&session_id_length);

        const cipher_suites_length = [_]u8{ '\x00', '\x02' }; // 2
        const cipher_suite = CipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384.bytes(); // 2
        try client_hello_buf.appendSlice(&cipher_suites_length);
        try client_hello_buf.appendSlice(&cipher_suite);

        const compression_methods_length = [_]u8{'\x01'}; // 1
        const compression_method = [_]u8{'\x00'}; // 1
        try client_hello_buf.appendSlice(&compression_methods_length);
        try client_hello_buf.appendSlice(&compression_method);

        const extensions_length = [_]u8{ '\x00', '\x00' }; // 2
        try client_hello_buf.appendSlice(&extensions_length);

        return client_hello_buf.items;
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
    try tls.handshake();
}
