pub const Backend = enum {
    sqlite,
    postgres,
};

pub fn Migrations(comptime backend: Backend) type {
    switch (backend) {
        .sqlite => return @import("migrations/sqlite.zig"),
        .postgres => return @import("migrations/postgres.zig"),
    }
}
