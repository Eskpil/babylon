const std = @import("std");
const zigimg = @import("zigimg");
const babylon = @import("../babylon.zig");
const bindings = @import("../bindings.zig");

pub const Image = struct {
    const Self = @This();

    image: zigimg.Image,
    alloc: std.mem.Allocator,

    cached_cairo_surface: ?*bindings.c.cairo_surface_t,
    width: f32,
    height: f32,

    pub fn init(alloc: std.mem.Allocator, image_data: []const u8, width: ?f32, height: ?f32) !*babylon.Block {
        const self = try alloc.create(Self);

        const image = try zigimg.Image.fromMemory(alloc, image_data);

        self.* = .{
            .image = image,
            .alloc = alloc,
            .cached_cairo_surface = null,
            .width = @floatFromInt(image.width),
            .height = @floatFromInt(image.height),
        };

        if (width != null and height != null) {
            try self.resize(width.?, height.?);

            self.width = width.?;
            self.height = height.?;
        }

        const block = try babylon.Block.init(
            Self,
            alloc,
            self,
        );

        block.layout = layout;
        block.draw = draw;
        block.destroy = destroy;

        return block;
    }

    pub fn replace(self: *Self, image_data: []const u8) !void {
        if (self.cached_cairo_surface) |surface| {
            bindings.c.cairo_surface_destroy(surface);
        }

        self.image.deinit(self.alloc);

        const image = try zigimg.Image.fromMemory(self.alloc, image_data);
        self.image = image;

        try self.resize(self.width, self.height);
    }

    pub fn resize(self: *Self, w: f32, h: f32) !void {
        try self.image.convert(self.alloc, .bgra32);

        const stride = bindings.c.cairo_format_stride_for_width(bindings.c.CAIRO_FORMAT_ARGB32, @intCast(self.image.width));

        const src = bindings.c.cairo_image_surface_create_for_data(
            @ptrCast(self.image.pixels.bgra32.ptr),
            bindings.c.CAIRO_FORMAT_ARGB32,
            @intCast(self.image.width),
            @intCast(self.image.height),
            stride,
        );
        defer bindings.c.cairo_surface_destroy(src);

        if (src == null) {
            std.log.err("failed to create cairo surface from image", .{});
            return;
        }

        const src_w: f32 = @floatFromInt(self.image.width);
        const src_h: f32 = @floatFromInt(self.image.height);

        if (src_w == w and src_h == h) {
            if (self.cached_cairo_surface) |surface| {
                bindings.c.cairo_surface_destroy(surface);
            }

            self.cached_cairo_surface = src;
            return;
        }

        const dst = bindings.c.cairo_image_surface_create(
            bindings.c.CAIRO_FORMAT_ARGB32,
            @intFromFloat(w),
            @intFromFloat(h),
        );

        if (bindings.c.cairo_surface_status(dst) != bindings.c.CAIRO_STATUS_SUCCESS) {
            return error.CairoSurfaceCreationFailed;
        }

        const cr = bindings.c.cairo_create(dst);
        defer bindings.c.cairo_destroy(cr);

        const scale_x = w / src_w;
        const scale_y = h / src_h;

        bindings.c.cairo_scale(cr, scale_x, scale_y);
        bindings.c.cairo_set_source_surface(cr, src, 0, 0);

        // High-quality downscaling (important!)
        const pattern = bindings.c.cairo_get_source(cr);
        bindings.c.cairo_pattern_set_filter(pattern, bindings.c.CAIRO_FILTER_BEST);

        bindings.c.cairo_paint(cr);

        if (self.cached_cairo_surface) |surface| {
            bindings.c.cairo_surface_destroy(surface);
        }

        self.cached_cairo_surface = dst;
        return;
    }

    fn destroy(context: *anyopaque, ctx: babylon.DestroyContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        if (self.cached_cairo_surface) |surface| {
            bindings.c.cairo_surface_destroy(surface);
        }

        self.image.deinit(self.alloc);
        ctx.alloc.destroy(self);
    }

    fn layout(context: *anyopaque, ctx: babylon.LayoutContext) babylon.BlockLayout {
        const self: *Self = @ptrCast(@alignCast(context));

        _ = ctx;

        return .{
            .sizing = .{
                .width = babylon.sizingFixed(self.width),
                .height = babylon.sizingFixed(self.height),
            },
        };
    }

    fn draw(context: *anyopaque, rect: babylon.LayoutRect, ctx: babylon.PaintContext) !void {
        const self: *Self = @ptrCast(@alignCast(context));

        if (self.cached_cairo_surface) |surface| {
            try ctx.painter.drawSurface(rect.x, rect.y, surface);
        }
    }
};
