#!/usr/bin/env python3
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './devices.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
qty_devices = 0

## Input:
## ------------------------------------------------------------ ##
## See: ./devices.yml
##      https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

def yaml_parse(content):
    result = ""
    lines = content.split('\n')
    for line in lines:
        if line.strip() and not line.strip().startswith('#'):
            result += line + "\n"
    return yaml.safe_load(result)

def generate_table(data):
    global qty_devices
    default = ""
    table  = "| Vendor | Board | CPU | CPU Cores | GPU | RAM | RAM Size | Ethernet | Ethernet Speed | Wi-Fi | Bluetooth | USB2 | USB3 | Storage | Notes |\n"
    table += "|--------|-------|-----|-----------|-----|-----|----------|----------|----------------|-------|-----------|------|------|---------|-------|\n"

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over vendors
        for vendor in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[vendor]:
                qty_devices += 1
                table += "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |\n".format(vendor,
                                                                                                            board.get('name', default),
                                                                                                            board.get('cpu', default),
                                                                                                            board.get('cpu-cores', default),
                                                                                                            board.get('gpu', default),
                                                                                                            board.get('ram', default),
                                                                                                            board.get('ram-size', default),
                                                                                                            board.get('ethernet', default),
                                                                                                            board.get('ethernet-speed', default),
                                                                                                            board.get('wifi', default),
                                                                                                            board.get('bluetooth', default),
                                                                                                            board.get('usb2', default),
                                                                                                            board.get('usb3', default),
                                                                                                            board.get('storage', default),
                                                                                                            board.get('notes', default))
    return table

def read_file(file):
    try:
        with open(file) as f:
            data = f.read()
            f.close()
    except Exception as e:
        print("[-] Cannot open input file: {} - {}".format(file, e))
    return data

def write_file(data, file):
    try:
        with open(file, 'w') as f:
            meta  = '---\n'
            meta += 'title: Kali ARM Devices\n'
            meta += '---\n\n'
            stats  = "- The official [Kali ARM repository](https://gitlab.com/kalilinux/build-scripts/kali-arm) contains build-scripts to support [**{}** Kali ARM devices](device-stats.html)\n".format(str(str(qty_devices)))
            stats += "- [Kali ARM Statistics](index.html)\n\n"
            f.write(str(meta))
            f.write(str(stats))
            f.write(str(data))
            f.write(str(repo_msg))
            f.close()
            print('[+] File: {} successfully written'.format(OUTPUT_FILE))
    except Exception as e:
        print("[-] Cannot write to output file: {} - {}".format(file, e))
    return 0

def print_summary():
    print('Devices        : {}'.format(qty_devices))

def main(argv):
    # Assign variables
    data = read_file(INPUT_FILE)

    # Get data
    res = yaml_parse(data)
    generated_markdown = generate_table(res)

    # Create markdown file
    write_file(generated_markdown, OUTPUT_FILE)

    # Print result
    print_summary()

    # Exit
    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])
