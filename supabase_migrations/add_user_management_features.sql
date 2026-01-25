-- User Management Features: Ban/Suspend, Status Tracking, Account Deletion
-- This migration adds the infrastructure for admin user management

-- 1. Add role column for admin identification
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user' 
CHECK (role IN ('user', 'admin', 'moderator'));

-- 2. Add user status column
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active' 
CHECK (status IN ('active', 'suspended', 'banned', 'deleted'));

-- 3. Add ban/suspension metadata
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS status_reason TEXT,
ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS status_changed_by UUID REFERENCES users(id);

-- 4. Add deleted_at for soft deletes (GDPR compliance)
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 5. Create indexes
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);

-- 5. Create function to check user status on auth
CREATE OR REPLACE FUNCTION check_user_status()
RETURNS TRIGGER AS $$
BEGIN
  -- This would ideally be called on login, but needs to integrate with Supabase Auth
  -- For now, apps should check user status after successful auth
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Create audit log table for admin actions
CREATE TABLE IF NOT EXISTS admin_actions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id UUID NOT NULL REFERENCES users(id),
  action_type TEXT NOT NULL, -- 'ban', 'suspend', 'delete', 'reset_password'
  target_user_id UUID NOT NULL REFERENCES users(id),
  reason TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_actions_admin ON admin_actions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_target ON admin_actions(target_user_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_created ON admin_actions(created_at DESC);

-- 7. RLS Policies for admin_actions (only admins can view)
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view admin actions" ON admin_actions
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role = 'admin' -- Assumes you have an admin role
  )
);

CREATE POLICY "Only admins can insert admin actions" ON admin_actions
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role = 'admin'
  )
);

-- 8. Comments for documentation
COMMENT ON COLUMN users.status IS 'User account status: active, suspended, banned, or deleted';
COMMENT ON COLUMN users.status_reason IS 'Reason for suspension/ban (visible to user)';
COMMENT ON COLUMN users.deleted_at IS 'Soft delete timestamp for GDPR compliance';
COMMENT ON TABLE admin_actions IS 'Audit log of all admin actions on user accounts';
