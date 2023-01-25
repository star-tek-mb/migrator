# Overview

migrator - database migration tool written in zig

# Features

Currently supported database drivers:

- sqlite3
- postgres

# Build

```
zig build
```

# Usage

Create migration file

```bash
migrator create
```

Write some SQL into created file
```sql
CREATE TABLE users(name text not null);
```

Then migrate

```bash
migrator migrate sqlite://hello.db
```
