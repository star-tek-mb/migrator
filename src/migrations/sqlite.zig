const std = @import("std");
const sqlite3 = @cImport(@cInclude("sqlite3.h"));

const Migrations = @This();

allocator: std.mem.Allocator,
list: std.ArrayListUnmanaged([:0]const u8),

pub fn getAll(allocator: std.mem.Allocator) !Migrations {
    var migrations_list = try std.ArrayListUnmanaged([:0]const u8).initCapacity(allocator, 10);
    var migrations_dir = std.fs.cwd().openIterableDir("migrations", .{}) catch {
        return Migrations{ .allocator = allocator, .list = .{} };
    };
    defer migrations_dir.close();

    var migrations_dir_iterator = migrations_dir.iterate();
    while (try migrations_dir_iterator.next()) |entry| {
        try migrations_list.append(allocator, try allocator.dupeZ(u8, entry.name));
    }

    const sorter = struct {
        pub fn do(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.orderIgnoreCase(a, b) == .lt;
        }
    };
    std.sort.sort([]const u8, migrations_list.items, {}, sorter.do);

    return Migrations{ .allocator = allocator, .list = migrations_list };
}

pub fn getMigrated(allocator: std.mem.Allocator, db: *sqlite3.sqlite3) !Migrations {
    try assertMigrationsTable(db);
    var migrations_list = try std.ArrayListUnmanaged([:0]const u8).initCapacity(allocator, 10);

    const sql = "SELECT name FROM migrator_migrations ORDER BY name;";
    var stmt: ?*sqlite3.sqlite3_stmt = null;
    var prepare_ret = sqlite3.sqlite3_prepare(db, sql, sql.len, &stmt, null);
    if (prepare_ret != sqlite3.SQLITE_OK) return error.SqlPrepareError;
    defer _ = sqlite3.sqlite3_finalize(stmt);
    var res = sqlite3.sqlite3_step(stmt);
    while (res == sqlite3.SQLITE_ROW) : (res = sqlite3.sqlite3_step(stmt)) {
        var text = sqlite3.sqlite3_column_text(stmt, 0);
        var slice = std.mem.sliceTo(text, 0);
        try migrations_list.append(allocator, try allocator.dupeZ(u8, slice));
    }

    return Migrations{ .allocator = allocator, .list = migrations_list };
}

pub fn getUnmigrated(allocator: std.mem.Allocator, db: *sqlite3.sqlite3) !Migrations {
    var all = try Migrations.getAll(allocator);
    defer all.free();
    var migrated = try Migrations.getMigrated(allocator, db);
    defer migrated.free();

    var migrations_list = try std.ArrayListUnmanaged([:0]const u8).initCapacity(allocator, 10);

    // TODO: optimize sorted array
    for (all.list.items) |a| {
        var found = false;
        for (migrated.list.items) |b| {
            if (std.mem.eql(u8, a, b)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try migrations_list.append(allocator, try allocator.dupeZ(u8, a));
        }
    }

    return Migrations{ .allocator = allocator, .list = migrations_list };
}

pub fn runMigration(allocator: std.mem.Allocator, db: *sqlite3.sqlite3, migration: [:0]const u8) !void {
    var migrations_dir = try std.fs.cwd().openDir("migrations", .{});
    defer migrations_dir.close();
    var migration_file = try migrations_dir.openFile(migration, .{});
    defer migration_file.close();
    var migration_sql = try migration_file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, 1, 0);
    defer allocator.free(migration_sql);

    var exec_ret = sqlite3.sqlite3_exec(db, migration_sql, null, null, null);
    if (exec_ret != sqlite3.SQLITE_OK) return error.SqlExecuteError;
}

pub fn markAsMigrated(_: std.mem.Allocator, db: *sqlite3.sqlite3, migration: [:0]const u8) !void {
    const sql = "INSERT INTO migrator_migrations(name) VALUES(?);";
    var stmt: ?*sqlite3.sqlite3_stmt = null;
    var prepare_ret = sqlite3.sqlite3_prepare(db, sql, sql.len, &stmt, null);
    if (prepare_ret != sqlite3.SQLITE_OK) return error.SqlPrepareError;
    defer _ = sqlite3.sqlite3_finalize(stmt);
    var bind_ret = sqlite3.sqlite3_bind_text(stmt, 1, migration, @intCast(c_int, migration.len), null);
    if (bind_ret != sqlite3.SQLITE_OK) return error.SqlBindError;
    var res = sqlite3.sqlite3_step(stmt);
    if (res != sqlite3.SQLITE_DONE) return error.SqlExecuteError;
}

pub fn assertMigrationsTable(db: *sqlite3.sqlite3) !void {
    if (!try Migrations.isMigrationsTableExists(db)) {
        try Migrations.createMigrationsTable(db);
    }
}

pub fn openDatabase(_: std.mem.Allocator, scheme: [:0]const u8) !*sqlite3.sqlite3 {
    var db: ?*sqlite3.sqlite3 = null;
    _ = std.mem.indexOf(u8, scheme, "sqlite://") orelse return error.BadConnectionUrl;
    var ret = sqlite3.sqlite3_open(scheme["sqlite://".len..], &db);
    if (ret != sqlite3.SQLITE_OK) return error.DatabaseNotFound;
    return db.?;
}

pub fn closeDatabase(db: *sqlite3.sqlite3) void {
    _ = sqlite3.sqlite3_close(db);
}

fn isMigrationsTableExists(db: *sqlite3.sqlite3) !bool {
    const sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'migrator_migrations';";
    var stmt: ?*sqlite3.sqlite3_stmt = null;
    var prepare_ret = sqlite3.sqlite3_prepare(db, sql, sql.len, &stmt, null);
    if (prepare_ret != sqlite3.SQLITE_OK) return error.SqlPrepareError;
    defer _ = sqlite3.sqlite3_finalize(stmt);
    var res = sqlite3.sqlite3_step(stmt);
    if (res == sqlite3.SQLITE_ROW) {
        return true;
    } else {
        return false;
    }
}

fn createMigrationsTable(db: *sqlite3.sqlite3) !void {
    const sql = "CREATE TABLE migrator_migrations(name text not null);";
    var ret = sqlite3.sqlite3_exec(db, sql, null, null, null);
    if (ret != sqlite3.SQLITE_OK) return error.SqlExecuteError;
}

pub fn free(self: *Migrations) void {
    for (self.list.items) |migration| {
        self.allocator.free(migration);
    }
    self.list.clearAndFree(self.allocator);
}
