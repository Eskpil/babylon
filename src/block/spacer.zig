const std = @import("std");

const babylon = @import("../babylon.zig");

// Spacer is an invisible block that grows to fill available space
pub const Spacer = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{};

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .primitive,
            .context = self,
            .key = null,
            .name = "spacer",
            .kind = "spacer",
            .layout = layout,
            .draw = draw,
        };
        return block;
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        _ = context;
        _ = ctx;

        return .{
            .direction = .z_stack,
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
        };
    }

    pub fn draw(context: *anyopaque, rect: babylon.LayoutRect, paint_ctx: babylon.PaintContext) !void {
        _ = context;
        _ = rect;
        _ = paint_ctx;
        // Invisible - spacers don't draw anything
    }
};
