const std = @import("std");
const net = std.net;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const print = std.debug.print;

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 3000);

    var server = try address.listen(.{ .reuse_address = true, .reuse_port = true });
    defer server.deinit();

    try stdout.print("[INFO] Server is listening on {}\n", .{server.listen_address});

    while (true) {
        const connection = try server.accept();
        try handler(allocator, connection.stream);
    }
}

fn handler(allocator: std.mem.Allocator, stream: net.Stream) !void {
    var request_line = std.ArrayList(u8).init(allocator);
    defer request_line.deinit();

    try stream.reader().streamUntilDelimiter(request_line.writer(), '\n', std.math.maxInt(usize));
    var request_line_iter = std.mem.splitAny(u8, request_line.items, " ");

    const method = request_line_iter.next().?;
    const uri = request_line_iter.next().?;
    const version = request_line_iter.next().?;

    //debug
    print("\nfirst line: {s}, {s}, {s}", .{ method, uri, version });

    var headers = std.StringHashMap([]const u8).init(allocator);
    var parsing_headers: bool = true;

    while (parsing_headers) {
        var header_line = std.ArrayList(u8).init(allocator);
        defer header_line.deinit();

        try stream.reader().streamUntilDelimiter(header_line.writer(), '\n', std.math.maxInt(usize));
        var header_line_iter = std.mem.tokenizeAny(u8, header_line.items, ": ");

        if (std.mem.eql(u8, header_line_iter.peek().?, "\r")) {
            parsing_headers = false;
            break;
        }
        const key = header_line_iter.next().?;
        const value = header_line_iter.next().?;
        const fallback_value: []const u8 = "default";
        const other = header_line_iter.next() orelse fallback_value;

        try headers.put(key, value);

        //debug
        print("\nsecond line: {s}, {s}, {s}\n", .{ key, value, other });
    }
    // try stream.writer().print("Connection was made. Method: {s}\n uri: {s}\n version: {s}\n", .{ method, uri, version });
    defer stream.close();
}
