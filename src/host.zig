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
        self.allocator.free(self.scheme);
        self.allocator.free(self.domain);
        self.allocator.free(self.path);
    }

    pub fn init(allocator: Allocator, target: []const u8) !Host {
        var scheme: []u8 = "";
        var domain: []u8 = "";
        var path: []u8 = "";
        var port: u16 = undefined;

        var tmp_scheme = std.ArrayList(u8).init(allocator);
        var tmp_domain = std.ArrayList(u8).init(allocator);
        const delimiter = "://";
        var start_domain: usize = 0;
        for (target) |_, i| {
            if (target[i] != delimiter[0]) {
                continue;
            }
            if (std.mem.eql(u8, delimiter, target[i .. i + 3])) {
                try tmp_scheme.appendSlice(target[0..i]);
                scheme = tmp_scheme.items;

                start_domain = i + 3;

                break;
            }
        }
        if (scheme.len == 0) {
            try tmp_domain.appendSlice(target);
            domain = tmp_domain.items;
        }

        // domain:port
        // domain:port/path
        var tmp_path = std.ArrayList(u8).init(allocator);
        var tmp_port = std.ArrayList(u8).init(allocator);
        defer allocator.free(tmp_port.items);

        var _port: []u8 = "";
        for (target[start_domain..]) |_, n| {
            var i = start_domain + n;

            if (target[i] == ':') {
                tmp_domain.clearAndFree();
                try tmp_domain.appendSlice(target[start_domain..i]);
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
            for (target[start_domain..]) |_, n| {
                var i = start_domain + n;

                if (target[i] == '/') {
                    tmp_domain.clearAndFree();
                    try tmp_domain.appendSlice(target[start_domain..i]);
                    domain = tmp_domain.items;

                    try tmp_path.appendSlice(target[i..]);
                    path = tmp_path.items;
                    break;
                }
            }
        }
        if (path.len == 0) {
            tmp_path.clearAndFree();
            try tmp_path.appendSlice("/");
            path = tmp_path.items;
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
        try testing.expect(std.mem.eql(u8, "/", host.path));
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

    {
        const in = "example.com:8082/accounts?userId=1";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(8082 == host.port);
        try testing.expect(std.mem.eql(u8, "/accounts?userId=1", host.path));
    }

    {
        const in = "http://example.com:8082/accounts?userId=1";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "http", host.scheme));
        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        try testing.expect(8082 == host.port);
        try testing.expect(std.mem.eql(u8, "/accounts?userId=1", host.path));
    }

    {
        const in = "https://example.com/accounts";
        const host = try Host.init(allocator, in);
        defer host.deinit();

        try testing.expect(std.mem.eql(u8, "https", host.scheme));
        try testing.expect(std.mem.eql(u8, "example.com", host.domain));
        // try testing.expect(443 == host.port); // TODO:
        try testing.expect(std.mem.eql(u8, "/accounts", host.path));
    }
}
