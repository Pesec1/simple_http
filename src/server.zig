const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 3000);

    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    try stdout.print("[INFO] Server is listening on {}\n", .{server.listen_address});

    while (true) {
        const connection = try server.accept();
        try handler(connection.stream);
    }
}

fn handler(stream: net.Stream) !void {
    defer stream.close();
    try stream.writer().print("Connection was made", .{});
}
