-- PostgreSQL Initialization Script for BiologiDex
-- This script runs when the database container is first created

-- Set default configuration parameters
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Logging configuration
ALTER SYSTEM SET log_min_duration_statement = 100;
ALTER SYSTEM SET log_checkpoints = on;
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET log_temp_files = 0;
ALTER SYSTEM SET log_autovacuum_min_duration = 0;
ALTER SYSTEM SET log_line_prefix = '%t [%p] %u@%d ';

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For text search optimization
CREATE EXTENSION IF NOT EXISTS "btree_gist";  -- For exclusion constraints

-- Create read-only user for analytics/monitoring (optional)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'biologidex_readonly') THEN
        CREATE USER biologidex_readonly WITH PASSWORD 'readonly_password_change_me';
        GRANT CONNECT ON DATABASE biologidex TO biologidex_readonly;
        GRANT USAGE ON SCHEMA public TO biologidex_readonly;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO biologidex_readonly;
        -- Grant select on existing tables
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO biologidex_readonly;
    END IF;
END
$$;

-- Create monitoring user (optional, for Prometheus postgres_exporter)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'biologidex_monitor') THEN
        CREATE USER biologidex_monitor WITH PASSWORD 'monitor_password_change_me';
        GRANT CONNECT ON DATABASE biologidex TO biologidex_monitor;
        GRANT USAGE ON SCHEMA public TO biologidex_monitor;
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO biologidex_monitor;
        GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO biologidex_monitor;

        -- Grant necessary permissions for monitoring
        GRANT pg_monitor TO biologidex_monitor;
    END IF;
END
$$;

-- Optimize database for Django
-- These are applied after Django creates its tables via migrations

-- Create function to update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Performance optimization indexes (will be created after Django migrations)
-- Note: These will fail gracefully if tables don't exist yet

-- Indexes for the animals app
DO $$
BEGIN
    -- Index on scientific_name for lookups
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'animals_animal') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_animals_scientific_name
        ON animals_animal USING btree (scientific_name);

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_animals_genus_species
        ON animals_animal USING btree (genus, species);

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_animals_verified
        ON animals_animal USING btree (verified) WHERE verified = true;
    END IF;
END
$$;

-- Indexes for the dex app
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'dex_dexentry') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dex_owner_created
        ON dex_dexentry USING btree (owner_id, created_at DESC);

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dex_visibility
        ON dex_dexentry USING btree (visibility) WHERE visibility != 'private';

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dex_favorite
        ON dex_dexentry USING btree (owner_id, is_favorite) WHERE is_favorite = true;
    END IF;
END
$$;

-- Indexes for the social app
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'social_friendship') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_friendship_users
        ON social_friendship USING btree (user1_id, user2_id);

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_friendship_status
        ON social_friendship USING btree (status) WHERE status = 'accepted';
    END IF;
END
$$;

-- Indexes for the vision app
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'vision_analysisjob') THEN
        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_analysisjob_status
        ON vision_analysisjob USING btree (status, created_at DESC);

        CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_analysisjob_user_created
        ON vision_analysisjob USING btree (user_id, created_at DESC);
    END IF;
END
$$;

-- Vacuum and analyze settings for tables
DO $$
BEGIN
    -- Set aggressive autovacuum for frequently updated tables
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'vision_analysisjob') THEN
        ALTER TABLE vision_analysisjob SET (autovacuum_vacuum_scale_factor = 0.1);
        ALTER TABLE vision_analysisjob SET (autovacuum_analyze_scale_factor = 0.05);
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'dex_dexentry') THEN
        ALTER TABLE dex_dexentry SET (autovacuum_vacuum_scale_factor = 0.2);
        ALTER TABLE dex_dexentry SET (autovacuum_analyze_scale_factor = 0.1);
    END IF;
END
$$;

-- Create database statistics
ANALYZE;

-- Reload configuration
SELECT pg_reload_conf();