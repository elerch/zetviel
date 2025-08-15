pub const c = @cImport({
    @cInclude("time.h");
    @cInclude("fcntl.h");
    @cInclude("notmuch.h");
    @cInclude("gmime/gmime.h");
});
