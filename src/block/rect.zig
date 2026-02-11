const std = @import("std");

const babylon = @import("../babylon.zig");

pub const Rect = struct {
    const Self = @This();

    sizing: babylon.Sizing,
    color: babylon.Color,
    border_radius: f32 = 0,

    pub fn init(alloc: std.mem.Allocator, sizing: babylon.Sizing, color: babylon.Color) !*babylon.Block {
        const self = try alloc.create(Rect);
        self.* = Rect{ .sizing = sizing, .color = color };

        const block = try babylon.Block.init(Self, alloc, .primitive, self);
        block.layout = layout;
        block.draw = draw;

        return block;
    }

    pub fn initWithRadius(alloc: std.mem.Allocator, sizing: babylon.Sizing, color: babylon.Color, border_radius: f32) !*babylon.Block {
        const self = try alloc.create(Rect);
        self.* = Rect{ .sizing = sizing, .color = color, .border_radius = border_radius };

        const block = try babylon.Block.init(Self, alloc, .primitive, self);
        block.layout = layout;
        block.draw = draw;

        return block;
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        _ = ctx;
        const self: *Self = @ptrCast(@alignCast(context));
        return .{
            .sizing = self.sizing,
        };
    }

    pub fn draw(context: *anyopaque, rect: babylon.LayoutRect, paint_ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        if (self.border_radius > 0) {
            paint_ctx.painter.fillRoundedRect(rect.x, rect.y, rect.width, rect.height, self.border_radius, self.color);
        } else {
            paint_ctx.painter.fillRect(rect.x, rect.y, rect.width, rect.height, self.color);
        }
    }
};
