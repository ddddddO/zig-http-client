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

        const writer = std.io.getStdOut().writer();
        const server_hello = try self.receiveServerHello();
        // try writer.print("{s}", .{server_hello.content_type});
        // try writer.print("{s}", .{server_hello.version_a});
        try writer.print("{s}", .{server_hello.length_a});
        // try writer.print("{s}", .{server_hello.handshake_type});
        // try writer.print("{s}", .{server_hello.length_b});
        // try writer.print("{s}", .{server_hello.version_b});
        // try writer.print("{s}", .{server_hello.random});
        // try writer.print("{s}", .{server_hello.session_id_length});
        // try writer.print("{s}", .{server_hello.session_id});
        // try writer.print("{s}", .{server_hello.cipher_suite});
        // try writer.print("{s}", .{server_hello.compression_method});
        // try writer.print("{s}", .{server_hello.extensions_length});
        // try writer.print("{s}", .{server_hello.extension_ec_point_formats});
        // try writer.print("{s}", .{server_hello.extension_application_layer_protocol_negotiation});

        // NOTE:
        // zig test src/tls.zig > dump.bin
        // od -x dump.bin
        // wiresharkで見るのと↑で見るのとで逆の並びになっている。
        // また、2byte毎に並びが逆になるので、ServerHello structに詰めるときor詰めた後で何とかしないといけなさそう。

        std.debug.print("END handshake\n", .{});
    }

    fn receiveServerHello(self: TLS) !ServerHello {
        var reader = self.tcp_conn.reader();
        // NOTE: BigでもLittleでも変わらない
        // var optimized_reader = std.io.bitReader(std.builtin.Endian.Big, reader);
        // var server_hello = ServerHello.init();
        // _ = try optimized_reader.read(std.mem.asBytes(&server_hello));
        var buf = std.ArrayList(u8).init(self.allocator);
        _ = try reader.readAllArrayList(&buf, 10000);
        var server_hello = ServerHello.init();
        for (buf.items) |_, i| {
            if (i == 5) {
                // NOTE: for debug
                break;
            }

            if (i == 0) {
                server_hello.content_type = [1]u8{buf.items[i]};
            }
            if (i == 1) {
                server_hello.version_a = [2]u8{ buf.items[i + 1], buf.items[i] };
            }
            if (i == 3) {
                server_hello.length_a = [2]u8{ buf.items[i + 1], buf.items[i] };
            }
            // NOTE: tlsのフィールドごとに↑と同様の操作をする...?

            std.debug.print("Readed Server Hello: {}\n", .{buf.items[i]});
        }

        return server_hello;
    }
};

