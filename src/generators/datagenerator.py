import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import SparkSession
from awsglue.context import GlueContext
from awsglue.job import Job
import boto3
import dbldatagen as dg
import yaml
import pyspark.sql.functions as F
import json
import os
from dbldatagen import fakerText

def read_config_file(s3bucket, config_file, logger, execmode='remote'):
    if (execmode == 'local'):
        with open(config_file,'rb') as file:
            confdata = yaml.safe_load(file)
        print("Config data is ", confdata)
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
            print("Bucket does not exist, hit error ", e)
        except s3_client.exceptions.NoSuchKey as e:
            print("Key path does not exist, hit error ", e)    

def getSecret(secretname, secretregion, logger):
    """
    Fetches the authorized apps from the secrets manager and ensures the appid matches the token provided
    Returns:
        list: returns the list of authorized apps
    """
    session = boto3.session.Session()
    client = session.client(
                            service_name='secretsmanager',
                            region_name=secretregion
    )
    try:
        logger.info("Fetching authorized apps from secrets manager")
        logger.info(f"Accessing {secretname} in {secretname}")
        get_secret_value_response = client.get_secret_value(SecretId=secretname)
    except ClientError as e:
        logger.error(f"ERROR: {e}")
        raise HTTPException(status_code=500, detail="Internal Server Error")
    secret = json.loads(get_secret_value_response['SecretString'])
    return secret

def fetchSchema(spark, s3bucket, dbschema, table, schemapath, logger, execmode):
    logger.info(f"Attempting to read schema for {dbschema}.{table}")
    if(execmode == 'local'):
        df = spark.read \
            .option("header", "true") \
            .csv(f"../../setup/schemafiles/{table}.csv") 
        df.createOrReplaceTempView("tbl")
        schema = spark.table("tbl").schema
        return schema
    else:
        table_exists = spark.catalog.tableExists(f"{dbschema}.{table}")
        if(table_exists):
            table_df = spark.table(f"{dbschema}.{table}")
            schema = table_df.schema
        else:
            df = spark.read \
            .option("header", "true") \
            .csv(f"s3://{s3bucket}/{schemapath}/{table}.csv") 
            df.createOrReplaceTempView("tbl")
            schema = spark.table("tbl").schema
        return schema

def bulkInsertIntoDB(spark, dbschema, table, df, logger,  execmode):
    table_name = f"{dbschema}.{table}"
    print(f"Table name is {table_name}" )
    if(execmode == 'local'):
        logger.info("Writing output")
        df.show(20, False)
    else:
        df.show(20, False)
        df.write.option("numpartitions", "10") \
            .mode("append") \
            .saveAsTable(table_name)                                              


def initializeDataGenerator(spark, spec, basedict):
    for colname in basedict.keys():
        col_prop = basedict.get(colname)
        print("Column being generated ", colname," with properties ", col_prop)
        spec.withColumn(colname,
        percentNulls = 0.0,
        minValue = col_prop.get("minVal",None),
        maxValue = col_prop.get("maxVal", None),
        step = col_prop.get("step",1),
        prefix = col_prop.get("prefix", None),
        random=False,
        text_separator='')
    return spec    


def dropBaseColumns(generated_df, basedict):
    basecollst = []
    for colname in basedict.keys():
        basecollst.append(colname)
    trimmed_df = generated_df.drop(*basecollst)
    return trimmed_df

def writeKeyFileToS3(spark, keydf, appname, version, s3bucket, keyfilepath, startingid, logger, execmode='remote'):
    auditkeydf = keydf.withColumn("appname", F.lit(appname)).withColumn("version",F.lit(version)).withColumn("startingId",F.lit(startingid)).withColumn("dt", F.date_format(F.current_timestamp(),'yyyyMMdd'))      
    if execmode == 'local':
        logger.info(f"In remote mode, file path will be {keyfilepath}/{appname} and sample contents are as below")
        auditkeydf.show(20, False)
        auditkeydf.write.partitionBy("version","dt").parquet("../data/generatoroutput")
    else:
        logger.info(f"Writing Keyfile output to {keyfilepath}/{appname}")
        auditkeydf.write.mode("append").partitionBy("version","dt").parquet(f"s3://{s3bucket}/{keyfilepath}/{appname}")    

