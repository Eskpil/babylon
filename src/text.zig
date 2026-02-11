const std = @import("std");
const bindings = @import("bindings.zig");
const babylon = @import("./babylon.zig");

pub const FontWeight = enum {
    regular,
    bold,
    medium,
    black,
    light,
};

pub const FontSlant = enum {
    italic,
    none,
};

/// Glyph information after shaping
pub const ShapedGlyph = struct {
    glyph_id: u32,
    x_offset: f32,
    y_offset: f32,
    x_advance: f32,
    y_advance: f32,
};

/// Result of text shaping
pub const ShapedText = struct {
    glyphs: []ShapedGlyph,
    width: f32,
    height: f32,
};

/// A line of wrapped text
pub const TextLine = struct {
    text: []const u8,
    width: f32,
};

/// Font face handle
pub const FontFace = struct {
    ft_face: bindings.c.FT_Face,
    hb_font: *bindings.c.hb_font_t,
    font_size: f32,

    pub fn deinit(self: *FontFace) void {
        bindings.c.hb_font_destroy(self.hb_font);
        _ = bindings.c.FT_Done_Face(self.ft_face);
    }
};

/// Global font manager
pub const FontManager = struct {
    ft_library: bindings.c.FT_Library,
    allocator: std.mem.Allocator,
    font_cache: std.StringHashMap(*FontFace),

    fontconfig: *bindings.c.FcConfig,

    pub fn init(allocator: std.mem.Allocator) !FontManager {
        var ft_library: bindings.c.FT_Library = undefined;
        const err = bindings.c.FT_Init_FreeType(&ft_library);
        if (err != 0) {
            return error.FreeTypeInitFailed;
        }

        _ = bindings.c.FcInit();
        const config = bindings.c.FcConfigGetCurrent();
        if (config == null) {
            return error.FontConfigInitFailed;
        }

        return FontManager{
            .ft_library = ft_library,
            .allocator = allocator,
            .font_cache = .init(allocator),
            .fontconfig = config.?,
        };
    }

    pub fn find(self: *FontManager, name: []const u8, weight: FontWeight, slant: FontSlant, size: f32) !*FontFace {
        const key = try std.fmt.allocPrint(self.allocator, "{s}-{d}-{d}-{d}", .{ name, size, slant, weight });
        if (self.font_cache.contains(key)) {
            return self.font_cache.get(key).?;
        }

        // Create a pattern for the requested font
        const pattern = bindings.c.FcPatternCreate() orelse return error.FontConfigPatternFailed;
        defer bindings.c.FcPatternDestroy(pattern);

        // Add family name
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);
        _ = bindings.c.FcPatternAddString(pattern, bindings.c.FC_FAMILY, name_z.ptr);

        // Map variant to weight and slant
        const weight_c: c_int = switch (weight) {
            .light => bindings.c.FC_WEIGHT_LIGHT,
            .regular => bindings.c.FC_WEIGHT_REGULAR,
            .medium => bindings.c.FC_WEIGHT_MEDIUM,
            .bold => bindings.c.FC_WEIGHT_BOLD,
            .black => bindings.c.FC_WEIGHT_BLACK,
        };
        _ = bindings.c.FcPatternAddInteger(pattern, bindings.c.FC_WEIGHT, weight_c);

        const slant_c: c_int = switch (slant) {
            .italic => bindings.c.FC_SLANT_ITALIC,
            else => bindings.c.FC_SLANT_ROMAN,
        };
        _ = bindings.c.FcPatternAddInteger(pattern, bindings.c.FC_SLANT, slant_c);

        // Add size
        _ = bindings.c.FcPatternAddDouble(pattern, bindings.c.FC_SIZE, size);

        // Perform font matching
        _ = bindings.c.FcConfigSubstitute(self.fontconfig, pattern, bindings.c.FcMatchPattern);
        bindings.c.FcDefaultSubstitute(pattern);

        var result: bindings.c.FcResult = undefined;
        const matched = bindings.c.FcFontMatch(self.fontconfig, pattern, &result);
        if (matched == null or result != bindings.c.FcResultMatch) {
            if (matched != null) bindings.c.FcPatternDestroy(matched);
            return error.FontNotFound;
        }
        defer bindings.c.FcPatternDestroy(matched);

        // Extract the font file path
        var file_path: [*c]u8 = undefined;
        if (bindings.c.FcPatternGetString(matched, bindings.c.FC_FILE, 0, &file_path) != bindings.c.FcResultMatch) {
            return error.FontPathNotFound;
        }

        // Convert to null-terminated slice
        const path_len = std.mem.len(file_path);
        const font_path = file_path[0..path_len :0];

        // Load the font using existing loadFont method
        const font_face = try self.loadFont(font_path, size);

        try self.font_cache.put(key, font_face);

        return font_face;
    }

    pub fn deinit(self: *FontManager) void {
        var it = self.font_cache.iterator();
        while (it.next()) |entry| {
            std.log.debug("removing {s} from font cache", .{entry.key_ptr.*});

            // Free the duplicated key string
            self.allocator.free(entry.key_ptr.*);
            // Free the font face
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.font_cache.deinit();
        _ = bindings.c.FT_Done_FreeType(self.ft_library);
    }

    pub fn loadFont(self: *FontManager, font_path: [:0]const u8, font_size: f32) !*FontFace {
        var ft_face: bindings.c.FT_Face = undefined;
        var err = bindings.c.FT_New_Face(self.ft_library, font_path.ptr, 0, &ft_face);
        if (err != 0) {
            return error.FontLoadFailed;
        }

        // Set font size (convert points to 1/64th points)
        err = bindings.c.FT_Set_Char_Size(ft_face, 0, @as(c_long, @intFromFloat(font_size * 64)), 72, 72);
        if (err != 0) {
            _ = bindings.c.FT_Done_Face(ft_face);
            return error.FontSizeSetFailed;
        }

        // Create HarfBuzz font from FreeType face
        const hb_font = bindings.c.hb_ft_font_create(ft_face, null);
        if (hb_font == null) {
            _ = bindings.c.FT_Done_Face(ft_face);
            return error.HarfBuzzFontCreateFailed;
        }

        // Create and cache font face
        const font_face = try self.allocator.create(FontFace);
        font_face.* = FontFace{
            .ft_face = ft_face,
            .hb_font = hb_font.?,
            .font_size = font_size,
        };

        return font_face;
    }
};

