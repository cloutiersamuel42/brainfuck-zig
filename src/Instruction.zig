const std = @import("std");

pub const Instruction = enum(u8) {
    invalid,
    inc_data_p,
    dec_data_p,
    inc,
    dec,
    output,
    input,
    open_loop,
    close_loop,

    // idk
    pub fn instructionFromChar(char: u8) Instruction {
        switch (char) {
            '>' => return Instruction.inc_data_p,
            '<' => return Instruction.dec_data_p,
            '+' => return Instruction.inc,
            '-' => return Instruction.dec,
            '.' => return Instruction.output,
            ',' => return Instruction.input,
            '[' => return Instruction.open_loop,
            ']' => return Instruction.close_loop,
            else => return Instruction.invalid,
        }
    }
};
