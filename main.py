import boto3
import time
import pandas as pd
# from pyod.models.iforest import IForest

athena_client = boto3.client('athena')

query = "SELECT * FROM vpc_flow_logs_table LIMIT 10;"

query_execution = athena_client.start_query_execution(
    QueryString=query,
    QueryExecutionContext={
        'Database': 'vpc_flow_logs_db',
    },
    ResultConfiguration={
        'OutputLocation': 's3://vpc-flow-logs-athena-querylogs-results/',
    }
)
execution_id = query_execution['QueryExecutionId']

while True:
    time.sleep(1)
    query_details = athena_client.get_query_execution(
        QueryExecutionId=execution_id
    )
    
    state = query_details['QueryExecution']['Status']['State']
    if state == 'SUCCEEDED':
        print(f"Query State: {state}")
        break
    
    elif state == 'FAILED' or 'CANCELLED':
        print(f"Query State: {state}, check Athena for the logs")
        exit()
        
        
query_result = athena_client.get_query_results(
            QueryExecutionId=execution_id
)
results = query_result['ResultSet']['Rows']
print(results)