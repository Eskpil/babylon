const std = @import("std");

const babylon = @import("../babylon.zig");

pub const ButtonConfig = struct {
    backgroundColor: babylon.Color,
    textColor: babylon.Color,
};

pub const Button = struct {
    const Self = @This();

    const State = enum {
        hovered,
        pressed,
        untouched,
    };

    state: State,
    text: []const u8,
    container: *babylon.Block,
    config: ButtonConfig,

    active_alpha_transition: ?babylon.AlphaTransition,

    pub fn init(alloc: std.mem.Allocator, text: []const u8, config: ButtonConfig) !*babylon.Block {
        const self = try alloc.create(Self);

        const block = try babylon.Block.init(Button, alloc, .composition, self);
        block.interaction = interaction;

        const textBlock = try babylon.Blocks.Span.init(alloc, text, null, .{
            .font = "Open Sans",
            .size = 16,
            .weight = .regular,
            .slant = .none,
            .color = config.textColor,
        });

        const center = try babylon.Blocks.Center.init(alloc, textBlock, .{
            .width = babylon.sizingFit(0, babylon.Max),
        });

        const container = try babylon.Blocks.Container.init(alloc, center, .{
            .background_color = config.backgroundColor,
            .padding = .all(12),
            .border_radius = 8,
            .sizing = .{
                .width = babylon.sizingFit(128, std.math.floatMax(f32)),
            },
        });

        self.* = Self{
            .text = text,
            .state = .untouched,
            .container = container,
            .active_alpha_transition = null,
            .config = config,
        };

        try block.append(alloc, container);

        return block;
    }

    fn on_background_color_change(data: *anyopaque, color: babylon.Color) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const container: *babylon.Blocks.Container = @ptrCast(@alignCast(self.container.context));
        container.set_background_color(color);
    }

    fn interaction(data: *anyopaque, context: babylon.InteractionContext) !void {
        const self: *Self = @ptrCast(@alignCast(data));

        switch (context.kind) {
            .mouse_button => {
                if (context.data.mouse_button.state == .press) {
                    std.log.debug("Button clicked?", .{});
                }
            },
            .hover => {
                self.state = .hovered;

                if (self.active_alpha_transition) |active| {
                    try @constCast(&active).cancel(context.app);
                }

                var background_color = self.config.backgroundColor;

                if (context.data.hover.enter) {
                    self.active_alpha_transition = .empty();
                    try self.active_alpha_transition.?.start(context.app, 0.8, 10, std.time.ms_per_s * 0.125, background_color, on_background_color_change, self);
                    context.shell.set_cursor_shape(.pointer);
                } else {
                    background_color.a = 0.8;
                    self.active_alpha_transition = .empty();
                    try self.active_alpha_transition.?.start(context.app, 1.0, 10, std.time.ms_per_s * 0.125, background_color, on_background_color_change, self);
                    context.shell.set_cursor_shape(.default);
                }
            },
            else => {},
        }
    }
};
