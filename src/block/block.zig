const std = @import("std");
const painter = @import("../painter.zig");
const text = @import("../text.zig");
const babylon = @import("../babylon.zig");

pub const MouseButton = enum {
    left,
    right,
    middle,
    back,
};

pub const MouseButtonState = enum {
    press,
    release,
};

pub const InteractionContext = struct {
    pub const Kind = enum {
        hover,
        mouse_button,
        key,
        key_repeat,
    };

    pub const HoverData = struct {
        enter: bool,
        x: f32,
        y: f32,
    };

    pub const MouseButtonData = struct {
        x: f32,
        y: f32,
        button: MouseButton,
        state: MouseButtonState,
    };

    pub const Data = union {
        hover: HoverData,
        mouse_button: MouseButtonData,
    };

    kind: Kind,
    data: Data,
    app: *babylon.Application,
    shell: *babylon.Shell,
};

pub const SizingType = enum {
    fit, // wrap to content
    grow, // fill available space
    fixed, // exact size
    percent, // % of parent
};

pub const SizingAxis = struct {
    type: SizingType = .fit,
    min: f32 = 0,
    max: f32 = std.math.floatMax(f32),
    value: f32 = 0, // For .fixed and .percent types
};

pub const Sizing = struct {
    width: SizingAxis = .{},
    height: SizingAxis = .{},
};

pub const LayoutDirection = enum {
    left_to_right, // HStack
    top_to_bottom, // VStack
    z_stack, // ZStack (all children overlap)
};

pub const ChildAlignment = enum {
    start,
    center,
    end,
    stretch,
};

pub const Padding = struct {
    const Self = @This();

    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,

    pub fn tblr(t: f32, b: f32, l: f32, r: f32) Self {
        return .{
            .top = t,
            .bottom = b,
            .left = l,
            .right = r,
        };
    }

    pub fn all(padding: f32) Self {
        return .{
            .left = padding,
            .right = padding,
            .top = padding,
            .bottom = padding,
        };
    }

    pub fn horizontal(padding: f32) Self {
        return .{
            .left = padding,
            .right = padding,
            .top = 0,
            .bottom = 0,
        };
    }

    pub fn vertical(padding: f32) Self {
        return .{
            .top = padding,
            .bottom = padding,
        };
    }
};

pub const Border = struct {
    const Self = @This();

    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,
    color: ?babylon.Color = null,

    pub fn all(width: f32, color: ?babylon.Color) Self {
        return .{
            .left = width,
            .right = width,
            .top = width,
            .bottom = width,
            .color = color,
        };
    }

    pub fn horizontal(width: f32, color: ?babylon.Color) Self {
        return .{
            .left = width,
            .right = width,
            .top = 0,
            .bottom = 0,
            .color = color,
        };
    }

    pub fn vertical(width: f32, color: ?babylon.Color) Self {
        return .{
            .top = width,
            .bottom = width,
            .left = 0,
            .right = 0,
            .color = color,
        };
    }

    pub fn tblr(t: f32, b: f32, l: f32, r: f32, color: ?babylon.Color) Self {
        return .{
            .top = t,
            .bottom = b,
            .left = l,
            .right = r,
            .color = color,
        };
    }
};

pub const BlockLayout = struct {
    sizing: Sizing = .{},
    direction: LayoutDirection = .top_to_bottom,

    // Alignment of children on the cross-axis
    child_alignment: ChildAlignment = .start,

    // Gap between children
    child_gap: f32 = 0,

    // Padding
    padding: Padding = .{},
};

pub const LayoutRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const LayoutContext = struct {
    parent_layout: ?BlockLayout = null,
    font_manager: *babylon.text.FontManager,
    allocator: std.mem.Allocator,
    block: *Block, // Reference to the block being laid out
    app: *babylon.Application,
    shell: *babylon.Shell,
};

pub const PaintContext = struct {
    painter: *babylon.Painter,
    font_manager: *babylon.text.FontManager,
    allocator: std.mem.Allocator,
    block: *Block, // Reference to the block being painted
    app: *babylon.Application,
    shell: *babylon.Shell,
    scale_factor: f32, // HiDPI scale factor for rendering
};

pub const DestroytContext = struct {
    app: *babylon.Application,
    shell: *babylon.Shell,
    alloc: std.mem.Allocator,
};

pub const Block = struct {
    const Self = @This();

    pub const Draw = *const fn (*anyopaque, LayoutRect, PaintContext) anyerror!void;
    pub const Layout = *const fn (*anyopaque, LayoutContext) BlockLayout;
    pub const Interaction = *const fn (*anyopaque, InteractionContext) anyerror!void;
    pub const Destroy = *const fn (*anyopaque, DestroytContext) anyerror!void;

    context: *anyopaque,
    children: std.ArrayList(*babylon.Block),

    name: []const u8,

    // Computed during layout pass
    computed: struct {
        width: f32 = 0,
        height: f32 = 0,
        x: f32 = 0,
        y: f32 = 0,
    } = .{},

    draw: ?Draw = null,
    layout: ?Layout = null,
    interaction: ?Interaction = null,
    destroy: ?Destroy = null,

    parent: ?*babylon.Block = null,

    pub fn init(comptime T: anytype, alloc: std.mem.Allocator, context: *anyopaque) !*babylon.Block {
        const self = try alloc.create(Self);

        self.* = .{
            .name = @typeName(T),
            .context = context,
            .children = .empty,
        };

        return self;
    }

    pub fn append(self: *Self, alloc: std.mem.Allocator, child: *babylon.Block) !void {
        child.parent = self;
        try self.children.append(alloc, child);
    }
};

pub fn destroyTree(block: *Block, ctx: DestroytContext) !void {
    for (block.children.items) |child| {
        try destroyTree(child, ctx);
    }

    std.log.debug("destroy callback on: {s}: {?}?", .{ block.name, block.destroy });
    if (block.destroy) |destroyFn| {
        std.log.debug("> calling vtable.destroy on: {s}", .{block.name});
        try destroyFn(block.context, ctx);
    } else {
        std.log.err("Destroy called on block without destroy callback, block in question: {s}", .{block.name});
    }

    std.log.debug(" > destroying children list of {s}", .{block.name});
    block.children.deinit(ctx.alloc);
    ctx.alloc.destroy(block);
}

pub fn paintTree(b: *Block, paint_ctx: PaintContext) anyerror!void {
    // Create context with current block reference
    var ctx_with_block = paint_ctx;
    ctx_with_block.block = b;

    if (b.draw) |drawFn| {
        const r = LayoutRect{
            .x = b.computed.x,
            .y = b.computed.y,
            .width = b.computed.width,
            .height = b.computed.height,
        };
        try drawFn(b.context, r, ctx_with_block);
    }

    for (b.children.items) |child| {
        try paintTree(child, paint_ctx);
    }
}

// Helper functions for creating sizing
pub fn sizingFit(min: f32, max: f32) SizingAxis {
    return .{ .type = .fit, .min = min, .max = max };
}

pub fn sizingGrow(min: f32, max: f32) SizingAxis {
    return .{ .type = .grow, .min = min, .max = max };
}

pub fn sizingFixed(size: f32) SizingAxis {
    return .{ .type = .fixed, .value = size, .min = size, .max = size };
}

pub fn sizingPercent(percent: f32) SizingAxis {
    return .{ .type = .percent, .value = percent };
}
