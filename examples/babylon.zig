const std = @import("std");
const babylon = @import("babylon");
const dbus = @import("sphdbus");
const mpris = @import("mpris");

const MediaInfo = struct {
    const Self = @This();

    title: []const u8,
    album: []const u8,
    id: []const u8,
    length: f64,
    position: f64,

    coverArtUri: []const u8,

    const empty: Self = .{
        .id = "",
        .album = "",
        .title = "",
        .coverArtUri = "",
        .length = 0,
        .position = 0,
    };
};

fn fetchCoverArt(alloc: std.mem.Allocator, url: []const u8) ![]u8 {
    // Create a HTTP client
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    var allocating = std.Io.Writer.Allocating.init(alloc);
    defer allocating.deinit();

    const uri = try std.Uri.parse(url);
    const res = try client.fetch(
        .{
            .method = .GET,
            .location = .{
                .uri = uri,
            },
            .response_writer = &allocating.writer,
        },
    );
    _ = res;

    const copy = try alloc.dupe(u8, allocating.writer.buffer);
    return copy;
}

const DbusHandler = struct {
    connection: dbus.DbusConnection,
    stream: std.net.Stream,
    state: union(enum) {
        wait_initialize,
        wait_position: dbus.CallHandle,
        wait_metadata: dbus.CallHandle,
    },
    current_position: u64,

    pub fn init(alloc: std.mem.Allocator) !DbusHandler {
        const stream = try dbus.sessionBus();

        const reader = try alloc.create(std.net.Stream.Reader);
        reader.* = stream.reader(try alloc.alloc(u8, 4096));

        const writer = try alloc.create(std.net.Stream.Writer);
        writer.* = stream.writer(try alloc.alloc(u8, 4096));

        const connection = try dbus.dbusConnection(reader.interface(), &writer.interface);

        return .{
            .current_position = 0,
            .stream = stream,
            .connection = connection,
            .state = .wait_initialize,
        };
    }

    pub fn deinit(self: *DbusHandler) void {
        self.stream.close();
    }

    fn poll(self: *DbusHandler, options: dbus.ParseOptions) !MediaInfo {
        while (true) {
            const res = try self.connection.poll(options);

            const player = mpris.OrgMprisMediaPlayer2Player{
                .connection = &self.connection,
                .service = "org.mpris.MediaPlayer2.spotify",
                .object_path = "/org/mpris/MediaPlayer2",
            };

            switch (self.state) {
                .wait_initialize => {
                    if (res == .initialized) {
                        self.state = .{ .wait_position = try player.getPosition() };
                    }
                },
                .wait_position => |wait_for| {
                    if (res != .response) continue;
                    if (res.response.handle.inner != wait_for.inner) continue;

                    const parsed = try mpris.OrgMprisMediaPlayer2Player.parseGetPositionResponse(res.response.header, options);
                    self.current_position = @intCast(parsed);

                    self.state = .{ .wait_metadata = try player.getMetadata() };
                },
                .wait_metadata => |wait_for| {
                    if (res != .response) continue;
                    if (res.response.handle.inner != wait_for.inner) continue;

                    const parsed = try mpris.OrgMprisMediaPlayer2Player.parseGetMetadataResponse(
                        res.response.header,
                        options,
                    );

                    var info: MediaInfo = .empty;

                    info.position = @floatFromInt(self.current_position);

                    var it = parsed.iter();
                    while (try it.next(options)) |kv| {
                        if (std.mem.eql(u8, kv.key.inner, "xesam:title")) {
                            const title = (try kv.val.toConcrete(dbus.DbusString, res.response.header.endianness, options)).inner;
                            info.title = title;
                        }

                        if (std.mem.eql(u8, kv.key.inner, "xesam:album")) {
                            const album = (try kv.val.toConcrete(dbus.DbusString, res.response.header.endianness, options)).inner;
                            info.album = album;
                        }

                        if (std.mem.eql(u8, kv.key.inner, "mpris:length")) {
                            const length = (try kv.val.toConcrete(u64, res.response.header.endianness, options));

                            info.length = @floatFromInt(length);
                        }

                        if (std.mem.eql(u8, kv.key.inner, "mpris:trackid")) {
                            const trackid = (try kv.val.toConcrete(dbus.DbusString, res.response.header.endianness, options)).inner;
                            info.id = trackid;
                        }

                        if (std.mem.eql(u8, kv.key.inner, "mpris:artUrl")) {
                            const artUrl = (try kv.val.toConcrete(dbus.DbusString, res.response.header.endianness, options)).inner;
                            info.coverArtUri = artUrl;
                        }
                    }

                    return info;
                },
            }
        }
    }
};

pub const Theme = struct {
    pub const Background = struct {
        pub const dark = babylon.Color{ .r = 0.11, .g = 0.11, .b = 0.11, .a = 1.0 };
        pub const darker = babylon.Color{ .r = 0.09, .g = 0.09, .b = 0.09, .a = 1.0 };
        pub const selected = babylon.Color{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1.0 };
    };

    pub const Text = struct {
        pub const white = babylon.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        pub const gray = babylon.Color{ .r = 0.6, .g = 0.6, .b = 0.6, .a = 1.0 };
    };

    pub const Colors = struct {
        pub const accent = babylon.Color{ .r = 0.5, .g = 0.4, .b = 0.8, .a = 1.0 };
        pub const separator = babylon.Color{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1.0 };
    };
};

