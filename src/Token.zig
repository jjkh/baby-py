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
    And,
    Or,
    True,
    False,
    None,
    If,
    Else,
    For,
    While,
    Print, // temp, for debug (maybe~)
    Def,
    Return,

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

    pub fn isNumeric(self: Literal) bool {
        return self == .int or self == .float;
    }

    pub fn isEqual(self: Literal, other: Literal) bool {
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

    pub fn toFloat(self: Literal) f32 {
        return switch (self) {
            .float => self.float,
            .int => @intToFloat(f32, self.int),
            else => unreachable,
        };
    }

    pub fn toInt(self: Literal) i32 {
        return switch (self) {
            .float => @floatToInt(i32, self.float),
            .int => self.int,
            else => unreachable,
        };
    }
};

pub const KeywordMap = std.ComptimeStringMap(Type, .{
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
});

pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    return std.fmt.format(writer, "{}: [{s}] {}", .{ self.token_type, self.lexeme, self.literal });
}
