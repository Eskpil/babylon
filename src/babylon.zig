const std = @import("std");

pub const api = @import("api/api.zig");

const painter = @import("painter.zig");
const constraints = @import("constraints.zig");
const block = @import("block/block.zig");
pub const text = @import("text.zig");
const application = @import("application.zig");
pub const eloop = @import("eloop.zig");

const rect = @import("block/rect.zig");
const span = @import("block/span.zig");
const vstack = @import("block/vstack.zig");
const hstack = @import("block/hstack.zig");
const zstack = @import("block/zstack.zig");
const center = @import("block/center.zig");
const button = @import("block/button.zig");
const container = @import("block/container.zig");
const separator = @import("block/separator.zig");
const spacer = @import("block/spacer.zig");
const svg = @import("block/svg.zig");
const image = @import("block/image.zig");
const progress = @import("block/progress.zig");

const alpha_transition = @import("transitions/alpha.zig");

pub const layout_engine = @import("layout.zig");

// Transitions
pub const AlphaTransition = alpha_transition.AlphaTransition;

// Core types
pub const Painter = painter.Painter;
pub const Color = painter.Color;
pub const Constraints = constraints.Constraints;
pub const Block = block.Block;
pub const Application = application.Application;
pub const Shell = application.Shell;
pub const Window = application.Window;
pub const InteractionContext = block.InteractionContext;
pub const DestroyContext = block.DestroytContext;
pub const MouseButton = block.MouseButton;
pub const MouseButtonState = block.MouseButtonState;

// Layout types
pub const BlockLayout = block.BlockLayout;
pub const LayoutRect = block.LayoutRect;
pub const LayoutContext = block.LayoutContext;
pub const PaintContext = block.PaintContext;
pub const Sizing = block.Sizing;
pub const SizingAxis = block.SizingAxis;
pub const SizingType = block.SizingType;
pub const LayoutDirection = block.LayoutDirection;
pub const ChildAlignment = block.ChildAlignment;
pub const Padding = block.Padding;
pub const Border = block.Border;
pub const FontSlant = text.FontSlant;
pub const FontWeight = text.FontWeight;

// Helper functions
pub const sizingFit = block.sizingFit;
pub const sizingGrow = block.sizingGrow;
pub const sizingFixed = block.sizingFixed;
pub const sizingPercent = block.sizingPercent;

// Layout engine
pub const calculateLayout = layout_engine.calculateLayout;

pub const destroyTree = block.destroyTree;
pub const paintTree = block.paintTree;

pub const Box = struct {
    width: f32,
    height: f32,
};

pub const Max = std.math.floatMax(f32);

// Blocks
pub const Blocks = struct {
    pub const Rect = rect.Rect;
    pub const Span = span.Span;
    pub const VStack = vstack.VStack;
    pub const HStack = hstack.HStack;
    pub const ZStack = zstack.ZStack;
    pub const Center = center.Center;
    pub const Button = button.Button;
    pub const Container = container.Container;
    pub const ContainerConfig = container.ContainerConfig;
    pub const Separator = separator.Separator;
    pub const SeparatorOrientation = separator.SeparatorOrientation;
    pub const Spacer = spacer.Spacer;
    pub const Svg = svg.Svg;
    pub const Image = image.Image;
    pub const Progress = progress.Progress;
};
