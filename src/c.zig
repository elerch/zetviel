pub const c = @cImport({
    @cInclude("notmuch.h");

    // vv - Needed for gmime
    @cInclude("fcntl.h");
    @cInclude("gmime/gmime.h");
});
