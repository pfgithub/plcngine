const std = @import("std");
const network = @import("network");

// Simple TCP echo server:
// Accepts a single incoming connection and will echo any received data back to the
// client. Increasing the buffer size might improve throughput.

// using 1000 here yields roughly 54 MBit/s
// using 100_00 yields 150 MB/s
const buffer_size = 1000;

// so question here is:
// - how to accept multiple incoming connections
// - how to make udp
// - how to make a client

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if(gpa.deinit() == .leak) @panic("memoer");

    const allocator = gpa.allocator();
    _ = allocator;

    const port_number = try std.fmt.parseInt(u16, "4455", 10);

    var sock = try network.Socket.create(.ipv4, .tcp);
    defer sock.close();

    try sock.bindToPort(port_number);

    try sock.listen();

    while (true) {
        var client = try sock.accept();
        defer client.close();

        std.debug.print("Client connected from {}.\n", .{
            try client.getLocalEndPoint(),
        });

        runEchoClient(client) catch |err| {
            std.debug.print("Client disconnected with msg {s}.\n", .{
                @errorName(err),
            });
            continue;
        };
        std.debug.print("Client disconnected.\n", .{});
    }
}

fn runEchoClient(client: network.Socket) !void {
    while (true) {
        var buffer: [buffer_size]u8 = undefined;

        const len = try client.receive(&buffer);
        if (len == 0)
            break;
        // we ignore the amount of data sent.
        _ = try client.send(buffer[0..len]);
    }
}