const std = @import("std");

const babylon = @import("../babylon.zig");

// ZStack is a layout block, allowing layout to be done on the Z-axis.
// With the z-stacking being done in the order of the children. The first
// child has the lowest "z-index" and the last child has the highest.
pub const ZStack = struct {
    const Self = @This();

    sizing: babylon.Sizing,

    pub fn init(alloc: std.mem.Allocator, children: []*babylon.Block, sizing: babylon.Sizing) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{ .sizing = sizing };

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .layout,
            .context = self,
            .children = children,
            .key = null,
            .name = "zstack",
            .kind = "zstack",
            .layout = layout,
        };
        return block;
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        _ = ctx;
        const self: *Self = @ptrCast(@alignCast(context));
        return .{
            .direction = .z_stack,
            .sizing = self.sizing,
        };
    }
};
