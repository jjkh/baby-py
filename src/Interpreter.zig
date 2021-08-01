allocator: *Allocator,
environment: *Environment,
arena: *Allocator = undefined,

const Interpreter = @This();
const std = @import("std");
const Token = @import("Token.zig");
const Expr = @import("expr.zig").Expr;
const Statement = @import("statement.zig").Statement;
const Environment = @import("Environment.zig");
const reportErr = @import("util.zig").reportErr;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Error = error{ RuntimeError, UserExit, UndefinedIdentifier } || Allocator.Error;

pub const Value = union(enum) {
    int: i32,
    float: f32,
    bool: bool,
    string: []const u8,
    none,

    pub fn copy(other_value: anytype) !Value {
        return switch (other_value) {
            .int => |value| .{ .int = value },
            .bool => |value| .{ .bool = value },
            .float => |value| .{ .float = value },
            .string => |value| .{ .string = value },
            .none => Value.none,
        };
    }

    pub fn copyAlloc(self: Value, allocator: *Allocator) !Value {
        return switch (self) {
            .string => |str| .{ .string = try allocator.dupe(u8, str) },
            else => self,
        };
    }

    pub fn destroy(self: *Value, allocator: *Allocator) void {
        if (self.* == .string)
            allocator.free(self.string);
    }

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        return switch (self) {
            .int => |value| std.fmt.format(writer, "{}", .{value}),
            .bool => |value| if (value) std.fmt.format(writer, "True", .{}) else std.fmt.format(writer, "False", .{}),
            .float => |value| std.fmt.format(writer, "{d}", .{value}),
            .string => |value| std.fmt.format(writer, "{s}", .{value}),
            .none => std.fmt.format(writer, "None", .{}),
        };
    }

    pub fn isTruthy(self: Value) bool {
        if (self == .none) return false;
        if (self == .bool) return self.bool;

        return true;
    }

    pub fn isNumeric(self: Value) bool {
        return self == .int or self == .float;
    }

    pub fn isEqual(self: Value, other: Value) bool {
        if (self.isNumeric() and other.isNumeric()) {
            if (self == .int and other == .int) {
                return self.int == other.int;
            } else {
                return self.toFloat() == other.toFloat();
            }
        }
        if (@enumToInt(self) != @enumToInt(other)) return false;

        return switch (self) {
            .bool => self.bool == other.bool,
            .string => std.mem.eql(u8, self.string, other.string),
            .none => true,
            else => unreachable,
        };
    }

    pub fn toFloat(self: Value) f32 {
        return switch (self) {
            .float => self.float,
            .int => @intToFloat(f32, self.int),
            else => unreachable,
        };
    }

    pub fn toInt(self: Value) i32 {
        return switch (self) {
            .float => @floatToInt(i32, self.float),
            .int => self.int,
            else => unreachable,
        };
    }
};

pub fn init(allocator: *Allocator) !Interpreter {
    var env = try allocator.create(Environment);
    env.* = Environment.init(allocator, null);
    return Interpreter{
        .allocator = allocator,
        .environment = env,
    };
}

pub fn deinit(self: *Interpreter) void {
    self.environment.deinit();
    self.allocator.destroy(self.environment);
}

pub fn interpret(self: *Interpreter, statements: []const Statement) Error!void {
    var arena = ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    self.arena = &arena.allocator;

    for (statements) |stmt| try self.execute(stmt);
}

pub fn visitExprStatement(self: *Interpreter, stmt: Statement.ExprStatement, _: struct {}) Error!void {
    _ = try self.evaluate(stmt.expr);
}

pub fn visitPrintStatement(self: *Interpreter, stmt: Statement.PrintStatement, _: struct {}) Error!void {
    const value = try self.evaluate(stmt.expr);
    std.debug.print("{}\n", .{value});
}

pub fn visitExitStatement(self: Interpreter, stmt: void, _: struct {}) Error!void {
    _ = self;
    _ = stmt;
    return error.UserExit;
}
pub fn visitDeclStatement(self: *Interpreter, stmt: Statement.DeclStatement, _: struct {}) Error!void {
    if (stmt.initialiser) |initialiser|
        try self.environment.define(stmt.identifier, try self.evaluate(initialiser))
    else
        try self.environment.define(stmt.identifier, Value.none);
}

pub fn visitBlockStatement(self: *Interpreter, stmt: Statement.BlockStatement, _: struct {}) Error!void {
    var block_env = Environment.init(self.allocator, self.environment);
    defer block_env.deinit();

    try self.executeBlock(stmt.statements, &block_env);
}

