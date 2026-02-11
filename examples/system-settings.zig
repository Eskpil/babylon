const std = @import("std");
const babylon = @import("babylon");

// Custom composite blocks for our settings UI

pub const Theme = struct {
    pub const Background = struct {
        pub const dark = babylon.Color{ .r = 0.11, .g = 0.11, .b = 0.11, .a = 1.0 };
        pub const darker = babylon.Color{ .r = 0.09, .g = 0.09, .b = 0.09, .a = 1.0 };
        pub const selected = babylon.Color{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1.0 };
    };

    pub const Text = struct {
        pub const white = babylon.Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        pub const gray = babylon.Color{ .r = 0.6, .g = 0.6, .b = 0.6, .a = 1.0 };
    };

    pub const Colors = struct {
        pub const accent = babylon.Color{ .r = 0.5, .g = 0.4, .b = 0.8, .a = 1.0 };
        pub const separator = babylon.Color{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1.0 };
    };
};

const NavigationItem = struct {
    const Self = @This();

    label: []const u8,
    is_selected: bool,

    pub fn init(alloc: std.mem.Allocator, label: []const u8, is_selected: bool) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .label = label,
            .is_selected = is_selected,
        };

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .composition,
            .context = self,
            .key = null,
            .name = "custom",
            .kind = "custom",
            .build = build,
        };
        return block;
    }

    pub fn build(context: *anyopaque, arena: std.mem.Allocator) anyerror!*babylon.Block {
        const self: *Self = @ptrCast(@alignCast(context));

        const text_color = if (self.is_selected) Theme.Colors.accent else Theme.Text.white;
        const bg_color = if (self.is_selected) Theme.Background.selected else null;

        const text = try babylon.Blocks.Span.init(arena, self.label, null, .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 16,
            .color = text_color,
        });

        return babylon.Blocks.Container.init(arena, text, .{
            .background_color = bg_color,
            .padding = babylon.Padding.all(12),
            .border_radius = 8,
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingFit(0, std.math.floatMax(f32)),
            },
        });
    }
};

const KeyValueRow = struct {
    const Self = @This();

    key: []const u8,
    value: []const u8,

    pub fn init(alloc: std.mem.Allocator, key: []const u8, value: []const u8) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .key = key,
            .value = value,
        };

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .composition,
            .context = self,
            .key = null,
            .name = @typeName(Self),
            .kind = @typeName(Self),
            .build = build,
        };
        return block;
    }

    pub fn build(context: *anyopaque, arena: std.mem.Allocator) anyerror!*babylon.Block {
        const self: *Self = @ptrCast(@alignCast(context));

        const key_text = try babylon.Blocks.Span.init(arena, self.key, null, .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 16,
            .color = Theme.Text.gray,
        });

        const spacer = try babylon.Blocks.Spacer.init(arena);

        const value_text = try babylon.Blocks.Span.init(arena, self.value, null, .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 16,
            .color = Theme.Text.white,
        });

        const row_items = try arena.alloc(*babylon.Block, 3);
        row_items[0] = key_text;
        row_items[1] = spacer;
        row_items[2] = value_text;

        return babylon.Blocks.HStack.init(
            arena,
            row_items,
            0,
            .start,
            .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingFit(0, std.math.floatMax(f32)),
            },
        );
    }
};

const SettingToggleRow = struct {
    const Self = @This();

    title: []const u8,
    description: []const u8,

    pub fn init(alloc: std.mem.Allocator, title: []const u8, description: []const u8) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{
            .title = title,
            .description = description,
        };

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .composition,
            .context = self,
            .key = null,
            .name = "custom",
            .kind = "custom",
            .build = build,
        };
        return block;
    }

    pub fn build(context: *anyopaque, arena: std.mem.Allocator) anyerror!*babylon.Block {
        const self: *Self = @ptrCast(@alignCast(context));

        const title_text = try babylon.Blocks.Span.init(arena, self.title, null, .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 16,
            .color = Theme.Text.white,
        });

        const spacer = try babylon.Blocks.Spacer.init(arena);

        const toggle = try babylon.Blocks.Rect.initWithRadius(
            arena,
            .{
                .width = babylon.sizingFixed(40),
                .height = babylon.sizingFixed(24),
            },
            Theme.Colors.accent,
            12,
        );

        const row_items = try arena.alloc(*babylon.Block, 3);
        row_items[0] = title_text;
        row_items[1] = spacer;
        row_items[2] = toggle;

        const row = try babylon.Blocks.HStack.init(
            arena,
            row_items,
            16,
            .center,
            .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingFit(0, std.math.floatMax(f32)),
            },
        );

        // If there's a description, create a VStack with row and description
        if (self.description.len > 0) {
            const desc_text = try babylon.Blocks.Span.init(arena, self.description, null, .{
                .font = "Open Sans",
                .weight = .regular,
                .slant = .none,
                .size = 14,
                .color = Theme.Text.gray,
            });

            const items = try arena.alloc(*babylon.Block, 2);
            items[0] = row;
            items[1] = desc_text;

            return babylon.Blocks.VStack.init(
                arena,
                items,
                8,
                .start,
                .{
                    .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                    .height = babylon.sizingFit(0, std.math.floatMax(f32)),
                },
            );
        }

        return row;
    }
};

