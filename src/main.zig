const std = @import("std");
const c = @cImport({
    @cInclude("notmuch.h");
});

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us. Status: {s}\n", .{ "codebase", c.notmuch_status_to_string(0) });

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "can get status" {
    try std.testing.expectEqualStrings("No error occurred", std.mem.span(c.notmuch_status_to_string(0)));
}
