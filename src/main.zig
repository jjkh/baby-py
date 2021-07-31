const debug = false;

const std = @import("std");
const Allocator = std.mem.Allocator;
// should probably use a buffered output writer instead
const print = std.debug.print;

const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");
const AstPrinter = @import("AstPrinter.zig");
// --------- global state ----------

var interpreter_state = struct {
    had_error: bool = false,
}{};

// --------- error handling ----------

pub fn reportErr(line: usize, comptime msg: []const u8, args: anytype) void {
    // TODO: something else, i guess
    var buf: [512]u8 = undefined;

    report(line, "", std.fmt.bufPrint(&buf, msg, args) catch "error writing error, how ironic :^(");
}

fn report(line: usize, where: []const u8, msg: []const u8) void {
    print("[line {}] Error{s}: {s}\n", .{ line + 1, where, msg });
    interpreter_state.had_error = true;
}

// --------- main ----------

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = general_purpose_allocator.deinit();

    const gpa = &general_purpose_allocator.allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    switch (args.len) {
        1 => try runPrompt(gpa),
        2 => try runScript(gpa, args[1]),
        else => {
            std.log.err("Usage: baby-py [script]", .{});
            return error.InvalidArgs;
        },
    }

    if (interpreter_state.had_error) return error.UserError;
}

// --------- user input handling ----------

fn runScript(allocator: *Allocator, path: []const u8) !void {
    const file_contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(file_contents);

    try run(allocator, file_contents);
}

// borrowed (stolen) from ziglearn.org
fn readNextLine(reader: anytype, buf: []u8) ![]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(buf, '\n')) orelse return error.NullLine;

    // trim annoying windows-only carriage return character
    if (std.builtin.os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    }
    return line;
}

fn runPrompt(allocator: *Allocator) !void {
    var in_buf = try allocator.alloc(u8, 2048);
    defer allocator.free(in_buf);

    const stdin = std.io.getStdIn();

    while (true) {
        print("> ", .{});
        const line = try readNextLine(stdin.reader(), in_buf);

        try run(allocator, line);
        interpreter_state.had_error = false;
    }
}

// --------- the rest ----------

fn run(allocator: *Allocator, source: []const u8) !void {
    var scanner = Scanner.init(allocator, source);
    defer scanner.deinit();

    try scanner.scanTokens();

    var parser = Parser.init(allocator, scanner.tokens.items);
    defer parser.deinit();

    if (debug) {
        for (scanner.tokens.items) |token|
            print("{}, ", .{token});
        print("\n", .{});
    }

    const expr = parser.parse() catch |err| switch (err) {
        error.ParseError => return,
        else => return err,
    };

    const writer = std.io.getStdErr().writer();
    var printer = AstPrinter{};
    try printer.parenthesize(expr, writer);
    try writer.writeByte('\n');
}
