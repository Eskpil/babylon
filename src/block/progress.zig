const std = @import("std");

const babylon = @import("../babylon.zig");

const ProgressFill = struct {
    const Self = @This();

    progress: f64,
    color: babylon.Color,

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));

        var sizing = babylon.Sizing{};

        if (ctx.parent_layout) |parent| {
            sizing.height = parent.sizing.height;
        }

        const parent_width = if (ctx.parent_layout) |parent| blk: {
            switch (parent.sizing.width.type) {
                .fixed => break :blk parent.sizing.width.value,
                .grow, .fit => break :blk parent.sizing.width.max,
                .percent => break :blk parent.sizing.width.max,
            }
        } else blk: {
            break :blk std.math.floatMax(f32);
        };

        const clamped = std.math.clamp(self.progress, 0.0, 1.0);

        sizing.width.type = .fixed;

        sizing.width.value = parent_width * @as(f32, @floatCast(clamped));

        return .{
            .direction = .z_stack,
            .sizing = sizing,
        };
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        ctx.alloc.destroy(self);
    }
};

pub const Progress = struct {
    const Self = @This();

    sizing: babylon.Sizing,
    progress: f64,
    fill: ProgressFill = .{
        .progress = 0.0,
        .color = .{
            .a = 0.0,
            .b = 0.0,
            .r = 0.0,
            .g = 0.0,
        },
    },
    color: babylon.Color,

    pub fn init(
        alloc: std.mem.Allocator,
        progress: f64,
        color: babylon.Color,
        sizing: babylon.Sizing,
    ) !*babylon.Block {
        const self = try alloc.create(Self);

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );

        block.destroy = destroy;

        // Track
        const track = try babylon.Blocks.Container.init(
            alloc,
            null,
            .{
                .sizing = sizing,
                .border_radius = 4,
                .background_color = .{ .a = 1, .r = 0.2, .g = 0.2, .b = 0.2 },
            },
        );

        self.fill.progress = progress;
        self.fill.color = color;

        const fill_block = try babylon.Block.init(
            ProgressFill,
            alloc,
            &self.fill,
        );
        fill_block.layout = ProgressFill.layout;

        self.* = .{
            .sizing = sizing,
            .progress = progress,
            .color = color,
        };

        // Fill visuals
        const fill_container = try babylon.Blocks.Container.init(
            alloc,
            fill_block,
            .{
                .sizing = .{
                    .height = sizing.height,
                    .width = babylon.sizingFit(0, 250),
                },
                .border_radius = 4,
                .background_color = color,
            },
        );

        try track.append(alloc, fill_container);
        try block.append(alloc, track);

        return block;
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        ctx.alloc.destroy(self);
    }

    pub fn setProgress(self: *Self, progress: f64) !void {
        self.fill.progress = progress;
    }
};
