const std = @import("std");
const babylon = @import("./babylon.zig");
const bindings = @import("./bindings.zig");
const hit = @import("./hit.zig");
const eloop = @import("eloop.zig");

const Cachedtree = struct {
    arena: std.heap.ArenaAllocator,
    tree: *babylon.Block,
};

fn recurseInteraction(
    b: *babylon.Block,
) ?*babylon.Block {
    if (b.interaction == null and b.parent != null) {
        return recurseInteraction(b.parent.?);
    }

    if (b.interaction != null) {
        return b;
    }

    return null;
}

pub const CursorShape = enum(bindings.c.wp_cursor_shape_device_v1_shape) {
    pointer = bindings.c.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER,
    default = bindings.c.WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_DEFAULT,
};

pub const Shell = struct {
    const Self = @This();

    pub const vtable: bindings.c.aylin_shell_listener = .{
        .frame = &Shell.frame,
        .resize = &Shell.resize,
        .pointer_motion = &Shell.pointer_motion,
        .pointer_button = &Shell.pointer_button,
        .close = &Shell.close,
    };

    size: babylon.Box,

    aylin_shell: *bindings.c.aylin_shell,
    root: *babylon.Block,
    app: *babylon.Application,
    scale_factor: f32 = 1.0,

    closed: bool = false,

    current_hovering: ?*babylon.Block,

    pub fn init(self: *Self, app: *babylon.Application, shell: [*c]bindings.c.aylin_shell, root: *babylon.Block) void {
        bindings.c.aylin_shell_set_buffer_scale(shell, @intFromFloat(self.scale_factor));

        self.aylin_shell = shell;
        self.root = root;
        self.app = app;
    }

    pub fn deinit(self: *Self) void {
        // babylon.destroyTree(self.root, ctx);

        babylon.destroyTree(self.root, .{
            .alloc = self.app.alloc,
            .shell = self,
            .app = self.app,
        }) catch |err| {
            std.log.err("failed to destroy the tree: {}", .{err});
            @panic("");
        };

        bindings.c.aylin_shell_destroy(self.aylin_shell);
        _ = self.app.shells.swapRemove(0);
        self.app.alloc.destroy(self);
    }

    pub fn set_cursor_shape(self: *Self, shape: CursorShape) void {
        bindings.c.aylin_shell_set_cursor_shape(self.aylin_shell, @intFromEnum(shape));
    }

    fn close(shell: [*c]bindings.c.aylin_shell, data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        _ = shell;
        self.closed = true;

        std.log.debug("closing window", .{});

        self.deinit();
    }

    fn resize(shell: [*c]bindings.c.aylin_shell, resize_event: [*c]bindings.c.aylin_shell_resize_event, data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.size.width = @floatFromInt(resize_event.*.width);
        self.size.height = @floatFromInt(resize_event.*.height);
        // bindings.c.aylin_shell_set_dimensions(shell, resize_event.*.width, resize_event.*.height);
        _ = shell;
    }

    fn pointer_button(shell: [*c]bindings.c.aylin_shell, button_event: [*c]bindings.c.aylin_shell_pointer_button_event, data: ?*anyopaque) callconv(.c) void {
        _ = shell;

        const self: *Self = @ptrCast(@alignCast(data));

        const x: f32 = @floatCast(button_event.*.x);
        const y: f32 = @floatCast(button_event.*.y);

        const block = hit.hitTest(self.root, x, y);
        const closest_interactable_ancestor = if (block) |b| recurseInteraction(b) else null;

        if (closest_interactable_ancestor == null) return;

        if (closest_interactable_ancestor.?.interaction) |interaction| {
            const button: babylon.MouseButton = switch (button_event.*.button) {
                bindings.c.BTN_LEFT => .left,
                else => .right,
            };

            const state: babylon.MouseButtonState = switch (button_event.*.action) {
                bindings.c.press => .press,
                bindings.c.release => .release,
                else => {
                    unreachable;
                },
            };

            const ctx = babylon.InteractionContext{
                .app = self.app,
                .shell = self,
                .kind = .mouse_button,
                .data = .{
                    .mouse_button = .{
                        .state = state,
                        .button = button,
                        .x = x,
                        .y = y,
                    },
                },
            };

            interaction(closest_interactable_ancestor.?, ctx) catch {
                unreachable;
            };
        }
    }

    fn pointer_motion(shell: [*c]bindings.c.aylin_shell, motion_event: [*c]bindings.c.aylin_shell_pointer_motion_event, data: ?*anyopaque) callconv(.c) void {
        _ = shell;
        const self: *Self = @ptrCast(@alignCast(data));

        const x: f32 = @floatCast(motion_event.*.x);
        const y: f32 = @floatCast(motion_event.*.y);

        const block = hit.hitTest(self.root, x, y);
        const closest_interactable_ancestor = if (block) |b| recurseInteraction(b) else null;

        // Handle hover state changes
        if (closest_interactable_ancestor != self.current_hovering) {
            // Send leave event to old block
            if (self.current_hovering) |old_block| {
                if (old_block.interaction) |old_interaction| {
                    const leave_ctx = babylon.InteractionContext{
                        .kind = .hover,
                        .data = .{
                            .hover = .{
                                .enter = false,
                                .x = x,
                                .y = y,
                            },
                        },
                        .app = self.app,
                        .shell = self,
                    };
                    old_interaction(old_block.context, leave_ctx) catch {
                        unreachable;
                    };
                }
            }

            // Send enter event to new block
            if (closest_interactable_ancestor) |new_block| {
                if (new_block.interaction) |new_interaction| {
                    const enter_ctx = babylon.InteractionContext{
                        .kind = .hover,
                        .data = .{
                            .hover = .{
                                .enter = true,
                                .x = x,
                                .y = y,
                            },
                        },
                        .app = self.app,
                        .shell = self,
                    };
                    new_interaction(new_block.context, enter_ctx) catch {
                        unreachable;
                    };
                }
            }

            // Update current hovering
            self.current_hovering = closest_interactable_ancestor;
        }
        // Note: If still hovering the same block, we don't send any event
    }

    fn frame(shell: [*c]bindings.c.aylin_shell, frame_event: [*c]bindings.c.aylin_shell_frame_event, data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data));

        _ = frame_event;

        var arena = std.heap.ArenaAllocator.init(self.app.alloc);
        const arena_alloc = arena.allocator();

        // Get scale_factor from shell (user will add this field)
        const scale_factor = self.scale_factor;

        // Layout works in logical pixels
        babylon.calculateLayout(self.root, self.size.width, self.size.height, &self.app.font_manager, arena_alloc, self.app, self);

        const buffer = bindings.c.aylin_shell_create_buffer(shell);
        const cairo_surface = bindings.c.aylin_buffer_create_cairo(buffer);

        // Create painter with physical pixel dimensions (logical * scale_factor)
        const physical_width: u32 = @intFromFloat(self.size.width);
        const physical_height: u32 = @intFromFloat(self.size.height);

        var painter = babylon.Painter.initWithSurface(cairo_surface.?, physical_width, physical_height) catch {
            unreachable;
        };
        defer painter.deinit();

        // Scale Cairo context so we can use logical coordinates in rendering
        bindings.c.cairo_scale(painter.ctx, scale_factor, scale_factor);

        //painter.clear(.{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 });

        const paint_ctx = babylon.PaintContext{
            .painter = &painter,
            .font_manager = &self.app.font_manager,
            .allocator = arena_alloc,
            .block = self.root, // Will be updated for each block in paintTree
            .app = self.app,
            .shell = self,
            .scale_factor = scale_factor,
        };
        babylon.paintTree(self.root, paint_ctx) catch {
            unreachable;
        };

        bindings.c.aylin_destroy_buffer(buffer);
    }
};

