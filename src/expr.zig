const std = @import("std");
const Writer = std.fs.File.Writer;

const Token = @import("Token.zig");

pub const Expr = union(enum) {
    binary: Binary,
    grouping: Grouping,
    literal: Literal,
    unary: Unary,

    pub const Binary = struct {
        left: *const Expr,
        operator: Token,
        right: *const Expr,
    };

    pub const Grouping = struct { expr: *const Expr };

    pub const Literal = struct { value: Token.Literal };

    pub const Unary = struct {
        operator: Token,
        right: *const Expr,
    };

    pub fn visit(self: Expr, visitor: anytype, args: anytype) !void {
        switch (self) {
            .binary => |expr| try visitor.visitBinary(expr, args),
            .grouping => |expr| try visitor.visitGrouping(expr, args),
            .literal => |expr| try visitor.visitLiteral(expr, args),
            .unary => |expr| try visitor.visitUnary(expr, args),
        }
    }
};
