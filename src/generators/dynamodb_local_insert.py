
def runjob(execmode):
    if(execmode == 'local'):
        glueContext._jsc.hadoopConfiguration.set("dynamodb.awsAccessKeyId","empty")
        glueContext._jsc.hadoopConfiguration.set("dynamodb.awsSecretAccessKey","empty")
        glueContext._jsc.hadoopConfiguration.set("dynamodb.endpoint","<value from ifconfig>")

if __name__ == '__main__':
    runjob('local')