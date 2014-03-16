CREATE TABLE IF NOT EXISTS `temperature_controller`.`parameters` (
    `name` VARCHAR(255) NOT NULL ,
    `value` VARCHAR(255) NOT NULL ,
    UNIQUE INDEX `name_UNIQUE` (`name` ASC) ,
    PRIMARY KEY (`name`) );
        
CREATE TABLE IF NOT EXISTS `temperature_controller`.`time_series` (      
    `measured_at` DATETIME NOT NULL ,
    `temperature` DECIMAL(6,3) NOT NULL ,
    `outside_temperature` decimal(6,3),
    `minimum_temperature` decimal(6,3) NOT NULL,
    `heat_on`     INT NOT NULL,
    PRIMARY KEY (`measured_at`) );

INSERT IGNORE INTO temperature_controller.parameters (name, value) VALUES ("heat_on_if_temp_lower_than", "11");
INSERT IGNORE INTO temperature_controller.parameters (name, value) VALUES ("min_seconds_between_heat_on_off", "1200");

