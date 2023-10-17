const xev = @import("xev");
const std = @import("std");

pub fn main() !void {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    const w = try xev.Timer.init();
    defer w.deinit();

    // 5s timer
    var c: xev.Completion = undefined;
    w.run(&loop, &c, 5000, void, null, &timerCallback);

    try loop.run(.until_done);
}

fn timerCallback(
    userdata: ?*void,
    loop: *xev.Loop,
    c: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
   _ = userdata;
   _ = loop;
   _ = c;
   _ = result catch unreachable;
   return .disarm;
}

fn demo() void {
    const testing = std.testing;

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Choose random available port (Zig #14907)
    var address = try std.net.Address.parseIp4("127.0.0.1", 0);
    const server = try xev.TCP.init(address);

    // Bind and listen
    try server.bind(address);
    try server.listen(1);

    // Retrieve bound port and initialize client
    var sock_len = address.getOsSockLen();
    const fd = if (xev.backend == .iocp) @as(std.os.windows.ws2_32.SOCKET, @ptrCast(server.fd)) else server.fd;
    try std.os.getsockname(fd, &address.any, &sock_len);
    const client = try xev.TCP.init(address);

    //const address = try std.net.Address.parseIp4("127.0.0.1", 3132);
    //var server = try Self.init(address);
    //var client = try Self.init(address);

    // Completions we need
    var c_accept: xev.Completion = undefined;
    var c_connect: xev.Completion = undefined;

    // Accept
    var server_conn: ?xev.TCP = null;
    server.accept(&loop, &c_accept, ?xev.TCP, &server_conn, (struct {
        fn callback(
            ud: ?*?xev.TCP,
            _: *xev.Loop,
            _: *xev.Completion,
            r: xev.TCP.AcceptError!xev.TCP,
        ) xev.CallbackAction {
            ud.?.* = r catch unreachable;
            return .disarm;
        }
    }).callback);

    // Connect
    var connected: bool = false;
    client.connect(&loop, &c_connect, address, bool, &connected, (struct {
        fn callback(
            ud: ?*bool,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            r: xev.TCP.ConnectError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            ud.?.* = true;
            return .disarm;
        }
    }).callback);

    // Wait for the connection to be established
    try loop.run(.until_done);
    try testing.expect(server_conn != null);
    try testing.expect(connected);

    // Close the server
    var server_closed = false;
    server.close(&loop, &c_accept, bool, &server_closed, (struct {
        fn callback(
            ud: ?*bool,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            r: xev.TCP.CloseError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            ud.?.* = true;
            return .disarm;
        }
    }).callback);
    try loop.run(.until_done);
    try testing.expect(server_closed);

    // Send
    var send_buf = [_]u8{ 1, 1, 2, 3, 5, 8, 13 };
    client.write(&loop, &c_connect, .{ .slice = &send_buf }, void, null, (struct {
        fn callback(
            _: ?*void,
            _: *xev.Loop,
            c: *xev.Completion,
            _: xev.TCP,
            _: xev.WriteBuffer,
            r: xev.TCP.WriteError!usize,
        ) xev.CallbackAction {
            _ = c;
            _ = r catch unreachable;
            return .disarm;
        }
    }).callback);

    // Receive
    var recv_buf: [128]u8 = undefined;
    var recv_len: usize = 0;
    server_conn.?.read(&loop, &c_accept, .{ .slice = &recv_buf }, usize, &recv_len, (struct {
        fn callback(
            ud: ?*usize,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            _: xev.ReadBuffer,
            r: xev.TCP.ReadError!usize,
        ) xev.CallbackAction {
            ud.?.* = r catch unreachable;
            return .disarm;
        }
    }).callback);

    // Wait for the send/receive
    try loop.run(.until_done);
    try testing.expectEqualSlices(u8, &send_buf, recv_buf[0..recv_len]);

    // Close
    server_conn.?.close(&loop, &c_accept, ?xev.TCP, &server_conn, (struct {
        fn callback(
            ud: ?*?xev.TCP,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            r: xev.TCP.CloseError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            ud.?.* = null;
            return .disarm;
        }
    }).callback);
    client.close(&loop, &c_connect, bool, &connected, (struct {
        fn callback(
            ud: ?*bool,
            _: *xev.Loop,
            _: *xev.Completion,
            _: xev.TCP,
            r: xev.TCP.CloseError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;
            ud.?.* = false;
            return .disarm;
        }
    }).callback);

    try loop.run(.until_done);
    try testing.expect(server_conn == null);
    try testing.expect(!connected);
    try testing.expect(server_closed);
}