/// Shape text using HarfBuzz
pub fn shapeText(alloc: std.mem.Allocator, text: []const u8, font: *FontFace) !ShapedText {
    // Create HarfBuzz buffer
    const hb_buffer = bindings.c.hb_buffer_create() orelse return error.HarfBuzzBufferCreateFailed;
    defer bindings.c.hb_buffer_destroy(hb_buffer);

    // Add text to buffer
    bindings.c.hb_buffer_add_utf8(hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));

    // Set buffer properties
    bindings.c.hb_buffer_set_direction(hb_buffer, bindings.c.HB_DIRECTION_LTR);
    bindings.c.hb_buffer_set_script(hb_buffer, bindings.c.HB_SCRIPT_LATIN);
    bindings.c.hb_buffer_set_language(hb_buffer, bindings.c.hb_language_from_string("en", -1));

    // Shape the text
    bindings.c.hb_shape(font.hb_font, hb_buffer, null, 0);

    // Get glyph information
    var glyph_count: c_uint = undefined;
    const glyph_infos = bindings.c.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count);
    const glyph_positions = bindings.c.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count);

    // Allocate shaped glyphs
    const glyphs = try alloc.alloc(ShapedGlyph, glyph_count);

    // Convert HarfBuzz output to our format
    var total_width: f32 = 0;
    const max_height: f32 = font.font_size; // Approximate

    for (0..glyph_count) |i| {
        const info = glyph_infos[i];
        const pos = glyph_positions[i];

        glyphs[i] = ShapedGlyph{
            .glyph_id = info.codepoint,
            .x_offset = @as(f32, @floatFromInt(pos.x_offset)) / 64.0,
            .y_offset = @as(f32, @floatFromInt(pos.y_offset)) / 64.0,
            .x_advance = @as(f32, @floatFromInt(pos.x_advance)) / 64.0,
            .y_advance = @as(f32, @floatFromInt(pos.y_advance)) / 64.0,
        };

        total_width += glyphs[i].x_advance;
    }

    return ShapedText{
        .glyphs = glyphs,
        .width = total_width,
        .height = max_height,
    };
}

