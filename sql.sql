CREATE TABLE IF NOT EXISTS `boss_menu_stats` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `job_name` VARCHAR(50) NOT NULL,
  `total_money` INT(11) DEFAULT 0,
  `total_withdraw` INT(11) DEFAULT 0,
  `total_deposit` INT(11) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `job_name` (`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
