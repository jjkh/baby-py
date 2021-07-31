const AstPrinter = @This();
const std = @import("std");
const Writer = std.fs.File.Writer;
const Error = error{EndOfStream} || std.fs.File.Writer.Error;
const Expr = @import("expr.zig").Expr;

pub fn parenthesize(expr: *const Expr, writer: Writer) Error!void {
    try expr.visit(AstPrinter, writer);
}

pub fn visitBinary(expr: Expr.Binary, writer: Writer) Error!void {
    try writer.print("({s} ", .{expr.operator.lexeme});
    try parenthesize(expr.left, writer);
    try writer.writeByte(' ');
    try parenthesize(expr.right, writer);
    try writer.writeByte(')');
}

pub fn visitGrouping(expr: Expr.Grouping, writer: Writer) Error!void {
    _ = try writer.write("(group ");
    try parenthesize(expr.expr, writer);
    try writer.writeByte(')');
}

pub fn visitLiteral(expr: Expr.Literal, writer: Writer) Error!void {
    try writer.print("{}", .{expr.value});
}

pub fn visitUnary(expr: Expr.Unary, writer: Writer) Error!void {
    try writer.print("({s} ", .{expr.operator.lexeme});
    try parenthesize(expr.right, writer);
    writer.writeByte(')') catch unreachable;
}

test "AST Printer" {
    const root = Expr{
        .binary = Expr.Binary{
            .left = &Expr{
                .unary = Expr.Unary{
                    .operator = .{ .token_type = .Minus, .lexeme = "-" },
                    .right = &Expr{
                        .literal = Expr.Literal{ .value = .{ .int = 123 } },
                    },
                },
            },
            .operator = .{ .token_type = .Star, .lexeme = "*" },
            .right = &Expr{
                .grouping = Expr.Grouping{
                    .expr = &Expr{ .literal = .{ .value = .{ .float = 45.67 } } },
                },
            },
        },
    };

    const writer = std.io.getStdErr().writer();
    try AstPrinter.parenthesize(&root, writer);
    try writer.writeByte('\n');
}