/// Measure text dimensions
pub fn measureText(allocator: std.mem.Allocator, text: []const u8, font: *FontFace) !babylon.Box {
    const shaped = try shapeText(allocator, text, font);
    defer allocator.free(shaped.glyphs);

    return .{
        .width = shaped.width,
        .height = shaped.height,
    };
}

pub fn wrapText(
    allocator: std.mem.Allocator,
    text: []const u8,
    max_width: f32,
    font: *FontFace,
) ![]TextLine {
    var lines: std.ArrayListUnmanaged(TextLine) = try .initCapacity(allocator, 32);
    defer lines.deinit(allocator);

    var line_start: usize = 0;
    var line_width: f32 = 0;

    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var word_start: ?usize = null;

    while (it.nextCodepointSlice()) |cp_slice| {
        const byte_index = @intFromPtr(cp_slice.ptr) - @intFromPtr(text.ptr);
        const cp = std.unicode.utf8Decode(cp_slice) catch unreachable;

        const is_space = cp == ' ';
        const is_newline = cp == '\n';

        if (!is_space and !is_newline) {
            if (word_start == null)
                word_start = byte_index;
            continue;
        }

        // End of a word
        if (word_start) |start| {
            const word_slice = text[start..byte_index];
            const word_width = (try measureText(allocator, word_slice, font)).width;

            try appendWord(
                allocator,
                &lines,
                text,
                word_slice,
                word_width,
                &line_start,
                &line_width,
                max_width,
                font,
            );

            word_start = null;
        }

        if (is_newline) {
            // Hard line break
            if (line_start < byte_index) {
                const slice = text[line_start..byte_index];
                try lines.append(allocator, .{
                    .text = slice,
                    .width = line_width,
                });
            }
            line_start = byte_index + cp_slice.len;
            line_width = 0;
        }
    }

    // Final word
    if (word_start) |start| {
        const word_slice = text[start..];
        const word_width = (try measureText(allocator, word_slice, font)).width;

        try appendWord(
            allocator,
            &lines,
            text,
            word_slice,
            word_width,
            &line_start,
            &line_width,
            max_width,
            font,
        );
    }

    // Flush final line
    if (line_start < text.len) {
        const slice = text[line_start..];
        try lines.append(allocator, .{
            .text = slice,
            .width = (try measureText(allocator, slice, font)).width,
        });
    }

    return lines.toOwnedSlice(allocator);
}

fn appendWord(
    allocator: std.mem.Allocator,
    lines: *std.ArrayList(TextLine),
    full_text: []const u8,
    word: []const u8,
    word_width: f32,
    line_start: *usize,
    line_width: *f32,
    max_width: f32,
    font: *FontFace,
) !void {
    const space_width = (try measureText(allocator, " ", font)).width;
    const needs_space = line_width.* > 0;

    const added_width = word_width + (if (needs_space) space_width else 0);

    // Word fits
    if (line_width.* + added_width <= max_width) {
        line_width.* += added_width;
        return;
    }

    // Flush current line
    if (line_width.* > 0) {
        const slice = full_text[line_start.* .. word.ptr - full_text.ptr];
        try lines.append(allocator, .{
            .text = slice,
            .width = line_width.*,
        });
        line_start.* = @intFromPtr(word.ptr) - @intFromPtr(full_text.ptr);
        line_width.* = 0;
    }

    // Word alone too wide → forced break (glyph-based would be better)
    if (word_width > max_width) {
        try lines.append(allocator, .{
            .text = word,
            .width = word_width,
        });
        line_start.* += word.len;
        return;
    }

    line_width.* = word_width;
}
