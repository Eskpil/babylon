const babylon = @import("./babylon.zig");
const std = @import("std");

// Function to check if a point is inside a rectangle (AABB test)
//int is_point_in_rect(int px, int py, UIElement* element) {
//    return (px >= element->x1 && px <= element->x2 &&
//            py >= element->y1 && py <= element->y2);
//}
//
//// Recursive hit test function
//UIElement* hit_test(UIElement* element, int px, int py) {
//    if (element == NULL) {
//        return NULL;
//    }
//
//    // 1. Perform a basic AABB check on the current element's bounds
//    if (!is_point_in_rect(px, py, element)) {
//        return NULL; // Pointer is outside this branch's bounds
//    }
//
//    // 2. Recursively check children first (depth-first)
//    // This ensures that topmost (or "foreground") elements in a UI hierarchy get priority
//    for (int i = 0; i < element->child_count; i++) {
//        UIElement* hit_child = hit_test(element->children[i], px, py);
//        if (hit_child != NULL) {
//            return hit_child; // A child (or a descendant) was hit
//        }
//    }
//
//    // 3. If no children were hit, the current element itself is the target
//    return element;
//}

fn isPointInBlock(block: *babylon.Block, px: f32, py: f32) bool {
    const x_axis = px >= block.computed.x and px <= block.computed.x + block.computed.width;
    const y_axis = py >= block.computed.y and py <= block.computed.y + block.computed.height;
    return x_axis and y_axis;
}

pub fn hitTest(root: *babylon.Block, px: f32, py: f32) ?*babylon.Block {
    if (!isPointInBlock(root, px, py)) return null;

    for (root.children.items) |child| {
        const hit_child = hitTest(child, px, py);
        if (hit_child) |block| {
            return block;
        }
    }

    return root;
}
