const std = @import("std");
const linux = std.os.linux;

fn on_ready_dummy(ctx: ?*anyopaque, event: Eloop.Event) !Eloop.Decision {
    _ = ctx;
    _ = event;

    return .kill;
}

pub const Timer = struct {
    const Self = @This();

    timer_fd: std.posix.fd_t,

    fn init() !Self {
        const fd = std.os.linux.timerfd_create(std.os.linux.TIMERFD_CLOCK.MONOTONIC, .{});

        if (fd < 0) {
            return error.TimerCreateFailed;
        }

        return .{
            .timer_fd = @intCast(fd),
        };
    }

    pub fn oneshot(ns: i64) !Self {
        const self = try Self.init();

        const itimerspec = std.os.linux.itimerspec{ .it_value = .{
            .sec = @intCast(@divFloor(ns, 1_000_000_000)),
            .nsec = @intCast(@mod(ns, 1_000_000_000)),
        }, .it_interval = .{
            .sec = 0,
            .nsec = 0,
        } };

        const result = std.os.linux.timerfd_settime(self.timer_fd, .{}, &itimerspec, null);
        if (result < 0) {
            std.posix.close(self.timer_fd);
            return error.TimerSetFailed;
        }

        return self;
    }

    pub fn interval(interval_ns: i64) !Self {
        const self = try Self.init();

        const itimerspec = std.os.linux.itimerspec{ .it_interval = .{
            .sec = @intCast(@divFloor(interval_ns, 1_000_000_000)),
            .nsec = @intCast(@mod(interval_ns, 1_000_000_000)),
        }, .it_value = .{
            .sec = @intCast(@divFloor(interval_ns, 1_000_000_000)),
            .nsec = @intCast(@mod(interval_ns, 1_000_000_000)),
        } };

        const result = std.os.linux.timerfd_settime(self.timer_fd, .{}, &itimerspec, null);
        if (result < 0) {
            std.posix.close(self.timer_fd);
            return error.TimerSetFailed;
        }

        return self;
    }

    // we need to read from it to keep it out of a readiness state.
    pub fn ready(event: Eloop.Event) !void {
        var buffer: [8]u8 = undefined;
        const nread = try std.posix.read(event.fd, &buffer);
        _ = nread;
    }

    pub fn deinit(self: *Self) void {
        std.posix.close(self.timer_fd);
    }
};

