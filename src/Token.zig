const Instruction = @import("Instruction.zig").Instruction;

pub const Token = struct {
    instruction: Instruction,
	pos: usize,
    /// If the instruction is a bracket, keep track of matching bracket
    matching_bracket: ?usize = null,
};
