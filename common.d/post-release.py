#!/usr/bin/env python3

###############################################
## Script to prepare Kali ARM quarterly release
##
## It parses the YAML sections of the devices.yml and creates:
## This should be run after images are created.
##
## - "<outputdir>/manifest.json": manifest file mapping image name to display name
##
## Usage:
##  python3 post-release.py --inputfile <input file> --outputdir <output directory> --release <release version>
##
## Example:
##  python3 post-release.py --inputfile devices.yml --outputdir $(PWD)/images/ --release 2022.3
##
## Install:
##  sudo apt -y install python3 python3-yaml

import yaml
import getopt, os, stat, sys

FS_SIZE = ""
manifest = ""
outputdir = ""
qty_images = 0
qty_devices = 0

def bail(message = "", strerror = ""):
    outstr = ""
    prog = sys.argv[0]
    if message != "":
      outstr = "\n\tError: {}\n".format(message)
    if strerror != "":
      outstr += "\n\tMessage: {}\n".format(strerror)
    else:
      outstr += "\n\tUsage: {} -inputfile <input file> --outputdir <output directory> --release <release>\n".format(prog)
    print(outstr)
    sys.exit(2)

def getargs(argv):
  global inputfile, outputdir, release

  try:
    opts, args = getopt.getopt(argv,"hi:o:r:",["inputfile=","outputdir=","release="])
  except getopt.GetoptError:
    bail("Missing arguments (1)")

  for opt, arg in opts:
    if opt == "-h":
      bail()
    elif opt in ("-i", "--inputfile"):
      inputfile = arg
    elif opt in ("-o", "--outputdir"):
      outputdir = arg.rstrip("/")
    elif opt in ("-r", "--release"):
      release = arg
    else:
      bail("Incorrect arguments: %s" % opt)
    return 0

def yaml_parse(content):
  result = ""
  lines = content.split('\n')
  for line in lines:
    if line.startswith('##*'):
      ## yaml doesn't like tabs so let's replace them with 4 spaces
      result += line.replace('\t', '    ')[3:] + "\n"
  return yaml.safe_load(result)

def generate_manifest(data):
  manifest = ""
  global release

  default = ""
  for element in data:
    print("data is", repr(data)) # Currently just keeps being None?
    for key in element.keys():
      print("key is", repr(key))
      if 'board' in element[key]:
        for image in element[key]['image']:
          print("image is", repr(image))
          ## Example filename
          ## kali-linux-2022.3-beaglebone-black-armhf.img
          ##            ^^release
          ##                   ^^board
          ##                                    ^^architecture
          manifest += "{},kali-linux-{}-{}-{}.img.xz\n".format(image.get('name', default), release, image.get('board', default), image.get('architecture', default))
  return manifest

def deduplicate(data):
  clean_data = ""
  lines_seen = set()
  for line in data.splitlines():
    if line not in lines_seen:
      clean_data += line + "\n"
      lines_seen.add(line)
  return clean_data

def createdir(dir):
  try:
    if not os.path.exists(dir):
      os.makedirs(dir)
  except:
      bail(' Directory "' + dir + 'does not exist and cannot be created')
  return 0

def readfile(file):
  try:
    with open(file) as f:
      data = f.read()
      f.close()
  except:
    bail("Cannot open input file")
  return data

def writefile(data, file):
  try:
    with open(file, 'w') as f:
      f.write(str(data))
      f.close()
  except:
    bail("Cannot write to output file" + file)
    return 0

def main(argv):
  global inputfile, outputdir, release

  getargs(argv)

  manifest = outputdir + "/manifest.json"
  data = readfile(inputfile)

  res = yaml_parse(data)
  manifest_list = generate_manifest(res)
  createdir(outputdir)
  writefile(manifest_list, manifest)
  print("\n")
  print('Manfiest file "{}" created.'.format(manifest))
  print("\n")

  exit(0)

if __name__ == "__main__":
  main(sys.argv[1:])