pub const Eloop = struct {
    const Self = @This();

    pub const Readiness = enum {
        read,
        write,
    };

    pub const Interest = enum {
        read,
        write,
        both,
    };

    pub const Event = struct {
        fd: std.posix.fd_t,
        readiness: Readiness,
    };

    pub const Decision = enum {
        proceed,
        kill,
    };

    pub const OnReady = *const fn (context: *anyopaque, event: Event) anyerror!Decision;
    pub const Handler = struct {
        ctx: *anyopaque,
        on_ready: OnReady,
        interest: Interest,
    };
    const Handlers = std.AutoHashMap(std.posix.fd_t, Handler);

    const PendingRegistrationMode = enum {
        register,
        unregister,
        reregister,
    };

    const PendingRegistration = struct {
        fd: std.posix.fd_t,
        mode: PendingRegistrationMode,
        interest: Interest,
        on_ready: OnReady,
        ctx: *anyopaque,
    };

    handlers: Handlers,
    pending_registrations: std.ArrayList(PendingRegistration),
    epoll_fd: std.posix.fd_t,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        self.epoll_fd = @intCast(linux.epoll_create());
        self.allocator = allocator;
        self.handlers = Handlers.init(self.allocator);
        self.pending_registrations = try std.ArrayList(PendingRegistration).initCapacity(allocator, 32);

        if (self.epoll_fd == -1) {
            return error.EpollCreate;
        }

        return self;
    }

    pub fn poll(self: *Self, timeout: i32) !std.ArrayList(Event) {
        // Process pending registrations before polling
        for (self.pending_registrations.items) |reg| {
            if (reg.mode == .unregister) {
                _ = self.handlers.remove(reg.fd);
                _ = linux.epoll_ctl(self.epoll_fd, 2, reg.fd, null);
            }

            if (reg.mode == .register) {
                try self.handlers.put(reg.fd, .{ .on_ready = reg.on_ready, .ctx = reg.ctx, .interest = reg.interest });
                const epoll_event = linux.epoll_event{
                    .events = make_flags(reg.interest),
                    .data = .{ .fd = reg.fd },
                };
                _ = linux.epoll_ctl(self.epoll_fd, 1, reg.fd, @ptrCast(@constCast(&epoll_event)));
            }

            if (reg.mode == .reregister) {
                try self.handlers.put(reg.fd, .{ .on_ready = reg.on_ready, .ctx = reg.ctx, .interest = reg.interest });
                const epoll_event = linux.epoll_event{
                    .events = make_flags(reg.interest),
                    .data = .{ .fd = reg.fd },
                };
                _ = linux.epoll_ctl(self.epoll_fd, 3, reg.fd, @ptrCast(@constCast(&epoll_event)));
            }
        }
        self.pending_registrations.clearRetainingCapacity();

        var buffer: [32]linux.epoll_event = undefined;
        const n_events = linux.epoll_wait(self.epoll_fd, &buffer, buffer.len, timeout);

        var events = try std.ArrayList(Event).initCapacity(self.allocator, @intCast(n_events));

        for (0..@intCast(n_events)) |i| {
            const raw_event = buffer[i];
            const is_readable = (raw_event.events & 0x001) != 0;
            const is_writable = (raw_event.events & 0x004) != 0;

            // Add read event if readable
            if (is_readable) {
                try events.append(self.allocator, .{
                    .fd = raw_event.data.fd,
                    .readiness = .read,
                });
            }

            // Add write event if writable
            if (is_writable) {
                try events.append(self.allocator, .{
                    .fd = raw_event.data.fd,
                    .readiness = .write,
                });
            }
        }

        for (events.items) |event| {
            const handler = self.handlers.get(event.fd).?;
            const decision = try handler.on_ready(handler.ctx, event);

            switch (decision) {
                .proceed => {
                    try self.reregister(event.fd, handler.interest, handler.on_ready, handler.ctx);
                },
                .kill => {
                    try self.unregister(event.fd);
                    std.posix.close(event.fd);
                },
            }
        }

        return events;
    }

    fn make_flags(interest: Interest) u32 {
        var flags: u32 = 0;

        // Oneshot
        flags |= 1 << 30;

        switch (interest) {
            .read => {
                // epollin
                flags |= 0x001;
            },
            .write => {
                // epollout
                flags |= 0x004;
            },
            .both => {
                // epollout && epollin;
                flags |= 0x001;
                flags |= 0x004;
            },
        }

        return flags;
    }

    pub fn register(self: *Self, fd: std.posix.fd_t, interest: Interest, on_ready: OnReady, ctx: *anyopaque) !void {
        try self.pending_registrations.append(self.allocator, .{
            .fd = fd,
            .mode = .register,
            .interest = interest,
            .on_ready = on_ready,
            .ctx = ctx,
        });
    }

    pub fn reregister(self: *Self, fd: std.posix.fd_t, interest: Interest, on_ready: OnReady, ctx: *anyopaque) !void {
        try self.pending_registrations.append(self.allocator, .{
            .fd = fd,
            .mode = .reregister,
            .interest = interest,
            .on_ready = on_ready,
            .ctx = ctx,
        });
    }

    pub fn unregister(self: *Self, fd: std.posix.fd_t) !void {
        try self.pending_registrations.append(self.allocator, .{
            .fd = fd,
            .mode = .unregister,
            .interest = .both,
            .on_ready = on_ready_dummy,
            .ctx = undefined,
        });
    }

    pub fn deinit(self: *Self) void {
        self.pending_registrations.deinit(self.allocator);
        self.handlers.deinit();
        std.posix.close(self.epoll_fd);
        self.allocator.destroy(self);
    }
};
