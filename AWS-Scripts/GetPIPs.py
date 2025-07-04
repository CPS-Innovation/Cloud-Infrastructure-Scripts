import boto3
import csv
import socket
import ipaddress
from botocore.exceptions import ClientError

# Services to check
services = ["EC2", "ElasticIP", "NATGateway", "ENI", "ELBv2", "ELB(Classic)"]

# Output CSV
output_file = "public_ips.csv"

# Get all AWS regions
def get_regions():
    ec2 = boto3.client("ec2")
    regions = ec2.describe_regions()["Regions"]
    return [r["RegionName"] for r in regions]

# Try to resolve DNS to IP
def resolve_dns(dns_name):
    try:
        return socket.gethostbyname(dns_name)
    except Exception:
        return None  # Explicitly return None if not resolvable

# Check if an IP is public
def is_public_ip(ip):
    try:
        return not ipaddress.ip_address(ip).is_private
    except ValueError:
        return False  # Invalid IP or None

# Write to CSV
def write_csv(rows):
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Region", "Service", "ResourceID", "PublicIP_or_DNS"])
        writer.writerows(rows)

def collect_ips():
    rows = []
    regions = get_regions()
    sts = boto3.client("sts")
    account_id = sts.get_caller_identity()["Account"]
    print(f"Account ID: {account_id}")

    for region in regions:
        print(f"Processing region: {region}")
        try:
            ec2 = boto3.client("ec2", region_name=region)
            elbv2 = boto3.client("elbv2", region_name=region)
            elb = boto3.client("elb", region_name=region)

            # EC2 Instances
            reservations = ec2.describe_instances()["Reservations"]
            for r in reservations:
                for i in r["Instances"]:
                    ip = i.get("PublicIpAddress")
                    if ip and is_public_ip(ip):
                        rows.append([region, "EC2", i["InstanceId"], ip])

            # Elastic IPs
            for eip in ec2.describe_addresses()["Addresses"]:
                ip = eip.get("PublicIp")
                if ip and is_public_ip(ip):
                    alloc_id = eip.get("AllocationId", ip)
                    rows.append([region, "ElasticIP", alloc_id, ip])

            # NAT Gateways
            for ngw in ec2.describe_nat_gateways()["NatGateways"]:
                for addr in ngw.get("NatGatewayAddresses", []):
                    ip = addr.get("PublicIp")
                    if ip and is_public_ip(ip):
                        rows.append([region, "NATGateway", ngw["NatGatewayId"], ip])

            # ENIs
            for eni in ec2.describe_network_interfaces()["NetworkInterfaces"]:
                assoc = eni.get("Association", {})
                ip = assoc.get("PublicIp")
                if ip and is_public_ip(ip):
                    rows.append([region, "ENI", eni["NetworkInterfaceId"], ip])

            # Load Balancers (ELBv2)
            for lb in elbv2.describe_load_balancers()["LoadBalancers"]:
                dns = lb["DNSName"]
                ip = resolve_dns(dns)
                if ip and is_public_ip(ip):
                    rows.append([region, "ELBv2", lb["LoadBalancerName"], ip])

            # Classic ELBs
            for lb in elb.describe_load_balancers()["LoadBalancerDescriptions"]:
                dns = lb["DNSName"]
                ip = resolve_dns(dns)
                if ip and is_public_ip(ip):
                    rows.append([region, "ELB(Classic)", lb["LoadBalancerName"], ip])

        except ClientError as e:
            print(f"Error in region {region}: {e}")

    return rows

def main():
    results = collect_ips()
    write_csv(results)
    print(f"\nDone. Output saved to: {output_file}")

main()
