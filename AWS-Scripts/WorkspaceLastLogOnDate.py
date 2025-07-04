import boto3
from datetime import datetime, timezone
import csv

output_file = "workspaces_last_log_on_date.csv"

def write_csv(rows):
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["WorkspaceId", "UserName", "LastSignIn"])
        writer.writerows(rows)


def get_workspaces_last_signin(region):
    client = boto3.client('workspaces', region_name=region)
    paginator = client.get_paginator('describe_workspaces')
    workspaces = []
    
    for page in paginator.paginate():
        workspaces.extend(page.get('Workspaces', []))
    
    last_signins = []
    
    for ws in workspaces:
        workspace_id = ws['WorkspaceId']
        user_name = ws['UserName']
        
        response = client.describe_workspaces_connection_status(
            WorkspaceIds=[workspace_id]
        )
        
        for status in response.get('WorkspacesConnectionStatus', []):
            last_signin = status.get('LastKnownUserConnectionTimestamp')
            
            if last_signin:
                last_signin = last_signin.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
            else:
                last_signin = "Never Signed In"
            
            last_signins.append([workspace_id, user_name, last_signin])
    
    return last_signins

def main():
    aws_regions = ["eu-west-2"] 
    
    for region in aws_regions:
        print(f"Checking WorkSpaces in {region}...")
        signins = get_workspaces_last_signin(region)
        write_csv(signins)
        print(f"\nDone. Output saved to: {output_file}")

main()
