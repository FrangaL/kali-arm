#!/usr/bin/env python3

## ARM Devices ~ https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

###############################################
## Script to prepare the rpi-imager json script for Kali ARM quarterly releases.
## Based on ./bin/pre-release.py
##
## This should be run after images are created.
##
## It parses the YAML sections of the devices.yml and creates:
##
## - "<outputdir>/rpi-imager.json": manifest file mapping image name to display name
##
## The upstream rpi-imager repo expects a json file that looks like:
##

##
## Dependencies:
##   sudo apt -y install python3 python3-yaml
##
## Usage:
##  ./bin/rpi-imager.py -i <input file> -o <output directory> -r <release>
##
## E.g.:
## ./bin/rpi-imager.py -i devices.yml -o images/ -r 2022.3

##
## Example output we are looking for:
##
## {
##   "os_list": [
##     {
##       "name": "Raspberry Pi Zero W (32-bit)",
##       "description": "Kali Linux image for the Raspberry Pi Zero W",
##       "url": "https://cdimage.kali.org/2022.3/arm/kali-linux-2022.3-raspberry-pi-zero-w-armel.img",
##       "icon": "https://www.kali.org/whatever/kali.png",
##       "release_date": "2022-XX-YY",
##       "extract_size": 2726297600,
##       "extract_sha256": "5f906ef5d29d4fa4b68c75ed8ea581f5edf0ba41a646173bab7fe27c72cc0fb6",
##       "image_download_size": 735031191,
##       "image_download_sha256": "dfd6f5f73344f16fd1d65cc3be26cca23897a6f1c5123369e371489a222d23fc",
##       "website": "https://www.kali.org/"
##    }
##  ]
## }
##
## What we currently end up with:
## With deduplicate:
##
## {
##   "raspberrypi": [
##     {
##       "name": "Raspberry Pi 2, 3, 4 and 400 (32-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-armhf.img"
##     },
##       "name": "Raspberry Pi 2 (v1.2), 3, 4 and 400 (64-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-arm64.img"
##       "name": "Raspberry Pi Zero W",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-w-armel.img"
##       "name": "Raspberry Pi Zero W (PiTail)",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-w-pitail-armel.img"
##       "name": "Raspberry Pi Zero 2 W",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-2-w-armhf.img"
##       "name": "Raspberry Pi Zero 2 W (PiTail)",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-2-w-pitail-armhf.img"
##       "name": "Raspberry Pi 1 (Original)",
##       "filename": "kali-linux-2022.3-raspberry-pi1-armel.img"
##     }
##   ]
## }
##
## Without deduplicate:
##
## {
##   "raspberrypi": [
##     {
##       "name": "Raspberry Pi 2, 3, 4 and 400 (32-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi 2 (v1.2), 3, 4 and 400 (64-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-arm64.img"
##     },
##     {
##       "name": "Raspberry Pi 2, 3, 4 and 400 (32-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi 2 (v1.2), 3, 4 and 400 (64-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-arm64.img"
##     },
##     {
##       "name": "Raspberry Pi 2, 3, 4 and 400 (32-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi 2 (v1.2), 3, 4 and 400 (64-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-arm64.img"
##     },
##     {
##       "name": "Raspberry Pi 2, 3, 4 and 400 (32-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi 2 (v1.2), 3, 4 and 400 (64-bit)",
##       "filename": "kali-linux-2022.3-raspberry-pi-arm64.img"
##     },
##     {
##       "name": "Raspberry Pi Zero W",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-w-armel.img"
##     },
##     {
##       "name": "Raspberry Pi Zero W (PiTail)",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-w-pitail-armel.img"
##     },
##     {
##       "name": "Raspberry Pi Zero W (P4wnP1 A.L.O.A)",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-w-p4wnp1-aloa-armel.img"
##     },
##     {
##       "name": "Raspberry Pi Zero 2 W",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-2-w-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi Zero 2 W (PiTail)",
##       "filename": "kali-linux-2022.3-raspberry-pi-zero-2-w-pitail-armhf.img"
##     },
##     {
##       "name": "Raspberry Pi 1 (Original)",
##      "filename": "kali-linux-2022.3-raspberry-pi1-armel.img"
##     }
##   ]
## }
import json
import datetime
import yaml # python3 -m pip install pyyaml --user
import getopt, os, stat, sys

