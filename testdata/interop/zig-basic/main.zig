const std = @import("std");
const math = @import("std").math;

const retry_limit: u8 = 3;

const Settings = struct {
    enable_tracing: bool = true,
};

fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn run(value: i32) i32 {
    const settings = Settings{ .enable_tracing = true };
    const doubled = add(value, retry_limit);
    return if (settings.enable_tracing) math.absInt(doubled) else doubled;
}
