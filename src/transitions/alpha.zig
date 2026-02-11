const std = @import("std");
const babylon = @import("../babylon.zig");
const eloop = @import("../eloop.zig");

pub const AlphaTransition = struct {
    pub const OnChange = *const fn (*anyopaque, babylon.Color) void;

    const Self = @This();

    step: f32,
    remaining_steps: u32,
    color: babylon.Color,

    original_color: babylon.Color,

    on_change: ?OnChange,
    context: ?*anyopaque,
    timer: ?eloop.Timer,

    active: bool = false,

    pub fn empty() Self {
        return .{
            .step = 0,
            .remaining_steps = 0,
            .color = undefined,
            .original_color = undefined,
            .on_change = null,
            .context = null,
            .timer = null,
            .active = false,
        };
    }

    // Time is passed in milliseconds
    pub fn start(
        self: *Self,
        app: *babylon.Application,
        target: f32,
        steps: u32,
        time_ms: u64,
        color: babylon.Color,
        on_change: OnChange,
        context: *anyopaque,
    ) !void {
        if (steps == 0) return error.InvalidSteps;
        if (self.active) return error.AlreadyRunning;

        const steps_f: f32 = @floatFromInt(steps);
        self.step = (target - color.a) / steps_f;
        self.remaining_steps = steps;
        self.color = color;
        self.original_color = color;
        self.on_change = on_change;
        self.context = context;
        self.active = true;

        const interval_ms = @max(time_ms / steps, 1);
        self.timer = try eloop.Timer.interval(
            @intCast(interval_ms * std.time.ns_per_ms),
        );

        try app.loop.register(
            self.timer.?.timer_fd,
            .read,
            on_wakeup,
            self,
        );
    }

    pub fn cancel(self: *Self, app: *babylon.Application) !void {
        if (!self.active) return;

        self.active = false;
        try app.loop.unregister(self.timer.?.timer_fd);

        // Optional: snap back to original color
        if (self.on_change) |on_change| {
            on_change(self.context.?, self.original_color);
        }
    }

    fn on_wakeup(
        context: *anyopaque,
        event: eloop.Eloop.Event,
    ) !eloop.Eloop.Decision {
        try eloop.Timer.ready(event);

        var self: *Self = @ptrCast(@alignCast(context));

        if (!self.active) {
            return .kill;
        }

        self.color.a += self.step;
        if (self.on_change) |on_change| {
            on_change(self.context.?, self.color);
        }

        self.remaining_steps -= 1;

        if (self.remaining_steps == 0) {
            self.active = false;
            return .kill;
        }

        return .proceed;
    }
};
