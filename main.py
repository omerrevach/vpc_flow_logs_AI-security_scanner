import boto3
import pandas as pd
from pyod.models.iforest import IForest

client = boto3.client('athena')