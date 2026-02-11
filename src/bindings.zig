pub const c = @cImport({
    @cInclude("hb.h");
    @cInclude("hb-ft.h");
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftmodapi.h");
    @cInclude("freetype/ftglyph.h");
    @cInclude("cairo/cairo.h");
    @cInclude("cairo/cairo-ft.h");
    @cInclude("fontconfig/fontconfig.h");
    @cInclude("aylin/aylin.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("librsvg/rsvg.h");
});
