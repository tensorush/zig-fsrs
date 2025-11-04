//! Root source file that exposes the library's API to users and Autodoc.

const std = @import("std");

pub const Card = @import("Card.zig");

test {
    std.testing.refAllDecls(@This());
}
