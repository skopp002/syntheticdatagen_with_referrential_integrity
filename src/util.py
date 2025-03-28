import requests
import boto3
import json
import yaml

def read_config_file(s3bucket, config_file, execmode):
    if (execmode == 'local'):
        with open(config_file,'rb') as file:
            confdata = yaml.safe_load(file)
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
