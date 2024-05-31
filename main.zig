const std = @import("std");
const net = std.net;
const print = std.debug.print;

const PacketType_ServerDataAuth = 3;
const PacketType_ServerDataAuthResponse = 2;
const PacketType_ServerDataExecuteCommand = 2;
const PacketType_ServerDataResponseValue = 0;

const Errors = error{ AuthFailed, WrongEndpoint };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        std.debug.assert(deinit_status == .ok);
    }

    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    var args = std.process.args();
    _ = args.skip();
    const addressArg = args.next().?;
    const passwordArg = args.next().?;

    const endpoint = try endpointToAddressPort(addressArg);
    const hostname = endpoint[0];
    const port = try std.fmt.parseInt(u16, endpoint[1], 10);

    const list = try net.getAddressList(allocator, hostname, port);
    defer list.deinit();

    const address = list.addrs[0];

    const stream = try net.tcpConnectToAddress(address);
    defer stream.close();

    try authenticate(allocator, stream, passwordArg);

    try stdout.writer().print("Connected to {s}\n", .{addressArg});

    while (true) {
        _ = try stdout.writer().print("> ", .{});

        const userCommand = (try stdin.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)).?;
        defer allocator.free(userCommand);

        const cmd_response = try send_command(allocator, stream, userCommand);
        defer cmd_response.deinit();

        _ = try stdout.write(cmd_response.body);
        _ = try stdout.writer().print("\n", .{});
    }
}

fn endpointToAddressPort(endpoint: []const u8) !struct { []const u8, []const u8 } {
    const pos = std.mem.indexOf(u8, endpoint, ":");
    if (pos == null) {
        return Errors.WrongEndpoint;
    }
    return .{ endpoint[0..pos.?], endpoint[pos.? + 1 ..] };
}

fn authenticate(allocator: std.mem.Allocator, stream: net.Stream, password: []const u8) !void {
    const req_pkt = try Packet.init(allocator, 123, PacketType_ServerDataAuth, password);
    defer req_pkt.deinit();

    const packet_data = try req_pkt.to_bytes(allocator);
    defer allocator.free(packet_data);

    _ = try stream.write(packet_data);

    const resp_pkt = try Packet.from_stream(allocator, stream);
    defer resp_pkt.deinit();

    if (req_pkt.id != resp_pkt.id) {
        return Errors.AuthFailed;
    }
}

fn send_command(allocator: std.mem.Allocator, stream: net.Stream, command: []const u8) !Packet {
    const req_packet = try Packet.init(allocator, 1, PacketType_ServerDataExecuteCommand, command);
    defer req_packet.deinit();
    const req_bytes = try req_packet.to_bytes(allocator);
    defer allocator.free(req_bytes);

    _ = try stream.write(req_bytes);

    return try Packet.from_stream(allocator, stream);
}

const Packet = struct {
    const Self = @This();

    id: i32,
    _type: i32,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: i32, _type: i32, body: []const u8) !Self {
        const pbody = try allocator.alloc(u8, body.len);
        std.mem.copyForwards(u8, pbody, body);

        return Self{
            .allocator = allocator,
            .id = id,
            ._type = _type,
            .body = pbody,
        };
    }

    pub fn from_stream(alloc: std.mem.Allocator, stream: net.Stream) !Packet {
        var int_buf: [4]u8 = undefined;
        var pkt_buf: [4092]u8 = undefined;

        _ = try stream.readAtLeast(&int_buf, 4);
        const length_le = std.mem.bytesToValue(i32, &int_buf);
        const length: usize = @intCast(std.mem.littleToNative(i32, length_le));

        _ = try stream.readAtLeast(&pkt_buf, length);

        const id = std.mem.bytesToValue(i32, pkt_buf[0..]);
        const _type = std.mem.bytesToValue(i32, pkt_buf[4..]);

        const body = try alloc.alloc(u8, length - 10);
        std.mem.copyForwards(u8, body, pkt_buf[8 .. 8 + length - 10]);

        return Packet{
            .id = id,
            ._type = _type,
            .body = body,
            .allocator = alloc,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.body);
    }

    pub fn to_bytes(self: Packet, allocator: std.mem.Allocator) ![]u8 {
        const length = 2 * @sizeOf(i32) + self.body.len + 2;

        const packet = try allocator.alloc(u8, length + @sizeOf(i32));
        copy_le(packet, &length);
        copy_le(packet[4..], &self.id);
        copy_le(packet[8..], &self._type);
        std.mem.copyForwards(u8, packet[12..], self.body);
        std.mem.copyForwards(u8, packet[length + 2 ..], &[_]u8{ 0, 0 });

        return packet;
    }
};

fn copy_le(dest: []u8, value: anytype) void {
    const le_value = std.mem.nativeToLittle(@TypeOf(value), value);
    const le_bytes = std.mem.asBytes(le_value);
    std.mem.copyForwards(u8, dest, le_bytes);
}