const ProgressBar = struct {
    const Self = @This();

    bar: *babylon.Block,

    lengthSpan: *babylon.Block,
    progressSpan: *babylon.Block,

    lengthBuf: [32]u8 = undefined,
    progressBuf: [32]u8 = undefined,

    fn formatSeconds(
        buf: []u8,
        total_seconds: f64,
    ) ![]const u8 {
        const total: u32 = @as(u32, @intFromFloat(total_seconds));

        const minutes: u32 = @divTrunc(total, 60);
        const seconds: u32 = @mod(total, 60);

        return try std.fmt.bufPrint(
            buf,
            "{}:{:02}",
            .{ minutes, seconds },
        );
    }

    pub fn init(alloc: std.mem.Allocator, length: f64, progress: f64) !*babylon.Block {
        const self = try alloc.create(Self);

        self.* = .{
            .bar = try babylon.Blocks.Progress.init(
                alloc,
                progress / length,
                Theme.Colors.accent,
                .{
                    .width = babylon.sizingFit(250, babylon.Max),
                    .height = babylon.sizingFixed(5),
                },
            ),
            .lengthSpan = try babylon.Blocks.Span.init(
                alloc,
                try formatSeconds(&self.lengthBuf, length / std.time.us_per_s),
                .{
                    .font = "Open Sans",
                    .size = 12,
                    .weight = .regular,
                    .slant = .none,
                    .color = Theme.Text.gray,
                },
            ),
            .progressSpan = try babylon.Blocks.Span.init(
                alloc,
                try formatSeconds(&self.progressBuf, progress / std.time.us_per_s),
                .{
                    .font = "Open Sans",
                    .size = 12,
                    .weight = .regular,
                    .slant = .none,
                    .color = Theme.Text.gray,
                },
            ),
        };
        var stack: std.ArrayList(*babylon.Block) = .empty;
        defer stack.deinit(alloc);

        const progressSpanContainer = try babylon.Blocks.Container.init(
            alloc,
            self.progressSpan,
            .{
                .padding = .{
                    .bottom = -5,
                },
            },
        );

        const lengthSpanContainer = try babylon.Blocks.Container.init(
            alloc,
            self.lengthSpan,
            .{
                .padding = .{
                    .bottom = -5,
                },
            },
        );

        try stack.append(alloc, progressSpanContainer);
        try stack.append(alloc, self.bar);
        try stack.append(alloc, lengthSpanContainer);

        const hstack = try babylon.Blocks.HStack.init(
            alloc,
            try stack.toOwnedSlice(alloc),
            8,
            .end,
            .{
                .width = babylon.sizingFit(300, babylon.Max),
                .height = babylon.sizingFit(0, babylon.Max),
            },
        );

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );

        block.destroy = destroy;

        try block.append(alloc, hstack);

        return block;
    }

    pub fn update(self: *Self, progress: f64, length: f64) !void {
        const bar: *babylon.Blocks.Progress = @ptrCast(@alignCast(self.bar.context));

        const progressSpan: *babylon.Blocks.Span = @ptrCast(@alignCast(self.progressSpan.context));
        const lengthSpan: *babylon.Blocks.Span = @ptrCast(@alignCast(self.lengthSpan.context));

        try lengthSpan.update(try formatSeconds(&self.lengthBuf, length / std.time.us_per_s));
        try progressSpan.update(try formatSeconds(&self.progressBuf, progress / std.time.us_per_s));

        try bar.setProgress(progress / length);
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        ctx.alloc.destroy(self);
    }
};