const ServerHello = struct {
    content_type: [1]u8,
    version_a: [2]u8,
    length_a: [2]u8,

    handshake_type: [1]u8,
    length_b: [3]u8,
    version_b: [2]u8,

    random: [32]u8, // 4+28=32
    session_id_length: [1]u8,
    session_id: [32]u8,

    cipher_suite: [2]u8,
    compression_method: [1]u8,

    // TODO: 可変長は可能？
    extensions_length: [2]u8,
    extension_ec_point_formats: [6]u8,
    extension_application_layer_protocol_negotiation: [17]u8,

    fn init() ServerHello {
        return ServerHello{
            .content_type = undefined,
            .version_a = undefined,
            .length_a = undefined,
            .handshake_type = undefined,
            .length_b = undefined,
            .version_b = undefined,
            .random = undefined,
            .session_id_length = undefined,
            .session_id = undefined,
            .cipher_suite = undefined,
            .compression_method = undefined,
            .extensions_length = undefined,
            .extension_ec_point_formats = undefined,
            .extension_application_layer_protocol_negotiation = undefined,
        };
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

const CompressionMethod = enum {
    Null,

    fn bytes(self: CompressionMethod) [1]u8 {
        return switch (self) {
            CompressionMethod.Null => [1]u8{'\x00'},
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
        //   -> https://milestone-of-se.nesuke.com/nw-basic/tls/https-structure/
        //   -> 変更後、[Client Hello] の表示を確認。[Client Hello]の後に、サーバーからACK -> [Server Hello]が送られてきていた。

        // wiresharkで、対象のパケットを選択して、「コピー」 -> 「as a Hex Stream」後、以下
        // echo a01b23456789 | sed -E ":l; s/^([0-9a-z]+)([a-z0-9]{2})/\1,\'\\\x\2\'/; t l;";
        var client_hello_buf = std.ArrayList(u8).init(self.allocator);

        const content_type = ContentType.handshake.bytes();
        const version_a = TLSVersion.v1_0.bytes();
        const content_length = [_]u8{ '\x01', '\x62' }; // 4 + 43 + 307(sum extensions) = 354
        try client_hello_buf.appendSlice(&content_type);
        try client_hello_buf.appendSlice(&version_a);
        try client_hello_buf.appendSlice(&content_length);

        const handshake_type = HandshakeType.client_hello.bytes();
        const length = [_]u8{ '\x00', '\x01', '\x5e' }; // 3: 354 - 4 = 350
        const version_b = TLSVersion.v1_2.bytes();
        try client_hello_buf.appendSlice(&handshake_type);
        try client_hello_buf.appendSlice(&length);
        try client_hello_buf.appendSlice(&version_b);

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
        const compression_method = CompressionMethod.Null.bytes(); // 1
        try client_hello_buf.appendSlice(&compression_methods_length);
        try client_hello_buf.appendSlice(&compression_method);

        const extensions_length = [_]u8{ '\x01', '\x33' }; // =307 =sum extensions
        try client_hello_buf.appendSlice(&extensions_length);
        const extension_server_name = [_]u8{ '\x00', '\x00', '\x00', '\x27', '\x00', '\x25', '\x00', '\x00', '\x22', '\x61', '\x70', '\x70', '\x2d', '\x64', '\x6f', '\x74', '\x2d', '\x74', '\x61', '\x67', '\x2d', '\x6d', '\x6e', '\x67', '\x2d', '\x32', '\x34', '\x33', '\x38', '\x32', '\x33', '\x2e', '\x61', '\x70', '\x70', '\x73', '\x70', '\x6f', '\x74', '\x2e', '\x63', '\x6f', '\x6d' }; // 39
        try client_hello_buf.appendSlice(&extension_server_name);
        const extension_ec_point_formats = [_]u8{ '\x00', '\x0b', '\x00', '\x04', '\x03', '\x00', '\x01', '\x02' }; // 4
        try client_hello_buf.appendSlice(&extension_ec_point_formats);
        const extension_supported_groups = [_]u8{ '\x00', '\x0a', '\x00', '\x1c', '\x00', '\x1a', '\x00', '\x17', '\x00', '\x19', '\x00', '\x1c', '\x00', '\x1b', '\x00', '\x18', '\x00', '\x1a', '\x00', '\x16', '\x00', '\x0e', '\x00', '\x0d', '\x00', '\x0b', '\x00', '\x0c', '\x00', '\x09', '\x00', '\x0a' }; // 28
        try client_hello_buf.appendSlice(&extension_supported_groups);
        const extension_signature_algorithms = [_]u8{ '\x00', '\x0d', '\x00', '\x20', '\x00', '\x1e', '\x06', '\x01', '\x06', '\x02', '\x06', '\x03', '\x05', '\x01', '\x05', '\x02', '\x05', '\x03', '\x04', '\x01', '\x04', '\x02', '\x04', '\x03', '\x03', '\x01', '\x03', '\x02', '\x03', '\x03', '\x02', '\x01', '\x02', '\x02', '\x02', '\x03' }; // 32
        try client_hello_buf.appendSlice(&extension_signature_algorithms);
        const extension_heartbeat = [_]u8{ '\x00', '\x0f', '\x00', '\x01', '\x01' };
        try client_hello_buf.appendSlice(&extension_heartbeat);
        const extension_next_protocol_negotiation = [_]u8{ '\x33', '\x74', '\x00', '\x00' };
        try client_hello_buf.appendSlice(&extension_next_protocol_negotiation);
        const extension_application_layer_protocol_negotiation = [_]u8{ '\x00', '\x10', '\x00', '\x0b', '\x00', '\x09', '\x08', '\x68', '\x74', '\x74', '\x70', '\x2f', '\x31', '\x2e', '\x31' };
        try client_hello_buf.appendSlice(&extension_application_layer_protocol_negotiation);
        const extension_padding = [_]u8{ '\x00', '\x15', '\x00', '\xa0', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00', '\x00' };
        try client_hello_buf.appendSlice(&extension_padding);

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
