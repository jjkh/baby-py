const debug = false;

const std = @import("std");
const Allocator = std.mem.Allocator;
// should probably use a buffered output writer instead
const print = std.debug.print;

const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");
const AstPrinter = @import("AstPrinter.zig");
const Interpreter = @import("Interpreter.zig");
const reportErr = @import("util").reportErr;

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
}

// --------- user input handling ----------

fn runScript(allocator: *Allocator, path: []const u8) !void {
    const file_contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(file_contents);

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    run(allocator, file_contents, & interpreter) catch |err| switch (err) {
        error.UserExit => return,
        else => return err,
    };
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

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    while (true) {
        print("> ", .{});
        const line = try readNextLine(stdin.reader(), in_buf);

        run(allocator, line, &interpreter) catch |err| {
            if (err == error.UserExit)
                return;
        }; // ignore errors and continue
    }
}

// --------- the rest ----------

fn run(allocator: *Allocator, source: []const u8, interpreter: *Interpreter) !void {
    var scanner = Scanner.init(allocator, source);
    defer scanner.deinit();

    const tokens = try scanner.scanTokens();
    if (debug) {
        for (tokens) |token|
            print("{}, ", .{token});
        print("\n", .{});
    }

    var parser = Parser.init(allocator, tokens);
    defer parser.deinit();

    const statements = try parser.parse();
    // if (debug) {
    //     const writer = std.io.getStdErr().writer();
    //     try AstPrinter.parenthesize(expr, writer);
    //     try writer.writeByte('\n');
    // }
    try interpreter.interpret(statements);
}
