const std = @import("std");
const Allocator = std.mem.Allocator;

const testing = std.testing;

const Instruction = @import("Instruction.zig").Instruction;
const Token = @import("Token.zig").Token;

const ParseError = error{
    FileTooBig,
    UnmatchedBrackets,
};
const RuntimeError = error{ StackPointerOutOfBounds, IllegalInstruction, OutputError };

const Program = struct {
    instructions: [max_instructions]Token,
    n_instructions: u32 = 0,
    stack: [stack_size]u8 = undefined,
    data_ptr: usize = 0,
    instr_ptr: usize = 0,

    const Self = @This();
    const max_instructions = 1024;
    const stack_size = 30_000;

    pub fn addInstruction(self: *Self, instruction: Token) !void {
        if (self.n_instructions >= max_instructions) return ParseError.FileTooBig;

        self.instructions[self.n_instructions] = instruction;
        self.n_instructions += 1;
    }

    pub fn dumpTokens(self: Self) !void {
        for (0..self.n_instructions) |i| {
            try std.io.getStdOut().writer().print("{any}\n", .{self.instructions[i]});
        }
    }

    pub fn dumpStack(self: Self) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("Program dump\ndata_ptr: {d}\ninstr_ptr: {d}\nstack: ", .{ self.data_ptr, self.instr_ptr });
        for (0..stack_size) |i| {
            try stdout.print("{d}", .{self.stack[i]});
            if (i != stack_size - 1) {
                try stdout.writeAll(" ");
            }
        }
        try stdout.writeAll("\n");
    }

    pub fn start(self: *Self) !void {
        @memset(&self.stack, 0);

        interpret: while (self.instr_ptr < self.n_instructions) {
            //std.debug.print("evaluating: {d}\n", .{self.instr_ptr});

            switch (self.instructions[self.instr_ptr].instruction) {
                Instruction.inc => self.stack[self.data_ptr] +%= 1,
                Instruction.dec => self.stack[self.data_ptr] -%= 1,
                Instruction.inc_data_p => {
                    if (self.data_ptr == stack_size - 1) return RuntimeError.StackPointerOutOfBounds;
                    self.data_ptr += 1;
                },
                Instruction.dec_data_p => {
                    if (self.data_ptr == 0) return RuntimeError.StackPointerOutOfBounds;
                    self.data_ptr -= 1;
                },
                Instruction.open_loop => {
                    // Jump to maching bracket
                    if (self.stack[self.data_ptr] == 0) {
                        self.instr_ptr = self.instructions[self.instr_ptr].matching_bracket.? + 1;
                        continue :interpret;
                    }
                },
                Instruction.close_loop => {
                    // Jump to maching bracket
                    if (self.stack[self.data_ptr] != 0) {
                        self.instr_ptr = self.instructions[self.instr_ptr].matching_bracket.? + 1;
                        continue :interpret;
                    }
                },
                Instruction.output => {
                    const stdout = std.io.getStdOut().writer();
                    const isAscii: bool = blk: {
                        if (self.stack[self.data_ptr] < 128 and self.stack[self.data_ptr] >= 0) break :blk true;
                        break :blk false;
                    };

                    if (isAscii) {
                        const byte: u8 = @intCast(self.stack[self.data_ptr]);
                        stdout.writeByte(byte) catch return RuntimeError.OutputError;
                    }
                },
                Instruction.input => {
                    const stdin = std.io.getStdIn().reader();

                    const read_byte = stdin.readByte() catch 0;
                    self.stack[self.data_ptr] = read_byte;
                },
                else => return RuntimeError.IllegalInstruction,
            }
            self.instr_ptr += 1;
        }
    }
};

fn parseProgram(data: []const u8) !Program {
    var i: usize = 0;
    var program: Program = Program{ .instructions = undefined };
    var brackets = std.ArrayList(usize).init(std.heap.page_allocator);
    defer brackets.deinit();

    while (i < data.len) : (i += 1) {
        const instr = Instruction.instructionFromChar(data[i]);
        if (instr != Instruction.invalid) {
            try program.addInstruction(Token{ .instruction = instr, .pos = program.n_instructions });

            // Find matching brackets
            if (instr == Instruction.open_loop) {
                try brackets.append(program.n_instructions - 1); // -1 because n_instructions is incremented with addInstuction()
            } else if (instr == Instruction.close_loop) {
                if (brackets.items.len == 0) return ParseError.UnmatchedBrackets;

                const matching: usize = brackets.pop();
                program.instructions[matching].matching_bracket = program.n_instructions - 1; // update open bracket
                program.instructions[program.n_instructions - 1].matching_bracket = matching; // update closed (current)
            }
        }
    }

    if (brackets.items.len != 0) return ParseError.UnmatchedBrackets;

    return program;
}