manifest = ""     # Generated automatically (<outputdir>/manifest.json)
release = ""
outputdir = ""
inputfile = ""
qty_images = 0
qty_devices = 0

## Input:
## ------------------------------------------------------------ ##
## See: ./devices.yml
##      https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

def bail(message = "", strerror = ""):
    outstr = ""
    prog = sys.argv[0]
    if message != "":
        outstr = "\nError: {}".format(message)
    if strerror != "":
        outstr += "\nMessage: {}\n".format(strerror)
    else:
        outstr += "\n\nUsage: {} -i <input file> -o <output directory> -r <release>".format(prog)
        outstr += "\nE.g. : {} -i devices.yml -o images/ -r {}.1\n".format(prog, datetime.datetime.now().year)
    print(outstr)
    sys.exit(2)

def getargs(argv):
    global inputfile, outputdir, release

    try:
        opts, args = getopt.getopt(argv,"hi:o:r:",["inputfile=","outputdir=","release="])
    except getopt.GetoptError as e:
        bail("Incorrect arguments: {}".format(e))

    if opts:
        for opt, arg in opts:
            if opt == '-h':
                bail()
            elif opt in ("-i", "--inputfile"):
                inputfile = arg
            elif opt in ("-o", "--outputdir"):
                outputdir = arg.rstrip("/")
            elif opt in ("-r", "--release"):
                release = arg
            else:
                bail("Unrecognised argument: " + opt)
    else:
        bail("Failed to read arguments")

    if not release:
        bail("Missing required argument: -r/--release")
    return 0

def yaml_parse(content):
    result = ""
    lines = content.split('\n')
    for line in lines:
        if line.strip() and not line.strip().startswith('#'):
            result += line + "\n"
    return yaml.safe_load(result)

def jsonarray(devices, vendor, name, filename):
    if not vendor in devices:
        devices[vendor] = []
    jsondata = {"name": name, "filename": filename}
    devices[vendor].append(jsondata)
    return devices

def generate_manifest(data):
    global release, qty_devices, qty_images
    default = ""
    devices = {}

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over vendors
        for vendor in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[vendor]:
                qty_devices += 1
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Check that it's not eol or community supported (depth 3)
                        # Iterate over image (depth 4)
                        for image in board[key]:
                            if image.get('image').startswith("raspberry"):
                                qty_images += 1
                                name = image.get('name', default)
                                filename = "kali-linux-{}-{}".format(release, image.get('image', default))
                                jsonarray(devices, vendor, name, filename)
    return json.dumps(devices, indent = 2)

def deduplicate(data):
    # Remove duplicate lines
    clean_data = ""
    lines_seen = set()
    for line in data.splitlines():
        if line not in lines_seen: # not a duplicate
            clean_data += line + "\n"
            lines_seen.add(line)
    return clean_data

def createdir(dir):
    try:
        if not os.path.exists(dir):
            os.makedirs(dir)
    except:
        bail('Directory "' + dir + '" does not exist and cannot be created')
    return 0

def readfile(file):
    try:
        with open(file) as f:
            data = f.read()
            f.close()
    except:
        bail("Cannot open input file: " + file)
    return data

def writefile(data, file):
    try:
        with open(file, 'w') as f:
            f.write(str(data))
            f.close()
    except:
        bail("Cannot write to output file: " + file)
    return 0

def main(argv):
    global inputfile, outputdir, release

    # Parse command-line arguments
    if len(sys.argv) > 1:
        getargs(argv)
    else:
        bail("Missing arguments")

    # Assign variables
    manifest = outputdir + "/rpi-imager.json"
    data = readfile(inputfile)

    # Get data
    res = yaml_parse(data)
    #manifest_list = deduplicate(generate_manifest(res))
    manifest_list = generate_manifest(res)

    # Create output directory if required
    createdir(outputdir)

    # Create manifest file
    writefile(manifest_list, manifest)

    # Print result and exit
    print('\nStats:')
    print('  - Devices\t: {}'.format(qty_devices))
    print('  - Images\t: {}'.format(qty_images))
    print("\n")
    print('Manifest file created\t: {}'.format(manifest))

    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])
