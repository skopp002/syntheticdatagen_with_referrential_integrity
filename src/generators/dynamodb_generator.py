import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import SparkSession
from awsglue.context import GlueContext
import boto3
import yaml
import pyspark.sql.functions as F
from pyspark.sql import Row
from nested_lookup import nested_update
from awsglue.job import Job
import json
from awsglue.dynamicframe import DynamicFrame
from botocore.exceptions import ClientError



def read_config_file(s3bucket, config_file, logger, execmode='remote'):
    if (execmode == 'local'):
        with open(config_file,'rb') as file:
            confdata = yaml.safe_load(file)
        logger.info(f"Config data is {confdata}")
        return confdata
    else:
        s3_client = boto3.client('s3')
        try:
            s3_response = s3_client.get_object(
                Bucket = s3bucket,
                Key = config_file
            )
            confdata = yaml.safe_load(s3_response.get('Body').read().decode())
            return confdata
        except s3_client.exceptions.NoSuchBucket as e:
            logger.error(f"Bucket does not exist, hit error {e}")
        except s3_client.exceptions.NoSuchKey as e:
            logger.error(f"Key path does not exist, hit error {e}")       


def replaceJsonValues(row, key_of_attr, replacement_map) -> Row:
    from datetime import datetime, timedelta, date
    json_data = json.loads(row[key_of_attr])
    for jsonkey, jsonval in replacement_map.items():
        #print(f"jsonkey -> {jsonkey}, jsonval -> {jsonval}")
        json_data = nested_update(json_data, \
                                        key=jsonkey, \
                                        in_place = True, \
                                        value= eval(jsonval))
    row[key_of_attr] = json.dumps(json_data)
    return Row(**row)                             


def generatefromkey(jsondf, key_of_attr, replacement_map):
    print(f"key_of_attr is {key_of_attr} and replacement_map -> {replacement_map}")
    for row in jsondf:
        row_dict = row.asDict()
        yield [replaceJsonValues(row_dict, key_of_attr, replacement_map)]


def buildPKSKsql(config_file):
    #PK - Partition Key and SK - Sort Key
    #anything that does not need to be part of PK or SK but needed for rest of the attributes, can be pulled in through additional_pk
    additional_pk = config_file.get('ADDITIONAL_SQL',"NA")
    match config_file['SK']['type']:
        case 'conf': return f"""select {config_file['SQL']} as PK,
                          {config_file['SK']['val']} as SK,
                          {additional_pk} as ADDITIONAL_PK
                          from keytable"""
        #Here we generate a range of SKs for the same PK by creating a sequence and then exploding it into multiple rows                  
        case _: return f"""select PK, FROM_UNIXTIME(UNIX_TIMESTAMP(SKdefault, 'yyyy-MM-dd HH:mm:ss'), {config_file['SK']['format']}) as SK,
                           ADDITIONAL_PK from 
                           (select {config_file['SQL']} as PK,
                           {additional_pk} as ADDITIONAL_PK,
                           explode(sequence(TO_TIMESTAMP({config_file['SK']['start']}),
                           TO_TIMESTAMP({config_file['SK']['end']}),
                           interval {config_file['SK']['interval_in_days']} day)) as SKdefault from keytable)"""                  


def generatePKSK(spark, config_file, keyfile_df,logger):
    keyfile_df.createOrReplaceTempView("keytable")
    gen_sql = buildPKSKsql(config_file)
    dynpk_sk = spark.sql(gen_sql)
    for attr in config_file['Attrs']:
        match config_file[attr]['type']:
            case "json":
                collst = dynpk_sk.columns
                dynpk_sk = dynpk_sk.withColumn(attr, F.lit(config_file[attr]["jsonstr"]))
                dynpk_sk = dynpk_sk.rdd.mapPartitions(
                    lambda partition : generatefromkey(partition, attr, config_file[attr]['replacement_map'])
                    ).toDF(collst.append(attr))
                dynpk_sk = dynpk_sk.select("_1.*")
            case "audit_date":
                dynpk_sk = dynpk_sk.withColumn(attr,
                F.date_format(F.to_date(eval(config_file[attr]["val"]), config_file[attr]['format']
                ),config_file[attr]['format']))
            case "relative_date":
                print("Printing relative date base field")
                dynpk_sk.select(config_file[attr]['base_date_column']).show()
                dynpk_sk = dynpk_sk.withColumn(attr,
                F.unix_timestamp(F.date_add(F.to_date(
                    config_file[attr]['base_date_column'], config_file[attr]['base_date_format']
                ),
                config_file[attr]['delta_days'])))
                dynpk_sk.printSchema()
                dynpk_sk.show(10, False)    
            case "string":
                dynpk_sk = dynpk_sk.withColumn(attr, F.lit(config_file[attr]["str"]))
            case "sql":
                dynpk_sk.createOrReplaceTempView("pksktbl")
                dynpk_sk = spark.sql(f"select *, {config_file[attr]['attr_SQL']} as {attr} from pksktbl")    
    return dynpk_sk