pub fn main() !u8 {
    const stderr = std.io.getStdErr().writer();

    const args = std.process.argsAlloc(std.heap.page_allocator) catch |err| {
        try stderr.print("brainfk: error: {any}\n", .{err});
        return 1;
    };
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        try stderr.print("brainfk: error: Enter brainfuck file as argument\n", .{});
        return 1;
    }

    const file = std.fs.cwd().openFile(args[1], .{ .mode = .read_only }) catch {
        try stderr.print("brainfk: {s}: Could not open file.\n", .{args[1]});
        return 1;
    };
    defer file.close();

    const txt = file.readToEndAlloc(std.heap.page_allocator, 65_000) catch {
        try stderr.print("brainfk: error: File too big\n", .{});
        return 1;
    };
    defer std.heap.page_allocator.free(txt);

    var p = try parseProgram(txt);

    p.start() catch |e| {
        std.debug.print("{any}\n", .{e});
        //try p.dumpStack();
        return 1;
    };

    //try p.dumpStack();
    return 0;
}

test "instruction from char" {
    const inc = '+';
    const dec = '-';
    const invalid = 'a';

    try testing.expect(Instruction.instructionFromChar(inc) == Instruction.inc);
    try testing.expect(Instruction.instructionFromChar(dec) == Instruction.dec);
    try testing.expect(Instruction.instructionFromChar(invalid) == Instruction.invalid);
}

test "matching brackets" {
    const test_ops: []const u8 = "Ignored garbage\n[->+<]";

    const program = try parseProgram(test_ops);

    try testing.expect(program.instructions[0].matching_bracket == 5);
    try testing.expect(program.instructions[5].matching_bracket == 0);
}

test "inc instruction" {
    const test_ops = "+++";

    var p = try parseProgram(test_ops);

    try p.start();

    try testing.expect(p.n_instructions == 3);
    try testing.expect(p.stack[0] == 3);
}

test "dec instruction" {
    const test_ops = "-";

    var p = try parseProgram(test_ops);

    try p.start();

    try testing.expect(p.n_instructions == 1);
    try testing.expect(p.stack[0] == 255);
}

test "move data ptr" {
    const test_ops = "++>++-<+";

    var p = try parseProgram(test_ops);

    try p.start();

    try testing.expect(p.stack[0] == 3);
    try testing.expect(p.stack[1] == 1);
}

test "mov data ptr out of bounds" {
    const test_ops = "<";

    var p = try parseProgram(test_ops);

    var err: RuntimeError = undefined;

    p.start() catch |e| {
        err = e;
    };

    try testing.expect(err == RuntimeError.StackPointerOutOfBounds);
}

test "parse program" {
    const test_ops: []const u8 = "[->+<]";

    var expected: Program = Program{ .instructions = undefined };

    try expected.addInstruction(Token{ .instruction = Instruction.open_loop, .pos = 0 });
    try expected.addInstruction(Token{ .instruction = Instruction.dec, .pos = 1 });
    try expected.addInstruction(Token{ .instruction = Instruction.inc_data_p, .pos = 2 });
    try expected.addInstruction(Token{ .instruction = Instruction.inc, .pos = 3 });
    try expected.addInstruction(Token{ .instruction = Instruction.dec_data_p, .pos = 4 });
    try expected.addInstruction(Token{ .instruction = Instruction.close_loop, .pos = 5 });

    const program = try parseProgram(test_ops);

    try testing.expect(program.n_instructions == expected.n_instructions);

    for (0..program.n_instructions) |i| {
        try testing.expect(program.instructions[i].instruction == expected.instructions[i].instruction);
        try testing.expect(program.instructions[i].pos == expected.instructions[i].pos);
    }
}

test "add two cells (5+2)" {
    const test_ops = "++ > +++++ [<+>-]";

    var p = try parseProgram(test_ops);

    try p.start();

    try testing.expect(p.instructions[8].matching_bracket.? == 13);
    try testing.expect(p.stack[0] == 7);
}
