const std = @import("std");
const babylon = @import("babylon");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Create arena for per-frame allocations
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Initialize text cache
    var text_cache = babylon.TextCache.init(alloc);
    defer text_cache.deinit();

    // Initialize painter (800x600 canvas)
    var painter = try babylon.Painter.init(800, 600);
    defer painter.deinit();

    // Clear background to white
    painter.clear(.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });

    // Initialize font manager
    var font_manager = try babylon.text.FontManager.init(alloc);
    defer font_manager.deinit();

    // Create Application instance for context
    var app = try babylon.Application.init(alloc, "babylon-example");
    defer app.deinit();

    // Create text spans
    const hello_text = try babylon.Blocks.Span.init(
        arena_alloc,
        "Hei verden, whææææ!",
        null,
        .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 32,
            .color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 }, // Black text
        },
    );

    const center = try babylon.Blocks.Center.init(
        arena_alloc,
        hello_text,
        .{},
    );

    const container = try babylon.Blocks.Container.init(arena_alloc, center, .{
        .background_color = .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
        .padding = babylon.Padding.all(12),
        .sizing = .{
            .height = babylon.sizingFit(32, std.math.floatMax(f32)),
            .width = babylon.sizingFit(20, 340),
        },
        .border_radius = 12,
    });

    // Center on screen
    const root = try babylon.Blocks.Center.init(
        arena_alloc,
        container,
        .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
        },
    );

    // Create Shell instance for context
    var shell = try alloc.create(babylon.Shell);
    defer alloc.destroy(shell);
    shell.* = babylon.Shell{
        .aylin_shell = undefined,
        .root = root,
        .app = app,
        .size = .{ .width = 800, .height = 600 },
        .text_cache = text_cache,
        .current_hovering = null,
    };

    // Run layout
    babylon.calculateLayout(root, 800, 600, &font_manager, &text_cache, arena_alloc, app, shell);

    // Paint
    const paint_ctx = babylon.PaintContext{
        .painter = &painter,
        .font_manager = &font_manager,
        .text_cache = &text_cache,
        .allocator = arena_alloc,
        .block = root,
        .app = app,
        .shell = shell,
    };
    try paintTree(root, paint_ctx);

    // Save to PNG
    try painter.saveToPNG("text_output.png");

    std.log.info("Text rendered to text_output.png!", .{});
}

fn paintTree(block: *babylon.Block, paint_ctx: babylon.PaintContext) anyerror!void {
    // Draw block if it has a draw function (primitives and some layout blocks like Container)
    if (block.draw) |drawFn| {
        const rect = babylon.LayoutRect{
            .x = block.computed.x,
            .y = block.computed.y,
            .width = block.computed.width,
            .height = block.computed.height,
        };
        try drawFn(block.context, rect, paint_ctx);
    }

    // Recursively paint children
    for (block.children) |child| {
        try paintTree(child, paint_ctx);
    }
}
