tokens: []const Token,
exprs: ExprLinkedList,
current_idx: usize = 0,

const Parser = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Expr = @import("expr.zig").Expr;

const reportErr = @import("root").reportErr;
const Token = @import("Token.zig");

const Error = error{ParseError} || std.mem.Allocator.Error;

// TODO: look at std.SinglyLinkedList
// TODO: is this overcomplicating this? should i just use an arena allocator instead?
// not using an ArrayList due to pointer invalidation on reallocation
pub const ExprLinkedList = struct {
    allocator: *Allocator,
    head: ?*Node = null,

    const Node = struct {
        expr: Expr,
        next: ?*Node = null,
    };

    pub fn init(allocator: *Allocator) ExprLinkedList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ExprLinkedList) void {
        while (self.head) |node| {
            self.remove(node);
        }
    }

    /// prepends the node to the start of the list
    pub fn add(self: *ExprLinkedList, expr: Expr) !*Expr {
        var new_head = try self.allocator.create(Node);
        new_head.* = Node{ .expr = expr, .next = self.head };
        self.head = new_head;

        return &self.head.?.expr;
    }

    fn remove(self: *ExprLinkedList, node: *Node) void {
        const next_node = node.next;
        self.allocator.destroy(node);
        self.head = next_node;
    }
};

test "ExprLinkedList" {
    var expr_linked_list = ExprLinkedList.init(std.testing.allocator);
    defer expr_linked_list.deinit();

    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .int = 1 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .int = 2 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .float = 34.567 } } });
    _ = try expr_linked_list.add(Expr{ .literal = .{ .value = .{ .string = "wow!" } } });

    try std.testing.expectEqual(@as(i32, 1), expr_linked_list.head.?.next.?.next.?.next.?.expr.literal.value.int);
    try std.testing.expectEqual(@as(i32, 2), expr_linked_list.head.?.next.?.next.?.expr.literal.value.int);
    try std.testing.expectEqual(@as(f32, 34.567), expr_linked_list.head.?.next.?.expr.literal.value.float);
    try std.testing.expectEqualStrings("wow!", expr_linked_list.head.?.expr.literal.value.string);
}

const AstPrinter = @import("AstPrinter.zig");

test "ExprLinkedList nested" {
    var expr_linked_list = ExprLinkedList.init(std.testing.allocator);
    defer expr_linked_list.deinit();

    const literal_123 = try expr_linked_list.add(.{ .literal = .{ .value = .{ .int = 123 } } });
    const unary_123 = try expr_linked_list.add(.{
        .unary = .{
            .operator = .{ .token_type = .Minus, .lexeme = "-" },
            .right = literal_123,
        },
    });

    const literal_45_67 = try expr_linked_list.add(.{ .literal = .{ .value = .{ .float = 45.67 } } });
    const grouping_45_67 = try expr_linked_list.add(.{ .grouping = .{ .expr = literal_45_67 } });

    const expr = try expr_linked_list.add(.{
        .binary = .{
            .left = unary_123,
            .operator = .{ .token_type = .Star, .lexeme = "*" },
            .right = grouping_45_67,
        },
    });

    const writer = std.io.getStdErr().writer();
    var printer = AstPrinter{};
    try printer.parenthesize(expr, writer);
    try writer.writeByte('\n');
}

pub fn init(allocator: *Allocator, tokens: []const Token) Parser {
    return Parser{
        .exprs = ExprLinkedList.init(allocator),
        .tokens = tokens,
    };
}

pub fn deinit(self: *Parser) void {
    self.exprs.deinit();
}

pub fn parse(self: *Parser) !*Expr {
    return try self.expression();
}

// recursive descent (into madness)
fn expression(self: *Parser) Error!*Expr {
    return try self.equality();
}

fn equality(self: *Parser) Error!*Expr {
    var expr = try self.comparison();

    while (self.match(&[_]Token.Type{ .BangEqual, .EqualEqual })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.comparison(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn comparison(self: *Parser) Error!*Expr {
    var expr = try self.term();

    while (self.match(&[_]Token.Type{ .Greater, .GreaterEqual, .Less, .LessEqual })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.term(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn term(self: *Parser) Error!*Expr {
    var expr = try self.factor();

    while (self.match(&[_]Token.Type{ .Minus, .Plus })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.factor(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn factor(self: *Parser) Error!*Expr {
    var expr = try self.unary();

    while (self.match(&[_]Token.Type{ .Slash, .Star })) {
        const binary_expr = Expr{ .binary = .{
            .left = expr,
            .operator = self.previous(),
            .right = try self.unary(),
        } };
        expr = try self.exprs.add(binary_expr);
    }

    return expr;
}

fn unary(self: *Parser) Error!*Expr {
    if (self.match(&[_]Token.Type{ .Bang, .Minus })) {
        const unary_expr = Expr{ .unary = .{
            .operator = self.previous(),
            .right = try self.unary(),
        } };
        return try self.exprs.add(unary_expr);
    }

    return try self.primary();
}

fn primary(self: *Parser) Error!*Expr {
    if (self.match(&[_]Token.Type{ .True, .False, .None, .String, .Integer, .Float }))
        return try self.exprs.add(.{ .literal = .{ .value = self.previous().literal } });

    if (self.matchOne(.LeftParen)) {
        const expr = try self.expression();
        try self.consume(.RightParen, "Expected ')' after expression, got {}", .{self.peek().token_type});
        return try self.exprs.add(.{ .grouping = .{ .expr = expr } });
    }

    return parseError(self.peek(), "Expected expression, got {}.", .{self.peek().token_type});
}

fn matchOne(self: *Parser, comptime token_type: Token.Type) bool {
    return self.match([_]Token.Type{token_type});
}

fn match(self: *Parser, comptime token_types: []const Token.Type) bool {
    for (token_types) |token_type| {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
    }

    return false;
}

fn consume(self: *Parser, token_type: Token.Type, comptime error_msg: []const u8, error_args: anytype) Error!Token {
    if (self.check(token_type)) return self.advance();

    // report error on the next token's line
    return parseError(self.peek(), error_msg, error_args);
}

fn parseError(token: Token, comptime error_msg: []const u8, error_args: anytype) error.ParseError {
    reportErr(token.line, error_msg, error_args);
    return error.ParseError;
}

// not currently used - we don't have statements yet!
fn synchronize(self: *Parser) void {
    self.advance();

    while (!self.atEnd()) {
        if (self.previous() == .Semicolon) return;

        switch (self.peek()) {
            // on statement, hope we're in 'sync'
            .If, .Else, .For, .While, .Print, .Def, .Return => return,
            else => self.advance(),
        }
    }
}

fn check(self: Parser, token_type: Token.Type) bool {
    return !self.atEnd() and self.peek().token_type == token_type;
}

fn advance(self: *Parser) Token {
    if (!self.atEnd())
        self.current_idx += 1;

    return self.previous();
}

fn atEnd(self: Parser) bool {
    return self.peek().token_type == .EndOfFile;
}

fn peek(self: Parser) Token {
    return self.tokens[self.current_idx];
}

fn previous(self: Parser) Token {
    return self.tokens[self.current_idx - 1];
}
