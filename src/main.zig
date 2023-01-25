const std = @import("std");
const Migrations = @import("migrations.zig").Migrations;

pub fn getDatetime(timestamp: i64) ![17]u8 {
    var ret: [17]u8 = undefined;
    var epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, timestamp) };
    var epoch_day = epoch_seconds.getEpochDay();
    var year_day = epoch_day.calculateYearDay();
    var month_day = year_day.calculateMonthDay();
    var day_seconds = epoch_seconds.getDaySeconds();

    var day = month_day.day_index + 1;
    var month = month_day.month.numeric();
    var year = year_day.year;
    var hour = day_seconds.getHoursIntoDay();
    var minute = day_seconds.getMinutesIntoHour();
    var second = day_seconds.getSecondsIntoMinute();

    _ = try std.fmt.bufPrint(&ret, "{d:0>4}_{d:0>2}_{d:0>2}_{d:0>2}{d:0>2}{d:0>2}", .{ year, month, day, hour, minute, second });
    return ret;
}

pub fn migrate(allocator: std.mem.Allocator, db_url: [:0]const u8, Backend: anytype) !void {
    var out = std.io.getStdOut().writer();

    var db = try Backend.openDatabase(allocator, db_url);
    defer Backend.closeDatabase(db);

    var runned_migrations_count: usize = 0;
    var migrations = try Backend.getUnmigrated(allocator, db);
    for (migrations.list.items) |migration| {
        try out.print("{s}", .{migration});
        try Backend.runMigration(allocator, db, migration);
        try Backend.markAsMigrated(allocator, db, migration);
        try out.print(" - OK\n", .{});
        runned_migrations_count += 1;
    }

    try out.print("Runned {d} migrations\n", .{runned_migrations_count});
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var out = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer out.flush() catch {};

    var command = args.next();
    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "create")) {
            var migration_description = args.next() orelse "no_comment";
            var migration_file_path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
            var datetime = try getDatetime(std.time.timestamp());
            var migration_file_path = try std.fmt.bufPrint(&migration_file_path_buffer, "migrations/{s}_{s}.sql", .{ datetime, migration_description });
            std.fs.cwd().makeDir("migrations") catch {};
            var migration_file = try std.fs.cwd().createFile(migration_file_path, .{});
            migration_file.close();
        }

        if (std.mem.eql(u8, cmd, "migrate")) {
            var db_url = args.next() orelse return error.DatabaseNotFound;
            var db_backend = db_url[0 .. std.mem.indexOf(u8, db_url, "://") orelse return error.BadConnectionUrl];

            if (std.mem.eql(u8, db_backend, "sqlite")) {
                try migrate(allocator, db_url, Migrations(.sqlite));
            } else if (std.mem.eql(u8, db_backend, "postgres")) {
                try migrate(allocator, db_url, Migrations(.postgres));
            } else {
                try out.writer().print("Database driver {s} not supported\n", .{db_backend});
            }
        }
    }
}
