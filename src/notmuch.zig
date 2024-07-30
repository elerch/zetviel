const std = @import("std");
const c = @cImport({
    @cInclude("notmuch.h");
});

pub const Status = struct {
    err: ?anyerror = null,
    status: c.notmuch_status_t = c.NOTMUCH_STATUS_SUCCESS,
    msg: ?[*:0]u8 = null,

    pub fn deinit(status: *Status) void {
        if (status.msg) |m| std.c.free(m);
        status.err = undefined;
        status.status = c.NOTMUCH_STATUS_SUCCESS;
        status.msg = null;
    }

    pub fn statusString(status: Status) []const u8 {
        return std.mem.span(c.notmuch_status_to_string(status.status));
    }
};
pub const Db = struct {
    handle: *c.notmuch_database_t,

    pub fn open(path: [:0]const u8, status: ?*Status) !Db {
        var db: ?*c.notmuch_database_t = null;
        var err: ?[*:0]u8 = null;

        const open_status = c.notmuch_database_open_with_config(
            path,
            c.NOTMUCH_DATABASE_MODE_READ_ONLY,
            "",
            null,
            &db,
            &err,
        );
        defer if (err) |e| if (status == null) std.c.free(e);
        if (open_status != c.NOTMUCH_STATUS_SUCCESS) {
            if (status) |s| s.* = .{
                .msg = err,
                .status = open_status,
                .err = error.CouldNotOpenDatabase,
            };
            return error.CouldNotOpenDatabase;
        }
        if (db == null) unreachable; // If we opened the database successfully, this should never be null
        if (status) |s| s.* = .{};
        return .{ .handle = db.? };
    }

    pub fn close(db: *Db) void {
        _ = c.notmuch_database_close(db.handle);
    }
    pub fn deinit(db: *Db) void {
        _ = c.notmuch_database_destroy(db.handle);
        db.handle = undefined;
    }

    //
    // Execute a query for threads, returning a notmuch_threads_t object
    // which can be used to iterate over the results. The returned threads
    // object is owned by the query and as such, will only be valid until
    // notmuch_query_destroy.
    //
    // Typical usage might be:
    //
    //     notmuch_query_t *query;
    //     notmuch_threads_t *threads;
    //     notmuch_thread_t *thread;
    //     notmuch_status_t stat;
    //
    //     query = notmuch_query_create (database, query_string);
    //
    //     for (stat = notmuch_query_search_threads (query, &threads);
    //	    stat == NOTMUCH_STATUS_SUCCESS &&
    //          notmuch_threads_valid (threads);
    //          notmuch_threads_move_to_next (threads))
    //     {
    //         thread = notmuch_threads_get (threads);
    //         ....
    //         notmuch_thread_destroy (thread);
    //     }
    //
    //     notmuch_query_destroy (query);
    //
    // Note: If you are finished with a thread before its containing
    // query, you can call notmuch_thread_destroy to clean up some memory
    // sooner (as in the above example). Otherwise, if your thread objects
    // are long-lived, then you don't need to call notmuch_thread_destroy
    // and all the memory will still be reclaimed when the query is
    // destroyed.
    //
    // Note that there's no explicit destructor needed for the
    // notmuch_threads_t object. (For consistency, we do provide a
    // notmuch_threads_destroy function, but there's no good reason
    // to call it if the query is about to be destroyed).
    pub fn searchThreads(db: Db, query: [:0]const u8) !ThreadIterator {
        const nm_query = c.notmuch_query_create(db.handle, query);
        if (nm_query == null) return error.CouldNotCreateQuery;
        const handle = nm_query.?;
        errdefer c.notmuch_query_destroy(handle);
        var threads: ?*c.notmuch_threads_t = undefined;
        const status = c.notmuch_query_search_threads(handle, &threads);
        if (status != c.NOTMUCH_STATUS_SUCCESS) return error.CouldNotSearchThreads;
        return .{
            .query = handle,
            .thread_state = threads orelse return error.CouldNotSearchThreads,
        };
    }

    pub const Message = struct {
        message_handle: *c.notmuch_message_t,

        pub fn getFilename(self: Message) []const u8 {
            return std.mem.span(c.notmuch_message_get_filename(self.message_handle));
        }

        pub fn deinit(self: Message) void {
            c.notmuch_message_destroy(self.message_handle);
        }
    };
    pub const MessageIterator = struct {
        messages_state: *c.notmuch_messages_t,
        first: bool = true,

        pub fn next(self: *MessageIterator) ?Message {
            if (!self.first) c.notmuch_messages_move_to_next(self.messages_state);
            self.first = false;
            if (c.notmuch_messages_valid(self.messages_state) == 0) return null;
            const message = c.notmuch_messages_get(self.messages_state) orelse return null;
            return .{
                .message_handle = message,
            };
        }

        // Docs imply strongly not to bother with deinitialization here

    };
    pub const Thread = struct {
        thread_handle: *c.notmuch_thread_t,

        // Get the thread ID of 'thread'.
        //
        // The returned string belongs to 'thread' and as such, should not be
        // modified by the caller and will only be valid for as long as the
        // thread is valid, (which is until deinit() or the query from which
        // it derived is destroyed).
        pub fn getThreadId(self: Thread) []const u8 {
            return std.mem.span(c.notmuch_thread_get_thread_id(self.thread_handle));
        }

        // Get the total number of messages in 'thread'.
        //
        // This count consists of all messages in the database belonging to
        // this thread. Contrast with notmuch_thread_get_matched_messages() .
        pub fn getTotalMessages(self: Thread) c_int {
            return c.notmuch_thread_get_total_messages(self.thread_handle);
        }

        // Get the total number of files in 'thread'.
        //
        // This sums notmuch_message_count_files over all messages in the
        // thread
        pub fn getTotalFiles(self: Thread) c_int {
            return c.notmuch_thread_get_total_files(self.thread_handle);
        }

        pub fn getMessages(self: Thread) !MessageIterator {
            return .{
                .messages_state = c.notmuch_thread_get_messages(self.thread_handle) orelse return error.CouldNotGetIterator,
            };
        }

        pub fn deinit(self: Thread) void {
            c.notmuch_thread_destroy(self.thread_handle);
            // self.thread_handle = undefined;
        }
    };
    pub const ThreadIterator = struct {
        query: *c.notmuch_query_t,
        thread_state: *c.notmuch_threads_t,
        first: bool = true,

        pub fn next(self: *ThreadIterator) ?Thread {
            if (!self.first) c.notmuch_threads_move_to_next(self.thread_state);
            self.first = false;
            if (c.notmuch_threads_valid(self.thread_state) == 0) return null;
            const thread = c.notmuch_threads_get(self.thread_state) orelse return null;
            return .{
                .thread_handle = thread,
            };
        }

        pub fn deinit(self: *ThreadIterator) void {
            c.notmuch_query_destroy(self.query);
            self.query = undefined;
        }
    };
};
