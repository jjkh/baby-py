token_type: Type,
lexeme: []const u8 = "",
literal: Literal = .none,
line: usize = 0,

const Token = @This();
const std = @import("std");

pub const Type = enum {
    // single-char tokens
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Colon,
    Slash,
    Star,

    // 1-2 char tokens
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,

    // literals
    Identifier,
    String,
    Integer,
    Float,

    // keywords
    Var,
    And,
    Or,
    True,
    False,
    None,
    If,
    Else,
    For,
    While,
    Print,
    Def,
    Return,
    Exit,

    EndOfFile,
};

pub const Literal = union(enum) {
    int: i32,
    float: f32,
    bool: bool,
    string: []const u8,
    none,

    pub fn format(self: Literal, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        return switch (self) {
            .int => |x_val| std.fmt.format(writer, "{}", .{x_val}),
            .bool => |x_bool| if (x_bool) std.fmt.format(writer, "True", .{}) else std.fmt.format(writer, "False", .{}),
            .float => |x_float| std.fmt.format(writer, "{d}", .{x_float}),
            .string => |x_string| std.fmt.format(writer, "\"{s}\"", .{x_string}),
            .none => std.fmt.format(writer, "None", .{}),
        };
    }
};

pub const KeywordMap = std.ComptimeStringMap(Type, .{
    .{ "var", .Var },
    .{ "and", .And },
    .{ "or", .Or },
    .{ "True", .True },
    .{ "False", .False },
    .{ "None", .None },
    .{ "if", .If },
    .{ "else", .Else },
    .{ "for", .For },
    .{ "while", .While },
    .{ "print", .Print },
    .{ "def", .Def },
    .{ "return", .Return },
    .{ "exit", .Exit },
});

pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    return std.fmt.format(writer, "{}: [{s}] {}", .{ self.token_type, self.lexeme, self.literal });
}