def synthesize(glueContext,
               spark,
               config_dict,
               dynamodb_table,
               keyfilepath,
               logger,
               execmode):
    keyfile_df = spark.read.parquet(keyfilepath)
    keyfile_df.show()
    for PK in config_dict['PKlst']:
        gen_dyn = generatePKSK(spark, config_dict['PKdesc'][PK], keyfile_df, logger)
        if (execmode =='local'):
            gen_dyn.show(10, False)
        else:
            gen_dyn_frame = DynamicFrame.fromDF(gen_dyn.drop('ADDITIONAL_PK'), glueContext, "gen_dyn_frame")
            logger.info(f"Writing to {dynamodb_table}")
            try:
                glueContext.write_dynamic_frame_from_options(
                    frame = gen_dyn_frame,
                    connection_type="dynamodb",
                    connection_options={"dynamodb.output.tableName": dynamodb_table, "dynamodb.throughput.write.percent":"1.0"}
                    )
            except Exception as e:
                error_message = str(e)
                logger.error(f"error message is {error_message}")
                if "ResourceNotFoundException" in error_message:
                    logger.error(f"Table {dynamodb_table} does not exist. Ensure runtime parameter Glue job runtime parameter --dynamodb_table matches the table created by Terraform and exists in same region")
                    raise e
                else:
                    logger.error(f"Unexpected error: {e}")
                    raise e                  
             

def rundyngenerator(sc):
    glueContext = GlueContext(sc)
    spark = SparkSession.builder.getOrCreate()
    logger = glueContext.get_logger()
    args={}
    execmode='remote'
    try:
        logger.info(f"Runtime arguments are {sys.argv}")
        args = getResolvedOptions(sys.argv, ['JOB_NAME', 'dynamodb_table','config_bucket','config_file','keyfilepath'])
    except:
        args = {
          'JOB_NAME': 'local execution',
          'dynamodb_table': 'dyn_test_tbl',
          'config_bucket' : '', #For remote provide S3 bucket,
          'config_file': '../config/dynamodb_generator.yaml', 
          'keyfilepath':'../data/generatoroutput' #Path to parquet output files from datagenerator. 
        }    
        execmode = 'local'
    
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    #spark.conf.set("spark.sql.legacy.timeParserPolicy","LEGACY") - Use if input date formats are Legacy patterns
    config_dict = read_config_file(args['config_bucket'], args['config_file'], logger, execmode)
    logger.info(f"Configuration is {config_dict}")
    synthesize(glueContext,
               spark,
               config_dict,
               args['dynamodb_table'],
               args['keyfilepath'],
               logger,
               execmode)

'''
This method is not used anymore. Instead use Terraform code to create the DynamoDB table.
The job will error if the table does not exist.

def create_dynamodb_table(table_name, logger):
    try:
        dynamodb = boto3.resource('dynamodb')
        key_schema = [
              {
               'AttributeName': 'PK',
               'KeyType': 'HASH'
              },
              {
             'AttributeName': 'SK',
             'KeyType': 'RANGE'
             }
         ]
        attribute_definitions = [
            {
            'AttributeName': 'PK',
            'AttributeType': 'S'  # String
            },
           {
            'AttributeName': 'SK',
            'AttributeType': 'S'  # String
           }
        ]
        billing_mode = 'PAY_PER_REQUEST'
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=key_schema,
            AttributeDefinitions=attribute_definitions,
            BillingMode=billing_mode
        )
        logger.info(f"Creating DynamoDB table {table_name}")
        table.wait_until_exists()
        logger.info(f"DynamoDB table {table_name} created successfully")
    except dynamodb.exceptions.ResourceInUseException:
        logger.info(f"DynamoDB table {table_name} already exists")
''' 

if __name__ == '__main__':
    sc = SparkContext()
    rundyngenerator(sc)