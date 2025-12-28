# Nhost CLI Guide for BiteMates

This guide documents how to use the Nhost CLI for the BiteMates project, including the specific local installation method used for this environment.

## 1. Installation (Local Project Method)

Since the standard global installation requires sudo permissions that might fail in some environments, we have installed the CLI locally within the project.

**Location:** `./bin/nhost`

To run any Nhost command, prefix it with `./bin/nhost` from the project root.

*Example:*
```bash
./bin/nhost --version
```

## 2. Project Initialization

To initialize a new Nhost project (already done for BiteMates):

```bash
./bin/nhost init
```

This creates the `nhost/` directory with the following structure:
- `nhost/config.yaml`: Configuration for services
- `nhost/migrations/`: Database migrations
- `nhost/metadata/`: Hasura metadata
- `nhost/seeds/`: Database seed data

## 3. Local Development Workflow

### Start the Environment
Starts the complete local stack (Postgres, Hasura, Auth, Storage, Functions).

```bash
./bin/nhost up
```

**Services URLs:**
- **Dashboard:** `https://local.dashboard.local.nhost.run`
- **GraphQL:** `https://local.graphql.local.nhost.run`
- **Auth:** `https://local.auth.local.nhost.run`
- **Postgres:** `postgres://postgres:postgres@localhost:5432/local`

### Stop the Environment
```bash
./bin/nhost down
```

### View Logs
```bash
./bin/nhost logs
```

## 4. Database Migrations

Migrations track changes to your database schema.

### Create a Migration
To create a new migration file (e.g., for creating tables):

```bash
./bin/nhost migration create name_of_migration
```
*Example:* `./bin/nhost migration create create_users_table`

This creates `up.sql` and `down.sql` files in `nhost/migrations/default/<timestamp>_name/`.
- **up.sql**: SQL to apply the change.
- **down.sql**: SQL to revert the change.

### Apply Migrations
To apply pending migrations to your local database:

```bash
./bin/nhost migration apply
```

### Auto-generate from Console
You can also make changes in the Hasura Console (via the local Dashboard) and let Nhost track them automatically.
1. Run `./bin/nhost up`
2. Open the dashboard
3. Make changes (create tables, etc.)
4. Nhost automatically creates migration files in `nhost/migrations/`

## 5. Deployment

### Login
Authenticate with your Nhost account:

```bash
./bin/nhost login
```

### Link to Cloud Project
Associate your local project with a project on Nhost Cloud:

```bash
./bin/nhost link
```
You will be prompted to select your project.

### Deploy
Deployments are typically handled via Git integration (pushing to GitHub), but you can manage config and metadata via CLI.

To push local changes (migrations/metadata) to the cloud manually (if not using GitOps):
```bash
./bin/nhost push
```

## 6. Troubleshooting

**"nhost folder already exists" error during init:**
If you need to re-initialize, you must remove the existing folder first:
```bash
rm -rf nhost
./bin/nhost init
```

**Permission denied:**
Ensure the binary is executable:
```bash
chmod +x bin/nhost
```
