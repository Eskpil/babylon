const std = @import("std");

const babylon = @import("../babylon.zig");

pub const SeparatorOrientation = enum {
    horizontal,
    vertical,
};

// Separator is a visual divider line
pub const Separator = struct {
    const Self = @This();

    orientation: SeparatorOrientation,
    color: babylon.Color,
    thickness: f32,

    pub fn init(
        alloc: std.mem.Allocator,
        orientation: SeparatorOrientation,
        color: babylon.Color,
        thickness: f32,
    ) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .orientation = orientation,
            .color = color,
            .thickness = thickness,
        };

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .primitive,
            .context = self,
            .key = null,
            .name = "separator",
            .kind = "separator",
            .layout = layout,
            .draw = draw,
        };
        return block;
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = ctx;

        return switch (self.orientation) {
            .horizontal => .{
                .direction = .z_stack,
                .sizing = .{
                    .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                    .height = babylon.sizingFixed(self.thickness),
                },
            },
            .vertical => .{
                .direction = .z_stack,
                .sizing = .{
                    .width = babylon.sizingFixed(self.thickness),
                    .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
                },
            },
        };
    }

    pub fn draw(context: *anyopaque, rect: babylon.LayoutRect, paint_ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        paint_ctx.painter.fillRect(rect.x, rect.y, rect.width, rect.height, self.color);
    }
};