const Sidebar = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{};

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .composition,
            .context = self,
            .key = null,
            .name = @typeName(Self),
            .kind = @typeName(Self),
            .build = build,
        };
        return block;
    }

    pub fn build(context: *anyopaque, arena: std.mem.Allocator) anyerror!*babylon.Block {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = self;
        // Build navigation items
        const nav_labels = [_][]const u8{
            "General",
            "Appearance",
            "Desktop & Dock",
            "Network",
            "Sound",
            "Displays",
            "Power",
            "Privacy & Security",
            "Notifications",
            "Users & Groups",
            "Keyboard & Input",
        };

        var nav_items = try arena.alloc(*babylon.Block, nav_labels.len);
        for (nav_labels, 0..) |label, i| {
            nav_items[i] = try NavigationItem.init(arena, label, i == 0);
        }

        const nav_stack = try babylon.Blocks.VStack.init(
            arena,
            nav_items,
            8,
            .start,
            .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingFit(0, std.math.floatMax(f32)),
            },
        );

        // Search box
        const search_text = try babylon.Blocks.Span.init(arena, "Search settings...", null, .{
            .font = "Open Sans",
            .weight = .regular,
            .slant = .none,
            .size = 16,
            .color = Theme.Text.gray,
        });

        const search_box = try babylon.Blocks.Container.init(arena, search_text, .{
            .background_color = Theme.Background.dark,
            .padding = babylon.Padding.all(12),
            .border_radius = 8,
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingFit(0, std.math.floatMax(f32)),
            },
            .border = babylon.Border.all(1, Theme.Colors.separator),
        });

        // Sidebar content
        const sidebar_items = try arena.alloc(*babylon.Block, 2);
        sidebar_items[0] = search_box;
        sidebar_items[1] = nav_stack;

        const sidebar_content = try babylon.Blocks.VStack.init(
            arena,
            sidebar_items,
            16,
            .start,
            .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
                .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
        );

        const sidebar = try babylon.Blocks.Container.init(arena, sidebar_content, .{
            .background_color = Theme.Background.darker,
            .padding = babylon.Padding.all(16),
            .sizing = .{
                .width = babylon.sizingFixed(288),
                .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
            .border = .{
                .color = Theme.Colors.separator,
                .right = 1,
            },
        });

        return sidebar;
    }
};

