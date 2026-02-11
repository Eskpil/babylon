const std = @import("std");

const babylon = @import("../babylon.zig");

pub const ContainerConfig = struct {
    sizing: babylon.Sizing = .{},
    padding: babylon.Padding = .{},
    background_color: ?babylon.Color = null,
    border_radius: f32 = 0,
    border: babylon.Border = .{},
};

// Container is a layout block that wraps a single child with padding, sizing, and optional background
pub const Container = struct {
    const Self = @This();

    config: ContainerConfig,

    pub fn init(
        alloc: std.mem.Allocator,
        child: ?*babylon.Block,
        config: ContainerConfig,
    ) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .config = config,
        };

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );
        block.draw = draw;
        block.layout = layout;
        block.destroy = destroy;

        if (child) |c| {
            try block.append(alloc, c);
        }

        return block;
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        std.log.debug("destroying container!", .{});

        const self: *Self = @ptrCast(@alignCast(context));
        ctx.alloc.destroy(self);
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));

        // If we have fit sizing and a parent with constraints, inherit parent's max
        var sizing = self.config.sizing;
        if (ctx.parent_layout) |parent| {
            if (sizing.width.type == .fit and parent.sizing.width.max < sizing.width.max) {
                sizing.width.max = parent.sizing.width.max;
            }
            if (sizing.height.type == .fit and parent.sizing.height.max < sizing.height.max) {
                sizing.height.max = parent.sizing.height.max;
            }
        }

        return .{
            .direction = .z_stack,
            .sizing = sizing,
            .padding = self.config.padding,
        };
    }

    pub fn set_background_color(self: *Self, color: babylon.Color) void {
        self.config.background_color = color;
    }

    pub fn get_background_color(self: *Self) babylon.Color {
        return self.config.background_color.?;
    }

    fn draw(context: *anyopaque, rect: babylon.LayoutRect, paint_ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        // Draw background if specified
        if (self.config.background_color) |color| {
            if (self.config.border_radius > 0) {
                paint_ctx.painter.fillRoundedRect(rect.x, rect.y, rect.width, rect.height, self.config.border_radius, color);
            } else {
                paint_ctx.painter.fillRect(rect.x, rect.y, rect.width, rect.height, color);
            }
        }

        // Draw borders if specified
        if (self.config.border.color) |border_color| {
            const border = self.config.border;

            // Check if all borders are the same width
            const uniform_border = border.top == border.right and
                border.right == border.bottom and
                border.bottom == border.left and
                border.top > 0;

            if (uniform_border and self.config.border_radius > 0) {
                // Use strokeRoundedRect for uniform borders with radius
                paint_ctx.painter.strokeRoundedRect(
                    rect.x + border.left / 2,
                    rect.y + border.top / 2,
                    rect.width - border.left / 2,
                    rect.height - border.top / 2,
                    self.config.border_radius,
                    border.top,
                    border_color,
                );
            } else if (uniform_border) {
                // Use strokeRect for uniform borders without radius
                paint_ctx.painter.strokeRect(
                    rect.x + border.left / 2,
                    rect.y + border.top / 2,
                    rect.width - border.left / 2,
                    rect.height - border.top / 2,
                    border.top,
                    border_color,
                );
            } else {
                // Draw individual border edges
                if (border.top > 0) {
                    paint_ctx.painter.fillRect(
                        rect.x,
                        rect.y,
                        rect.width,
                        border.top,
                        border_color,
                    );
                }
                if (border.right > 0) {
                    paint_ctx.painter.fillRect(
                        rect.x + rect.width - border.right,
                        rect.y,
                        border.right,
                        rect.height,
                        border_color,
                    );
                }
                if (border.bottom > 0) {
                    paint_ctx.painter.fillRect(
                        rect.x,
                        rect.y + rect.height - border.bottom,
                        rect.width,
                        border.bottom,
                        border_color,
                    );
                }
                if (border.left > 0) {
                    paint_ctx.painter.fillRect(
                        rect.x,
                        rect.y,
                        border.left,
                        rect.height,
                        border_color,
                    );
                }
            }
        }
    }
};
