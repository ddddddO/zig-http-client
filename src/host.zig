const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

pub const Host = struct {
    allocator: Allocator,
    scheme: []u8,
    domain: []u8,
    path: []u8,
    port: u16,

    pub fn deinit(self: Host) void {
        self.allocator.free(self.domain);
        self.allocator.free(self.path);
    }

    // NOTE: 一旦、以下のパターンだけ考える
    // domain
    // domain/path
    // domain:port
    // domain:port/path
    pub fn init(allocator: Allocator, target: []const u8) !Host {
        var scheme: []u8 = "";
        var domain: []u8 = "";
        var path: []u8 = "";
        var port: u16 = undefined;

        // domain
        var tmp_domain = std.ArrayList(u8).init(allocator);
        try tmp_domain.appendSlice(target);
        domain = tmp_domain.items;

        // domain:port
        // domain:port/path
        var tmp_port = std.ArrayList(u8).init(allocator);
        defer allocator.free(tmp_port.items);

        var tmp_path = std.ArrayList(u8).init(allocator);
        var _port: []u8 = "";
        for (target) |_, i| {
            if (target[i] == ':') {
                tmp_domain.clearAndFree();
                try tmp_domain.appendSlice(target[0..i]);
                domain = tmp_domain.items;

                try tmp_port.appendSlice(target[i + 1 ..]);
                _port = tmp_port.items;
                for (tmp_port.items) |_, j| {
                    if (tmp_port.items[j] == '/') {
                        _port = tmp_port.items[0..j];

                        try tmp_path.appendSlice(target[i + 1 + j ..]);
                        path = tmp_path.items;
                        break;
                    }
                }
            }
        }
        if (_port.len == 0) {
            try tmp_port.appendSlice("80");
            _port = tmp_port.items;
        }
        port = try std.fmt.parseUnsigned(u16, _port, 10);

        // domain/path
        if (path.len == 0) {
            for (target) |_, i| {
                if (target[i] == '/') {
                    tmp_domain.clearAndFree();
                    try tmp_domain.appendSlice(target[0..i]);
                    domain = tmp_domain.items;

                    try tmp_path.appendSlice(target[i..]);
                    path = tmp_path.items;
                    break;
                }
            }
        }

        return Host{
            .allocator = allocator,
            .scheme = scheme,
            .domain = domain,
            .path = path,
            .port = port,
        };
    }
};

test "Host test" {
    const allocator = testing.allocator;

    {
        const in = "example.com";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(80 == host.port);
    }

    {
        const in = "example.com:8082";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(8082 == host.port);
    }

    {
        const in = "example.com:8082/accounts";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(8082 == host.port);
        try testing.expect(std.mem.eql(u8, "/accounts", host.path));
    }

    {
        const in = "example.com/accounts";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(80 == host.port);
        try testing.expect(std.mem.eql(u8, "/accounts", host.path));
    }
}
