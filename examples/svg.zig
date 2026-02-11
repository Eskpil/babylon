const std = @import("std");
const babylon = @import("babylon");

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

const ImageStack = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !*babylon.Block {
        const tiger_svg = @embedFile("fish.svg");
        const jpeg = @embedFile("mountain.jpeg");

        const svg = try babylon.Blocks.Svg.init(
            alloc,
            tiger_svg,
            24 * 5,
            24 * 5,
        );

        const image = try babylon.Blocks.Image.init(alloc, jpeg, null, null);

        var stack: std.ArrayList(*babylon.Block) = .empty;
        try stack.append(alloc, svg);
        try stack.append(alloc, image);

        return try babylon.Blocks.VStack.init(
            alloc,
            stack.items,
            32,
            .center,
            .{},
        );
    }
};

const Root = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !*babylon.Block {
        const image_stack = try ImageStack.init(alloc);

        const center = try babylon.Blocks.Center.init(alloc, image_stack, .{
            .width = babylon.sizingGrow(300, babylon.Max),
            .height = babylon.sizingGrow(300, babylon.Max),
        });

        const app = try babylon.Blocks.Container.init(alloc, center, .{
            .background_color = Theme.Background.darker,
            .sizing = .{
                .width = babylon.sizingGrow(0, babylon.Max),
                .height = babylon.sizingGrow(0, babylon.Max),
            },
            .padding = babylon.Padding.all(24),
        });
        return app;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const application = try babylon.Application.init(alloc, "io.babylon.image_examples");
    defer application.deinit();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const root = try Root.init(arena_alloc);

    const window = try babylon.Window.init(application, root);
    window.set_title("Svg example!");

    const window_2 = try babylon.Window.init(application, root);
    window_2.set_title("Svg example 2!");

    try application.run();
}