pub const Window = struct {
    const Self = @This();

    shell: *Shell,

    pub fn init(
        app: *Application,
        root: *babylon.Block,
    ) !Self {
        const shell = try app.alloc.create(Shell);
        shell.* = Shell{
            .aylin_shell = undefined,
            .root = root,
            .app = app,
            .size = .{
                .width = 720,
                .height = 480,
            },
            .current_hovering = null,
        };

        try app.shells.append(app.alloc, shell);

        const aylin_shell = bindings.c.aylin_window_create(app.aylin_app, &Shell.vtable, shell);

        shell.aylin_shell = aylin_shell;

        const self: Self = .{
            .shell = shell,
        };

        return self;
    }

    pub fn set_dimensions(self: Self, w: f32, h: f32) void {
        self.shell.size.width = w;
        self.shell.size.height = h;
    }

    pub fn deinit(self: Self, app: *Application) void {
        bindings.c.aylin_shell_destroy(self.shell.aylin_shell);

        self.shell.text_cache.deinit();
        app.alloc.destroy(self.shell);
    }

    pub fn set_title(self: Self, title: []const u8) void {
        bindings.c.aylin_window_set_title(self.shell.aylin_shell, @constCast(title.ptr));
    }
};

pub const Application = struct {
    const Self = @This();

    aylin_app: *bindings.c.aylin_application,
    alloc: std.mem.Allocator,

    font_manager: babylon.text.FontManager,

    shells: std.ArrayList(*Shell),

    loop: *eloop.Eloop,

    fn on_display_read(context: *anyopaque, event: eloop.Eloop.Event) !eloop.Eloop.Decision {
        const self: *Self = @ptrCast(@alignCast(context));

        if (event.readiness == .read) {
            const ret = bindings.c.aylin_application_dispatch(self.aylin_app);
            if (0 > ret) {
                return error.AylinDispatchFailed;
            }
        }

        return .proceed;
    }

    pub fn init(alloc: std.mem.Allocator, app_id: []const u8) !*Self {
        const self = try alloc.create(Self);

        const listener: bindings.c.aylin_application_listener = .{
            .output = &application_on_output,
            .process = &application_on_process,
        };

        const aylin_app = bindings.c.aylin_application_create_nopoll(@constCast(app_id.ptr), &listener, self);
        if (aylin_app == null) {
            return error.ApplicationInitFailed;
        }

        const font_manger = try babylon.text.FontManager.init(alloc);

        const loop = try eloop.Eloop.init(alloc);

        const fd = bindings.c.aylin_application_get_fd(aylin_app);
        try loop.register(fd, .read, on_display_read, self);

        self.* = Self{
            .aylin_app = aylin_app,
            .alloc = alloc,
            .font_manager = font_manger,
            .loop = loop,
            .shells = .empty,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        bindings.c.aylin_application_destroy(self.aylin_app);
        self.font_manager.deinit();
        self.loop.deinit();
        self.shells.deinit(self.alloc);

        self.alloc.destroy(self);
    }

    pub fn run(self: *Self) !void {
        while (true) {
            _ = bindings.c.aylin_application_flush_display(self.aylin_app);

            if (self.shells.items.len == 0) break;

            const events = try self.loop.poll(10);
            defer self.loop.allocator.free(events.items);
        }
    }

    fn application_on_output(app: [*c]bindings.c.aylin_application, output: [*c]bindings.c.aylin_output, data: ?*anyopaque) callconv(.c) void {
        _ = app;
        _ = output;
        _ = data;
    }

    fn application_on_process(app: [*c]bindings.c.aylin_application, data: ?*anyopaque) callconv(.c) void {
        _ = app;
        _ = data;
    }
};
