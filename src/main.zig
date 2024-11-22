const std = @import("std");
const Allocator = std.mem.Allocator;

const testing = std.testing;

const Instruction = @import("Instruction.zig").Instruction;
const Token = @import("Token.zig").Token;

const ParseError = error{ FileTooBig, UnclosedBrackets };

const Program = struct {
    instructions: [max_instructions]Token,
    n_instructions: u32 = 0,

    const Self = @This();
    const max_instructions: usize = 1024;

    pub fn addInstruction(self: *Self, instruction: Token) !void {
        if (self.n_instructions >= max_instructions) return ParseError.FileTooBig;

        self.instructions[self.n_instructions] = instruction;
        self.n_instructions += 1;
    }

    pub fn dumpProgram(self: Self) !void {
        for (0..self.n_instructions) |i| {
            try std.io.getStdOut().writer().print("{any}\n", .{self.instructions[i]});
        }
    }
};

pub fn main() !void {
    var ins = std.ArrayList(Token).init(std.heap.page_allocator);

    try ins.append(Token{ .instruction = Instruction.open_loop, .pos = 0 });

    std.debug.print("{any}\n", .{ins.items[0]});
}

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
                try brackets.append(program.n_instructions - 1); // -1 because n_instructions is incremented automatically
            } else if (instr == Instruction.close_loop) {
                const matching: usize = brackets.pop();
                program.instructions[matching].matching_bracket = program.n_instructions - 1;   // update open bracket
                program.instructions[program.n_instructions - 1].matching_bracket = matching;   // update closed (current)
            }
        }
    }

    if (brackets.items.len != 0) return ParseError.UnclosedBrackets;

    return program;
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

    try program.dumpProgram();

    try testing.expect(program.instructions[0].matching_bracket == 5);
    try testing.expect(program.instructions[5].matching_bracket == 0);
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
