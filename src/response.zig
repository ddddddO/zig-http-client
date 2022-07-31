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

    pub fn cookie(self: Response) []u8 {
        const cookie_header_string = "Set-Cookie: ";

        var start_cookie: usize = 0;
        var exist_cookie = false;
        const raw_headers = self.rawHeaders();
        for (raw_headers) |_, i| {
            if ((i + cookie_header_string.len) == raw_headers.len) {
                break;
            }

            if (std.mem.eql(u8, cookie_header_string, raw_headers[i .. i + cookie_header_string.len])) {
                start_cookie = i + cookie_header_string.len;
                exist_cookie = true;
                break;
            }
        }
        if (!exist_cookie) {
            return "";
        }

        var end_cookie: usize = 0;
        const crlf = "\r\n";
        for (raw_headers[start_cookie..raw_headers.len]) |_, i| {
            const point = i + start_cookie;
            if (std.mem.eql(u8, crlf, raw_headers[point .. point + 2])) {
                end_cookie = point;
                break;
            }
        }

        return raw_headers[start_cookie..end_cookie];
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