def synthesize(glueContext, spark, config_data, appname, version, keyfilepath, rowcount, startFrom, dbschema, secretname, secretregion, logger, execmode='remote'):
    RDS = False
    numpartitions = config_data['num_partitions']
    keyspec = (dg.DataGenerator(spark, rows = rowcount, partitions = numpartitions, startingId = startFrom))
    keydict = config_data['keymap']
    basedict = config_data['basemap']
    s3bucket = config_data['settings']['s3bucket']
    schemapath = config_data['settings']['schemapath']
    print("Configured columns are ", keydict)
    keyspec = initializeDataGenerator(spark, keyspec, basedict)
    print("Initialized Key spec is ", keyspec)
    if config_data['datasink'] == "rds":
        rds_secrets = getSecret(secretname, secretregion, logger)
    for table in config_data['table_list']:
        if RDS:
            tbl_schema =  fetchRDSSchema(spark, dbschema, table, rds_secrets, logger, execmode)
        else:
            tbl_schema = fetchSchema(spark, 
                                     s3bucket, 
                                     dbschema, 
                                     table,
                                     schemapath,
                                     logger, 
                                     execmode)
        logger.info(f"{table} Table schema is {tbl_schema}")
        dataspec = (dg.DataGenerator(spark, rows = rowcount, partitions = numpartitions, startingId = startFrom).withSchema(tbl_schema))
        dataspec = initializeDataGenerator(spark, dataspec, basedict)
        print("Dataspec before keymap based generation ", dataspec)
        cols_in_tbl = tbl_schema.fieldNames()
        print("All columns in the table are ", cols_in_tbl, " and the keys in the conf are ", keydict.keys())
        for colname in keydict.keys():
            try:
                col_prop = keydict.get(colname)
                if (colname in tbl_schema.fieldNames()):
                    logger.info(f"for {table} column {colname} values configured to be {col_prop}")
                    if (col_prop.get("datatype") == "date" and col_prop.get("genType") == "dateRange"):
                        dataspec.withColumnSpec(colname, "date", data_range=dg.DataRange(col_prop.get("minVal"), col_prop.get("maxVal"), "days=1", datetime_format = "%Y%m%d"))
                        keyspec.withColunm(f"{table}_{colname}", "date", data_range=dg.DataRange(col_prop.get("minVal"), col_prop.get("maxVal"), "days=1", datetime_format = "%Y%m%d"))
                    elif (col_prop.get("datatype") == "date" and col_prop.get("genType") == "deltaDays"):
                        dataspec.withColumnSpec(colname, "date", expr =f"""date_format(date_add(current_timestamp(),{col_prop.get("deltaDays")}),'yyyyMMdd')""")
                        keyspec.withColumn(f"{table}_{colname}", "date", expr =f"""date_format(date_add(current_timestamp(),{col_prop.get("deltaDays")}),'yyyyMMdd')""")
                    elif (col_prop.get("datatype") == "date" and col_prop.get("genType") == "columnBasedDeltaDays"):
                        dataspec.withColumnSpec(colname, "date", expr=f"""date_format(date_add(to_date({col_prop.get("baseCol")['val']},'yyyyMMdd'),{col_prop.get("deltaDays")}),'yyyyMMdd')""")
                        keyspec.withColumn(f"{table}_{colname}", "date", expr =f"""date_format(date_add(to_date({col_prop.get("baseCol")['val']},'yyyyMMdd'),{col_prop.get("deltaDays")}),'yyyyMMdd')""")
                    elif (col_prop.get("datatype") == "faker"):
                        valrange = col_prop.get("options",None)
                        if valrange == None:
                            dataspec.withColumnSpec(colname, text=fakerText(col_prop.get("fakerText")))
                            keyspec.withColumn(f"{table}_{colname}", text=fakerText(col_prop.get("fakerText")))
                        else:
                            dataspec.withColumnSpec(colname, 
                                                    text=fakerText(col_prop.get("fakerText"),
                                                                   ext_word_list=valrange), 
                                                    baseColumns = col_prop.get("baseCol", id),
                                                    random = False)
                            keyspec.withColumn(f"{table}_{colname}", 
                                               text=fakerText(col_prop.get("fakerText"),
                                                              ext_word_list=valrange), 
                                               baseColumns = col_prop.get("baseCol", id),
                                               random = False)
                    elif (col_prop.get("datatype") == "confdate"):
                        val = f"""date_format(to_date({col_prop.get("val")}, 'yyyyMMdd'),'yyyyMMdd')"""
                        dataspec.withColumnSpec(colname, "date", expr=val)
                        keyspec.withColumn(f"{table}_{colname}","date", expr=val)
                    elif (col_prop.get("datatype") == "confval"):
                        dataspec.withColumnSpec(colname, expr=col_prop.get("val"))
                        keyspec.withColumn(f"{table}_{colname}",expr=col_prop.get("val"))
                    else:
                        print("Col props, without dateranges", col_prop)
                        dataspec.withColumnSpec(colname,
                        percentNulls = 0.0,
                        minValue = col_prop.get("minVal",None),
                        maxValue = col_prop.get("maxVal", None),
                        step = col_prop.get("step", 1),
                        baseColumns = col_prop.get("baseCol", id),
                        baseColumnType = col_prop.get("baseColType", None),
                        #template = col_prop.get("template",  None),
                        prefix = col_prop.get("prefix",  None),
                        random = False,
                        text_separator=''
                        )
                        print("dataspec now is ", dataspec)
                        keyspec.withColumn(colname,
                        percentNulls = 0.0,
                        minValue = col_prop.get("minVal",None),
                        maxValue = col_prop.get("maxVal", None),
                        step = col_prop.get("step", 1),
                        baseColumns = col_prop.get("baseCol", id),
                        baseColumnType = col_prop.get("baseColType", None),
                        #template = col_prop.get("template",  None),
                        prefix = col_prop.get("prefix",  None),
                        random = False,
                        text_separator=''
                        )
                    cols_in_tbl.remove(colname)
            except KeyError as ke:
                print(f"key error {ke} while processing {table}.{colname}")
            except Exception as e:
                print(f"Error {e} while processing {table}.{colname}")    
        logger.info(f"setting defaults for {cols_in_tbl} in table {table}")
        for unspecified_col in cols_in_tbl:
            logger.info(f"{unspecified_col} present in schema for {table} but no config found. Hence setting to null")
            dataspec.withColumnSpec(unspecified_col, 
                                    percentNulls = 1.0, 
                                    minValue = None,
                        maxValue = None)
        print("Dataspec so far is ", dataspec)
        generated_df = dataspec.build()
        print("lets check the entire DF")
        generated_df.show()
        trimmed_df = dropBaseColumns(generated_df, basedict).distinct()
        if RDS:
            bulkInsertIntoRDSDB(spark, dbschema, table, trimmed_df, rds_secrets, execmode)
        else:
            bulkInsertIntoDB(spark, dbschema, table, trimmed_df, logger, execmode)    
    keydf = keyspec.build()
    writeKeyFileToS3(spark, keydf, appname, version, s3bucket, keyfilepath, startFrom, logger, execmode)    