const MediaView = struct {
    const Self = @This();

    currentTrackId: []const u8,
    coverArt: *babylon.Block,
    progress: *babylon.Block,

    albumSpan: *babylon.Block,
    titleSpan: *babylon.Block,

    albumText: [128]u8 = undefined,
    titleText: [128]u8 = undefined,

    dbusDiagnosticsBuf: [4096]u8 = undefined,

    alloc: std.mem.Allocator,

    fn onMediaChange(ctx: *anyopaque, event: babylon.eloop.Eloop.Event) !babylon.eloop.Eloop.Decision {
        try babylon.eloop.Timer.ready(event);

        const self: *Self = @ptrCast(@alignCast(ctx));

        var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_alloc.deinit();
        const dbus_alloc = arena_alloc.allocator();

        var handler = try DbusHandler.init(dbus_alloc);
        defer handler.deinit();

        var diagnostics = dbus.DbusErrorDiagnostics.init(&self.dbusDiagnosticsBuf);

        const parse_options = dbus.ParseOptions{
            .diagnostics = &diagnostics,
        };

        const media_info = try handler.poll(parse_options);

        const progress: *ProgressBar = @ptrCast(@alignCast(self.progress.context));
        try progress.update(media_info.position, media_info.length);

        if (std.mem.eql(u8, self.currentTrackId, media_info.id)) {
            return .proceed;
        }

        const coverArtData = try fetchCoverArt(self.alloc, media_info.coverArtUri);
        defer self.alloc.free(coverArtData);

        const titleSpan: *babylon.Blocks.Span = @ptrCast(@alignCast(self.titleSpan.context));
        const albumSpan: *babylon.Blocks.Span = @ptrCast(@alignCast(self.albumSpan.context));
        const coverArt: *babylon.Blocks.Image = @ptrCast(@alignCast(self.coverArt.context));

        try titleSpan.update(media_info.title);
        try albumSpan.update(media_info.album);
        try coverArt.replace(coverArtData);

        self.alloc.free(self.currentTrackId);
        self.currentTrackId = try self.alloc.dupe(u8, media_info.id);

        return .proceed;
    }

    pub fn init(alloc: std.mem.Allocator, loop: *babylon.eloop.Eloop) !*babylon.Block {
        const self = try alloc.create(Self);

        const timer = try babylon.eloop.Timer.interval(15 * std.time.ns_per_ms);

        try loop.register(timer.timer_fd, .read, onMediaChange, self);

        var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_alloc.deinit();
        const dbus_alloc = arena_alloc.allocator();

        var handler = try DbusHandler.init(dbus_alloc);
        defer handler.deinit();

        var diagnostics = dbus.DbusErrorDiagnostics.init(&self.dbusDiagnosticsBuf);

        const parse_options = dbus.ParseOptions{
            .diagnostics = &diagnostics,
        };

        const media_info = try handler.poll(parse_options);
        const coverArt = try fetchCoverArt(alloc, media_info.coverArtUri);
        defer alloc.free(coverArt);

        self.* = .{
            .alloc = alloc,
            .currentTrackId = try alloc.dupe(u8, media_info.id),
            .titleSpan = try babylon.Blocks.Span.init(
                alloc,
                media_info.title,
                .{
                    .font = "Open Sans",
                    .size = 20,
                    .weight = .bold,
                    .slant = .none,
                    .color = Theme.Text.white,
                },
            ),
            .albumSpan = try babylon.Blocks.Span.init(
                alloc,
                media_info.album,
                .{
                    .font = "Open Sans",
                    .size = 16,
                    .weight = .regular,
                    .slant = .none,
                    .color = Theme.Text.gray,
                },
            ),
            .progress = try ProgressBar.init(
                alloc,
                media_info.length,
                media_info.position,
            ),
            .coverArt = try babylon.Blocks.Image.init(
                alloc,
                coverArt,
                256,
                256,
            ),
        };

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );

        block.destroy = destroy;

        const coverArtContaniner = try babylon.Blocks.Container.init(
            alloc,
            self.coverArt,
            .{
                .border_radius = 96,
            },
        );

        var vstack_items: std.ArrayList(*babylon.Block) = .empty;
        defer vstack_items.deinit(alloc);

        var hstack_items: std.ArrayList(*babylon.Block) = .empty;
        defer hstack_items.deinit(alloc);

        try vstack_items.append(alloc, self.titleSpan);
        try vstack_items.append(alloc, self.albumSpan);
        try vstack_items.append(alloc, self.progress);

        const vstack = try babylon.Blocks.VStack.init(
            alloc,
            try vstack_items.toOwnedSlice(self.alloc),
            16,
            .center,
            .{
                .width = babylon.sizingGrow(0, babylon.Max),
                .height = babylon.sizingGrow(0, babylon.Max),
            },
        );

        try hstack_items.append(alloc, coverArtContaniner);

        try hstack_items.append(alloc, vstack);

        const hstack = try babylon.Blocks.HStack.init(
            alloc,
            try hstack_items.toOwnedSlice(alloc),
            48,
            .end,
            .{
                .width = babylon.sizingFit(640, babylon.Max),
                .height = babylon.sizingFit(0, babylon.Max),
            },
        );

        try block.append(alloc, hstack);

        return block;
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.alloc.free(self.currentTrackId);
        ctx.alloc.destroy(self);
    }
};

const Root = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, loop: *babylon.eloop.Eloop) !*babylon.Block {
        const media_view = try MediaView.init(alloc, loop);

        const app = try babylon.Blocks.Container.init(
            alloc,
            media_view,
            .{
                .background_color = Theme.Background.darker,
                .sizing = .{
                    .width = babylon.sizingGrow(640, babylon.Max),
                    .height = babylon.sizingGrow(0, babylon.Max),
                },
                .padding = babylon.Padding.all(24),
            },
        );

        return app;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const application = try babylon.Application.init(alloc, "io.babylon.media_viewer");
    defer application.deinit();

    const root = try Root.init(alloc, application.loop);
    const window = try babylon.Window.init(application, root);

    window.set_dimensions(640, 270);
    window.set_title("Media Viewer!");

    try application.run();

    std.log.info("Babylon UI Framework - use 'zig build render' to see the render example", .{});
}
