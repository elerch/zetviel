const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us. \n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // Example of using the root.zig functionality
    const allocator = std.heap.page_allocator;
    var db_result = root.openNotmuchDb(allocator, "mail") catch |err| {
        std.debug.print("Failed to open notmuch database: {}\n", .{err});
        return;
    };
    defer db_result.close();

    std.debug.print("Successfully opened notmuch database at: {s}\n", .{db_result.path});

    try bw.flush(); // don't forget to flush!
}
