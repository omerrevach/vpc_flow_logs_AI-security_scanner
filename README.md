# AWS VPC Flow Logs AI Security Scanner

## 🔍 **Automated AI-powered threat detection for AWS network traffic**

## 📌 Overview

### This project automates AWS VPC Flow Log analysis to detect network anomalies such as:
- ✅ **Unusual traffic spikes (DDoS attacks)**
- ✅ **Suspicious SSH or RDP access attempts**
- ✅ **Large data transfers (possible exfiltration)**
- ✅ **Unexpected service communication (lateral movement)**

### It stores logs in S3, queries them using AWS Athena, and applies AI anomaly detection using PyOD.
## 🛠 How It Works
1️⃣ **Terraform Setup (Infrastructure as Code)**

    Enables VPC Flow Logs and stores them in an S3 bucket.
    Creates an Athena database & table to analyze logs.
    Configures IAM roles for Athena & S3 access.

2️⃣ **AWS Athena Queries (Log Filtering)**

    Queries logs from S3 to extract high-risk traffic.
    Filters out SSH brute force attempts, high-packet traffic, and unknown IPs.

3️⃣ **AI-Based Threat Detection (PyOD)**

    Uses machine learning to detect anomalies in network traffic.
    Flags suspicious activity and saves it in a report (vpc_anomalies.csv).
    Can be integrated with AWS Security Hub for alerts.