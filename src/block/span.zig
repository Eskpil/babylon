const std = @import("std");

const babylon = @import("../babylon.zig");

const SpanCache = struct {
    wrap_width: f32,
    font_size: f32,
    lines: []babylon.text.TextLine,
};

// Span is our primitive text block, it resembles the HTML span element.
pub const Span = struct {
    const Self = @This();

    pub const SpanConfig = struct {
        font: []const u8,
        weight: babylon.FontWeight,
        slant: babylon.FontSlant,
        size: f32,
        color: babylon.Color,
    };

    text: []const u8 = undefined,
    config: SpanConfig,
    alloc: std.mem.Allocator,

    cache: ?SpanCache = null,

    pub fn init(
        alloc: std.mem.Allocator,
        text: []const u8,
        config: SpanConfig,
    ) !*babylon.Block {
        const self = try alloc.create(Self);

        self.* = Self{
            .text = try alloc.dupe(u8, text),
            .config = config,
            .alloc = alloc,
        };

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );
        block.draw = draw;
        block.layout = layout;
        block.destroy = destroy;

        return block;
    }

    pub fn update(self: *Self, text: []const u8) !void {
        self.alloc.free(self.text);

        self.text = try self.alloc.dupe(u8, text);

        self.freeCache();
    }

    fn freeCache(self: *Self) void {
        if (self.cache) |cached| {
            self.alloc.free(cached.lines);
            self.cache = null;
        }
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        self.freeCache();

        self.alloc.free(self.text);
        ctx.alloc.destroy(self);
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));

        // Determine wrap width from parent constraints
        const wrap_width = if (ctx.parent_layout) |parent| blk: {
            switch (parent.sizing.width.type) {
                .fixed => break :blk parent.sizing.width.value,
                .grow, .fit => break :blk parent.sizing.width.max,
                .percent => break :blk parent.sizing.width.max,
            }
        } else blk: {
            break :blk std.math.floatMax(f32);
        };

        // Use block path as cache key
        // Check text cache first
        if (self.cache) |cached| {
            const num_lines: f32 = @floatFromInt(cached.lines.len);
            const text_height = num_lines * cached.font_size;

            var max_line_width: f32 = 0;
            for (cached.lines) |line| {
                max_line_width = @max(max_line_width, line.width);
            }

            return .{
                .direction = .z_stack,
                .sizing = .{
                    .width = babylon.sizingFixed(max_line_width),
                    .height = babylon.sizingFixed(text_height),
                },
            };
        }

        // Cache miss - calculate layout
        const font_face = ctx.font_manager.find(self.config.font, self.config.weight, self.config.slant, self.config.size) catch unreachable;

        // Wrap text and calculate height
        const lines = babylon.text.wrapText(self.alloc, self.text, wrap_width, font_face) catch unreachable;

        const num_lines: f32 = @floatFromInt(lines.len);
        const text_height = num_lines * font_face.font_size;

        // Calculate actual width based on wrapping
        var max_line_width: f32 = 0;
        for (lines) |line| {
            max_line_width = @max(max_line_width, line.width);
        }

        self.cache = .{
            .wrap_width = wrap_width,
            .lines = lines,
            .font_size = font_face.font_size,
        };

        return .{
            .direction = .z_stack,
            .sizing = .{
                .width = babylon.sizingFixed(max_line_width),
                .height = babylon.sizingFixed(text_height),
            },
        };
    }

    pub fn draw(context: *anyopaque, rect: babylon.LayoutRect, paint_ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        const font_face = try paint_ctx.font_manager.find(self.config.font, self.config.weight, self.config.slant, self.config.size);

        // Try to get cached lines - they should be there since layout already computed them
        const lines = if (self.cache) |cached|
            cached.lines
        else
            // Fallback: re-wrap if not in cache (shouldn't happen in normal flow)
            try babylon.text.wrapText(self.alloc, self.text, rect.width, font_face);

        if (self.cache) |cached| {
            if (rect.width > cached.wrap_width) {
                self.freeCache();
            }
        }

        for (lines, 0..lines.len) |line, i| {
            const fi: f32 = @floatFromInt(i);

            const shaped = try babylon.text.shapeText(self.alloc, line.text, font_face);

            paint_ctx.painter.renderText(&shaped, font_face, rect.x, rect.y + fi * font_face.font_size, self.config.color);

            self.alloc.free(shaped.glyphs);
        }
    }
};
