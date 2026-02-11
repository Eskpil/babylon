const std = @import("std");
const babylon = @import("../babylon.zig");
const bindings = @import("../bindings.zig");

pub const Svg = struct {
    const Self = @This();

    width: f32,
    height: f32,

    rsvg_handle: *bindings.c.RsvgHandle,

    pub fn init(alloc: std.mem.Allocator, svg: []const u8, width: f32, height: f32) !*babylon.Block {
        const self = try alloc.create(Self);

        var err: ?*bindings.c.GError = null;

        const handle = bindings.c.rsvg_handle_new_from_data(svg.ptr, svg.len, @ptrCast(&err));
        if (handle == null) {
            std.log.info("could not create handle", .{});
            std.process.exit(69);
        }

        self.* = .{
            .width = width,
            .height = height,
            .rsvg_handle = handle,
        };

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );

        block.layout = layout;
        block.draw = draw;

        return block;
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = ctx;

        return babylon.BlockLayout{
            .sizing = .{
                .width = babylon.sizingGrow(self.width, babylon.Max),
                .height = babylon.sizingGrow(self.height, babylon.Max),
            },
        };
    }

    fn draw(context: *anyopaque, rect: babylon.LayoutRect, ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        const viewport = bindings.c.RsvgRectangle{
            .x = rect.x,
            .y = rect.y,
            .height = rect.height,
            .width = rect.width,
        };

        var err: ?*bindings.c.GError = null;

        if (bindings.c.rsvg_handle_render_document(self.rsvg_handle, ctx.painter.ctx, @ptrCast(&viewport), @ptrCast(&err)) != 1) {
            std.log.err("could not render the document: {s}", .{err.?.message});
            std.process.exit(78);
        }
    }
};