fn executeBlock(self: *Interpreter, statements: []const Statement, environment: *Environment) Error!void {
    const enclosing_environment = self.environment;
    self.environment = environment;
    defer self.environment = enclosing_environment;

    for (statements) |stmt| try self.execute(stmt);
}

fn execute(self: *Interpreter, stmt: Statement) Error!void {
    try stmt.visit(self, .{});
}

fn evaluate(self: *Interpreter, expr: *const Expr) Error!Value {
    return expr.visit(self, .{});
}

pub fn visitBinary(self: *Interpreter, expr: Expr.Binary, _: struct {}) Error!Value {
    const left = try self.evaluate(expr.left);
    const right = try self.evaluate(expr.right);

    switch (expr.operator.token_type) {
        // arithmetic...
        .Plus => {
            // ...with the exception of string concat
            if (left == .string and right == .string)
                return Value{ .string = try std.mem.concat(self.arena, u8, &[_][]const u8{ left.string, right.string }) };

            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Value{ .int = left.int + right.toInt() },
                .float => Value{ .float = left.float + right.toFloat() },
                else => unreachable,
            };
        },
        .Minus => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Value{ .int = left.int - right.toInt() },
                .float => Value{ .float = left.float - right.toFloat() },
                else => unreachable,
            };
        },
        .Slash => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Value{ .int = @divTrunc(left.int, right.toInt()) },
                .float => Value{ .float = left.float / right.toFloat() },
                else => unreachable,
            };
        },
        .Star => {
            try assertNumericOperands(expr.operator.line, left, right);
            return switch (left) {
                .int => Value{ .int = left.int * right.toInt() },
                .float => Value{ .float = left.float * right.toFloat() },
                else => unreachable,
            };
        },
        // comparison
        .Greater => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Value{ .bool = left.toFloat() > right.toFloat() };
        },
        .GreaterEqual => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Value{ .bool = left.toFloat() >= right.toFloat() };
        },
        .Less => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Value{ .bool = left.toFloat() < right.toFloat() };
        },
        .LessEqual => {
            try assertNumericOperands(expr.operator.line, left, right);
            return Value{ .bool = left.toFloat() <= right.toFloat() };
        },
        // equality
        .BangEqual => return Value{ .bool = !left.isEqual(right) },
        .EqualEqual => return Value{ .bool = left.isEqual(right) },
        else => unreachable,
    }
}

pub fn visitGrouping(self: *Interpreter, expr: Expr.Grouping, _: struct {}) Error!Value {
    return try self.evaluate(expr.expr);
}

pub fn visitLiteral(self: *Interpreter, expr: Expr.Literal, _: struct {}) Error!Value {
    _ = self;
    return Value.copy(expr.value);
}

pub fn visitUnary(self: *Interpreter, expr: Expr.Unary, _: struct {}) Error!Value {
    const right = try self.evaluate(expr.right);

    switch (expr.operator.token_type) {
        .Minus => {
            try assertNumeric(expr.operator.line, right);
            return switch (right) {
                .float => Value{ .float = -right.float },
                .int => Value{ .int = -right.int },
                else => unreachable,
            };
        },
        .Bang => return Value{ .bool = !right.isTruthy() },
        else => unreachable,
    }
}

pub fn visitVariable(self: Interpreter, expr: Expr.Variable, _: struct {}) Error!Value {
    return self.environment.get(expr.identifier.lexeme) catch |err| switch (err) {
        error.UndefinedIdentifier => {
            reportErr(expr.identifier.line, "Undefined identifier \"{s}\"", .{expr.identifier.lexeme});
            return error.RuntimeError;
        },
        else => return err,
    };
}

pub fn visitAssign(self: *Interpreter, expr: Expr.Assign, _: struct {}) Error!Value {
    const right = try self.evaluate(expr.value);

    self.environment.assign(expr.identifier.lexeme, right) catch |err| switch (err) {
        error.UndefinedIdentifier => {
            reportErr(expr.identifier.line, "Undefined identifier \"{s}\"", .{expr.identifier.lexeme});
            return error.RuntimeError;
        },
        else => return err,
    };

    return right;
}

fn assertNumeric(line: usize, literal: Value) !void {
    if (!literal.isNumeric()) {
        reportErr(line, "Expected number, found '{}'", .{literal});
        return error.RuntimeError;
    }
}

fn assertNumericOperands(line: usize, a: Value, b: Value) !void {
    try assertNumeric(line, a);
    try assertNumeric(line, b);
}

test "Interpreter" {
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

    std.debug.print("{}\n", .{try Interpreter.evaluate(&root)});
}
