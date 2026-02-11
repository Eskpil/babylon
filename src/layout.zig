const std = @import("std");
const babylon = @import("babylon.zig");

const Block = babylon.Block;
const BlockLayout = babylon.BlockLayout;
const LayoutContext = babylon.LayoutContext;
const SizingType = babylon.SizingType;
const SizingAxis = babylon.SizingAxis;
const FontManager = babylon.text.FontManager;

/// Main entry point: calculates layout for entire tree
pub fn calculateLayout(root: *Block, screen_width: f32, screen_height: f32, font_manager: *FontManager, allocator: std.mem.Allocator, app: *babylon.Application, shell: *babylon.Shell) void {
    const root_layout = BlockLayout{
        .sizing = .{
            .width = babylon.sizingFixed(screen_width),
            .height = babylon.sizingFixed(screen_height),
        },
    };

    sizeContainersAlongAxis(
        root,
        screen_width,
        true,
        root_layout,
        font_manager,
        allocator,
        app,
        shell,
    );
    propagateDimensionChanges(
        root,
        false,
        font_manager,
        allocator,
        app,
        shell,
    ); // false = height
    sizeContainersAlongAxis(
        root,
        screen_height,
        false,
        root_layout,
        font_manager,
        allocator,
        app,
        shell,
    );
    calculatePositions(
        root,
        0,
        0,
        font_manager,
        allocator,
        app,
        shell,
    );
}

