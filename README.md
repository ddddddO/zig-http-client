# **WIP** zig-http-client
HTTP client lib for Zig. Inspired by **[go-resty](https://github.com/go-resty/resty)**!

## Usage

### GET method
```zig
const std = @import("std");
const HttpClient = @import("http-client").HttpClient;

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;
    const host = "www.google.com";

    const client = HttpClient.init(allocator);
    const res = try client.req()
        .setHeader("Accept: text/html")
        .get(host);
    defer res.deinit();

    const writer = std.io.getStdOut().writer();
    try writer.print("Status Line: {s}\n", .{res.statusLine()});
    try writer.print("Status Code: {s}\n", .{res.statusCode()});
    try writer.print("Status: {s}\n", .{res.status()});

    // Output:
    // Status Line: HTTP/1.1 200 OK
    // Status Code: 200
    // Status: OK
}
```

### POST and GET method (HTTP Request with cookie)
```zig
const std = @import("std");
const HttpClient = @import("http-client").HttpClient;

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;
    const client = HttpClient.init(allocator);

    const user_name = std.os.getenv("NAME");
    const password = std.os.getenv("PASSWORD");

    var body = try std.fmt.allocPrint(allocator, "name={s}&passwd={s}", .{ user_name, password });
    defer allocator.free(body);

    var content_length_header = try std.fmt.allocPrint(allocator, "Content-Length: {d}", .{body.len});
    defer allocator.free(content_length_header);

    const host = "http://localhost:8082/auth";
    const res = try client.req()
        .setHeader("Content-Type: application/x-www-form-urlencoded")
        .setHeader(content_length_header)
        .setBody(body)
        .post(host);
    defer res.deinit();

    var cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{res.cookie()});
    defer allocator.free(cookie_header);

    const host_2 = "http://localhost:8082/memos?userId=1";
    const res_2 = try client.req()
        .setHeader(cookie_header)
        .get(host_2);
    defer res_2.deinit();

    const writer = std.io.getStdOut().writer();
    try writer.print("Status Line: {s}\n", .{res_2.statusLine()});
    // Output:
    // Status Line: HTTP/1.1 200 OK
}
```