const std = @import("std");
const pgz = @import("pgz");

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

pub fn getMigrated(allocator: std.mem.Allocator, db:*pgz.Connection) !Migrations {
    try assertMigrationsTable(db);
    var migrations_list = try std.ArrayListUnmanaged([:0]const u8).initCapacity(allocator, 10);

    const sql = "SELECT name FROM migrator_migrations ORDER BY name;";
    var result = try db.query(sql, struct { name: []const u8 });
    defer result.deinit();

    for (result.data) |row| {
        try migrations_list.append(allocator, try allocator.dupeZ(u8, row.name));
    }

    return Migrations{ .allocator = allocator, .list = migrations_list };
}

pub fn getUnmigrated(allocator: std.mem.Allocator, db:*pgz.Connection) !Migrations {
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

pub fn runMigration(allocator: std.mem.Allocator, db:*pgz.Connection, migration: [:0]const u8) !void {
    var migrations_dir = try std.fs.cwd().openDir("migrations", .{});
    defer migrations_dir.close();
    var migration_file = try migrations_dir.openFile(migration, .{});
    defer migration_file.close();
    var migration_sql = try migration_file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, 1, 0);
    defer allocator.free(migration_sql);
    try db.exec(migration_sql);
}

pub fn markAsMigrated(allocator: std.mem.Allocator, db:*pgz.Connection, migration: [:0]const u8) !void {
    var literal = try pgz.quoteLiteral(allocator, migration);
    defer allocator.free(literal);
    var sql = try std.fmt.allocPrint(allocator, "INSERT INTO migrator_migrations(name) VALUES({s});", .{literal});
    defer allocator.free(sql);
    try db.exec(sql);
}

pub fn assertMigrationsTable(db:*pgz.Connection) !void {
    if (!try Migrations.isMigrationsTableExists(db)) {
        try Migrations.createMigrationsTable(db);
    }
}

pub fn openDatabase(allocator: std.mem.Allocator, scheme: [:0]const u8) !*pgz.Connection {
    _ = std.mem.indexOf(u8, scheme, "postgres://") orelse return error.BadConnectionUrl;
    var db = try allocator.create(pgz.Connection);
    db.* = try pgz.Connection.init(allocator, try std.Uri.parse(scheme));
    return db;
}

pub fn closeDatabase(db: *pgz.Connection) void {
    var allocator = db.allocator;
    db.deinit();
    allocator.destroy(db);
}

fn isMigrationsTableExists(db:*pgz.Connection) !bool {
    const sql = "SELECT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'migrator_migrations') as value;";
    var result = try db.query(sql, struct { value: []const u8 });
    defer result.deinit();
    if (result.data.len > 0 and result.data[0].value[0] == 't') {
        return true;
    } else {
        return false;
    }
}

fn createMigrationsTable(db:*pgz.Connection) !void {
    const sql = "CREATE TABLE migrator_migrations(name text not null);";
    try db.exec(sql);
}

pub fn free(self: *Migrations) void {
    for (self.list.items) |migration| {
        self.allocator.free(migration);
    }
    self.list.clearAndFree(self.allocator);
}
