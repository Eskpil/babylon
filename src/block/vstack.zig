const std = @import("std");

const babylon = @import("../babylon.zig");

// VStack arranges children vertically (top to bottom)
pub const VStack = struct {
    const Self = @This();

    spacing: f32,
    alignment: babylon.ChildAlignment,
    sizing: babylon.Sizing,

    pub fn init(
        alloc: std.mem.Allocator,
        children: []*babylon.Block,
        spacing: f32,
        alignment: babylon.ChildAlignment,
        sizing: babylon.Sizing,
    ) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .spacing = spacing,
            .alignment = alignment,
            .sizing = sizing,
        };

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );
        block.layout = layout;
        block.destroy = destroy;

        for (children) |child| {
            try block.append(alloc, child);
        }

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
            .direction = .top_to_bottom,
            .sizing = sizing,
            .child_gap = self.spacing,
            .child_alignment = self.alignment,
        };
    }
};
