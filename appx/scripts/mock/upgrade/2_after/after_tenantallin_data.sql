-- mock after：升级后标记（对标 upgrade/2_after/after_tenantallin_data.sql）
UPDATE deploy_marker SET phase = 'after', updated_at = now() WHERE id = 1;
