#!/usr/bin/env python3

## NetHunter ~ https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-project/-/blob/2e26ee29/nethunter-installer/prep-release.py
## ARM Devices ~ https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

###############################################
## Script to prepare Kali ARM quarterly release
##
## This should be run after images are created.
##
## It parses the YAML sections of the devices.yml and creates:
##
## - "<outputdir>/manifest.json": manifest file mapping image name to display name
##
## Dependencies:
##   sudo apt -y install python3 python3-yaml
##
## Usage:
##  ./bin/pre-release.py -i <input file> -o <output directory> -r <release>
##
## E.g.:
## ./bin/pre-release.py -i devices.yml -o images/ -r 2022.3

import json
import datetime
import yaml # python3 -m pip install pyyaml --user
import getopt, os, stat, sys
import hashlib # sha256 support

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

def jsonarray(devices, vendor, name, filename, preferred, slug):
    if not vendor in devices:
        devices[vendor] = []
    jsondata = {"name": name, "filename": filename, "preferred": preferred, "slug": slug}
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
                            if image.get('support') == "kali":
                                qty_images += 1
                                name = image.get('name', default)
                                filename = "kali-linux-{}-{}".format(release, image.get('image', default))
                                preferred = image.get('preferred-image', default)
                                slug = image.get('slug', default)
                                jsonarray(devices, vendor, name, filename, preferred, slug)
    return json.dumps(devices, indent = 2)

def hash_file(filename):
    # This function returns the SHA-256 hash
    h = hashlib.sha256()

    # open file for reading, binary
    with open(filename, 'rb') as file:
        chunk = 0
        while chunk != b'':
            # read only 1024 bytes at a time
            chunk = file.read(1024)
            h.update(chunk)
    return h.hexdigest()

# We don't want to dedupe everything, we want it to only do so based on the "name"
# and we want to remove the stanza, rather than just that line.
# Ideally, we look at vendor, then check if the "name" already exists
# if so, leave off that stanza.
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
    manifest = outputdir + "/manifest.json"
    data = readfile(inputfile)

    # Get data
    res = yaml_parse(data)
    manifest_list = deduplicate(generate_manifest(res))

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