/// Recursive function to size containers along one axis
fn sizeContainersAlongAxis(
    block: *Block,
    available: f32,
    x_axis: bool,
    parent_layout: ?BlockLayout,
    font_manager: *FontManager,
    allocator: std.mem.Allocator,
    app: *babylon.Application,
    shell: *babylon.Shell,
) void {
    const ctx = LayoutContext{
        .parent_layout = parent_layout,
        .font_manager = font_manager,
        .allocator = allocator,
        .block = block,
        .app = app,
        .shell = shell,
    };
    const block_layout = if (block.layout) |layoutFn| blk: {
        break :blk layoutFn(block.context, ctx);
    } else BlockLayout{};

    // If this is a composition block with no layout and exactly one child, delegate to child
    if (block.layout == null and block.children.items.len == 1) {
        const child = block.children.items[0];
        sizeContainersAlongAxis(
            child,
            available,
            x_axis,
            parent_layout,
            font_manager,
            allocator,
            app,
            shell,
        );
        // Copy child's computed dimension
        if (x_axis) {
            block.computed.width = child.computed.width;
        } else {
            block.computed.height = child.computed.height;
        }
        return;
    }

    const sizing = if (x_axis) block_layout.sizing.width else block_layout.sizing.height;
    const padding = if (x_axis)
        block_layout.padding.left + block_layout.padding.right
    else
        block_layout.padding.top + block_layout.padding.bottom;

    // Check if we're sizing along the layout axis or cross axis
    const sizing_along_axis = (x_axis and block_layout.direction == .left_to_right) or
        (!x_axis and block_layout.direction == .top_to_bottom);

    // Calculate size based on sizing type
    var size: f32 = 0;
    switch (sizing.type) {
        .fixed => size = sizing.value,
        .percent => size = available * sizing.value,
        .grow => size = available,
        .fit => {
            // For FIT, we need to measure children
            if (block.children.items.len > 0) {
                size = measureChildren(
                    block,
                    x_axis,
                    block_layout,
                    sizing_along_axis,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
                size = std.math.clamp(size, sizing.min, sizing.max);
            } else {
                size = sizing.min;
            }
        },
    }

    // Clamp to min/max
    size = std.math.clamp(size, sizing.min, sizing.max);

    // Store computed size
    if (x_axis) {
        block.computed.width = size;
    } else {
        block.computed.height = size;
    }

    // Layout children
    if (block.children.items.len > 0) {
        if (sizing_along_axis) {
            distributeSpaceToChildren(
                block,
                size - padding,
                x_axis,
                block_layout,
                font_manager,
                allocator,
                app,
                shell,
            );
        } else {
            // Cross-axis: each child gets the full size
            for (block.children.items) |child| {
                sizeContainersAlongAxis(
                    child,
                    size - padding,
                    x_axis,
                    block_layout,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
            }
        }
    }
}

/// Measures children to determine FIT size
fn measureChildren(
    block: *Block,
    x_axis: bool,
    block_layout: BlockLayout,
    sizing_along_axis: bool,
    font_manager: *FontManager,
    allocator: std.mem.Allocator,
    app: *babylon.Application,
    shell: *babylon.Shell,
) f32 {
    var total_size: f32 = 0;
    var max_size: f32 = 0;

    for (block.children.items) |child| {
        // Recurse to size child
        const ctx = LayoutContext{
            .parent_layout = block_layout,
            .font_manager = font_manager,
            .allocator = allocator,
            .block = child,
            .app = app,
            .shell = shell,
        };
        const child_layout = if (child.layout) |layoutFn|
            layoutFn(child.context, ctx)
        else
            BlockLayout{};

        const child_sizing = if (x_axis) child_layout.sizing.width else child_layout.sizing.height;

        var child_size: f32 = 0;
        switch (child_sizing.type) {
            .fixed => child_size = child_sizing.value,
            .percent => child_size = 0, // Can't determine yet
            .grow => child_size = child_sizing.min, // Use min, don't let GROW children dictate FIT parent size
            .fit => {
                // Recursively measure
                sizeContainersAlongAxis(
                    child,
                    std.math.floatMax(f32),
                    x_axis,
                    block_layout,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
                child_size = if (x_axis) child.computed.width else child.computed.height;
            },
        }

        if (sizing_along_axis) {
            total_size += child_size;
        } else {
            max_size = @max(max_size, child_size);
        }
    }

    const padding = if (x_axis)
        block_layout.padding.left + block_layout.padding.right
    else
        block_layout.padding.top + block_layout.padding.bottom;

    if (sizing_along_axis) {
        const gaps = if (block.children.items.len > 1)
            @as(f32, @floatFromInt(block.children.items.len - 1)) * block_layout.child_gap
        else
            0;
        return total_size + gaps + padding;
    } else {
        return max_size + padding;
    }
}

/// Distributes space to children along the layout axis
fn distributeSpaceToChildren(
    block: *Block,
    available: f32,
    x_axis: bool,
    block_layout: BlockLayout,
    font_manager: *FontManager,
    allocator: std.mem.Allocator,
    app: *babylon.Application,
    shell: *babylon.Shell,
) void {
    // Count GROW children and calculate space used by FIT/FIXED children
    var grow_count: usize = 0;
    var fixed_total: f32 = 0;
    var percent_total: f32 = 0;

    for (block.children.items) |child| {
        const ctx = LayoutContext{
            .parent_layout = block_layout,
            .font_manager = font_manager,
            .allocator = allocator,
            .block = child,
            .app = app,
            .shell = shell,
        };
        const child_layout = if (child.layout) |layoutFn|
            layoutFn(child.context, ctx)
        else
            BlockLayout{};

        const child_sizing = if (x_axis) child_layout.sizing.width else child_layout.sizing.height;

        switch (child_sizing.type) {
            .grow => grow_count += 1,
            .fit => {
                // Already measured in measureChildren
                const fit_size = if (x_axis) child.computed.width else child.computed.height;
                fixed_total += fit_size;
            },
            .fixed => fixed_total += child_sizing.value,
            .percent => percent_total += child_sizing.value,
        }
    }

    // Calculate gaps
    const gaps = if (block.children.items.len > 1)
        @as(f32, @floatFromInt(block.children.items.len - 1)) * block_layout.child_gap
    else
        0;

    // Calculate space for GROW children
    const remaining = available - fixed_total - gaps;
    const grow_size = if (grow_count > 0)
        remaining / @as(f32, @floatFromInt(grow_count))
    else
        0;

    // Assign sizes to children
    for (block.children.items) |child| {
        const ctx = LayoutContext{
            .parent_layout = block_layout,
            .font_manager = font_manager,
            .allocator = allocator,
            .block = child,
            .app = app,
            .shell = shell,
        };
        const child_layout = if (child.layout) |layoutFn|
            layoutFn(child.context, ctx)
        else
            BlockLayout{};

        const child_sizing = if (x_axis) child_layout.sizing.width else child_layout.sizing.height;

        const child_size = switch (child_sizing.type) {
            .grow => std.math.clamp(grow_size, child_sizing.min, child_sizing.max),
            .fit => if (x_axis) child.computed.width else child.computed.height,
            .fixed => child_sizing.value,
            .percent => available * child_sizing.value,
        };

        if (x_axis) {
            child.computed.width = child_size;
        } else {
            child.computed.height = child_size;
        }

        // Recurse to size child's children
        sizeContainersAlongAxis(
            child,
            child_size,
            x_axis,
            block_layout,
            font_manager,
            allocator,
            app,
            shell,
        );
    }
}

/// Propagates dimension changes bottom-up (for text wrapping, etc)
fn propagateDimensionChanges(
    block: *Block,
    x_axis: bool,
    font_manager: *FontManager,
    allocator: std.mem.Allocator,
    app: *babylon.Application,
    shell: *babylon.Shell,
) void {
    // First, recurse to children
    for (block.children.items) |child| {
        propagateDimensionChanges(
            child,
            x_axis,
            font_manager,
            allocator,
            app,
            shell,
        );
    }

    // Then update this block based on children
    if (block.children.items.len == 0) return;

    // If this is a composition block with no layout and exactly one child, copy child's dimension
    if (block.layout == null and block.children.items.len == 1) {
        const child = block.children.items[0];
        if (x_axis) {
            block.computed.width = child.computed.width;
        } else {
            block.computed.height = child.computed.height;
        }
        return;
    }

    // Note: We don't have parent layout info in this bottom-up pass
    const ctx = LayoutContext{
        .parent_layout = null,
        .font_manager = font_manager,
        .allocator = allocator,
        .block = block,
        .app = app,
        .shell = shell,
    };
    const block_layout = if (block.layout) |layoutFn|
        layoutFn(block.context, ctx)
    else
        BlockLayout{};

    const sizing = if (x_axis) block_layout.sizing.width else block_layout.sizing.height;
    if (sizing.type != .fit) return;

    const sizing_along_axis = (x_axis and block_layout.direction == .left_to_right) or
        (!x_axis and block_layout.direction == .top_to_bottom);

    var total_size: f32 = 0;
    var max_size: f32 = 0;

    for (block.children.items) |child| {
        const child_size = if (x_axis) child.computed.width else child.computed.height;
        if (sizing_along_axis) {
            total_size += child_size;
        } else {
            max_size = @max(max_size, child_size);
        }
    }

    const padding = if (x_axis)
        block_layout.padding.left + block_layout.padding.right
    else
        block_layout.padding.top + block_layout.padding.bottom;

    const new_size = if (sizing_along_axis) blk: {
        const gaps = if (block.children.items.len > 1)
            @as(f32, @floatFromInt(block.children.items.len - 1)) * block_layout.child_gap
        else
            0;
        break :blk total_size + gaps + padding;
    } else max_size + padding;

    const clamped_size = std.math.clamp(new_size, sizing.min, sizing.max);

    if (x_axis) {
        block.computed.width = clamped_size;
    } else {
        block.computed.height = clamped_size;
    }
}

/// Calculates final positions for all blocks
fn calculatePositions(
    block: *Block,
    x: f32,
    y: f32,
    font_manager: *FontManager,
    allocator: std.mem.Allocator,
    app: *babylon.Application,
    shell: *babylon.Shell,
) void {
    block.computed.x = x;
    block.computed.y = y;

    if (block.children.items.len == 0) return;

    // Note: We don't have parent layout info in this positioning pass
    const ctx = LayoutContext{
        .parent_layout = null,
        .font_manager = font_manager,
        .allocator = allocator,
        .block = block,
        .app = app,
        .shell = shell,
    };
    const block_layout = if (block.layout) |layoutFn|
        layoutFn(block.context, ctx)
    else
        BlockLayout{};

    const content_width = block.computed.width - block_layout.padding.left - block_layout.padding.right;
    const content_height = block.computed.height - block_layout.padding.top - block_layout.padding.bottom;

    var offset_x = x + block_layout.padding.left;
    var offset_y = y + block_layout.padding.top;

    for (block.children.items) |child| {
        var child_x = offset_x;
        var child_y = offset_y;

        // Apply alignment
        switch (block_layout.direction) {
            .left_to_right => {
                // Align on cross-axis (vertical)
                switch (block_layout.child_alignment) {
                    .start => {},
                    .center => child_y += (content_height - child.computed.height) / 2,
                    .end => child_y += content_height - child.computed.height,
                    .stretch => {}, // Stretching should be handled in sizing phase
                }
                calculatePositions(
                    child,
                    child_x,
                    child_y,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
                offset_x += child.computed.width + block_layout.child_gap;
            },
            .top_to_bottom => {
                // Align on cross-axis (horizontal)
                switch (block_layout.child_alignment) {
                    .start => {},
                    .center => child_x += (content_width - child.computed.width) / 2,
                    .end => child_x += content_width - child.computed.width,
                    .stretch => {}, // Stretching should be handled in sizing phase
                }
                calculatePositions(
                    child,
                    child_x,
                    child_y,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
                offset_y += child.computed.height + block_layout.child_gap;
            },
            .z_stack => {
                // Center on both axes if alignment is center
                switch (block_layout.child_alignment) {
                    .center => {
                        child_x += (content_width - child.computed.width) / 2;
                        child_y += (content_height - child.computed.height) / 2;
                    },
                    .start => {},
                    .end => {
                        child_x += content_width - child.computed.width;
                        child_y += content_height - child.computed.height;
                    },
                    .stretch => {}, // Stretching should be handled in sizing phase
                }
                calculatePositions(
                    child,
                    child_x,
                    child_y,
                    font_manager,
                    allocator,
                    app,
                    shell,
                );
            },
        }
    }

    // If this is a composition block with no layout function and exactly one child,
    // copy the child's dimensions to this block so hit testing works
    if (block.layout == null and block.children.items.len == 1) {
        const child = block.children.items[0];
        block.computed.width = child.computed.width;
        block.computed.height = child.computed.height;
    }
}