fn build_ui(arena_alloc: std.mem.Allocator) !*babylon.Block {
    const sidebar = try Sidebar.init(arena_alloc);

    // Main content - breadcrumb
    const breadcrumb = try babylon.Blocks.Span.init(arena_alloc, "Settings  >  General", null, .{
        .font = "Open Sans",
        .weight = .regular,
        .slant = .none,
        .size = 14,
        .color = Theme.Text.gray,
    });

    const breadcrumb_container = try babylon.Blocks.Container.init(
        arena_alloc,
        breadcrumb,
        .{
            .padding = babylon.Padding.horizontal(32),
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
        },
    );

    // System Information section
    const sys_info_title = try babylon.Blocks.Span.init(arena_alloc, "System Information", null, .{
        .font = "Open Sans",
        .weight = .bold,
        .slant = .none,
        .size = 32,
        .color = Theme.Text.white,
    });

    const sys_info_rows = try arena_alloc.alloc(*babylon.Block, 12);
    sys_info_rows[0] = try babylon.Blocks.Container.init(arena_alloc, sys_info_title, .{ .padding = .tblr(0, 12, 0, 0) });
    sys_info_rows[1] = try KeyValueRow.init(
        arena_alloc,
        "Device Name",
        "fedora",
    );
    sys_info_rows[2] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    sys_info_rows[3] = try KeyValueRow.init(
        arena_alloc,
        "Operating System",
        "Babylon 0.0.1",
    );
    sys_info_rows[4] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    sys_info_rows[5] = try KeyValueRow.init(
        arena_alloc,
        "Kernel Version",
        "6.1.0-desktop",
    );
    sys_info_rows[6] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    sys_info_rows[7] = try KeyValueRow.init(
        arena_alloc,
        "Processor",
        "Intel Core i7-8750H",
    );
    sys_info_rows[8] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    sys_info_rows[9] = try KeyValueRow.init(
        arena_alloc,
        "Memory",
        "16 GB",
    );
    sys_info_rows[10] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    sys_info_rows[11] = try KeyValueRow.init(
        arena_alloc,
        "Graphics",
        "NVIDIA GeForce GTX 1060",
    );

    const sys_info_section = try babylon.Blocks.VStack.init(
        arena_alloc,
        sys_info_rows,
        20,
        .start,
        .{
            .width = babylon.sizingGrow(900, std.math.floatMax(f32)),
            .height = babylon.sizingFit(0, std.math.floatMax(f32)),
        },
    );

    const sys_info_container = try babylon.Blocks.Container.init(
        arena_alloc,
        sys_info_section,
        .{
            .padding = babylon.Padding.tblr(8, 8, 32, 32),
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
        },
    );

    // Startup & Login section
    const startup_title = try babylon.Blocks.Span.init(arena_alloc, "Startup and Login", null, .{
        .font = "Open Sans",
        .weight = .bold,
        .slant = .none,
        .size = 32,
        .color = Theme.Text.white,
    });

    const startup_rows = try arena_alloc.alloc(*babylon.Block, 8);
    startup_rows[0] = try babylon.Blocks.Container.init(arena_alloc, startup_title, .{ .padding = .tblr(0, 12, 0, 0) });
    startup_rows[1] = try SettingToggleRow.init(arena_alloc, "Launch on startup", "Start the desktop environment automatically");
    startup_rows[2] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    startup_rows[3] = try SettingToggleRow.init(arena_alloc, "Restore previous session", "Reopen windows from your last session");
    startup_rows[4] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    startup_rows[5] = try SettingToggleRow.init(arena_alloc, "Show welcome screen", "Display welcome message on login");
    startup_rows[6] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    startup_rows[7] = try SettingToggleRow.init(arena_alloc, "Enable animations", "Show smooth transitions and effects");

    const startup_section = try babylon.Blocks.VStack.init(
        arena_alloc,
        startup_rows,
        16,
        .start,
        .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingFit(0, std.math.floatMax(f32)),
        },
    );

    const startup_container = try babylon.Blocks.Container.init(
        arena_alloc,
        startup_section,
        .{
            .padding = babylon.Padding.tblr(8, 8, 32, 32),
            .sizing = .{
                .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            },
        },
    );

    // Combine main content
    const content_items = try arena_alloc.alloc(*babylon.Block, 5);
    content_items[0] = breadcrumb_container;
    content_items[1] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    content_items[2] = sys_info_container;
    content_items[3] = try babylon.Blocks.Separator.init(arena_alloc, .horizontal, Theme.Colors.separator, 1);
    content_items[4] = startup_container;

    const main_content = try babylon.Blocks.VStack.init(
        arena_alloc,
        content_items,
        24,
        .start,
        .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingFit(0, std.math.floatMax(f32)),
        },
    );

    const main_container = try babylon.Blocks.Container.init(arena_alloc, main_content, .{
        .background_color = Theme.Background.darker,
        .padding = babylon.Padding.vertical(32),
        .sizing = .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
        },
    });

    // Root layout
    const main_layout_items = try arena_alloc.alloc(*babylon.Block, 2);
    main_layout_items[0] = sidebar;
    main_layout_items[1] = main_container;

    const root = try babylon.Blocks.HStack.init(
        arena_alloc,
        main_layout_items,
        0,
        .start,
        .{
            .width = babylon.sizingGrow(0, std.math.floatMax(f32)),
            .height = babylon.sizingGrow(0, std.math.floatMax(f32)),
        },
    );

    return root;
}

const Root = struct {
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !*babylon.Block {
        const self = try alloc.create(Self);
        self.* = Self{};

        const block = try alloc.create(babylon.Block);
        block.* = babylon.Block{
            .purpose = .composition,
            .context = self,
            .key = null,
            .name = "custom",
            .kind = "custom",
            .build = build,
        };
        return block;
    }

    pub fn build(context: *anyopaque, arena: std.mem.Allocator) anyerror!*babylon.Block {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = self;

        return build_ui(arena);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const application = try babylon.Application.init(alloc, "io.babylon.settings");
    defer application.deinit();

    const root = try Root.init(alloc);

    const window = try babylon.Window.init(application, root);
    defer window.deinit(application);

    window.set_title("System Settings");

    application.run();
}
