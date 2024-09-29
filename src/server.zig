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

const ParsingError = error{
    MethodNotValid,
    VersionNotValid,
};

const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,

    pub fn fromString(s: []const u8) !Method {
        if (std.mem.eql(u8, "GET", s)) return .GET;
        if (std.mem.eql(u8, "PUT", s)) return .PUT;
        if (std.mem.eql(u8, "POST", s)) return .POST;
        if (std.mem.eql(u8, "PATCH", s)) return .PATCH;
        if (std.mem.eql(u8, "DELETE", s)) return .DELETE;
        if (std.mem.eql(u8, "OPTIONS", s)) return .OPTIONS;
        return ParsingError.MethodNotValid;
    }
};

const Version = enum {
    @"1.1",
    @"2",

    pub fn fromString(s: []const u8) !Version {
        if (std.mem.eql(u8, "HTTP/1.1\r", s)) return .@"1.1";
        if (std.mem.eql(u8, "HTTP/2\r", s)) return .@"2";
        return ParsingError.VersionNotValid;
    }

    pub fn toString(self: Version) []const u8 {
        const version = switch (self) {
            .@"1.1" => "HTTP/1.1",
            .@"2" => "HTTP/2",
        };

        return version;
    }
};

const HTTPContext = struct {
    method: Method,
    uri: []const u8,
    version: Version,
    headers: std.StringHashMap([]const u8),
    stream: net.Stream,

    pub fn init(allocator: std.mem.Allocator, stream: std.net.Stream) !HTTPContext {
        var request_line = std.ArrayList(u8).init(allocator);
        try stream.reader().streamUntilDelimiter(request_line.writer(), '\n', std.math.maxInt(usize));
        var request_line_iter = std.mem.splitAny(u8, request_line.items, " ");

        const method = request_line_iter.next().?;
        const uri = request_line_iter.next().?;
        const version = request_line_iter.next().?;
        var headers = std.StringHashMap([]const u8).init(allocator);

        while (true) {
            var header_line = std.ArrayList(u8).init(allocator);

            try stream.reader().streamUntilDelimiter(header_line.writer(), '\n', std.math.maxInt(usize));
            var header_line_iter = std.mem.tokenizeAny(u8, header_line.items, ": ");

            if (std.mem.eql(u8, header_line_iter.peek().?, "\r")) {
                break;
            }
            const key = header_line_iter.next().?;
            const value = header_line_iter.next().?;
            // if host with port
            // const fallback_value: []const u8 = "default";
            // const other = header_line_iter.next() orelse fallback_value;
            try headers.put(key, value);
        }
        return HTTPContext{
            .method = try Method.fromString(method),
            .uri = uri,
            .version = try Version.fromString(version),
            .headers = headers,
            .stream = stream,
        };
    }

    pub fn body(self: HTTPContext) net.Stream.Reader {
        return self.stream.reader();
    }

    pub fn response(self: HTTPContext, stream: net.Stream) !void {
        const version = self.version.toString();
        try stream.writer().print("{s} 200 OK", .{version});
    }

    pub fn debugPrint(self: HTTPContext) void {
        print("\nRequest {any}, {s}, {any}\n", .{ self.method, self.uri, self.version });
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
};

fn handler(allocator: std.mem.Allocator, stream: net.Stream) !void {
    const http_context = try HTTPContext.init(allocator, stream);
    http_context.debugPrint();
    try http_context.response(stream);
    defer stream.close();
}
