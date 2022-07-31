const std = @import("std");
const log = std.log;

const Host = @import("host.zig").Host;
const Response = @import("response.zig").Response;

const Allocator = std.mem.Allocator;

pub const Request = struct {
    allocator: Allocator,
    headers: ?[]const u8, // TODO: 複数保持

    pub fn get(self: Request, target: []const u8) !Response {
        const host = try Host.init(self.allocator, target);
        defer host.deinit();

        const dest = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ host.domain, host.path });
        defer self.allocator.free(dest);

        const tcp_conn = try std.net.tcpConnectToHost(self.allocator, dest, host.port);
        defer tcp_conn.close();

        _ = try tcp_conn.write("GET / HTTP/1.1\r\n");
        const host_header = try std.fmt.allocPrint(self.allocator, "Host: {s}\r\n", .{host.domain});
        defer self.allocator.free(host_header);
        _ = try tcp_conn.write(host_header);

        if ((self.headers != null) and (self.headers.?.len != 0)) {
            _ = try tcp_conn.write(self.headers.?);
            _ = try tcp_conn.write("\r\n");
        }
        _ = try tcp_conn.write("\r\n");

        // TODO: この辺り要注意
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

        return Response.init(buf);
    }

    pub fn setHeader(self: *Request, header: []const u8) *Request {
        self.headers = header;
        return self;
    }
};