def rungenerator(sc):
    glueContext = GlueContext(sc)
    spark = SparkSession.builder.getOrCreate()
    logger = glueContext.get_logger()
    args={}
    execmode='remote'
    try:
        logger.info(f"Trying to resolve runtime arguments {sys.argv}")
        args = getResolvedOptions(sys.argv, ['JOB_NAME', 'appname','version','config_bucket','config_file','dbschema','secretname','secretregion','rowcount','startingid'])
        #Add  for RDS access
        
        logger.info(f"Args available are {args}")
    except Exception as e:
        logger.error(f"Runtime arguments missing, switching to local mode, due to {e}")
        args = {
          'JOB_NAME': 'local execution',
          'appname': 'testapp',
          'version' :'1',
          'config_bucket' : '', #For remote provide S3 bucket,
          'config_file': '../config/datagenerator_config.yaml', #'s3://apg-synthetic-datagen-skoppar/generatorConfig/datagenerator_config.yaml', # 
          'dbschema':'',
          'secretname':'',
          'secretregion':'', 
          'rowcount':'100',
          'startingid':'1'
        }   
        logger.info(f"Reading configuration from -> {args['config_file']}") 
        execmode = 'local'
    logger.info(f"Generator mode set to {execmode}")
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    logger.info(f"Current working directory is {os.path.dirname(os.path.abspath(__file__))}")
    config_dict = read_config_file(args['config_bucket'], args['config_file'], 
                                   logger,execmode)
    synthesize(glueContext,
               spark,
               config_dict,
               args['appname'],
               args['version'],
               config_dict['settings']['keyfilepath'],
               int(args['rowcount']),
               int(args['startingid']),
               args['dbschema'],
               args['secretname'],
               args['secretregion'],
               logger,
               execmode) ## TODO hardcoded

if __name__ == '__main__':
    sc = SparkContext()
    rungenerator(sc)
    
    
"""Below methods can be leveraged for RDS based tables.
    """
def fetchRDSSchema(spark, dbschema, table, rds_secrets, logger, execmode):
    logger.info(f"Attempting to read schema for {dbschema}.{table}")
    if(execmode == 'local'):
        df = spark.read \
            .option("header", "true") \
            .csv(f"src/data/appname/{dbschema}/{table}.csv") 
        df.createOrReplaceTempView("tbl")
        schema = spark.table("tbl").schema
        return schema
    else:
        table_df = spark.read.format("jdbc") \
            .option("url", rds_secrets["connecturl"]) \
            .option("dbtable", f"{dbschema}.{table}") \
            .option("user", rds_secrets["username"]) \
            .option("password", rds_secrets["password"]) \
            .option("numpartitions", "10") \
            .load()
        table_df = createOrReplaceTempView(table)
        return spark.table(table).schema

def bulkInsertIntoRDSDB(spark, dbschema, table, df, rds_secrets, logger, execmode):
    if(execmode == 'local'):
        logger.info()
        df.show(20, False)
    else:
        df.write.format("jdbc") \
            .option("url", rds_secrets["connecturl"]) \
            .option("dbtable", f"{dbschema}.{table}") \
            .option("user", rds_secrets["username"]) \
            .option("password", rds_secrets["password"]) \
            .option("numpartitions", "10") \
            .option("append") \
            .save()                                              
