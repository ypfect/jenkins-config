-- mock before：升级前标记（对标 upgrade/1_before/before_tenantallin_data.sql）
UPDATE deploy_marker SET phase = 'before', updated_at = now() WHERE id = 1;
