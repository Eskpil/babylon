const std = @import("std");
const babylon = @import("babylon");
const dbus = babylon.transport.dbus;
const mpris = @import("mpris");

fn onVolumeRetrieved(ctx: ?*anyopaque, response: f64) !void {
    _ = ctx;
    std.debug.print("volume: {d}\n", .{response});
}

fn onMetadataRetrieved(ctx: ?*anyopaque, metadata: []dbus.DbusKV(dbus.DbusString, dbus.Variant)) !void {
    _ = ctx;

    for (metadata) |dict| {
        std.log.info("{s}:", .{dict.key.inner});

        switch (dict.val) {
            .string => {
                std.log.info(" > {s}", .{dict.val.string});
            },
            .i64 => {
                std.log.info(" > {}", .{dict.val.i64});
            },
            .array => |arr| {
                for (arr.items) |entry| {
                    std.log.info(" > {s}", .{entry.string});
                }
            },
            else => {},
        }

        //        std.log.info(" > {any}", .{dict.val});
    }
}

fn onPositionRetreived(ctx: ?*anyopaque, position: i64) !void {
    _ = ctx;
    std.log.info("position: {d}", .{position});

    const position_f: f64 = @floatFromInt(position);
    const seconds: f64 = position_f / 1_000_000.0;

    std.log.info("position: {}", .{seconds});
    std.log.info("minutes: {}", .{@mod(seconds, 60)});
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const loop = try babylon.eloop.Eloop.init(alloc);

    const OnInitialized = struct {
        pub fn notify(ctx: @This(), connection: anytype, writer: *std.Io.Writer) !void {
            _ = ctx;

            const player = mpris.OrgMprisMediaPlayer2Player.interface(connection, "org.mpris.MediaPlayer2.chromium.instance2", "/org/mpris/MediaPlayer2");

            try player.getMetadata(
                writer,
                undefined,
                onMetadataRetrieved,
            );

            try player.getPosition(
                writer,
                undefined,
                onPositionRetreived,
            );

            std.log.info("initialized?", .{});
        }
    };

    try dbus.connect(alloc, loop, OnInitialized{});

    while (true) {
        var events = try loop.poll(10);
        defer events.deinit(loop.allocator);
    }
}
