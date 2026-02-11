const std = @import("std");

const babylon = @import("../babylon.zig");

// Center centers a single child within the available space
pub const Center = struct {
    const Self = @This();

    sizing: babylon.Sizing,

    pub fn init(alloc: std.mem.Allocator, child: *babylon.Block, sizing: babylon.Sizing) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{ .sizing = sizing };

        const block = try babylon.Block.init(
            Center,
            alloc,
            self,
        );
        block.layout = layout;
        block.destroy = destroy;

        try block.append(alloc, child);

        return block;
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        ctx.alloc.destroy(self);
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));

        // If we have fit sizing and a parent with constraints, inherit parent's max
        var sizing = self.sizing;
        if (ctx.parent_layout) |parent| {
            if (sizing.width.type == .fit and parent.sizing.width.max < sizing.width.max) {
                sizing.width.max = parent.sizing.width.max;
            }
            if (sizing.height.type == .fit and parent.sizing.height.max < sizing.height.max) {
                sizing.height.max = parent.sizing.height.max;
            }
        }

        return .{
            .direction = .z_stack, // Use z_stack so child doesn't affect parent size
            .sizing = sizing,
            .child_alignment = .center, // Center on both axes
        };
    }
};
