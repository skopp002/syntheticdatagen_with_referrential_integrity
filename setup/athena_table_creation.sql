-- Create the department table
CREATE TABLE department (
    department_id INT PRIMARY KEY,
    department_name STRING,
    department_location STRING,
    department_budget DECIMAL(10, 2)
)
USING iceberg
PARTITIONED BY (dt STRING)
LOCATION 's3://apg-synthetic-datagen-skoppar/department/';

-- Create the employee table
CREATE TABLE employee (
    employee_id INT PRIMARY KEY,
    department_id INT,
    employee_name STRING,
    employee_email STRING,
    manager_id INT,
    employee_level INT
)
USING iceberg
PARTITIONED BY (dt STRING)
LOCATION 's3://apg-synthetic-datagen-skoppar/employee/';

-- Create the skills table
CREATE TABLE skills (
    skill_id INT,
    employee_id INT,
    skill_name STRING
)
USING iceberg
PARTITIONED BY (dt STRING)
LOCATION 's3://apg-synthetic-datagen-skoppar/skills/';


-- Create the department table
CREATE EXTERNAL TABLE department (
    department_id INT,
    department_name STRING
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://apg-synthetic-datagen-skoppar/department/';

-- Create the employee table
CREATE EXTERNAL TABLE employee (
    employee_id INT,
    department_id INT,
    employee_name STRING,employee_email STRING
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://apg-synthetic-datagen-skoppar/employee/';

-- Create the skills table
CREATE EXTERNAL TABLE skills (
    skill_id INT,
    employee_id INT,
    skill_name STRING
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://apg-synthetic-datagen-skoppar/skills/';
