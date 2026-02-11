const std = @import("std");
const bindings = @import("bindings.zig");
const text = @import("text.zig");

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,
};

pub const Painter = struct {
    surface: *bindings.c.cairo_surface_t,
    ctx: *bindings.c.cairo_t,
    width: u32,
    height: u32,

    pub fn initWithSurface(surface: *bindings.c.cairo_surface_t, width: u32, height: u32) !Painter {
        const status = bindings.c.cairo_surface_status(surface);
        if (status != bindings.c.CAIRO_STATUS_SUCCESS) {
            bindings.c.cairo_surface_destroy(surface);
            return error.CairoSurfaceCreateFailed;
        }

        const ctx = bindings.c.cairo_create(surface) orelse {
            bindings.c.cairo_surface_destroy(surface);
            return error.CairoContextCreateFailedclose;
        };

        return Painter{
            .surface = surface,
            .ctx = ctx,
            .width = width,
            .height = height,
        };
    }

    pub fn init(width: u32, height: u32) !Painter {
        const surface = bindings.c.cairo_image_surface_create(
            bindings.c.CAIRO_FORMAT_ARGB32,
            @intCast(width),
            @intCast(height),
        ) orelse return error.CairoSurfaceCreateFailed;

        return initWithSurface(surface, width, height);
    }

    pub fn deinit(self: *Painter) void {
        bindings.c.cairo_destroy(self.ctx);
        bindings.c.cairo_surface_destroy(self.surface);
    }

    pub fn clear(self: *Painter, color: Color) void {
        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );
        bindings.c.cairo_paint(self.ctx);
    }

    pub fn fillRect(self: *Painter, x: f32, y: f32, width: f32, height: f32, color: Color) void {
        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );
        bindings.c.cairo_rectangle(
            self.ctx,
            @floatCast(x),
            @floatCast(y),
            @floatCast(width),
            @floatCast(height),
        );
        bindings.c.cairo_fill(self.ctx);
    }

    pub fn fillRoundedRect(self: *Painter, x: f32, y: f32, width: f32, height: f32, radius: f32, color: Color) void {
        const x_f64: f64 = @floatCast(x);
        const y_f64: f64 = @floatCast(y);
        const width_f64: f64 = @floatCast(width);
        const height_f64: f64 = @floatCast(height);
        const radius_f64: f64 = @floatCast(radius);

        const degrees = std.math.pi / 180.0;

        bindings.c.cairo_new_sub_path(self.ctx);
        bindings.c.cairo_arc(self.ctx, x_f64 + width_f64 - radius_f64, y_f64 + radius_f64, radius_f64, -90 * degrees, 0 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + width_f64 - radius_f64, y_f64 + height_f64 - radius_f64, radius_f64, 0 * degrees, 90 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + radius_f64, y_f64 + height_f64 - radius_f64, radius_f64, 90 * degrees, 180 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + radius_f64, y_f64 + radius_f64, radius_f64, 180 * degrees, 270 * degrees);
        bindings.c.cairo_close_path(self.ctx);

        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );
        bindings.c.cairo_fill(self.ctx);
    }

    pub fn strokeRect(self: *Painter, x: f32, y: f32, width: f32, height: f32, line_width: f32, color: Color) void {
        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );
        bindings.c.cairo_set_line_width(self.ctx, @floatCast(line_width));
        bindings.c.cairo_rectangle(
            self.ctx,
            @floatCast(x),
            @floatCast(y),
            @floatCast(width),
            @floatCast(height),
        );
        bindings.c.cairo_stroke(self.ctx);
    }

    pub fn strokeRoundedRect(self: *Painter, x: f32, y: f32, width: f32, height: f32, radius: f32, line_width: f32, color: Color) void {
        const x_f64: f64 = @floatCast(x);
        const y_f64: f64 = @floatCast(y);
        const width_f64: f64 = @floatCast(width);
        const height_f64: f64 = @floatCast(height);
        const radius_f64: f64 = @floatCast(radius);

        const degrees = std.math.pi / 180.0;

        bindings.c.cairo_new_sub_path(self.ctx);
        bindings.c.cairo_arc(self.ctx, x_f64 + width_f64 - radius_f64, y_f64 + radius_f64, radius_f64, -90 * degrees, 0 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + width_f64 - radius_f64, y_f64 + height_f64 - radius_f64, radius_f64, 0 * degrees, 90 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + radius_f64, y_f64 + height_f64 - radius_f64, radius_f64, 90 * degrees, 180 * degrees);
        bindings.c.cairo_arc(self.ctx, x_f64 + radius_f64, y_f64 + radius_f64, radius_f64, 180 * degrees, 270 * degrees);
        bindings.c.cairo_close_path(self.ctx);

        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );
        bindings.c.cairo_set_line_width(self.ctx, @floatCast(line_width));
        bindings.c.cairo_stroke(self.ctx);
    }

    pub fn drawSurface(self: *Painter, x: f32, y: f32, surface: *bindings.c.cairo_surface_t) !void {
        bindings.c.cairo_set_source_surface(self.ctx, surface, x, y);
        bindings.c.cairo_paint(self.ctx);
    }

    /// Render shaped text using HarfBuzz glyphs
    /// Note: x, y are in logical pixels. Cairo context should already be scaled
    /// by scale_factor in the frame function, so font rendering will be crisp.
    pub fn renderText(self: *Painter, shaped: *const text.ShapedText, font: *text.FontFace, x: f32, y: f32, color: Color) void {
        const ft_face = font.ft_face;

        bindings.c.cairo_set_antialias(self.ctx, bindings.c.CAIRO_ANTIALIAS_SUBPIXEL);

        // Set color
        bindings.c.cairo_set_source_rgba(
            self.ctx,
            @floatCast(color.r),
            @floatCast(color.g),
            @floatCast(color.b),
            @floatCast(color.a),
        );

        const cairo_ft_face = bindings.c.cairo_ft_font_face_create_for_ft_face(ft_face, 0);

        bindings.c.cairo_set_font_face(self.ctx, cairo_ft_face);
        // Font size is in logical pixels - Cairo's scaling handles HiDPI
        bindings.c.cairo_set_font_size(self.ctx, font.font_size);

        var cursor_x: f32 = x;
        var cursor_y: f32 = y + shaped.height - 4;

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const temp_alloc = gpa.allocator();

        const cairo_glyphs = temp_alloc.alloc(bindings.c.cairo_glyph_t, shaped.glyphs.len) catch unreachable;
        defer temp_alloc.free(cairo_glyphs);

        for (shaped.glyphs, 0..shaped.glyphs.len) |glyph, i| {
            cairo_glyphs[i] =
                bindings.c.cairo_glyph_t{
                    .index = glyph.glyph_id,
                    .x = cursor_x + (glyph.x_offset),
                    .y = cursor_y - (glyph.y_offset),
                };

            cursor_x += glyph.x_advance;
            cursor_y -= glyph.y_advance;
        }

        bindings.c.cairo_show_glyphs(self.ctx, cairo_glyphs.ptr, @intCast(cairo_glyphs.len));
    }

    pub fn saveToPNG(self: *Painter, filename: [:0]const u8) !void {
        bindings.c.cairo_surface_flush(self.surface);
        const status = bindings.c.cairo_surface_write_to_png(self.surface, filename.ptr);
        if (status != bindings.c.CAIRO_STATUS_SUCCESS) {
            return error.CairoPNGWriteFailed;
        }
    }
};
