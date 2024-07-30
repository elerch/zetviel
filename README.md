Zetviel
-------

As some background, I've had some issues with the very usable [netviel](https://github.com/DavidMStraub/netviel).

I wanted to address those issues, but also simplify the deployment. And, I like zig,
so I decided this was small enough I'd just re-write the thing to make my own.

This is still very work in progress, to the point it is not yet usable. It has
some basic notmuch integration and a usable build system.

Building
--------

If you have notmuch installed (libnotmuch-dev on a debian-based system),
`zig build` is all you need. If you are using nix, you can `nix develop`, which
will install the necessary notmuch header/library, and the build system will
detect and use that. Again, `zig build` will work in that instance, but you must
`nix develop` first.

More to come...
