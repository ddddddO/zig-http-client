# **WIP** zig-http-client
HTTP client lib for Zig. Inspired by go-resty!

## Usage
```zig
pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;
    const host = "www.google.com";

    const client = HttpClient.init(allocator);
    defer client.deinit();
    const res = try client.req()
        .setHeader("Accept: text/html")
        .get(host);
    defer res.deinit();

    const writer = std.io.getStdOut().writer();
    try writer.print("Status Line: {s}\n", .{res.status_line()});
    try writer.print("Status Code: {s}\n", .{res.status_code()});
    try writer.print("Status: {s}\n", .{res.status()});

    // Output:
    // Status Line: HTTP/1.1 200 OK
    // Status Code: 200
    // Status: OK
}
```
