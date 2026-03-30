from __future__ import print_function

import argparse
import os
import re
import ipaddress
import json

try:
    from urllib import urlopen
except ImportError:
    from urllib.request import urlopen
    from urllib.error import HTTPError

import netaddr

IPRANGE_URLS = {
    "goog": "https://www.gstatic.com/ipranges/goog.json",
    "cloud": "https://www.gstatic.com/ipranges/cloud.json",
}

def print_log(msg):
    print(msg)

def read_url(url):
    try:
        return json.loads(urlopen(url).read())
    except (IOError, HTTPError):
        print_log("ERROR: Invalid HTTP response from %s" % url)
    except json.decoder.JSONDecodeError:
        print_log("ERROR: Could not parse HTTP response from %s" % url)


def get_data(link):
    data = read_url(link)
    if data:
        print_log("{} published: {}".format(link, data.get("creationTime")))
        cidrs = netaddr.IPSet()
        for e in data["prefixes"]:
            if "ipv4Prefix" in e:
                cidrs.add(e.get("ipv4Prefix"))
            if "ipv6Prefix" in e:
                cidrs.add(e.get("ipv6Prefix"))
        return cidrs

def is_cidr(text):
      try:
          ipaddress.ip_network(text, strict=False)
          return True
      except ValueError:
          return False

def extract_cidrs(content):
    # IPv4 CIDR 正则
    ipv4_pattern = r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}\b'
    # IPv6 CIDR 正则（支持 :: 压缩格式）
    ipv6_pattern = r'\b[0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4}){1,7}/\d{1,3}\b'
    results = set()
    # 提取 IPv4
    for match in re.findall(ipv4_pattern, content):
        if is_cidr(match):
            results.add(match)
    # 提取 IPv6
    for match in re.findall(ipv6_pattern, content):
        if is_cidr(match):
            results.add(match)
    return results

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', help='保存文件的目录')
    args = parser.parse_args()
    
    print_log("rule save path: {}".format(args.directory))

    # 1. google ip list
    google_ip_file = os.path.join(args.directory, 'google-official-ip-temp.txt')
    cidrs = {group: get_data(link) for group, link in IPRANGE_URLS.items()}
    #if len(cidrs) != 2:
    #    raise ValueError("ERROR: Could process data from Google")
    #print_log("IP ranges for Google APIs and services default domains:")
    if len(cidrs) == 2:
        with open(google_ip_file, 'w') as f:
            for ip in (cidrs["goog"] - cidrs["cloud"]).iter_cidrs():
                if is_cidr(ip):
                    f.write(str(ip) + '\n')
    
    # 2. microsoft ip list
    url = 'https://download.microsoft.com/download/83c030bb-d583-4bf4-b8d5-53eac0e46bed/msft-public-ips.csv'
    microsoft_ip_file = os.path.join(args.directory, 'microsoft-official-ip-temp.txt')
    print_log("{} published: {}".format(url, "-"))
    with urlopen(url) as response:
        content = response.read().decode('utf-8')

    lines = content.strip().split('\n')
    with open(microsoft_ip_file, 'w') as f:
        for line in lines[1:]:  # 跳过第一行
            line = line.strip()
            if not line:  # 排除空行
                continue
            ip = line.split(',')[0]
            if is_cidr(ip):
                f.write(str(ip) + '\n')

    # 3. apple ip list
    url = 'https://support.apple.com/zh-cn/101555'
    apple_ip_file = os.path.join(args.directory, 'apple-official-ip-temp.txt')
    print_log("{} published: {}".format(url, "-"))
    with urlopen(url) as response:
        content = response.read().decode('utf-8')
    cidrs = extract_cidrs(content)
    with open(apple_ip_file, 'w') as f:
        for ip in sorted(cidrs):
            if is_cidr(ip):
                f.write(str(ip) + '\n')

if __name__ == "__main__":
    main()