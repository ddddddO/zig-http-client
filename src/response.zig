const std = @import("std");

pub const Response = struct {
    buf: std.ArrayList(u8),
    status_line: []u8,
    raw_headers: []u8,
    raw_body: []u8,

    pub fn init(buf: std.ArrayList(u8)) Response {
        var serched_point: usize = undefined;

        // status line
        var status_line: []u8 = "";
        for (buf.items) |_, i| {
            if (std.mem.eql(u8, buf.items[i .. i + 2], "\r\n")) {
                status_line = buf.items[0..i];
                serched_point = i + 1;
                break;
            }
        }

        // response headers
        var raw_headers: []u8 = "";
        for (buf.items) |_, i| {
            if (std.mem.eql(u8, buf.items[i .. i + 4], "\r\n\r\n")) {
                raw_headers = buf.items[serched_point + 1 .. i];
                serched_point = i + 4;
                break;
            }
        }

        // response body
        var raw_body: []u8 = buf.items[serched_point..];

        return Response{
            .buf = buf,
            .status_line = status_line,
            .raw_headers = raw_headers,
            .raw_body = raw_body,
        };
    }

    pub fn deinit(self: Response) void {
        self.buf.deinit();
    }

    pub fn raw(self: Response) []u8 {
        return self.buf.items;
    }

    pub fn rawHeaders(self: Response) []u8 {
        return self.raw_headers;
    }

    pub fn rawBody(self: Response) []u8 {
        return self.raw_body;
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
