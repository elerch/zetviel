const std = @import("std");
const notmuch = @import("notmuch.zig");

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

    try bw.flush(); // don't forget to flush!
}

test "can get status" {
    // const allocator = std.testing.allocator;
    // const db_path = try std.fs.path.join(
    //     allocator,
    //     std.fs.cwd(),
    //     "mail",
    // );

    // Current directory under test is root of project
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(path_buf[0..]);
    const db_path = try std.fs.path.joinZ(fba.allocator(), &[_][]const u8{ cwd, "mail" });
    {
        var status: notmuch.Status = undefined;
        var db = try notmuch.Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        try std.testing.expectEqualStrings("No error occurred", status.statusString());
    }
    {
        var db = try notmuch.Db.open(db_path, null);
        defer db.deinit();
        defer db.close();
    }
    {
        var status: notmuch.Status = undefined;
        try std.testing.expectError(error.CouldNotOpenDatabase, notmuch.Db.open(
            "NON-EXISTANT",
            &status,
        ));
        defer status.deinit();
        try std.testing.expectEqualStrings(
            "Path supplied is illegal for this function",
            status.statusString(),
        );
    }
    //
    // // This is the python that's executing
    // //         def get(self, thread_id):
    // // threads = notmuch.Query(
    // //     get_db(), "thread:{}".format(thread_id)
    // // ).search_threads()
    // // thread = next(threads)  # there can be only 1
    // // messages = thread.get_messages()
    // // return messages_to_json(messages)
    // try std.testing.expectEqualStrings("No error occurred", std.mem.span(c.notmuch_status_to_string(open_status)));
}

test "can search threads" {
    // const allocator = std.testing.allocator;
    // const db_path = try std.fs.path.join(
    //     allocator,
    //     std.fs.cwd(),
    //     "mail",
    // );

    // Current directory under test is root of project
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", cwd_buf[0..]);
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(path_buf[0..]);
    const db_path = try std.fs.path.joinZ(fba.allocator(), &[_][]const u8{ cwd, "mail" });
    {
        var status: notmuch.Status = undefined;
        var db = try notmuch.Db.open(db_path, &status);
        defer db.deinit();
        defer db.close();
        defer status.deinit();
        try std.testing.expectEqualStrings("No error occurred", status.statusString());
        var t_iter = try db.searchThreads("Tablets");
        defer t_iter.deinit();
        var inx: usize = 0;
        while (t_iter.next()) |t| : (inx += 1) {
            defer t.deinit();
            try std.testing.expectEqual(@as(c_int, 1), t.getTotalMessages());
            try std.testing.expectEqualStrings("0000000000000001", t.getThreadId());
            var message_iter = try t.getMessages();
            var jnx: usize = 0;
            while (message_iter.next()) |m| : (jnx += 1) {
                defer m.deinit();
                try std.testing.expectStringEndsWith(m.getFilename(), "/1721591945.R4187135327503631514.nucman:2,S");
            }
            try std.testing.expectEqual(@as(usize, 1), jnx);
        }
        try std.testing.expectEqual(@as(usize, 1), inx);
    }

    // This is the json we're looking to match on api/query/<term>
    // [
    //    {
    //      "authors": "The Washington Post",
    //      "matched_messages": 1,
    //      "newest_date": 1721664948,
    //      "oldest_date": 1721664948,
    //      "subject": "Biden is out. What now?",
    //      "tags": [
    //        "inbox",
    //        "unread"
    //      ],
    //      "thread_id": "0000000000031723",
    //      "total_messages": 1
    //    },
    //    {
    //      "authors": "The Washington Post",
    //      "matched_messages": 1,
    //      "newest_date": 1721603115,
    //      "oldest_date": 1721603115,
    //      "subject": "Upcoming Virtual Programs",
    //      "tags": [
    //        "inbox",
    //        "unread"
    //      ],
    //      "thread_id": "0000000000031712",
    //      "total_messages": 1
    //    },
    //    {
    //      "authors": "The Washington Post",
    //      "matched_messages": 1,
    //      "newest_date": 1721590157,
    //      "oldest_date": 1721590157,
    //      "subject": "Biden Steps Aside",
    //      "tags": [
    //        "inbox"
    //      ],
    //      "thread_id": "000000000003170d",
    //      "total_messages": 1
    //    }
    // ]
    //
    // And on api/thread/<threadid>
    //
    // [
    //   {
    //     "from": "The Washington Post <email@washingtonpost.com>",
    //     "to": "elerch@lerch.org",
    //     "cc": null,
    //     "bcc": null,
    //     "date": "Sun, 21 Jul 2024 19:23:38 +0000",
    //     "subject": "Biden steps aside",
    //     "content": "...content...",
    //     "content_type": "text/html",
    //     "attachments": [],
    //     "message_id": "01010190d6bfe4e1-185e2720-e415-4086-8865-9604cde886c2-000000@us-west-2.amazonses.com"
    //   }
    // ]
}
