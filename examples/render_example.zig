const std = @import("std");
const babylon = @import("babylon");

fn materializeTree(block: *babylon.Block, arena: std.mem.Allocator) anyerror!*babylon.Block {
    if (block.build) |buildFn| {
        // It's a composition block - build it
        const built = try buildFn(block.context, arena);
        // Recursively materialize the built tree
        return try materializeTree(built, arena);
    }

    // Layout block - materialize all children
    if (block.children.len > 0) {
        for (block.children) |child| {
            _ = try materializeTree(child, arena);
        }
    }

    return block;
}

fn paintTree(block: *babylon.Block, paint_ctx: babylon.PaintContext) anyerror!void {
    if (block.purpose == .primitive and block.draw != null) {
        const rect = babylon.LayoutRect{
            .x = block.computed.x,
            .y = block.computed.y,
            .width = block.computed.width,
            .height = block.computed.height,
        };
        try block.draw.?(block.context, rect, paint_ctx);
    }

    for (block.children) |child| {
        try paintTree(child, paint_ctx);
    }
}

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

    // Initialize font manager (required even if not using text)
    var font_manager = try babylon.text.FontManager.init(alloc);
    defer font_manager.deinit();

    // Create Application instance for context
    var app = try babylon.Application.init(alloc, "babylon-example");
    defer app.deinit();

    // Build UI tree
    const red_rect = try babylon.Blocks.Rect.initWithRadius(
        arena_alloc,
        .{
            .width = babylon.sizingFixed(100),
            .height = babylon.sizingFixed(100),
        },
        .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        15, // border radius
    );

    const green_rect = try babylon.Blocks.Rect.initWithRadius(
        arena_alloc,
        .{
            .width = babylon.sizingGrow(100, std.math.floatMax(f32)),
            .height = babylon.sizingFixed(80),
        },
        .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
        10, // border radius
    );

    const blue_rect = try babylon.Blocks.Rect.initWithRadius(
        arena_alloc,
        .{
            .width = babylon.sizingFixed(100),
            .height = babylon.sizingFixed(100),
        },
        .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
        20, // border radius
    );

    // Create a horizontal stack with fixed width so GROW child has space
    var hstack_children = [_]*babylon.Block{ red_rect, green_rect, blue_rect };
    const hstack = try babylon.Blocks.HStack.init(
        arena_alloc,
        &hstack_children,
        20, // spacing
        .start, // alignment
        .{
            .width = babylon.sizingFixed(600), // Fixed width for green to grow within
            .height = babylon.sizingFit(0, std.math.floatMax(f32)),
        },
    );

    // Center the hstack on the screen
    const container = try babylon.Blocks.Center.init(
        arena_alloc,
        hstack,
        .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
        },
    );

    // Materialize composition blocks
    const materialized = try materializeTree(container, arena_alloc);

    // Create Shell instance for context
    var shell = try alloc.create(babylon.Shell);
    defer alloc.destroy(shell);
    shell.* = babylon.Shell{
        .aylin_shell = undefined,
        .root = materialized,
        .app = app,
        .size = .{ .width = 800, .height = 600 },
        .text_cache = text_cache,
        .current_hovering = null,
    };

    // Run layout
    babylon.calculateLayout(materialized, 800, 600, &font_manager, &text_cache, arena_alloc, app, shell);

    // Paint
    const paint_ctx = babylon.PaintContext{
        .painter = &painter,
        .font_manager = &font_manager,
        .text_cache = &text_cache,
        .allocator = arena_alloc,
        .block = materialized,
        .app = app,
        .shell = shell,
    };
    try paintTree(materialized, paint_ctx);

    // Save to PNG
    try painter.saveToPNG("output.png");

    std.log.info("Rendered to output.png!", .{});
}
